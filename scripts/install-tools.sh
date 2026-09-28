#!/usr/bin/env bash
# Download the CLI tools that scripts/validate.py and the git hooks need into .bin/ (git-ignored).
# OpenTofu isn't included: install it with tenv, which reads the version from .opentofu-version.
# Linux/macOS, amd64/arm64.
set -euo pipefail
cd "$(dirname "$0")/.."
HELM_VERSION=v4.3.0
KUBECONFORM_VERSION=v0.8.0

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m); case $arch in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac
mkdir -p .bin

curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-${os}-${arch}.tar.gz" \
  | tar xz -C .bin --strip-components=1 "${os}-${arch}/helm"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${os}-${arch}.tar.gz" \
  | tar xz -C .bin kubeconform

.bin/helm version --short
.bin/kubeconform -v
echo 'Add .bin to PATH for the hooks:  export PATH="$PWD/.bin:$PATH"'
