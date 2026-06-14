# Added for AutoCut Studio: JSON backend used by the native macOS app.

from __future__ import annotations

import argparse
import array
from contextlib import redirect_stdout
import json
import math
import os
import subprocess
import sys
from datetime import timedelta
from typing import TYPE_CHECKING, Any, Dict, List

if TYPE_CHECKING:
    import srt

    from .app_project import AutoCutProject


def _print_json(payload: Dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def _ffprobe(media_path: str) -> Dict[str, Any]:
    cmd = [
        "ffprobe",
        "-hide_banner",
        "-loglevel",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        media_path,
    ]
    raw = subprocess.check_output(cmd, text=True)
    data = json.loads(raw)
    audio_stream = next(
        (
            stream
            for stream in data.get("streams", [])
            if stream.get("codec_type") == "audio"
        ),
        {},
    )
    fmt = data.get("format", {})
    return {
        "mediaPath": os.path.abspath(media_path),
        "duration": float(fmt.get("duration") or 0),
        "format": fmt.get("format_name", ""),
        "codec": audio_stream.get("codec_name", ""),
        "sampleRate": int(audio_stream.get("sample_rate") or 0),
        "channels": int(audio_stream.get("channels") or 0),
    }


def _waveform(media_path: str, samples: int) -> Dict[str, Any]:
    cmd = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        media_path,
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-ac",
        "1",
        "-ar",
        "8000",
        "-",
    ]
    raw = subprocess.check_output(cmd)
    audio = array.array("h")
    audio.frombytes(raw)
    if sys.byteorder != "little":
        audio.byteswap()

    if not audio:
        peaks: List[float] = []
    else:
        bucket_size = max(1, math.ceil(len(audio) / max(samples, 1)))
        peaks = [
            min(
                1.0,
                max(abs(sample) for sample in audio[offset : offset + bucket_size])
                / 32768.0,
            )
            for offset in range(0, len(audio), bucket_size)
        ]
    return {"mediaPath": os.path.abspath(media_path), "samples": peaks}


def _detect_silence_ranges(
    audio: Any,
    sampling_rate: int,
    duration: float,
    min_silence: float = 0.80,
    frame_seconds: float = 0.05,
    hop_seconds: float = 0.025,
) -> List[tuple[float, float]]:
    import numpy as np

    if len(audio) == 0:
        return []

    frame_length = max(1, int(frame_seconds * sampling_rate))
    hop_length = max(1, int(hop_seconds * sampling_rate))
    starts = np.arange(0, max(1, len(audio) - frame_length + 1), hop_length)
    ends = np.minimum(starts + frame_length, len(audio))

    squared = np.square(audio.astype(np.float64))
    cumsum = np.concatenate(([0.0], np.cumsum(squared)))
    rms = np.sqrt((cumsum[ends] - cumsum[starts]) / np.maximum(1, ends - starts))
    finite_rms = rms[np.isfinite(rms)]
    if finite_rms.size == 0:
        return []

    adaptive_threshold = float(np.percentile(finite_rms, 20)) * 2.5
    threshold = min(max(adaptive_threshold, 0.006), 0.020)
    silent = rms <= threshold

    ranges: List[tuple[float, float]] = []
    run_start: int | None = None
    for index, is_silent in enumerate(silent):
        if is_silent and run_start is None:
            run_start = index
        elif not is_silent and run_start is not None:
            start = starts[run_start] / sampling_rate
            end = ends[index - 1] / sampling_rate
            if end - start >= min_silence:
                ranges.append((start, min(end, duration)))
            run_start = None
    if run_start is not None:
        start = starts[run_start] / sampling_rate
        end = ends[-1] / sampling_rate
        if end - start >= min_silence:
            ranges.append((start, min(end, duration)))

    return ranges


