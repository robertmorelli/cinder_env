#!/bin/bash
set -e

SUBMODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="cinder-env"
PYENV_VERSION="cinder"
PYENV_BIN="$HOME/.pyenv/versions/$PYENV_VERSION/bin"

echo "==> Building Cinder image..."
docker build --platform linux/amd64 -t "$IMAGE_NAME" "$SUBMODULE_DIR"

echo "==> Installing pyenv shims..."
mkdir -p "$PYENV_BIN"

if ! command -v go &>/dev/null; then
  echo "Error: 'go' is required to build the python shim. Install from https://go.dev/dl/" >&2
  exit 1
fi

echo "==> Building python shim..."
cd "$SUBMODULE_DIR/shim"
go mod tidy
go build -ldflags "-X main.imageName=$IMAGE_NAME" -o "$PYENV_BIN/python" .
ln -sf python "$PYENV_BIN/python3"

sed "s/__IMAGE_NAME__/$IMAGE_NAME/g" "$SUBMODULE_DIR/shims/pip" > "$PYENV_BIN/pip"
chmod +x "$PYENV_BIN/pip"

echo "==> Done. Activate with:"
echo "    pyenv local cinder"
echo "    pyenv global cinder"