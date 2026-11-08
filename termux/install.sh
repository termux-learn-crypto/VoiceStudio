#!/data/data/com.termux/files/usr/bin/bash
# VoiceStudio — Termux installer (Android, aarch64, no root, CPU only).
#
#   curl -fsSL https://raw.githubusercontent.com/termux-learn-crypto/VoiceStudio/termux/termux/install.sh | bash
#
# Re-running is safe: it updates the checkout and skips what is installed.
set -euo pipefail

REPO_URL="${VS_REPO_URL:-https://github.com/termux-learn-crypto/VoiceStudio.git}"
BRANCH="${VS_BRANCH:-termux}"
APP_DIR="${VS_DIR:-$HOME/VoiceStudio}"
WEBUI_URL="${VS_WEBUI_URL:-https://github.com/termux-learn-crypto/VoiceStudio/releases/download/termux-webui/voicestudio-webui.tar.gz}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

case "${PREFIX:-}" in
  *com.termux*) ;;
  *) die "This script is for the Termux app on Android (PREFIX=${PREFIX:-unset})." ;;
esac
[ "$(uname -m)" = "aarch64" ] || warn "Only aarch64 is targeted; $(uname -m) may not work."

# Install each package on its own so one missing package does not stop the rest.
pkg_try() {
  local p
  for p in "$@"; do
    if dpkg -s "$p" >/dev/null 2>&1; then continue; fi
    # retry once: Android sometimes kills a long download ("Terminated")
    if pkg install -y "$p" >/dev/null 2>&1 || { sleep 2; pkg install -y "$p" >/dev/null 2>&1; }; then
      echo "  + $p"
    else
      warn "pkg '$p' not available — skipped"
    fi
  done
}

# If the selected mirror is broken, switch to Termux's main CDN automatically.
fix_mirror() {
  local sl="$PREFIX/etc/apt/sources.list"
  warn "Mirror problem — switching to packages-cf.termux.dev (backup: $sl.bak)"
  [ -f "$sl" ] && cp -f "$sl" "$sl.bak"
  echo "deb https://packages-cf.termux.dev/apt/termux-main stable main" > "$sl"
  rm -f "$PREFIX/etc/termux/chosen_mirrors" 2>/dev/null || true
  yes | pkg update -y >/dev/null 2>&1
}

say "Updating Termux packages"
if ! yes | pkg update -y >/dev/null 2>&1; then
  fix_mirror || warn "pkg update still failing — continuing (agar aage error aaye: termux-change-repo)"
fi
yes | pkg upgrade -y -o Dpkg::Options::=--force-confnew >/dev/null 2>&1 || true

say "Base tools (python, ffmpeg, git, compilers, audio libs)"
pkg_try python git ffmpeg clang binutils make cmake pkg-config \
        libsndfile portaudio libffi openssl libxml2 libxslt zlib \
        libjpeg-turbo libpng termux-api

# Rust is big (~300 MB) and is needed to compile pydantic-core (no Android
# wheel exists). Install it on its own, with output, and retry once.
say "Rust compiler (needed for pydantic-core)"
if ! command -v rustc >/dev/null 2>&1; then
  pkg install -y rust || { warn "rust install failed, fixing mirror and retrying"; fix_mirror || true; pkg install -y rust; } \
    || die "Rust install nahi hua. 'termux-change-repo' se mirror badlo, phir: pkg install rust  — aur script dobara chalao."
fi
echo "  + $(rustc --version 2>/dev/null)"

say "Enabling tur-repo (prebuilt torch / scipy for Termux)"
pkg_try tur-repo
yes | pkg update -y >/dev/null 2>&1 || true

say "Prebuilt Python packages (avoids hours of compiling)"
pkg_try python-numpy python-scipy python-pillow python-cryptography \
        python-psutil \
        python-torch python-torchaudio python-onnxruntime
# pydantic / pydantic-core / pyyaml have no Termux package: pip builds them below.
pkg_try python-torchvision   # optional

