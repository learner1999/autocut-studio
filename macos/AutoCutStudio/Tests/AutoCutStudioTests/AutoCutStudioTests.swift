import XCTest
@testable import AutoCutStudio

final class AutoCutStudioTests: XCTestCase {
    @MainActor
    func testPlaybackRangesUseSelectionPaddingAndMerge() {
        let store = ProjectStore()
        store.project = fixtureProject(segments: [
            segment(start: 0, end: 2, selected: true),
            segment(start: 2.2, end: 4, selected: true),
        ])

        let ranges = store.playbackRanges()

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start, 0, accuracy: 0.001)
        XCTAssertGreaterThan(ranges[0].end, 4)
        XCTAssertLessThan(ranges[0].end, 5)
    }

    @MainActor
    func testPlaybackRangesKeepManualSpeechCutExact() {
        let store = ProjectStore()
        store.project = fixtureProject(segments: [
            segment(start: 0, end: 5, selected: true),
            segment(start: 5, end: 6, selected: false),
            segment(start: 6, end: 10, selected: true),
        ])

        let ranges = store.playbackRanges()

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].end, 5, accuracy: 0.001)
        XCTAssertEqual(ranges[1].start, 6, accuracy: 0.001)
    }

    @MainActor
    func testPlaybackRangesLeavePaddingForCutSilenceWithoutMergeGap() {
        let store = ProjectStore()
        store.project = fixtureProject(segments: [
            segment(start: 0, end: 5, selected: true),
            segment(start: 5, end: 8, selected: false, kind: .silence),
            segment(start: 8, end: 12, selected: true),
        ])

        let ranges = store.playbackRanges()

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].end, 5.45, accuracy: 0.001)
        XCTAssertEqual(ranges[1].start, 7.8, accuracy: 0.001)
    }

    @MainActor
    func testSegmentLookupSelectsSourceTime() {
        let store = ProjectStore()
        let first = segment(start: 0, end: 2, selected: true)
        let second = segment(start: 2, end: 5, selected: true)
        store.project = fixtureProject(segments: [first, second])

        store.setPlayhead(3.2)

        XCTAssertEqual(store.selectedSegmentID, second.id)
    }

    @MainActor
    func testSegmentLookupUsesNextSegmentAtSharedBoundary() {
        let store = ProjectStore()
        let first = segment(start: 0, end: 2, selected: true)
        let second = segment(start: 2, end: 5, selected: true)
        store.project = fixtureProject(segments: [first, second])

        store.setPlayhead(2)

        XCTAssertEqual(store.selectedSegmentID, second.id)
    }

    @MainActor
    func testPreviewJumpMovesToNextPlayableRange() {
        let player = AudioPreviewPlayer()

        let target = player.jump(
            to: 3,
            ranges: [
                PlaybackRange(start: 0, end: 1),
                PlaybackRange(start: 5, end: 6),
            ],
            duration: 10
        )

        XCTAssertEqual(target, 5, accuracy: 0.001)
        XCTAssertEqual(player.currentTime, 5, accuracy: 0.001)
    }

    @MainActor
    func testPlaybackRateClampsToSupportedPreviewRange() {
        let player = AudioPreviewPlayer()

        player.setPlaybackRate(1.75)
        XCTAssertEqual(player.playbackRate, 1.75, accuracy: 0.001)

        player.setPlaybackRate(0.2)
        XCTAssertEqual(player.playbackRate, 0.5, accuracy: 0.001)

        player.setPlaybackRate(3.0)
        XCTAssertEqual(player.playbackRate, 2.0, accuracy: 0.001)
    }

    func testPlaybackRateTitlesStayCompact() {
        XCTAssertEqual(PlaybackRateOptions.title(for: 1.0), "1x")
        XCTAssertEqual(PlaybackRateOptions.title(for: 1.5), "1.5x")
        XCTAssertEqual(PlaybackRateOptions.title(for: 1.25), "1.25x")
    }

    func testPythonBackendEnvironmentFindsHomebrewFFmpegWhenLaunchedAsApp() {
        let environment = PythonBackend.backendEnvironment(
            repositoryRoot: URL(fileURLWithPath: "/tmp/autocut"),
            base: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(environment["PYTHONPATH"], "/tmp/autocut")
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:") == true)
        XCTAssertTrue(environment["PATH"]?.contains("/usr/bin:/bin") == true)
    }

    func testPythonBackendParsesProgressEventsFromStderr() throws {
        let progress = try XCTUnwrap(PythonBackend.progressEvent(
            fromStderrLine: #"AUTOCUT_PROGRESS {"stage":"transcribing","progress":0.42,"message":"Transcribing 42%"}"#
        ))

        XCTAssertEqual(progress.stage, "transcribing")
        XCTAssertEqual(progress.fraction ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(progress.message, "Transcribing 42%")
        XCTAssertNil(PythonBackend.progressEvent(fromStderrLine: "ordinary warning"))
    }

    @MainActor
    func testTimelineScrollRequestClampsTimeAndRefreshesID() throws {
        let store = ProjectStore()
        store.project = fixtureProject(segments: [segment(start: 0, end: 2, selected: true)])

        store.requestTimelineScroll(to: 20)
        let firstRequest = try XCTUnwrap(store.timelineScrollRequest)

        XCTAssertEqual(firstRequest.time, 12, accuracy: 0.001)

        store.requestTimelineScroll(to: 4)
        let secondRequest = try XCTUnwrap(store.timelineScrollRequest)

        XCTAssertEqual(secondRequest.time, 4, accuracy: 0.001)
        XCTAssertNotEqual(secondRequest.id, firstRequest.id)
    }

    func testTextSplitterUsesRatioWithoutDroppingText() {
        let parts = TextSplitter.split("one two three four", ratio: 0.5)

        XCTAssertFalse(parts.0.isEmpty)
        XCTAssertFalse(parts.1.isEmpty)
        XCTAssertEqual("\(parts.0) \(parts.1)", "one two three four")
    }

    @MainActor
    func testSplitAtPlayheadCreatesTwoReviewSegments() {
        let store = ProjectStore()
        let original = segment(start: 0, end: 10, selected: true, text: "one two three four")
        store.project = fixtureProject(segments: [original])
        store.setPlayhead(5)

        store.splitAtPlayhead()

        let segments = store.project?.segments ?? []
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments.allSatisfy(\.needsRetranscribe))
        XCTAssertEqual(segments[0].end, 5, accuracy: 0.001)
        XCTAssertEqual(segments[1].start, 5, accuracy: 0.001)
    }
}

private func fixtureProject(segments: [ProjectSegment]) -> AutoCutProject {
    AutoCutProject(
        version: 1,
        mediaPath: "/tmp/example.m4a",
        duration: 12,
        segments: segments,
        settings: .defaults
    )
}

private func segment(
    start: Double,
    end: Double,
    selected: Bool,
    text: String = "hello world",
    kind: SegmentKind = .speech
) -> ProjectSegment {
    ProjectSegment(
        id: UUID().uuidString,
        start: start,
        end: end,
        text: text,
        selected: selected,
        kind: kind,
        sourceIndex: nil,
        needsRetranscribe: false
    )
}
