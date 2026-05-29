import dataclasses
import json
import os
import re
import uuid
from datetime import timedelta
from typing import Any, Dict, List, Optional, Tuple

import srt

PROJECT_VERSION = 1
MIN_SPLIT_DURATION = 0.30
EDGE_SILENCE_MIN_DURATION = 0.80
EDGE_SILENCE_BOUNDARY_TOLERANCE = 0.25
EDGE_SPEECH_MIN_DURATION = 0.30
EDGE_SPEECH_GUARD = 0.15


@dataclasses.dataclass
class ProjectSettings:
    lang: str = "en"
    whisperModel: str = "base"
    padHead: float = 0.20
    padTail: float = 0.45
    mergeGap: float = 0.50
    bitrate: str = "192k"


@dataclasses.dataclass
class ProjectSegment:
    id: str
    start: float
    end: float
    text: str
    selected: bool = True
    kind: str = "speech"
    sourceIndex: Optional[int] = None
    needsRetranscribe: bool = False


@dataclasses.dataclass
class AutoCutProject:
    version: int
    mediaPath: str
    duration: float
    segments: List[ProjectSegment]
    settings: ProjectSettings = dataclasses.field(default_factory=ProjectSettings)


def _segment_id() -> str:
    return str(uuid.uuid4())


def _segment_kind(text: str) -> str:
    return "silence" if text.strip().lower() == "< no speech >" else "speech"


def _segment_to_dict(segment: ProjectSegment) -> Dict[str, Any]:
    return dataclasses.asdict(segment)


def project_to_dict(project: AutoCutProject) -> Dict[str, Any]:
    return {
        "version": project.version,
        "mediaPath": project.mediaPath,
        "duration": project.duration,
        "segments": [_segment_to_dict(segment) for segment in project.segments],
        "settings": dataclasses.asdict(project.settings),
    }


def project_from_dict(data: Dict[str, Any]) -> AutoCutProject:
    settings = ProjectSettings(**data.get("settings", {}))
    segments = [ProjectSegment(**segment) for segment in data.get("segments", [])]
    return AutoCutProject(
        version=int(data.get("version", PROJECT_VERSION)),
        mediaPath=data["mediaPath"],
        duration=float(data["duration"]),
        segments=segments,
        settings=settings,
    )


def load_project(path: str) -> AutoCutProject:
    with open(path, encoding="utf-8") as f:
        return project_from_dict(json.load(f))


