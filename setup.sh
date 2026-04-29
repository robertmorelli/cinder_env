#!/bin/bash
set -euo pipefail

SUBMODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="cinder-env"
BIN="$SUBMODULE_DIR/bin"

using_podman_backend() {
  local probe
  probe="$(docker images 2>&1 || true)"
  grep -qi "podman" <<<"$probe"
}

ensure_podman_socket() {
  local socket_path

  if ! command -v podman &>/dev/null; then
    return
  fi

  socket_path="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)"
  if [[ -z "$socket_path" ]]; then
    return
  fi

  if [[ ! -S "$socket_path" ]]; then
    systemctl --user start podman.socket >/dev/null 2>&1 || true
  fi

  if [[ -S "$socket_path" ]]; then
    export DOCKER_HOST="unix://$socket_path"
  fi
}

echo "==> Initializing submodules..."
git -C "$SUBMODULE_DIR" submodule update --init

if using_podman_backend; then
  IMAGE_NAME="localhost/cinder-env:latest"
  ensure_podman_socket
  echo "==> Detected Podman-backed docker; using image $IMAGE_NAME"
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    echo "==> Using DOCKER_HOST=$DOCKER_HOST"
  fi
fi

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
go build -ldflags "-X main.imageName=$IMAGE_NAME" -o "$BIN/python-shim" .

if [[ -n "${DOCKER_HOST:-}" ]]; then
  cat > "$BIN/python" << EOF
#!/bin/bash
export DOCKER_HOST="$DOCKER_HOST"
exec "$BIN/python-shim" "\$@"
EOF
else
  cat > "$BIN/python" << EOF
#!/bin/bash
exec "$BIN/python-shim" "\$@"
EOF
fi
chmod +x "$BIN/python"

cat > "$BIN/pip" << 'EOF'
#!/bin/bash
echo "pip shim is currently unsupported in cinder-env." >&2
exit 2
EOF
chmod +x "$BIN/pip"

echo "==> Done. Activate with:"
echo "    source $SUBMODULE_DIR/bin/activate"
