# GitLab repo-creds rotation (Argo CD)

Purpose: rotate the group access token used by Argo CD to access repos on
`https://gitlab.ops.last-try.org`.

## Apply method

Do **not** apply the secret manually with `kubectl apply`. This repo is GitOps‑managed;
commit the new SealedSecret and let Argo CD sync `infrastructure/argocd`.

## Procedure

1) Create a new group access token (scopes: `read_repository`, `api`, with an expiry date):

```bash
~/.claude/skills/gitlab-token/scripts/gitlab-token.sh create group-pat \
  --project "green" \
  --name "argocd-gitlab-host" \
  --expires-at "YYYY-MM-DD" \
  --host gitlab.ops.last-try.org
```

2) Regenerate the SealedSecret (only `password` encrypted; keep `url`, `username`, `type` in clear text):

```bash
TOKEN_JSON=$(~/.claude/skills/gitlab-token/scripts/gitlab-token.sh create group-pat \
  --project "green" --name "argocd-gitlab-host" --expires-at "YYYY-MM-DD" \
  --host gitlab.ops.last-try.org)
TOKEN=$(printf '%s' "$TOKEN_JSON" | jq -r '.token')

kubectl -n argocd create secret generic gitlab-ops-repo-creds \
  --from-literal=url=https://gitlab.ops.last-try.org \
  --from-literal=username=oauth2 \
  --from-literal=password="$TOKEN" \
  --from-literal=type=git \
  --dry-run=client -o yaml | \
  kubectl label --local -f - argocd.argoproj.io/secret-type=repo-creds -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/argocd/gitlab-ops-repo-creds-sealed.yaml
```

3) Commit and push. Then sync the Argo CD app that applies `infrastructure/argocd`
   (currently `argocd-ingress`).

4) Verify Argo CD apps that reference `gitlab.ops.last-try.org` are Synced.

5) Delete the old group access token in GitLab.

## Notes

- The repo‑creds secret is host‑wide; do not add per‑repo secrets for
  `green/green` or `green/green-envs`.
- Username for OAuth token auth is `oauth2`.