PY=python
"$PY" -c 'import torch' 2>/dev/null || die "PyTorch is not installed. Try: pkg install tur-repo && pkg install python-torch python-torchaudio  — then re-run this script."
"$PY" -c 'import torchaudio' 2>/dev/null || warn "torchaudio missing — VoiceStudio still starts, some audio features degrade."

# Build env for anything pip still has to compile.
export MATHLIB=m
export CFLAGS="${CFLAGS:-} -Wno-error=incompatible-function-pointer-types"
export LDFLAGS="${LDFLAGS:-} -lm"
ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 24)"
export ANDROID_API_LEVEL
export CARGO_BUILD_TARGET=aarch64-linux-android
# Fewer parallel jobs = less RAM; Android kills big compiles otherwise.
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export MAKEFLAGS="-j2"

say "Getting VoiceStudio ($BRANCH) into $APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$APP_DIR" checkout -q -B "$BRANCH" FETCH_HEAD
else
  # --depth 1 + no LFS blobs keeps the download small.
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"

say "Python venv (re-uses Termux's torch/numpy via --system-site-packages)"
[ -d .venv-termux ] || "$PY" -m venv --system-site-packages .venv-termux
# shellcheck disable=SC1091
. .venv-termux/bin/activate
pip install -q --upgrade pip wheel

say "Python requirements (trimmed for phones)"
if ! python -c 'import pydantic_core' 2>/dev/null; then
  warn "pydantic-core will be compiled with Rust: 10-25 min lagenge. Phone charge pe rakho, Termux band mat karo."
  command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true
fi
pip install --prefer-binary -r termux/requirements-termux.txt
pip install --prefer-binary --no-deps "huggingface_hub>=1.7"
# The repo's own `omnivoice` package is put on sys.path by the backend itself
# (core/omnivoice_path.py), so no `pip install -e .` (it would pull GPU deps).

say "Speech-to-text (optional): whisper.cpp"
if ! command -v whisper-cli >/dev/null 2>&1 && [ "${VS_SKIP_WHISPER:-0}" != 1 ]; then
  if pkg install -y whisper-cpp >/dev/null 2>&1; then echo "  + whisper-cpp (pkg)"; else
    echo "  building whisper.cpp from source (~5 min)…"
    WDIR="$HOME/.cache/whisper.cpp"
    if { [ -d "$WDIR/.git" ] || git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp "$WDIR"; } \
       && cmake -S "$WDIR" -B "$WDIR/build" -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF -DGGML_OPENMP=OFF >/dev/null \
       && cmake --build "$WDIR/build" -j2 --target whisper-cli >/dev/null \
       && install -m755 "$WDIR/build/bin/whisper-cli" "$PREFIX/bin/whisper-cli"; then
      echo "  + whisper-cli (built)"
    else
      warn "whisper.cpp build failed — speech-to-text off, baaki sab chalega."
    fi
  fi
fi

say "Light TTS engine (Supertonic 3, ONNX, CPU)"
if python -c 'import onnxruntime' 2>/dev/null; then
  pip install --prefer-binary --no-deps "supertonic>=1.3" && echo "  + supertonic"
else
  warn "onnxruntime not available (pkg python-onnxruntime). Light ONNX engines disabled;"
  warn "only torch-based engines remain (slow on a phone)."
fi

say "Web UI (prebuilt — bun/Electron cannot run on Termux)"
if [ ! -f frontend/dist/index.html ]; then
  mkdir -p frontend/dist
  if curl -fsSL "$WEBUI_URL" | tar xz -C frontend/dist; then
    echo "  + web UI installed"
  else
    warn "Could not download the web UI. The API still runs (open /docs)."
  fi
fi

chmod +x termux/run.sh
mkdir -p "$HOME/.shortcuts" 2>/dev/null && ln -sf "$APP_DIR/termux/run.sh" "$HOME/.shortcuts/VoiceStudio" 2>/dev/null || true

say "Done!"
cat <<EOF
Start it:   bash $APP_DIR/termux/run.sh
Then open:  http://127.0.0.1:3900  in your phone browser (Chrome/Firefox).
Shuru karo: bash $APP_DIR/termux/run.sh   phir browser me http://127.0.0.1:3900 kholo.
EOF
