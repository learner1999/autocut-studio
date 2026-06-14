# Modified for AutoCut Studio: package version and public exports for this
# derivative desktop app.

__version__ = "0.1.0"

from .type import LANG, WhisperModel, WhisperMode

__all__ = ["Transcribe", "load_audio", "WhisperMode", "WhisperModel", "LANG"]


def __getattr__(name):
    if name == "load_audio":
        from .utils import load_audio

        return load_audio
    if name == "Transcribe":
        from .package_transcribe import Transcribe

        return Transcribe
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