def save_project(project: AutoCutProject, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(project_to_dict(project), f, ensure_ascii=False, indent=2)
        f.write("\n")


def md_selection_map(md_path: str) -> Dict[int, bool]:
    selections: Dict[int, bool] = {}
    task_pattern = re.compile(r"- +\[([ xX])\] +\[(\d+),")
    with open(md_path, encoding="utf-8") as f:
        for line in f:
            match = task_pattern.match(line)
            if match:
                selections[int(match.group(2))] = match.group(1).lower() == "x"
    return selections


def subtitles_from_srt(path: str) -> List[srt.Subtitle]:
    with open(path, encoding="utf-8") as f:
        return list(srt.parse(f.read()))


def project_from_subtitles(
    media_path: str,
    duration: float,
    subtitles: List[srt.Subtitle],
    selections: Optional[Dict[int, bool]] = None,
    settings: Optional[ProjectSettings] = None,
    silence_ranges: Optional[List[Tuple[float, float]]] = None,
) -> AutoCutProject:
    selections = selections or {}
    subtitle_items = sorted(subtitles, key=lambda item: item.start)
    detected_silences = _normalize_ranges(silence_ranges or [], duration)

    speech_items: List[Tuple[srt.Subtitle, float, float]] = []
    explicit_silence_ranges: List[Tuple[float, float]] = []
    for subtitle in subtitle_items:
        start = subtitle.start.total_seconds()
        end = subtitle.end.total_seconds()
        if _segment_kind(subtitle.content) == "silence":
            explicit_silence_ranges.append((start, end))
            continue
        trimmed_start, trimmed_end = _trim_range_edges_to_silence(
            start,
            end,
            detected_silences,
        )
        speech_items.append((subtitle, trimmed_start, trimmed_end))

    speech_ranges = [(start, end) for _, start, end in speech_items if end > start]
    occupied_ranges = speech_ranges + explicit_silence_ranges
    detected_silence_ranges = _subtract_range_list(detected_silences, speech_ranges)
    silence_ranges = (
        _gap_ranges_from_ranges(occupied_ranges, duration)
        + detected_silence_ranges
        + explicit_silence_ranges
    )

    silences = _normalize_ranges(silence_ranges, duration)
    segments: List[ProjectSegment] = [
        ProjectSegment(
            id=_segment_id(),
            start=start,
            end=end,
            text="< No Speech >",
            selected=True,
            kind="silence",
            sourceIndex=None,
        )
        for start, end in silences
    ]

    for subtitle, start, end in speech_items:
        text = subtitle.content.strip()
        selected = selections.get(subtitle.index, True)
        if end <= start:
            continue
        segments.append(
            ProjectSegment(
                id=_segment_id(),
                start=start,
                end=end,
                text=text,
                selected=selected,
                kind="speech",
                sourceIndex=subtitle.index,
            )
        )

    segments.sort(
        key=lambda segment: (segment.start, 0 if segment.kind == "speech" else 1)
    )
    return AutoCutProject(
        version=PROJECT_VERSION,
        mediaPath=os.path.abspath(media_path),
        duration=float(duration),
        segments=segments,
        settings=settings or ProjectSettings(),
    )


def _subtitle_gap_ranges(
    subtitles: List[srt.Subtitle], duration: float
) -> List[Tuple[float, float]]:
    return _gap_ranges_from_ranges(
        [
            (subtitle.start.total_seconds(), subtitle.end.total_seconds())
            for subtitle in subtitles
        ],
        duration,
    )


def _gap_ranges_from_ranges(
    occupied_ranges: List[Tuple[float, float]], duration: float
) -> List[Tuple[float, float]]:
    ranges: List[Tuple[float, float]] = []
    cursor = 0.0
    for start, end in sorted(occupied_ranges):
        if start > cursor + 1.0:
            ranges.append((cursor, start))
        cursor = max(cursor, end)
    if duration > cursor + 1.0:
        ranges.append((cursor, float(duration)))
    return ranges


def _normalize_ranges(
    ranges: List[Tuple[float, float]],
    duration: float,
    min_duration: float = 0.80,
    merge_gap: float = 0.12,
) -> List[Tuple[float, float]]:
    normalized: List[Tuple[float, float]] = []
    for start, end in sorted(ranges):
        start = max(0.0, min(float(start), duration))
        end = max(0.0, min(float(end), duration))
        if end - start < min_duration:
            continue
        if normalized and start <= normalized[-1][1] + merge_gap:
            normalized[-1] = (normalized[-1][0], max(normalized[-1][1], end))
        else:
            normalized.append((start, end))
    return normalized


def _subtract_ranges(
    start: float, end: float, cuts: List[Tuple[float, float]]
) -> List[Tuple[float, float]]:
    ranges = [(start, end)]
    for cut_start, cut_end in cuts:
        if cut_end <= start or cut_start >= end:
            continue
        next_ranges: List[Tuple[float, float]] = []
        for range_start, range_end in ranges:
            if cut_end <= range_start or cut_start >= range_end:
                next_ranges.append((range_start, range_end))
                continue
            if cut_start > range_start:
                next_ranges.append((range_start, min(cut_start, range_end)))
            if cut_end < range_end:
                next_ranges.append((max(cut_end, range_start), range_end))
        ranges = next_ranges
    return [
        (range_start, range_end)
        for range_start, range_end in ranges
        if range_end - range_start >= 0.05
    ]


def _subtract_range_list(
    ranges: List[Tuple[float, float]], cuts: List[Tuple[float, float]]
) -> List[Tuple[float, float]]:
    remaining: List[Tuple[float, float]] = []
    for start, end in ranges:
        remaining.extend(_subtract_ranges(start, end, cuts))
    return remaining


def _trim_range_edges_to_silence(
    start: float,
    end: float,
    silences: List[Tuple[float, float]],
    min_silence: float = EDGE_SILENCE_MIN_DURATION,
    boundary_tolerance: float = EDGE_SILENCE_BOUNDARY_TOLERANCE,
    min_speech_duration: float = EDGE_SPEECH_MIN_DURATION,
    speech_guard: float = EDGE_SPEECH_GUARD,
) -> Tuple[float, float]:
    trimmed_start = start
    trimmed_end = end
    for silence_start, silence_end in silences:
        overlap_start = max(start, silence_start)
        overlap_end = min(end, silence_end)
        overlap_duration = overlap_end - overlap_start
        if overlap_duration < min_silence:
            continue
        if (
            overlap_start <= start + boundary_tolerance
            and overlap_end <= end - min_speech_duration
        ):
            trimmed_start = max(trimmed_start, max(start, overlap_end - speech_guard))
        if (
            overlap_end >= end - boundary_tolerance
            and overlap_start >= start + min_speech_duration
        ):
            trimmed_end = min(trimmed_end, min(end, overlap_start + speech_guard))

    if trimmed_end - trimmed_start < min_speech_duration:
        return start, end
    return trimmed_start, trimmed_end


def project_from_srt_md(
    media_path: str,
    duration: float,
    srt_path: str,
    md_path: Optional[str] = None,
    settings: Optional[ProjectSettings] = None,
) -> AutoCutProject:
    selections = md_selection_map(md_path) if md_path else None
    return project_from_subtitles(
        media_path=media_path,
        duration=duration,
        subtitles=subtitles_from_srt(srt_path),
        selections=selections,
        settings=settings,
    )


def _split_text_by_ratio(text: str, ratio: float) -> Tuple[str, str]:
    stripped = text.strip()
    if not stripped or _segment_kind(stripped) == "silence":
        return stripped, stripped

    target = max(1, min(len(stripped) - 1, round(len(stripped) * ratio)))
    candidates = [match.start() for match in re.finditer(r"\s+", stripped)]
    if candidates:
        split_at = min(candidates, key=lambda index: abs(index - target))
    else:
        split_at = target

    left = stripped[:split_at].strip()
    right = stripped[split_at:].strip()
    if not left or not right:
        return stripped, ""
    return left, right


def split_segment(
    project: AutoCutProject,
    segment_id: str,
    at_seconds: float,
    min_duration: float = MIN_SPLIT_DURATION,
) -> AutoCutProject:
    for index, segment in enumerate(project.segments):
        if segment.id != segment_id:
            continue
        if (
            at_seconds - segment.start < min_duration
            or segment.end - at_seconds < min_duration
        ):
            raise ValueError("Split point must leave at least 0.30s on both sides")

        ratio = (at_seconds - segment.start) / max(segment.end - segment.start, 0.001)
        left_text, right_text = _split_text_by_ratio(segment.text, ratio)
        left = ProjectSegment(
            id=_segment_id(),
            start=segment.start,
            end=at_seconds,
            text=left_text,
            selected=segment.selected,
            kind=segment.kind,
            sourceIndex=segment.sourceIndex,
            needsRetranscribe=True,
        )
        right = ProjectSegment(
            id=_segment_id(),
            start=at_seconds,
            end=segment.end,
            text=right_text,
            selected=segment.selected,
            kind=segment.kind,
            sourceIndex=segment.sourceIndex,
            needsRetranscribe=True,
        )
        project.segments[index : index + 1] = [left, right]
        return project
    raise ValueError(f"Segment not found: {segment_id}")


def selected_ranges(project: AutoCutProject) -> List[Dict[str, float]]:
    padded: List[Tuple[int, Dict[str, float]]] = []
    settings = project.settings
    segments = sorted(project.segments, key=lambda item: item.start)
    for index, segment in enumerate(segments):
        if not segment.selected:
            continue
        previous_segment = segments[index - 1] if index > 0 else None
        next_segment = segments[index + 1] if index + 1 < len(segments) else None
        blocks_head_padding = (
            previous_segment is not None
            and not previous_segment.selected
            and previous_segment.kind == "speech"
        )
        blocks_tail_padding = (
            next_segment is not None
            and not next_segment.selected
            and next_segment.kind == "speech"
        )
        start = (
            segment.start
            if blocks_head_padding
            else max(0.0, segment.start - settings.padHead)
        )
        end = (
            segment.end
            if blocks_tail_padding
            else min(project.duration, segment.end + settings.padTail)
        )
        if end > start:
            padded.append((index, {"start": start, "end": end}))

    merged: List[Dict[str, float]] = []
    previous_index: Optional[int] = None
    for index, current in padded:
        if not merged:
            merged.append(current)
            previous_index = index
            continue
        previous = merged[-1]
        has_explicit_cut = any(
            not segment.selected
            for segment in segments[(previous_index or 0) + 1 : index]
        )
        merge_gap = 0.0 if has_explicit_cut else settings.mergeGap
        if current["start"] <= previous["end"] + merge_gap:
            previous["end"] = max(previous["end"], current["end"])
        else:
            merged.append(current)
        previous_index = index
    return merged


def export_audio(project: AutoCutProject, output_path: str) -> str:
    from moviepy import editor

    ranges = selected_ranges(project)
    if not ranges:
        raise ValueError("No selected segments to export")

    media = editor.AudioFileClip(project.mediaPath)
    clips = []
    final_clip = None
    try:
        clips = [media.subclip(item["start"], item["end"]) for item in ranges]
        final_clip = (
            clips[0] if len(clips) == 1 else editor.concatenate_audioclips(clips)
        )
        final_clip = final_clip.fx(editor.afx.audio_normalize)
        final_clip.write_audiofile(
            output_path,
            codec="libmp3lame",
            fps=44100,
            bitrate=project.settings.bitrate,
        )
    finally:
        if final_clip is not None and final_clip not in clips:
            final_clip.close()
        for clip in clips:
            clip.close()
        media.close()
    return output_path


def subtitles_from_project(project: AutoCutProject) -> List[srt.Subtitle]:
    subtitles: List[srt.Subtitle] = []
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


def export_srt(project: AutoCutProject, output_path: str) -> str:
    with open(output_path, "wb") as f:
        f.write(srt.compose(subtitles_from_project(project)).encode("utf-8", "replace"))
    return output_path


def export_md(project: AutoCutProject, output_path: str) -> str:
    lines = [
        "- [x] <-- Mark if you are done editing.",
        "",
        f"Texts generated from [{os.path.basename(project.mediaPath)}].Mark the sentences to keep for autocut.",
        "The format is [subtitle_index,duration_in_second] subtitle context.",
        "",
    ]
    for index, segment in enumerate(project.segments, start=1):
        minutes = int(segment.start) // 60
        seconds = int(segment.start) % 60
        mark = "x" if segment.selected else " "
        lines.append(
            f"- [{mark}] [{index},{minutes:02d}:{seconds:02d}] {segment.text.strip()}"
        )
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return output_path
