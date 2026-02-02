# 0042. Adding New Cluster Nodes

**Status**: In Progress

**Date**: 2026-02-02

## Context

Documenting the process of adding new bare-metal nodes to the Kubernetes cluster on Hetzner dedicated servers. This serves as a runbook for cluster expansion.

## Prerequisites

- [ ] Server ordered from Hetzner (Serverbörse/Auction recommended for cost)
- [ ] Server added to vSwitch in Robot (VLAN 4000, same as existing nodes)
- [ ] SSH public key configured in Robot → Key Management
- [ ] Server boots into Rescue mode by default (new servers do this automatically)

---

## Phase 1: OS Installation via installimage

### Step 1.1: Verify server is in Rescue mode

```bash
ssh root@<SERVER_IP> "cat /etc/motd | grep -A1 'Welcome'"
```

**Expected:**
```
Welcome to the Hetzner Rescue System.
```

**Note:** New Hetzner servers boot into Rescue mode (Debian 12) by default. This is NOT the installed OS - it's a temporary system for running `installimage`.

### Step 1.2: Check available disks

```bash
ssh root@<SERVER_IP> "lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -v loop"
```

### Step 1.3: Check available OS images

```bash
ssh root@<SERVER_IP> "ls /root/images/ | grep -i ubuntu"
```

**Expected:** `Ubuntu-2404-noble-amd64-base.tar.gz`

### Step 1.4: Create installimage config

```bash
ssh root@<SERVER_IP> "cat > /autosetup << 'EOF'
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1
FORMATDRIVE2 0

SWRAID 0

BOOTLOADER grub

HOSTNAME <NODE_NAME>

PART /boot ext4 1G
PART / ext4 300G
PART /mnt/longhorn-disk1 ext4 all

IMAGE /root/images/Ubuntu-2404-noble-amd64-base.tar.gz
EOF"
```

**Config explanation:**

| Directive | Value | Description |
|-----------|-------|-------------|
| `DRIVE1` | `/dev/nvme0n1` | Primary disk for OS |
| `DRIVE2` | `/dev/nvme1n1` | Secondary disk (declared but not formatted) |
| `FORMATDRIVE2` | `0` | Don't touch second disk during install |
| `SWRAID` | `0` | No software RAID (disks used separately) |
| `BOOTLOADER` | `grub` | Use GRUB2 bootloader |
| `HOSTNAME` | `<NODE_NAME>` | e.g., k8s-03, k8s-04 |
| `PART /boot` | `1G` | Boot partition |
| `PART /` | `300G` | Root partition |
| `PART /mnt/longhorn-disk1` | `all` | Remaining space for Longhorn |
| `IMAGE` | `Ubuntu-2404-...` | Ubuntu 24.04 LTS base image |

**Why no RAID?**
- Separate disks = ~1.9TB usable (vs ~954GB with RAID1)
- Longhorn provides replication at cluster level
- OS disk failure = reinstall needed, but data safe on other nodes

### Step 1.5: Run installimage

```bash
ssh root@<SERVER_IP> "/root/.oldroot/nfs/install/installimage -a -c /autosetup"
```

**Note:** `installimage` is not in PATH, use full path.

### Step 1.6: Reboot and verify Ubuntu

```bash
ssh root@<SERVER_IP> "reboot"

# Wait ~60 seconds, then clear old host key and connect
ssh-keygen -R <SERVER_IP>
ssh -o StrictHostKeyChecking=accept-new root@<SERVER_IP> "cat /etc/os-release | head -2 && hostname"
```

**Expected:**
```
PRETTY_NAME="Ubuntu 24.04.3 LTS"
NAME="Ubuntu"
k8s-0X
```

---

## Phase 2: Partition Second Disk for Longhorn

### Step 2.1: Identify second disk

**Important:** Disk order may vary between servers! Check which disk has the OS:

```bash
ssh root@<SERVER_IP> "lsblk -o NAME,SIZE,MOUNTPOINTS | grep -E 'nvme|NAME'"
```

The disk WITHOUT partitions is your second disk for longhorn-disk2.

### Step 2.2: Clean residual RAID metadata

Hetzner auction servers often have leftover RAID superblocks from previous tenants:

```bash
ssh root@<SERVER_IP> "
  DISK2=/dev/nvme1n1  # Adjust if disk order is different!
  mdadm --stop /dev/md* 2>/dev/null
  mdadm --zero-superblock \${DISK2} 2>/dev/null
  wipefs -a \${DISK2}
"
```

### Step 2.3: Create partition and format

```bash
ssh root@<SERVER_IP> "
  DISK2=/dev/nvme1n1  # Adjust if needed
  parted -s \${DISK2} mklabel gpt
  parted -s \${DISK2} mkpart primary ext4 0% 100%
  partprobe \${DISK2}
  sleep 1
  mkfs.ext4 -L longhorn-disk2 \${DISK2}p1
"
```

### Step 2.4: Mount and add to fstab

