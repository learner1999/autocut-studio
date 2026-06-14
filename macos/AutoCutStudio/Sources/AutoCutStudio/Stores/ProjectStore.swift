import Combine
import Foundation

struct TimelineScrollRequest: Equatable {
    let id: UUID
    let time: Double
}

@MainActor
final class ProjectStore: ObservableObject {
    private static let waveformSamplesPerSecond = 20.0
    private static let minimumWaveformSamples = 2400
    private static let maximumWaveformSamples = 120_000

    @Published var project: AutoCutProject?
    @Published var projectURL: URL?
    @Published var waveform: [Double] = []
    @Published var selectedSegmentID: String?
    @Published var playheadTime: Double = 0
    @Published var zoomPixelsPerSecond: Double = 14
    @Published var isWorking = false
    @Published var workProgress: BackendProgress?
    @Published var statusMessage = "Open an audio file to begin."
    @Published var timelineScrollRequest: TimelineScrollRequest?

    private let backend = PythonBackend()
    private let audioAnalyzer = AudioAnalyzer()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    var mediaURL: URL? {
        guard let path = project?.mediaPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var hasProject: Bool {
        project != nil
    }

    var canDeselectSilenceSegments: Bool {
        project?.segments.contains { $0.kind == .silence && $0.selected } ?? false
    }

    static func waveformSampleCount(for duration: Double) -> Int {
        let durationBasedCount = Int(ceil(max(0, duration) * waveformSamplesPerSecond))
        return min(
            maximumWaveformSamples,
            max(minimumWaveformSamples, durationBasedCount)
        )
    }

    func importAudio(_ url: URL) async {
        await runTask("Probing audio...") {
            let probe = try await audioAnalyzer.probe(mediaURL: url)
            let emptyProject = AutoCutProject(
                version: 1,
                mediaPath: probe.mediaPath,
                duration: probe.duration,
                segments: [],
                settings: .defaults
            )
            project = emptyProject
            projectURL = nil
            selectedSegmentID = nil
            playheadTime = 0
            statusMessage = "Generating waveform..."
            waveform = try await audioAnalyzer.waveform(
                mediaURL: url,
                samples: Self.waveformSampleCount(for: probe.duration)
            )
            statusMessage = "Loaded \(url.lastPathComponent). Ready to transcribe."
        }
    }

    func loadProject(_ url: URL) async {
        await runTask("Opening project...") {
            let data = try Data(contentsOf: url)
            let loadedProject = try decoder.decode(AutoCutProject.self, from: data)
            project = projectByInsertingSilenceGaps(loadedProject)
            projectURL = url
            selectedSegmentID = project?.segments.first?.id
            playheadTime = project?.segments.first?.start ?? 0
            if let mediaURL {
                statusMessage = "Generating waveform..."
                waveform = try await audioAnalyzer.waveform(
                    mediaURL: mediaURL,
                    samples: Self.waveformSampleCount(for: loadedProject.duration)
                )
            }
            statusMessage = "Opened \(url.lastPathComponent)."
        }
    }

    func saveProject(to url: URL? = nil) async {
        await runTask("Saving project...") {
            guard let project else { return }
            let destination = url ?? projectURL
            guard let destination else { return }
            let data = try encoder.encode(project)
            try data.write(to: destination, options: .atomic)
            projectURL = destination
            statusMessage = "Saved \(destination.lastPathComponent)."
        }
    }

    func transcribe() async {
        await runTask("Transcribing with Whisper base...") {
            guard let mediaURL, let settings = project?.settings else { return }
            let transcribedProject = try await backend.transcribe(
                mediaURL: mediaURL,
                settings: settings,
                onProgress: updateProgress
            )
            project = projectByInsertingSilenceGaps(transcribedProject)
            selectedSegmentID = project?.segments.first?.id
            playheadTime = 0
            statusMessage = "Transcription complete."
        }
    }

    func importSRT(_ srtURL: URL, mdURL: URL?) async {
        await runTask("Importing SRT...") {
            guard let mediaURL else { return }
            let importedProject = try await backend.projectFromSRT(mediaURL: mediaURL, srtURL: srtURL, mdURL: mdURL)
            project = projectByInsertingSilenceGaps(importedProject)
            selectedSegmentID = project?.segments.first?.id
            playheadTime = project?.segments.first?.start ?? 0
            statusMessage = "Imported \(srtURL.lastPathComponent)."
        }
    }

    func export(to outputURL: URL) async {
        await runTask("Exporting MP3...") {
            let temporaryURL = try writeTemporaryProject()
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            _ = try await backend.export(projectURL: temporaryURL, outputURL: outputURL)
            statusMessage = "Exported \(outputURL.lastPathComponent)."
        }
    }

    func exportSRT(to outputURL: URL) async {
        await runTask("Exporting SRT...") {
            let temporaryURL = try writeTemporaryProject()
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            _ = try await backend.exportSRT(projectURL: temporaryURL, outputURL: outputURL)
            statusMessage = "Exported \(outputURL.lastPathComponent)."
        }
    }

    func exportMarkdown(to outputURL: URL) async {
        await runTask("Exporting Markdown...") {
            let temporaryURL = try writeTemporaryProject()
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            _ = try await backend.exportMD(projectURL: temporaryURL, outputURL: outputURL)
            statusMessage = "Exported \(outputURL.lastPathComponent)."
        }
    }

    func retranscribeSelectedSegment() async {
        await runTask("Retranscribing segment...") {
            guard let mediaURL, let project, let selectedSegmentID else { return }
            guard let index = project.segments.firstIndex(where: { $0.id == selectedSegmentID }) else { return }
            let segment = project.segments[index]
            let result = try await backend.retranscribe(
                mediaURL: mediaURL,
                segment: segment,
                settings: project.settings,
                onProgress: updateProgress
            )
            updateSegment(segment.id) { item in
                item.text = result.text.isEmpty ? item.text : result.text
                item.needsRetranscribe = false
            }
            statusMessage = "Retranscribed selected segment."
        }
    }

    func setPlayhead(_ time: Double, selectSegment: Bool = true) {
        let bounded = boundedTime(time)
        playheadTime = bounded
        if selectSegment, let segment = segment(at: bounded) {
            selectedSegmentID = segment.id
        }
    }

    func requestTimelineScroll(to time: Double) {
        timelineScrollRequest = TimelineScrollRequest(id: UUID(), time: boundedTime(time))
    }

    func selectSegment(_ id: String) {
        selectedSegmentID = id
        if let segment = project?.segments.first(where: { $0.id == id }) {
            playheadTime = segment.start
        }
    }

    func splitAtPlayhead() {
        guard var project, let index = project.segments.firstIndex(where: {
            playheadTime > $0.start && playheadTime < $0.end
        }) else {
            statusMessage = "Move the playhead inside a subtitle segment before splitting."
            return
        }

        let segment = project.segments[index]
        guard playheadTime - segment.start >= 0.30, segment.end - playheadTime >= 0.30 else {
            statusMessage = "Split point must leave at least 0.30s on both sides."
            return
        }

        let ratio = (playheadTime - segment.start) / max(segment.duration, 0.001)
        let parts = TextSplitter.split(segment.text, ratio: ratio)
        let left = ProjectSegment(
            id: UUID().uuidString,
            start: segment.start,
            end: playheadTime,
            text: parts.0,
            selected: segment.selected,
            kind: segment.kind,
            sourceIndex: segment.sourceIndex,
            needsRetranscribe: true
        )
        let right = ProjectSegment(
            id: UUID().uuidString,
            start: playheadTime,
            end: segment.end,
            text: parts.1,
            selected: segment.selected,
            kind: segment.kind,
            sourceIndex: segment.sourceIndex,
            needsRetranscribe: true
        )
        project.segments.replaceSubrange(index...index, with: [left, right])
        self.project = project
        selectedSegmentID = right.id
        statusMessage = "Split segment at \(TimeFormatters.clockWithTenths(playheadTime))."
    }

    func deselectSilenceSegments() {
        guard var project else { return }
        var changedCount = 0
        for index in project.segments.indices where project.segments[index].kind == .silence && project.segments[index].selected {
            project.segments[index].selected = false
            changedCount += 1
        }
        guard changedCount > 0 else {
            statusMessage = "All silence segments are already unchecked."
            return
        }
        self.project = project
        let label = changedCount == 1 ? "silence segment" : "silence segments"
        statusMessage = "Unchecked \(changedCount) \(label)."
    }

    func playbackRanges() -> [PlaybackRange] {
        guard let project else { return [] }
        let settings = project.settings
        let segments = project.segments.sorted { $0.start < $1.start }
        let padded = segments.enumerated()
            .compactMap { index, segment -> (Int, PlaybackRange)? in
                guard segment.selected else { return nil }

                let previousSegment = index > 0 ? segments[index - 1] : nil
                let nextSegment = index + 1 < segments.count ? segments[index + 1] : nil
                let blocksHeadPadding = previousSegment?.selected == false && previousSegment?.kind == .speech
                let blocksTailPadding = nextSegment?.selected == false && nextSegment?.kind == .speech
                let start = blocksHeadPadding ? segment.start : max(0, segment.start - settings.padHead)
                let end = blocksTailPadding ? segment.end : min(project.duration, segment.end + settings.padTail)
                return end > start ? (index, PlaybackRange(start: start, end: end)) : nil
            }

        var merged: [PlaybackRange] = []
        var previousIndex: Int?
        for (index, range) in padded {
            guard let previous = merged.last else {
                merged.append(range)
                previousIndex = index
                continue
            }
            let cutSegments = segments[(previousIndex ?? 0) + 1..<index]
            let hasExplicitCut = cutSegments.contains { !$0.selected }
            let mergeGap = hasExplicitCut ? 0 : settings.mergeGap
            if range.start <= previous.end + mergeGap {
                merged[merged.count - 1].end = max(previous.end, range.end)
            } else {
                merged.append(range)
            }
            previousIndex = index
        }
        return merged
    }

    func segment(at time: Double) -> ProjectSegment? {
        guard let segments = project?.segments else { return nil }
        return segments.first { time >= $0.start && time < $0.end }
            ?? segments.last { abs(time - $0.end) < 0.001 }
    }

    func updateCurrentSegmentFromPlayback(_ time: Double) {
        playheadTime = time
        if let segment = segment(at: time), segment.id != selectedSegmentID {
            selectedSegmentID = segment.id
        }
    }

    private func updateSegment(_ id: String, mutate: (inout ProjectSegment) -> Void) {
        guard var project, let index = project.segments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&project.segments[index])
        self.project = project
    }

