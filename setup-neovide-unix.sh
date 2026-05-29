#!/usr/bin/env sh
set -eu

CLIENT_OS="${1:-}"

case "$CLIENT_OS" in
  linux|macos) ;;
  *)
    echo "usage: sh setup-neovide-unix.sh <linux|macos>" >&2
    exit 1
    ;;
esac

mkdir -p "$HOME/.local/bin"

# Add ~/.local/bin to shell rc for bash/zsh users.
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

touch "$SHELL_RC"

if ! grep -q 'HOME/.local/bin' "$SHELL_RC"; then
  cat >> "$SHELL_RC" <<'RC'

export PATH="$HOME/.local/bin:$PATH"
RC
fi

if [ "$CLIENT_OS" = "linux" ]; then
  mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
  mkdir -p "$HOME/.local/share/applications"

  curl -fsSL \
    https://raw.githubusercontent.com/neovide/neovide/main/assets/neovide.svg \
    -o "$HOME/.local/share/icons/hicolor/scalable/apps/neovide.svg"

  NEOVIDE_BIN="$(command -v neovide)"

  cat > "$HOME/.local/share/applications/neovide.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Neovide
Exec=$NEOVIDE_BIN %F
Icon=neovide
Terminal=false
Categories=Utility;TextEditor;
StartupWMClass=neovide
DESKTOP

  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

{
cat <<HEADER
#!/usr/bin/env sh
set -eu

CLIENT_OS="$CLIENT_OS"
HEADER

cat <<'SCRIPT'

if [ "$#" -lt 2 ]; then
  echo "usage: neovide-remote <ssh-host-alias> <port>" >&2
  echo "example: neovide-remote emu 6666" >&2
  exit 1
fi

HOST="$1"
PORT="$2"

case "$PORT" in
  *[!0-9]*|"")
    echo "error: port must be numeric" >&2
    exit 1
    ;;
esac

TAG="$(printf '%s_%s' "$HOST" "$PORT" | sed 's/[^A-Za-z0-9_.-]/_/g')"
MAIN_LOG="/tmp/neovide-remote-${TAG}.log"
CLIENT_LOG="/tmp/neovide-remote-client-${TAG}.log"

if [ "${NEOVIDE_REMOTE_DETACHED:-0}" != "1" ]; then
  SCRIPT_PATH="$0"
  case "$SCRIPT_PATH" in
    */*) ;;
    *) SCRIPT_PATH="$(command -v "$SCRIPT_PATH")" ;;
  esac

  if [ "$CLIENT_OS" = "linux" ] && command -v setsid >/dev/null 2>&1; then
    setsid -f env NEOVIDE_REMOTE_DETACHED=1 "$SCRIPT_PATH" "$HOST" "$PORT" \
      >"$MAIN_LOG" 2>&1
  else
    nohup env NEOVIDE_REMOTE_DETACHED=1 "$SCRIPT_PATH" "$HOST" "$PORT" \
      >"$MAIN_LOG" 2>&1 </dev/null &
  fi

  exit 0
fi

find_neovide() {
  if [ "$CLIENT_OS" = "macos" ]; then
    if [ -x "/Applications/Neovide.app/Contents/MacOS/neovide" ]; then
      printf '%s\n' "/Applications/Neovide.app/Contents/MacOS/neovide"
      return
    fi

    if [ -x "$HOME/Applications/Neovide.app/Contents/MacOS/neovide" ]; then
      printf '%s\n' "$HOME/Applications/Neovide.app/Contents/MacOS/neovide"
      return
    fi
  fi

  command -v neovide
}

NEOVIDE_BIN="$(find_neovide)"
ICON="$HOME/.local/share/icons/hicolor/scalable/apps/neovide.svg"

ssh -nN \
  -o ExitOnForwardFailure=yes \
  -L "127.0.0.1:${PORT}:127.0.0.1:${PORT}" \
  "$HOST" &

TUNNEL_PID=$!

cleanup() {
  kill "$TUNNEL_PID" 2>/dev/null || true
  ssh "$HOST" "fuser -k ${PORT}/tcp >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

REMOTE_LAUNCHER="
if command -v bash >/dev/null 2>&1; then
  exec bash -s -- ${PORT}
elif command -v zsh >/dev/null 2>&1; then
  exec zsh -f -s -- ${PORT}
else
  exec sh -s -- ${PORT}
fi
"

ssh "$HOST" "$REMOTE_LAUNCHER" <<'REMOTE'
set -eu
(set -o pipefail) 2>/dev/null || true

PORT="$1"

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  nvm use --silent default >/dev/null
fi

export PATH="$HOME/neovim/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
fi

cd "$HOME"

if [ -x "$HOME/neovim/bin/nvim" ]; then
  REMOTE_NVIM="$HOME/neovim/bin/nvim"
else
  REMOTE_NVIM="$(command -v nvim 2>/dev/null || true)"
fi

if [ -z "${REMOTE_NVIM:-}" ]; then
  echo "ERROR: could not find remote nvim" >&2
  exit 1
fi

rm -f "/tmp/neovide-nvim-${PORT}.log"

nohup "$REMOTE_NVIM" \
  --headless \
  --listen "127.0.0.1:${PORT}" \
  --cmd 'let g:neovide_detach_on_quit = "always_quit"' \
  >"/tmp/neovide-nvim-${PORT}.log" 2>&1 &
REMOTE

i=0
while [ "$i" -lt 50 ]; do
  if ssh "$HOST" "if command -v ss >/dev/null 2>&1; then ss -ltn | grep -q '127.0.0.1:${PORT}'; else netstat -an 2>/dev/null | grep -q '127.0.0.1.*${PORT}.*LISTEN'; fi"; then
    if [ "$CLIENT_OS" = "linux" ] && [ -f "$ICON" ]; then
      if "$NEOVIDE_BIN" --help 2>&1 | grep -q -- '--wayland_app_id'; then
        "$NEOVIDE_BIN" \
          --server "127.0.0.1:${PORT}" \
          --icon "$ICON" \
          --wayland_app_id neovide \
          2>"$CLIENT_LOG"
      else
        "$NEOVIDE_BIN" \
          --server "127.0.0.1:${PORT}" \
          --icon "$ICON" \
          2>"$CLIENT_LOG"
      fi
    else
      "$NEOVIDE_BIN" \
        --server "127.0.0.1:${PORT}" \
        2>"$CLIENT_LOG"
    fi

    exit 0
  fi

  i=$((i + 1))
  sleep 0.1
done

echo "remote nvim did not start on 127.0.0.1:${PORT}" >&2
echo "remote log:" >&2
ssh "$HOST" "cat /tmp/neovide-nvim-${PORT}.log 2>/dev/null || true" >&2
exit 1
SCRIPT
} > "$HOME/.local/bin/neovide-remote"

chmod +x "$HOME/.local/bin/neovide-remote"

echo "Done."
echo "Use:"
echo "  neovide-remote emu 6666"
echo "  neovide-remote otherhost 6667"