```bash
ssh root@<SERVER_IP> "
  DISK2=/dev/nvme1n1  # Adjust if needed
  mkdir -p /mnt/longhorn-disk2
  echo \"\${DISK2}p1 /mnt/longhorn-disk2 ext4 defaults 0 2\" >> /etc/fstab
  mount -a
"
```

### Step 2.5: Verify both Longhorn disks

```bash
ssh root@<SERVER_IP> "df -h | grep longhorn"
```

**Expected:**
```
/dev/nvme0n1p3  642G   28K  609G   1% /mnt/longhorn-disk1
/dev/nvme1n1p1  938G   28K  891G   1% /mnt/longhorn-disk2
```

---

## Phase 3: Configure vSwitch Network

### Step 3.1: Identify network interface

```bash
ssh root@<SERVER_IP> "ip link show | grep -E '^[0-9]+:.*state UP' | grep -v lo"
```

Common names: `eno1`, `eth0`, `enp0s31f6`

### Step 3.2: Create vSwitch netplan config

```bash
ssh root@<SERVER_IP> "
  IFACE=eno1  # Adjust based on Step 3.1
  cat > /etc/netplan/60-vswitch.yaml << EOF
network:
  version: 2
  vlans:
    vlan4000:
      id: 4000
      link: \${IFACE}
      mtu: 1400
      addresses:
        - 10.0.0.<NODE_NUMBER>/24
EOF
  chmod 600 /etc/netplan/60-vswitch.yaml
"
```

**Node IP assignments:**
| Node | vSwitch IP |
|------|------------|
| k8s-mn | 10.0.0.1 |
| k8s-02 | 10.0.0.2 |
| k8s-03 | 10.0.0.3 |
| k8s-04 | 10.0.0.4 |

### Step 3.3: Apply and verify

```bash
ssh root@<SERVER_IP> "netplan apply && sleep 2 && ip addr show vlan4000 && ping -c2 10.0.0.1"
```

---

## Phase 4: Install Kubernetes Prerequisites

### Step 4.1: Disable swap and load kernel modules

```bash
ssh root@<SERVER_IP> "
  # Disable swap
  swapoff -a
  sed -i '/swap/d' /etc/fstab

  # Load required kernel modules
  cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
  modprobe overlay
  modprobe br_netfilter

  # Set sysctl params
  cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system
"
```

### Step 4.2: Install containerd

```bash
ssh root@<SERVER_IP> "
  apt-get update
  apt-get install -y ca-certificates curl gnupg

  # Add Docker repository (for containerd)
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y containerd.io

  # Configure containerd for systemd cgroup
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd
"
```

### Step 4.3: Install kubeadm, kubelet, kubectl

```bash
ssh root@<SERVER_IP> "
  # Add Kubernetes repository
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

  apt-get update
  apt-get install -y kubelet kubeadm kubectl conntrack
  apt-mark hold kubelet kubeadm kubectl

  systemctl enable kubelet
"
```

**Note:** `conntrack` package is required for kubeadm preflight checks.

### Step 4.4: Verify installation

```bash
ssh root@<SERVER_IP> "kubeadm version && kubelet --version && kubectl version --client"
```

---

## Phase 5: Join Cluster as Control-Plane Node

### Prerequisites: Control Plane Endpoint (Load Balancer)

**BLOCKER:** Joining additional control-plane nodes requires a stable `controlPlaneEndpoint` configured in the cluster. This is a load balancer that distributes API server traffic across all control-plane nodes.

**Current state:** The cluster was initialized as single control-plane without `controlPlaneEndpoint`. Before proceeding, a load balancer must be set up.

