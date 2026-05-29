"""Progress events for the AutoCut Studio JSON backend."""

from contextlib import contextmanager
import json
import sys
import time
from typing import Any, Dict, List

PROGRESS_PREFIX = "AUTOCUT_PROGRESS "


class ProgressEmitter:
    def __init__(self, enabled: bool):
        self.enabled = enabled
        self._last_progress = -1.0
        self._last_emit_time = 0.0

    def emit(self, stage: str, progress: float | None, message: str) -> None:
        if not self.enabled:
            return
        payload: Dict[str, Any] = {
            "stage": stage,
            "message": message,
        }
        if progress is not None:
            payload["progress"] = max(0.0, min(1.0, round(progress, 4)))

        print(
            PROGRESS_PREFIX + json.dumps(payload, ensure_ascii=False),
            file=sys.stderr,
            flush=True,
        )

    def emit_throttled(self, stage: str, progress: float, message: str) -> None:
        if not self.enabled:
            return
        now = time.monotonic()
        should_wait = (
            progress < 1.0
            and progress - self._last_progress < 0.01
            and now - self._last_emit_time < 0.5
        )
        if should_wait:
            return
        self._last_progress = progress
        self._last_emit_time = now
        self.emit(stage, progress, message)


class ProgressTqdm:
    def __init__(
        self,
        *args: Any,
        emitter: ProgressEmitter,
        base_progress: float,
        progress_span: float,
        message: str,
        **kwargs: Any,
    ):
        self.iterable = args[0] if args else kwargs.pop("iterable", None)
        self.total = kwargs.get("total")
        if self.total is None and self.iterable is not None:
            try:
                self.total = len(self.iterable)
            except TypeError:
                self.total = None
        self.disable = bool(kwargs.get("disable", False))
        self.emitter = emitter
        self.base_progress = base_progress
        self.progress_span = progress_span
        self.message = message
        self.n = 0.0
        self._emit()

    def __enter__(self) -> "ProgressTqdm":
        self._emit()
        return self

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        return None

    def __iter__(self):
        if self.iterable is None:
            return iter(())
        for item in self.iterable:
            yield item
            self.update(1)

    def update(self, amount: float = 1) -> None:
        self.n += amount
        self._emit()

    def close(self) -> None:
        return None

    def _emit(self) -> None:
        if self.disable or not self.total:
            return
        ratio = max(0.0, min(1.0, self.n / self.total))
        progress = self.base_progress + self.progress_span * ratio
        percent = int(round(progress * 100))
        self.emitter.emit_throttled(
            "transcribing", progress, f"{self.message} {percent}%"
        )


@contextmanager
def install_progress_tqdm(
    emitter: ProgressEmitter,
    base_progress: float,
    progress_span: float,
    message: str,
):
    if not emitter.enabled:
        yield
        return

    patched: List[tuple[Any, str, Any]] = []

    def factory(*args: Any, **kwargs: Any) -> ProgressTqdm:
        return ProgressTqdm(
            *args,
            emitter=emitter,
            base_progress=base_progress,
            progress_span=progress_span,
            message=message,
            **kwargs,
        )

    try:
        import whisper as openai_whisper

        tqdm_module = openai_whisper.transcribe.__globals__.get("tqdm")
        if tqdm_module is not None and hasattr(tqdm_module, "tqdm"):
            patched.append((tqdm_module, "tqdm", tqdm_module.tqdm))
            tqdm_module.tqdm = factory
    except Exception:
        pass

    try:
        from . import whisper_model

        patched.append((whisper_model, "tqdm", whisper_model.tqdm))
        whisper_model.tqdm = factory
    except Exception:
        pass

    try:
        yield
    finally:
        for target, name, original in reversed(patched):
            setattr(target, name, original)
