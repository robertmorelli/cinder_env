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

sed "s/__IMAGE_NAME__/$IMAGE_NAME/g" "$SUBMODULE_DIR/shims/python" > "$PYENV_BIN/python"
sed "s/__IMAGE_NAME__/$IMAGE_NAME/g" "$SUBMODULE_DIR/shims/pip"    > "$PYENV_BIN/pip"
chmod +x "$PYENV_BIN/python" "$PYENV_BIN/pip"
ln -sf python "$PYENV_BIN/python3"

echo "==> Done. Activate with:"
echo "    pyenv local cinder"
echo "    pyenv global cinder"