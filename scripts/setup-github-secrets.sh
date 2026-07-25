#!/usr/bin/env bash
# One-time helper: push the secrets the release workflow needs to GitHub.
#
# No secret values live in this script or in the repo — it reads .env.local
# (gitignored) and prompts for the .p12 password.
#
# Prereqs:
#   1. `gh` authenticated as the account that owns the repo:
#          gh auth login
#   2. Export your Developer ID Application cert *with its private key*:
#          Keychain Access → My Certificates → right-click
#          "Developer ID Application: … (TEAMID)" → Export → save as a .p12
#   3. Copy .env.local.example to .env.local and fill it in.
#
# Usage:
#   ./scripts/setup-github-secrets.sh /path/to/cert.p12
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
P12="${1:?usage: $0 /path/to/cert.p12}"
ENV_FILE="${ENV_FILE:-.env.local}"

[ -n "$REPO" ]     || { echo "✗ set REPO=owner/name (gh could not detect it)" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "✗ $ENV_FILE not found — copy .env.local.example" >&2; exit 1; }
[ -f "$P12" ]      || { echo "✗ p12 not found: $P12" >&2; exit 1; }

echo "==> target repo: $REPO"
gh repo view "$REPO" >/dev/null 2>&1 || {
    echo "✗ gh cannot access $REPO — run: gh auth login" >&2; exit 1; }

# Parse line-by-line rather than sourcing: DEVELOPER_ID_APP holds spaces and
# parens ("… (TEAMID)"), which `source` would glob and word-split.
envval() { grep "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2-; }
DEVELOPER_ID_APP="$(envval DEVELOPER_ID_APP)"
NOTARY_APPLE_ID="$(envval NOTARY_APPLE_ID)"
NOTARY_TEAM_ID="$(envval NOTARY_TEAM_ID)"
NOTARY_PASSWORD="$(envval NOTARY_PASSWORD)"
: "${DEVELOPER_ID_APP:?missing in $ENV_FILE}"
: "${NOTARY_APPLE_ID:?missing in $ENV_FILE}"
: "${NOTARY_TEAM_ID:?missing in $ENV_FILE}"
: "${NOTARY_PASSWORD:?missing in $ENV_FILE}"

read -r -s -p "Password you set when exporting the .p12: " P12_PWD; echo

echo "==> setting secrets on $REPO"
gh secret set DEVELOPER_ID_APP      --repo "$REPO" --body "$DEVELOPER_ID_APP"
gh secret set NOTARY_APPLE_ID       --repo "$REPO" --body "$NOTARY_APPLE_ID"
gh secret set NOTARY_TEAM_ID        --repo "$REPO" --body "$NOTARY_TEAM_ID"
gh secret set NOTARY_PASSWORD       --repo "$REPO" --body "$NOTARY_PASSWORD"
gh secret set MACOS_CERTIFICATE_PWD --repo "$REPO" --body "$P12_PWD"
gh secret set MACOS_CERTIFICATE_P12 --repo "$REPO" --body "$(base64 -i "$P12")"

echo
echo "Done. Cut a release with:"
echo "  git tag v2.0.0 && git push origin v2.0.0"
