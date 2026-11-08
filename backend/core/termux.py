"""Termux (Android, aarch64, no root) support helpers.

Everything here is a no-op off Termux. On Termux it only *defaults* settings
(``os.environ.setdefault``), so an explicit env var or Settings choice still
wins. Detection follows Termux's own convention: ``$PREFIX`` lives under
``/data/data/com.termux/``.
"""

from __future__ import annotations

import importlib.util
import os
import shutil

#: Light, CPU-friendly TTS engines in the order we prefer them on a phone.
#: Each entry is (engine id, python module that must be importable).
_LIGHT_TTS_ENGINES: tuple[tuple[str, str], ...] = (
    ("supertonic3", "supertonic"),  # ONNX, ~66M params, needs onnxruntime
    ("kittentts", "kittentts"),  # ONNX, ~80 MB
    ("sherpa-onnx", "sherpa_onnx"),  # Piper/Kokoro/VITS via OMNIVOICE_SHERPA_MODEL
)


def is_termux() -> bool:
    """True when running inside the Termux app on Android."""
    if os.environ.get("OMNIVOICE_TERMUX", "").strip().lower() in {"1", "true", "yes"}:
        return True
    return "com.termux" in os.environ.get("PREFIX", "")


def _has_module(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except Exception:  # noqa: BLE001 - a broken package must not break startup
        return False


def default_tts_backend() -> str | None:
    """Lightest installed TTS engine on Termux, else None (use upstream default)."""
    if not is_termux():
        return None
    for engine_id, module in _LIGHT_TTS_ENGINES:
        if engine_id == "sherpa-onnx" and not os.environ.get("OMNIVOICE_SHERPA_MODEL"):
            continue
        if _has_module(module):
            return engine_id
    return None


def apply_defaults() -> None:
    """Set phone-friendly defaults before torch / model code is imported."""
    if not is_termux():
        return
    env = os.environ
    # No CUDA/ROCm/MPS on a phone: never probe for them.
    env.setdefault("OMNIVOICE_DEVICE", "cpu")
    env.setdefault("CUDA_VISIBLE_DEVICES", "")
    env.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "0")
    # Bind to the phone only (run.sh passes --host too).
    env.setdefault("OMNIVOICE_BIND_HOST", "127.0.0.1")
    # Keep thread pools small so the phone stays responsive / cool.
    threads = str(max(1, min(4, (os.cpu_count() or 4) // 2)))
    for var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
        env.setdefault(var, threads)
    # imageio-ffmpeg's bundled binary is glibc-only; use Termux's ffmpeg.
    prefix = env.get("PREFIX", "")
    for tool, var in (("ffmpeg", "FFMPEG_PATH"), ("ffprobe", "FFPROBE_PATH")):
        path = shutil.which(tool) or (os.path.join(prefix, "bin", tool) if prefix else "")
        if path and os.path.isfile(path):
            env.setdefault(var, path)
            if tool == "ffmpeg":
                env.setdefault("IMAGEIO_FFMPEG_EXE", path)
    # hf-xet is a Rust extension with no Android wheel.
    env.setdefault("HF_HUB_DISABLE_XET", "1")
    env.setdefault("TORCHAUDIO_USE_TORCHCODEC", "0")