See [Load Balancer Setup](#load-balancer-setup-for-ha-control-plane) section below.

### Step 5.1: Generate join command on existing control-plane

```bash
ssh -p 22022 root@<EXISTING_CP_IP> "
  # Create new bootstrap token
  kubeadm token create --print-join-command

  # Upload certificates and get certificate key
  kubeadm init phase upload-certs --upload-certs
"
```

### Step 5.2: Join as control-plane

```bash
ssh root@<NEW_NODE_IP> "
  kubeadm join <LB_IP_OR_DNS>:6443 \\
    --token <TOKEN> \\
    --discovery-token-ca-cert-hash sha256:<HASH> \\
    --control-plane \\
    --certificate-key <CERT_KEY>
"
```

### Step 5.3: Remove control-plane taint (allow workloads)

```bash
kubectl taint nodes <NODE_NAME> node-role.kubernetes.io/control-plane:NoSchedule-
```

---

## Phase 6: Configure Longhorn Storage

(TODO - not yet executed)

---

## Phase 7: Verification

(TODO - not yet executed)

---

## Troubleshooting

### SSH permission denied after reinstall
```bash
ssh-keygen -R <SERVER_IP>
```

### Disk appears "in use" when formatting
Residual RAID metadata from previous tenant:
```bash
mdadm --stop /dev/md*
mdadm --zero-superblock /dev/nvmeXn1p1
wipefs -a /dev/nvmeXn1
```

### vSwitch MTU issues
```bash
ip link show vlan4000 | grep mtu
# Should be 1400
```

### Disk order varies between servers
Always check `lsblk` to identify which disk has the OS before partitioning the second disk.

---

## Load Balancer Setup

See **[ADR 0043: Hetzner Load Balancer](0043-hetzner-load-balancer.md)** for full details.

### Quick Reference

| Service | LB Port | Target Port |
|---------|---------|-------------|
| kubernetes-api | 6443 | 6443 |
| https-ingress | 443 | 443 |
| http-ingress | 80 | 80 |
| gitlab-ssh | 22 | 22 |

### Setup Steps

1. Create LB in Hetzner Cloud Console (LB11, ~€5.39/month)
2. Add all nodes as targets
3. Configure 4 services above
4. Update DNS: `*.ops.last-try.org` → LB IP
5. Update kubeadm-config with `controlPlaneEndpoint: <LB_IP>:6443`
6. Regenerate API server certs, restart API server

### Current State

**Blocked:** Cluster lacks `controlPlaneEndpoint`. Must set up LB before joining k8s-03/k8s-04 as control-plane nodes.

---

## Execution Log

### k8s-03 (88.99.208.86)

| Phase | Step | Status | Notes |
|-------|------|--------|-------|
| 1 | 1.1 Verify Rescue | ✅ | `Welcome to the Hetzner Rescue System` |
| 1 | 1.2 Check disks | ✅ | 2x 954GB Samsung NVMe |
| 1 | 1.3 Check images | ✅ | Ubuntu-2404-noble-amd64-base.tar.gz |
| 1 | 1.4 Create config | ✅ | HOSTNAME=k8s-03 |
| 1 | 1.5 Run installimage | ✅ | INSTALLATION COMPLETE |
| 1 | 1.6 Reboot & verify | ✅ | Ubuntu 24.04.3 LTS |
| 2 | 2.1 Identify disk2 | ✅ | nvme1n1 (empty) |
| 2 | 2.2 Clean RAID | ✅ | md127 stopped, superblock zeroed |
| 2 | 2.3 Partition/format | ✅ | ext4 labeled longhorn-disk2 |
| 2 | 2.4 Mount | ✅ | /mnt/longhorn-disk2 |
| 2 | 2.5 Verify | ✅ | 642GB + 938GB |
| 3 | 3.1 Interface | ✅ | eno1 |
| 3 | 3.2 Netplan config | ✅ | 10.0.0.3/24 |
| 3 | 3.3 Apply & verify | ✅ | Ping to 10.0.0.1 OK |
| 4 | 4.1 Kernel modules | ✅ | overlay, br_netfilter, sysctl |
| 4 | 4.2 containerd | ✅ | v1.7.28, SystemdCgroup enabled |
| 4 | 4.3 kubeadm/kubelet | ✅ | v1.31.14 |
| 4 | 4.4 Verify | ✅ | All components ready |
| 5 | Join as CP | ⏳ | **BLOCKED: No controlPlaneEndpoint** |

### k8s-04 (116.202.39.186)

| Phase | Step | Status | Notes |
|-------|------|--------|-------|
| 1 | 1.1 Verify Rescue | ✅ | `Welcome to the Hetzner Rescue System` |
| 1 | 1.2 Check disks | ✅ | 2x 954GB Samsung NVMe |
| 1 | 1.3 Check images | ✅ | Ubuntu-2404-noble-amd64-base.tar.gz |
| 1 | 1.4 Create config | ✅ | HOSTNAME=k8s-04 |
| 1 | 1.5 Run installimage | ✅ | INSTALLATION COMPLETE |
| 1 | 1.6 Reboot & verify | ✅ | Ubuntu 24.04.3 LTS |
| 2 | 2.1 Identify disk2 | ✅ | **nvme0n1** (disk order swapped!) |
| 2 | 2.2 Clean RAID | ✅ | md127 stopped, superblock zeroed |
| 2 | 2.3 Partition/format | ✅ | ext4 labeled longhorn-disk2 |
| 2 | 2.4 Mount | ✅ | /mnt/longhorn-disk2 |
| 2 | 2.5 Verify | ✅ | 642GB + 938GB |
| 3 | 3.1 Interface | ✅ | eno1 |
| 3 | 3.2 Netplan config | ✅ | 10.0.0.4/24 |
| 3 | 3.3 Apply & verify | ✅ | Ping to 10.0.0.1 and 10.0.0.3 OK |
| 4 | 4.1 Kernel modules | ✅ | overlay, br_netfilter, sysctl |
| 4 | 4.2 containerd | ✅ | v1.7.28, SystemdCgroup enabled |
| 4 | 4.3 kubeadm/kubelet | ✅ | v1.31.14 |
| 4 | 4.4 Verify | ✅ | All components ready |
| 5 | Join as CP | ⏳ | **BLOCKED: No controlPlaneEndpoint** |

---

## References

- [Hetzner Installimage Docs](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installimage/)
- [Hetzner vSwitch Docs](https://docs.hetzner.com/robot/dedicated-server/network/vswitch/)
- [Kubernetes kubeadm join](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/)
- ADR 0007: Longhorn StorageClass Strategy
- ADR 0035: Cluster Target Architecture
