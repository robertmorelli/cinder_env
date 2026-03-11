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
rm -f "$BIN/python3"

cat > "$BIN/pip" << EOF
#!/bin/bash
if ! docker info > /dev/null 2>&1; then
  echo '("docker error", "Docker daemon is not running", "")' >&2
  exit 1
fi
exec docker run --rm -i -v "\$(pwd):/app" -w /app $IMAGE_NAME pip "\$@"
EOF
chmod +x "$BIN/pip"

echo "==> Done. Activate with:"
echo "    source $SUBMODULE_DIR/bin/activate"
