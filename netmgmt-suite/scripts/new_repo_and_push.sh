#!/usr/bin/env bash
set -euo pipefail
REPO_NAME=${1:-netmgmt-suite}
VISIBILITY=${2:-private}   # private|public|internal
: "${GITHUB_TOKEN:=}"
USE_GH=0
if command -v gh >/dev/null 2>&1; then USE_GH=1; fi
if [[ $USE_GH -eq 0 ]]; then
  for dep in curl jq; do command -v "$dep" >/dev/null 2>&1 || { echo "Missing $dep"; exit 1; }; done
  [[ -n "$GITHUB_TOKEN" ]] || { echo "Set GITHUB_TOKEN (PAT with repo scope)"; exit 1; }
fi
if [[ $USE_GH -eq 1 ]]; then
  gh repo create "${REPO_NAME}" --${VISIBILITY} --disable-wiki --disable-issues --confirm >/dev/null
  WEB_URL=$(gh repo view "${REPO_NAME}" --json url -q .url)
  OWNER=$(gh api user --jq .login)
  SSH_URL="git@github.com:${OWNER}/${REPO_NAME}.git"
else
  API="https://api.github.com/user/repos"
  PRIV=$([[ "$VISIBILITY" == "public" ]] && echo false || echo true)
  PAYLOAD=$(printf '{"name":"%s","private":%s}' "$REPO_NAME" "$PRIV")
  RESP=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -d "$PAYLOAD" "$API")
  WEB_URL=$(echo "$RESP" | jq -r '.html_url')
  SSH_URL=$(echo "$RESP" | jq -r '.ssh_url')
fi
git init
git add .
git commit -m "Initial commit: NetBox + Nautobot + add-ons + ELK shipping" || true
git branch -M main
if git remote | grep -q '^origin$'; then git remote set-url origin "$SSH_URL"; else git remote add origin "$SSH_URL"; fi
git push -u origin main
echo "Repo: $WEB_URL"
