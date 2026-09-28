#!/usr/bin/env bash
# Git hook: refuse to commit a plaintext Kubernetes Secret or anything from .secrets/.
# SealedSecrets (kind: SealedSecret) are fine; templates in scripts/secret-templates/ only hold
# placeholders and are allowed.
set -euo pipefail
status=0
for f in "$@"; do
  case $f in
    .secrets/README.md) continue ;;
    .secrets/*) echo "BLOCKED: $f is in .secrets/ (plaintext, never commit it)"; status=1; continue ;;
    scripts/secret-templates/*) continue ;;
  esac
  [[ -f $f ]] || continue
  if grep -Eq '^kind:[[:space:]]*Secret[[:space:]]*$' "$f"; then
    echo "BLOCKED: $f contains a plaintext 'kind: Secret'. Seal it: scripts/secrets.sh seal"
    status=1
  fi
done
exit $status
