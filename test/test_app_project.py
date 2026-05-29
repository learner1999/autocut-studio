import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

import numpy as np
import srt

from autocut.app_project import (
    AutoCutProject,
    MIN_SPLIT_DURATION,
    ProjectSettings,
    ProjectSegment,
    export_audio,
    load_project,
    project_from_subtitles,
    project_from_srt_md,
    project_to_dict,
    save_project,
    selected_ranges,
    split_segment,
)
from autocut.app_backend import _detect_silence_ranges
from autocut.package_transcribe import Transcribe
from config import TEST_CONTENT_PATH, TEST_MEDIA_PATH


class TestAppProject(unittest.TestCase):
    def _project(self):
        media = os.path.join(TEST_MEDIA_PATH, "test005.mp3")
        srt = os.path.join(TEST_CONTENT_PATH, "test.srt")
        md = os.path.join(TEST_CONTENT_PATH, "test_md.md")
        return project_from_srt_md(media, 10.26, srt, md)

    def test_import_srt_md_maps_checkbox_selection(self):
        project = self._project()

        self.assertEqual(project.version, 1)
        self.assertEqual(len(project.segments), 2)
        self.assertFalse(project.segments[0].selected)
        self.assertTrue(project.segments[1].selected)
        self.assertEqual(project.segments[0].sourceIndex, 1)

    def test_save_and_load_project_json(self):
        project = self._project()

        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "episode.autocutproj.json")
            save_project(project, path)
            loaded = load_project(path)

        self.assertEqual(
            project_to_dict(loaded)["segments"][1]["text"], project.segments[1].text
        )
        self.assertEqual(loaded.settings.bitrate, "192k")

    def test_split_segment_inherits_selection_and_splits_text(self):
        project = self._project()
        segment = project.segments[1]
        midpoint = (segment.start + segment.end) / 2

        split_segment(project, segment.id, midpoint)

        self.assertEqual(len(project.segments), 3)
        left, right = project.segments[1], project.segments[2]
        self.assertTrue(left.selected)
        self.assertTrue(right.selected)
        self.assertTrue(left.needsRetranscribe)
        self.assertTrue(right.needsRetranscribe)
        self.assertAlmostEqual(left.end, midpoint)
        self.assertAlmostEqual(right.start, midpoint)
        self.assertTrue(left.text)
        self.assertTrue(right.text)

    def test_split_segment_rejects_too_short_sides(self):
        project = self._project()
        segment = project.segments[1]

        with self.assertRaises(ValueError):
            split_segment(project, segment.id, segment.start + MIN_SPLIT_DURATION / 2)

    def test_selected_ranges_apply_padding_and_merge_gap_without_explicit_cut(self):
        project = self._project()
        project.duration = 11.0
        project.settings = ProjectSettings(padHead=0.2, padTail=0.45, mergeGap=0.5)
        project.segments[0].selected = True

        ranges = selected_ranges(project)

        self.assertEqual(len(ranges), 1)
        self.assertGreater(ranges[0]["end"], project.segments[1].end)

    def test_selected_ranges_keep_unselected_speech_cut_exact(self):
        project = AutoCutProject(
            version=1,
            mediaPath=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=10,
            segments=[
                ProjectSegment(id="a", start=0, end=5, text="keep"),
                ProjectSegment(id="b", start=5, end=6, text="mistake", selected=False),
                ProjectSegment(id="c", start=6, end=10, text="keep again"),
            ],
            settings=ProjectSettings(padHead=0.2, padTail=0.45, mergeGap=0.5),
        )

        ranges = selected_ranges(project)

        self.assertEqual(len(ranges), 2)
        self.assertAlmostEqual(ranges[0]["end"], 5)
        self.assertAlmostEqual(ranges[1]["start"], 6)

    def test_selected_ranges_leave_padding_for_unselected_silence(self):
        project = AutoCutProject(
            version=1,
            mediaPath=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=12,
            segments=[
                ProjectSegment(id="a", start=0, end=5, text="keep"),
                ProjectSegment(
                    id="b",
                    start=5,
                    end=8,
                    text="< No Speech >",
                    selected=False,
                    kind="silence",
                ),
                ProjectSegment(id="c", start=8, end=12, text="keep again"),
            ],
            settings=ProjectSettings(padHead=0.2, padTail=0.45, mergeGap=0.5),
        )

        ranges = selected_ranges(project)

        self.assertEqual(len(ranges), 2)
        self.assertAlmostEqual(ranges[0]["end"], 5.45)
        self.assertAlmostEqual(ranges[1]["start"], 7.8)

    def test_project_from_subtitles_inserts_silence_gaps(self):
        subtitles = [
            srt.Subtitle(
                index=1,
                start=timedelta(seconds=0),
                end=timedelta(seconds=2),
                content="hello",
            ),
            srt.Subtitle(
                index=2,
                start=timedelta(seconds=4),
                end=timedelta(seconds=5),
                content="again",
            ),
        ]

        project = project_from_subtitles(
            media_path=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=7,
            subtitles=subtitles,
        )

        self.assertEqual(
            [segment.kind for segment in project.segments],
            ["speech", "silence", "speech", "silence"],
        )
        self.assertTrue(project.segments[1].selected)
        self.assertEqual(project.segments[1].text, "< No Speech >")

    def test_project_from_subtitles_preserves_speech_over_detected_silence(self):
        subtitles = [
            srt.Subtitle(
                index=1,
                start=timedelta(seconds=0),
                end=timedelta(seconds=6),
                content="one two three four five six",
            )
        ]

        project = project_from_subtitles(
            media_path=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=6,
            subtitles=subtitles,
            silence_ranges=[(2, 4)],
        )

        self.assertEqual(
            [segment.kind for segment in project.segments],
            ["speech"],
        )
        self.assertAlmostEqual(project.segments[0].start, 0)
        self.assertAlmostEqual(project.segments[0].end, 6)
        self.assertEqual(project.segments[0].text, "one two three four five six")

    def test_project_from_subtitles_peels_detected_silence_from_speech_edges(self):
        subtitles = [
            srt.Subtitle(
                index=1,
                start=timedelta(seconds=0),
                end=timedelta(seconds=8),
                content="one complete sentence",
            )
        ]

        project = project_from_subtitles(
            media_path=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=8,
            subtitles=subtitles,
            selections={1: False},
            silence_ranges=[(0, 1.1), (6.2, 8)],
        )

        self.assertEqual(
            [segment.kind for segment in project.segments],
            ["silence", "speech", "silence"],
        )
        self.assertAlmostEqual(project.segments[0].start, 0)
        self.assertAlmostEqual(project.segments[0].end, 1.1)
        self.assertAlmostEqual(project.segments[1].start, 1.1)
        self.assertAlmostEqual(project.segments[1].end, 6.2)
        self.assertAlmostEqual(project.segments[2].start, 6.2)
        self.assertAlmostEqual(project.segments[2].end, 8)
        self.assertEqual(project.segments[1].text, "one complete sentence")
        self.assertFalse(project.segments[1].selected)
        self.assertTrue(project.segments[0].selected)
        self.assertTrue(project.segments[2].selected)

    def test_project_from_subtitles_inserts_detected_silence_between_subtitles(self):
        subtitles = [
            srt.Subtitle(
                index=1,
                start=timedelta(seconds=0),
                end=timedelta(seconds=1),
                content="hello",
            ),
            srt.Subtitle(
                index=2,
                start=timedelta(seconds=2),
                end=timedelta(seconds=3),
                content="again",
            ),
        ]

        project = project_from_subtitles(
            media_path=os.path.join(TEST_MEDIA_PATH, "test005.mp3"),
            duration=3,
            subtitles=subtitles,
            silence_ranges=[(1.05, 1.9)],
        )

        self.assertEqual(
            [segment.kind for segment in project.segments],
            ["speech", "silence", "speech"],
        )
        self.assertAlmostEqual(project.segments[1].start, 1.05)
        self.assertAlmostEqual(project.segments[1].end, 1.9)
        self.assertEqual(project.segments[0].text, "hello")
        self.assertEqual(project.segments[2].text, "again")

    def test_detect_silence_ranges_finds_local_low_energy_gap(self):
        sampling_rate = 1000
        audio = np.concatenate(
            [
                np.full(1000, 0.08, dtype=np.float32),
                np.zeros(1200, dtype=np.float32),
                np.full(1000, 0.08, dtype=np.float32),
            ]
        )

        ranges = _detect_silence_ranges(
            audio, sampling_rate, duration=3.2, min_silence=0.8
        )

        self.assertEqual(len(ranges), 1)
        self.assertLess(ranges[0][0], 1.1)
        self.assertGreater(ranges[0][1], 2.1)

    def test_vad_failure_falls_back_to_full_audio(self):
        transcriber = Transcribe.__new__(Transcribe)
        transcriber.vad = True
        transcriber.vad_model = None
        transcriber.detect_speech = None
        transcriber.sampling_rate = 16000
        audio = np.zeros(16000, dtype=np.float32)

        with mock.patch("torch.hub.load", side_effect=RuntimeError("offline")):
            ranges = transcriber._detect_voice_activity(audio)

        self.assertEqual(ranges, [{"start": 0, "end": len(audio)}])

    def test_export_audio_generates_mp3(self):
        project = self._project()
        project.settings.bitrate = "96k"

        with tempfile.TemporaryDirectory() as tmpdir:
            output = os.path.join(tmpdir, "cut.mp3")
            export_audio(project, output)
            self.assertTrue(os.path.exists(output))
            self.assertGreater(os.path.getsize(output), 1000)

    def test_backend_export_keeps_stdout_json_only(self):
        project = self._project()
        project.settings.bitrate = "96k"

        with tempfile.TemporaryDirectory() as tmpdir:
            project_path = os.path.join(tmpdir, "episode.autocutproj.json")
            output = os.path.join(tmpdir, "cut.mp3")
            save_project(project, project_path)

            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "autocut.app_backend",
                    "export",
                    "--project",
                    project_path,
                    "--output",
                    output,
                ],
                capture_output=True,
                text=True,
                check=True,
            )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["output"], output)
        self.assertTrue(result.stdout.strip().startswith("{"))
        self.assertNotIn("MoviePy", result.stdout)


if __name__ == "__main__":
    unittest.main()
