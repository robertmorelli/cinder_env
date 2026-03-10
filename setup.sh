#!/bin/bash
set -e

SUBMODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="cinder-env"
BIN="$SUBMODULE_DIR/bin"

echo "==> Initializing submodules..."
git -C "$SUBMODULE_DIR" submodule update --init

echo "==> Building Cinder image..."
docker build --platform linux/amd64 -t "$IMAGE_NAME" "$SUBMODULE_DIR"

if ! command -v go &>/dev/null; then
  echo "Error: 'go' is required to build the python shim. Install from https://go.dev/dl/" >&2
  exit 1
fi

echo "==> Building python shim..."
mkdir -p "$BIN"
cd "$SUBMODULE_DIR/shim"
go mod tidy
go build -ldflags "-X main.imageName=$IMAGE_NAME" -o "$BIN/python" .
ln -sf python "$BIN/python3"

sed "s/__IMAGE_NAME__/$IMAGE_NAME/g" "$SUBMODULE_DIR/shims/pip" > "$BIN/pip"
chmod +x "$BIN/pip"

echo "==> Done. Activate with:"
echo "    source $SUBMODULE_DIR/activate"