    private func projectByInsertingSilenceGaps(_ project: AutoCutProject) -> AutoCutProject {
        var normalized = project
        let sortedSegments = project.segments.sorted { $0.start < $1.start }
        var result: [ProjectSegment] = []
        var cursor = 0.0

        for segment in sortedSegments {
            if segment.start > cursor + 1.0 {
                result.append(
                    ProjectSegment(
                        id: UUID().uuidString,
                        start: cursor,
                        end: segment.start,
                        text: "< No Speech >",
                        selected: true,
                        kind: .silence,
                        sourceIndex: nil,
                        needsRetranscribe: false
                    )
                )
            }
            result.append(segment)
            cursor = max(cursor, segment.end)
        }

        if project.duration > cursor + 1.0 {
            result.append(
                ProjectSegment(
                    id: UUID().uuidString,
                    start: cursor,
                    end: project.duration,
                    text: "< No Speech >",
                    selected: true,
                    kind: .silence,
                    sourceIndex: nil,
                    needsRetranscribe: false
                )
            )
        }

        normalized.segments = result
        return normalized
    }

    private func boundedTime(_ time: Double) -> Double {
        min(max(0, time), project?.duration ?? time)
    }

    private func writeTemporaryProject() throws -> URL {
        guard let project else {
            throw BackendError.processFailed("No project is open.")
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("autocutproj.json")
        let data = try encoder.encode(project)
        try data.write(to: temporaryURL, options: .atomic)
        return temporaryURL
    }

    private nonisolated func updateProgress(_ progress: BackendProgress) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.workProgress = progress
            self.statusMessage = progress.message
        }
    }

    private func runTask(_ message: String, operation: () async throws -> Void) async {
        isWorking = true
        workProgress = nil
        statusMessage = message
        defer {
            workProgress = nil
            isWorking = false
        }
        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