def _transcribe(
    media_path: str, args: argparse.Namespace, progress: ProgressEmitter
) -> AutoCutProject:
    from . import utils
    from .app_progress import install_progress_tqdm
    from .app_project import ProjectSettings, project_from_subtitles
    from .package_transcribe import Transcribe

    sampling_rate = 16000
    progress.emit("loading_audio", 0.02, "Loading audio...")
    audio = utils.load_audio(media_path, sr=sampling_rate)
    progress.emit("loading_model", 0.08, f"Loading Whisper {args.model} model...")
    transcriber = Transcribe(
        whisper_model_size=args.model,
        vad=args.vad != "0",
        device=args.device,
    )
    progress.emit("transcribing", 0.15, "Transcribing 15%")
    with install_progress_tqdm(progress, 0.15, 0.70, "Transcribing"):
        results = transcriber.run(audio, args.lang, args.prompt)
    progress.emit("formatting", 0.86, "Detecting silence and formatting subtitles...")
    subtitles = transcriber.format_results_to_srt(results)
    duration = _ffprobe(media_path)["duration"]
    silence_ranges = _detect_silence_ranges(audio, sampling_rate, duration)
    settings = ProjectSettings(
        lang=args.lang,
        whisperModel=args.model,
        padHead=args.pad_head,
        padTail=args.pad_tail,
        mergeGap=args.merge_gap,
        bitrate=args.bitrate,
    )
    project = project_from_subtitles(
        media_path,
        duration,
        subtitles,
        settings=settings,
        silence_ranges=silence_ranges,
    )
    progress.emit("complete", 1.0, "Transcription complete.")
    return project


def _retranscribe_range(
    media_path: str, args: argparse.Namespace, progress: ProgressEmitter
) -> Dict[str, Any]:
    from . import utils
    from .app_progress import install_progress_tqdm
    from .package_transcribe import Transcribe

    sampling_rate = 16000
    progress.emit("loading_audio", 0.05, "Loading audio range...")
    audio = utils.load_audio(media_path, sr=sampling_rate)
    start_index = max(0, int(args.start * sampling_rate))
    end_index = min(len(audio), int(args.end * sampling_rate))
    if end_index <= start_index:
        raise ValueError("Range end must be after range start")

    progress.emit("loading_model", 0.15, f"Loading Whisper {args.model} model...")
    transcriber = Transcribe(
        whisper_model_size=args.model,
        vad=False,
        device=args.device,
    )
    progress.emit("transcribing", 0.25, "Retranscribing 25%")
    with install_progress_tqdm(progress, 0.25, 0.65, "Retranscribing"):
        results = transcriber.run(audio[start_index:end_index], args.lang, args.prompt)
    progress.emit("formatting", 0.92, "Formatting retranscription...")
    subtitles = transcriber.format_results_to_srt(results)
    segments = []
    text_parts = []
    for subtitle in subtitles:
        text = subtitle.content.strip()
        if text.lower() == "< no speech >":
            continue
        text_parts.append(text)
        segments.append(
            {
                "start": args.start + subtitle.start.total_seconds(),
                "end": args.start + subtitle.end.total_seconds(),
                "text": text,
            }
        )
    progress.emit("complete", 1.0, "Retranscription complete.")
    return {"text": " ".join(text_parts).strip(), "segments": segments}


def _project_to_subtitles(project: AutoCutProject) -> List[srt.Subtitle]:
    import srt

    subtitles = []
    for index, segment in enumerate(project.segments, start=1):
        subtitles.append(
            srt.Subtitle(
                index=index,
                start=timedelta(seconds=segment.start),
                end=timedelta(seconds=segment.end),
                content=segment.text,
            )
        )
    return subtitles


