# VoiceStudio on Termux (Android) — phone pe chalao

Unofficial Termux port of [debpalash/VoiceStudio](https://github.com/debpalash/VoiceStudio).
CPU only, no root. Upstream's official Android option is the APK; this branch is for people
who want the full Python backend + web UI inside Termux.

> ⚠️ **Status: experimental, not yet tested on a real phone.** The scripts were checked
> statically (shellcheck, `py_compile`) only. Please open an issue on this fork with your
> phone model + error log if something breaks.
>
> ⚠️ **Status: experimental — abhi real phone pe test nahi hua.** Kuch toote to fork pe issue
> kholo, phone ka model aur error log ke saath.

---

## 1. Requirements / Kya chahiye

| | Minimum | Recommended |
|---|---|---|
| Android | 7+ (Termux from **F-Droid / GitHub**, not Play Store) | 10+ |
| CPU | aarch64 (64-bit ARM) | Snapdragon 8xx / Dimensity 8000+ |
| RAM | 4 GB | 8 GB+ |
| Free storage | ~4 GB (Termux packages + torch + venv) | 8 GB+ (models alag se) |

English: torch alone is ~1 GB installed. Each voice model downloads on first use (Supertonic ≈ 250 MB, bigger engines 1–4 GB).
Hinglish: Sirf torch hi ~1 GB leta hai. Har voice model pehli baar use karne pe download hota hai (Supertonic ≈ 250 MB, bade engines 1–4 GB).

## 2. Install — one command / ek command

Open Termux and paste / Termux kholo aur paste karo:

```bash
curl -fsSL https://raw.githubusercontent.com/termux-learn-crypto/VoiceStudio/termux/termux/install.sh | bash
```

Or with git / ya git se:

```bash
pkg install -y git && git clone --depth 1 -b termux https://github.com/termux-learn-crypto/VoiceStudio ~/VoiceStudio && bash ~/VoiceStudio/termux/install.sh
```

Takes 10–40 minutes depending on network and phone (some packages may compile).
Network aur phone ke hisaab se 10–40 minute lagenge (kuch packages compile ho sakte hain). Phone charging pe rakho.

What it does / Ye kya karta hai:
- `pkg install` python, ffmpeg, git, clang, rust, libsndfile, portaudio, whisper-cpp …
- enables **tur-repo** and installs prebuilt `python-torch`, `python-torchaudio`, `python-numpy`, `python-scipy`, `python-onnxruntime`
- makes a venv (`.venv-termux`, reuses those system packages) and pip-installs `termux/requirements-termux.txt` (GPU / desktop deps removed)
- installs **Supertonic 3** (small ONNX TTS) as the default phone engine
- downloads a prebuilt web UI (bun/Electron don't run on Termux)

## 3. Run / Chalao

```bash
bash ~/VoiceStudio/termux/run.sh
```

Then open **http://127.0.0.1:3900** in Chrome/Firefox on the same phone.
Phir usi phone ke browser me **http://127.0.0.1:3900** kholo. Band karne ke liye Termux me `Ctrl+C`.

- Server binds to `127.0.0.1` only — not visible on Wi-Fi. (Want LAN access? `VS_HOST=0.0.0.0 bash termux/run.sh` — only on a trusted network.)
- Server sirf `127.0.0.1` pe chalta hai — Wi-Fi pe dusre nahi dekh sakte.
- Different port / alag port: `VS_PORT=8080 bash ~/VoiceStudio/termux/run.sh`
- `termux-wake-lock` is taken automatically so Android doesn't kill it. Also disable battery optimisation for Termux.
- Data & models: `~/.voicestudio/`

## 4. What works / Kya chalega (expected)

| Feature | Phone pe | Note |
|---|---|---|
| Web UI, projects, voice library, settings | ✅ likely | served by the Python backend |
| Text-to-speech with **Supertonic 3** (ONNX) | ✅ likely | default on Termux; needs `python-onnxruntime` |
| KittenTTS / Sherpa-ONNX (Piper, Kokoro) | ⚠️ maybe | only if you manage to install them; picked automatically if importable |
| Speech-to-text via **whisper.cpp** | ⚠️ maybe | uses Termux's `whisper-cli` (`pkg install whisper-cpp`) |
| Audio convert / trim (ffmpeg) | ✅ likely | Termux `ffmpeg` is used instead of the bundled glibc one |
| OmniVoice / torch voice cloning on CPU | 🐢 slow | works only if TUR torch installs; expect minutes per sentence, high RAM |
| Big engines (CosyVoice, IndexTTS2, VoxCPM2, Dots, MOSS) | ❌ | too heavy / CUDA / separate glibc venvs |
| WhisperX, faster-whisper, diarization (pyannote), Demucs stem split | ❌ | no Android builds (ctranslate2, etc.) |
| Dubbing pipeline, translation (argos), audio FX (pedalboard), watermark (audioseal) | ❌ / partial | deps dropped; UI should show the engine/feature as unavailable |
| GGUF native engines (omnivoice-gguf, cosyvoice-gguf) | ❌ | prebuilt binaries are glibc, not Android |
| Electron desktop app, MCP server, LiteLLM cloud routing | ❌ | dropped from the phone install |
| GPU (Adreno/Mali) | ❌ | CPU only |

Hinglish: Basic TTS (Supertonic) aur web UI chalne ki ummeed hai. Bade models, GPU, dubbing,
diarization, Demucs — phone pe nahi chalenge.

## 5. Code changes in this branch

- `backend/core/termux.py` — detects Termux (`com.termux` in `$PREFIX`), sets CPU-only, loopback,
  small thread pools, Termux ffmpeg, `HF_HUB_DISABLE_XET`; picks the lightest installed TTS engine.
- `backend/main.py` — calls `apply_defaults()` first thing (no-op off Termux).
- `backend/core/device_caps.py` — device override returns `cpu` on Termux.
- `backend/services/tts_backend.py` — default TTS engine on Termux = lightest installed (Supertonic 3 → KittenTTS → Sherpa-ONNX), else upstream default. Your Settings choice / `OMNIVOICE_TTS_BACKEND` still wins.
- `termux/install.sh`, `termux/run.sh`, `termux/requirements-termux.txt`, this README.

## 6. Troubleshooting / Dikkat aaye to

- **`PyTorch is not installed`** → `pkg install tur-repo && pkg update && pkg install python-torch python-torchaudio`, then re-run install.sh. If TUR's torch is built for a different Python version than Termux's `python`, wait for TUR to update.
- **pip compiling Rust forever (pydantic-core etc.)** → it's normal the first time (5–20 min). Keep the phone on charge, screen on.
- **`soundfile` can't find libsndfile** → `pkg install libsndfile`.
- **Killed / app closed** → low RAM. Close other apps, use Supertonic only, disable battery optimisation for Termux.
- **Logs** → the Termux window, and `~/.voicestudio/`.

Update / naya version: re-run the install command — it pulls the latest `termux` branch.
