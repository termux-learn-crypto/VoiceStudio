#!/data/data/com.termux/files/usr/bin/bash
# Start VoiceStudio on Termux: CPU only, bound to this phone (127.0.0.1).
#   bash ~/VoiceStudio/termux/run.sh            # port 3900
#   VS_PORT=8080 bash ~/VoiceStudio/termux/run.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${VS_PORT:-${OMNIVOICE_PORT:-3900}}"
HOST="${VS_HOST:-127.0.0.1}"
cd "$APP_DIR"

if [ -f .venv-termux/bin/activate ]; then
  # shellcheck disable=SC1091
  . .venv-termux/bin/activate
else
  echo "[x] Not installed yet. Run termux/install.sh first." >&2
  exit 1
fi

export OMNIVOICE_TERMUX=1
export OMNIVOICE_DEVICE="${OMNIVOICE_DEVICE:-cpu}"
export OMNIVOICE_PORT="$PORT"
export OMNIVOICE_BIND_HOST="$HOST"
export OMNIVOICE_DATA_DIR="${OMNIVOICE_DATA_DIR:-$HOME/.voicestudio}"
export OMNIVOICE_CACHE_DIR="${OMNIVOICE_CACHE_DIR:-$HOME/.voicestudio/models}"
mkdir -p "$OMNIVOICE_DATA_DIR" "$OMNIVOICE_CACHE_DIR"

python - <<'PY' || { echo "[x] PyTorch import failed — re-run termux/install.sh" >&2; exit 1; }
import torch
print(f"torch {torch.__version__} (CPU)")
PY

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
  trap 'command -v termux-wake-unlock >/dev/null && termux-wake-unlock' EXIT
fi

URL="http://127.0.0.1:${PORT}"
echo
echo "  VoiceStudio is starting (first start can take 1-3 minutes)…"
echo "  Open in your phone browser / Browser me kholo:  $URL"
echo "  API docs: $URL/docs      Stop / band karo: Ctrl+C"
echo
if command -v termux-open-url >/dev/null 2>&1 && [ "${VS_OPEN_BROWSER:-1}" = "1" ]; then
  ( sleep 25; termux-open-url "$URL" >/dev/null 2>&1 || true ) &
fi

exec python -m uvicorn backend.main:app --host "$HOST" --port "$PORT" --workers 1