def main() -> None:
    parser = argparse.ArgumentParser(description="AutoCut Studio JSON backend")
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe = subparsers.add_parser("probe")
    probe.add_argument("--media", required=True)

    waveform = subparsers.add_parser("waveform")
    waveform.add_argument("--media", required=True)
    waveform.add_argument("--samples", type=int, default=2400)

    transcribe = subparsers.add_parser("transcribe")
    transcribe.add_argument("--media", required=True)
    transcribe.add_argument("--lang", default="en")
    transcribe.add_argument("--model", default="base")
    transcribe.add_argument("--prompt", default="")
    transcribe.add_argument("--vad", default="0", choices=["0", "1", "auto"])
    transcribe.add_argument("--device", default="cpu")
    transcribe.add_argument("--pad-head", type=float, default=0.20)
    transcribe.add_argument("--pad-tail", type=float, default=0.45)
    transcribe.add_argument("--merge-gap", type=float, default=0.50)
    transcribe.add_argument("--bitrate", default="192k")
    transcribe.add_argument("--output")
    transcribe.add_argument("--progress", action="store_true")

    retranscribe = subparsers.add_parser("retranscribe-range")
    retranscribe.add_argument("--media", required=True)
    retranscribe.add_argument("--start", type=float, required=True)
    retranscribe.add_argument("--end", type=float, required=True)
    retranscribe.add_argument("--lang", default="en")
    retranscribe.add_argument("--model", default="base")
    retranscribe.add_argument("--prompt", default="")
    retranscribe.add_argument("--device", default="cpu")
    retranscribe.add_argument("--progress", action="store_true")

    import_project = subparsers.add_parser("project-from-srt")
    import_project.add_argument("--media", required=True)
    import_project.add_argument("--srt", required=True)
    import_project.add_argument("--md")
    import_project.add_argument("--output")

    ranges = subparsers.add_parser("ranges")
    ranges.add_argument("--project", required=True)

    export = subparsers.add_parser("export")
    export.add_argument("--project", required=True)
    export.add_argument("--output", required=True)

    export_srt_cmd = subparsers.add_parser("export-srt")
    export_srt_cmd.add_argument("--project", required=True)
    export_srt_cmd.add_argument("--output", required=True)

    export_md_cmd = subparsers.add_parser("export-md")
    export_md_cmd.add_argument("--project", required=True)
    export_md_cmd.add_argument("--output", required=True)

    args = parser.parse_args()

    if args.command == "probe":
        _print_json(_ffprobe(args.media))
    elif args.command == "waveform":
        _print_json(_waveform(args.media, args.samples))
    elif args.command == "transcribe":
        from .app_progress import ProgressEmitter
        from .app_project import project_to_dict, save_project

        progress = ProgressEmitter(args.progress)
        project = _transcribe(args.media, args, progress)
        if args.output:
            save_project(project, args.output)
        _print_json(project_to_dict(project))
    elif args.command == "retranscribe-range":
        from .app_progress import ProgressEmitter

        progress = ProgressEmitter(args.progress)
        _print_json(_retranscribe_range(args.media, args, progress))
    elif args.command == "project-from-srt":
        from .app_project import project_from_srt_md, project_to_dict, save_project

        duration = _ffprobe(args.media)["duration"]
        project = project_from_srt_md(args.media, duration, args.srt, args.md)
        if args.output:
            save_project(project, args.output)
        _print_json(project_to_dict(project))
    elif args.command == "ranges":
        from .app_project import load_project, selected_ranges

        project = load_project(args.project)
        _print_json({"ranges": selected_ranges(project)})
    elif args.command == "export":
        from .app_project import export_audio, load_project

        with redirect_stdout(sys.stderr):
            export_audio(load_project(args.project), args.output)
        _print_json({"output": os.path.abspath(args.output)})
    elif args.command == "export-srt":
        from .app_project import export_srt, load_project

        export_srt(load_project(args.project), args.output)
        _print_json({"output": os.path.abspath(args.output)})
    elif args.command == "export-md":
        from .app_project import export_md, load_project

        export_md(load_project(args.project), args.output)
        _print_json({"output": os.path.abspath(args.output)})


if __name__ == "__main__":
    main()
