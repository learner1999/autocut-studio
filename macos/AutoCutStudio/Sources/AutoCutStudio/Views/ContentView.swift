import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var player: AudioPreviewPlayer

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            TimelineView(onJump: { time in
                jumpToTime(time, revealTimeline: false)
            })
                .frame(height: 190)
            Divider()
            SubtitleListView(onJump: { time in
                jumpToTime(time, revealTimeline: true)
            })
            Divider()
            statusBar
        }
        .background(
            EditorKeyboardShortcuts(
                isEnabled: store.project != nil,
                onTogglePlayback: togglePlayback,
                onSplit: splitAtPlayhead
            )
            .frame(width: 0, height: 0)
        )
        .onReceive(player.$currentTime) { time in
            guard player.isPlaying else { return }
            store.updateCurrentSegmentFromPlayback(time)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    if let url = FilePanels.openAudio() {
                        await store.importAudio(url)
                    }
                }
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                Task {
                    if let url = FilePanels.openProject() {
                        await store.loadProject(url)
                    }
                }
            } label: {
                Label("Project", systemImage: "doc")
            }

            Button {
                Task { await store.transcribe() }
            } label: {
                Label("Transcribe", systemImage: "text.badge.waveform")
            }
            .disabled(store.project == nil || store.isWorking)

            Button {
                togglePlayback()
            } label: {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(store.project == nil)
            .help("Play/Pause (Space)")

            playbackSpeedMenu

            Button {
                splitAtPlayhead()
            } label: {
                Label("Split", systemImage: "scissors")
            }
            .disabled((store.project?.segments.isEmpty ?? true))
            .help("Split at playhead (B)")

            Button {
                Task { await store.retranscribeSelectedSegment() }
            } label: {
                Label("Retranscribe", systemImage: "waveform.and.magnifyingglass")
            }
            .disabled(store.selectedSegmentID == nil || store.isWorking)

            Menu {
                Button("Import SRT...") {
                    Task {
                        if let srtURL = FilePanels.openSRT() {
                            let mdURL = FilePanels.openMarkdownForImport()
                            await store.importSRT(srtURL, mdURL: mdURL)
                        }
                    }
                }
                .disabled(store.mediaURL == nil || store.isWorking)

                Divider()

                Button("Export SRT...") {
                    Task {
                        if let url = FilePanels.saveSRT(defaultName: defaultSRTName()) {
                            await store.exportSRT(to: url)
                        }
                    }
                }
                .disabled((store.project?.segments.isEmpty ?? true) || store.isWorking)

                Button("Export Markdown...") {
                    Task {
                        if let url = FilePanels.saveMarkdown(defaultName: defaultMarkdownName()) {
                            await store.exportMarkdown(to: url)
                        }
                    }
                }
                .disabled((store.project?.segments.isEmpty ?? true) || store.isWorking)
            } label: {
                Label("SRT/MD", systemImage: "text.page")
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $store.zoomPixelsPerSecond, in: 4...80)
                    .frame(width: 160)
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Timeline zoom")

            Button {
                Task {
                    let defaultName = defaultProjectName()
                    if let url = FilePanels.saveProject(defaultName: defaultName) {
                        await store.saveProject(to: url)
                    }
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(store.project == nil || store.isWorking)

            Button {
                Task {
                    if let url = FilePanels.saveMP3(defaultName: defaultExportName()) {
                        await store.export(to: url)
                    }
                }
            } label: {
                Label("Export", systemImage: "music.note")
            }
            .disabled((store.project?.segments.isEmpty ?? true) || store.isWorking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(PlaybackRateOptions.values, id: \.self) { rate in
                Button {
                    player.setPlaybackRate(rate)
                } label: {
                    HStack {
                        Text(PlaybackRateOptions.title(for: rate))
                        if abs(player.playbackRate - rate) < 0.001 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(PlaybackRateOptions.title(for: player.playbackRate), systemImage: "speedometer")
        }
        .disabled(store.project == nil)
        .help("Playback speed")
    }

    private var statusBar: some View {
        HStack {
            if store.isWorking {
                if let fraction = store.workProgress?.fraction {
                    ProgressView(value: fraction)
                        .frame(width: 120)
                    Text("\(Int(round(fraction * 100)))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text(store.statusMessage)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            if let project = store.project {
                Text("\(project.segments.filter(\.selected).count)/\(project.segments.count) selected")
                    .foregroundStyle(.secondary)
                Text(TimeFormatters.clockWithTenths(store.playheadTime))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else if let mediaURL = store.mediaURL, let duration = store.project?.duration {
            player.play(mediaURL: mediaURL, from: store.playheadTime, ranges: store.playbackRanges(), duration: duration)
        }
    }

    private func jumpToTime(_ time: Double, revealTimeline: Bool) {
        store.setPlayhead(time)
        var focusTime = store.playheadTime
        if player.isPlaying, let duration = store.project?.duration {
            let target = player.jump(to: store.playheadTime, ranges: store.playbackRanges(), duration: duration)
            store.setPlayhead(target)
            focusTime = target
        }
        if revealTimeline {
            store.requestTimelineScroll(to: focusTime)
        }
    }

    private func splitAtPlayhead() {
        guard !(store.project?.segments.isEmpty ?? true) else { return }
        store.splitAtPlayhead()
        store.requestTimelineScroll(to: store.playheadTime)
    }

    private func defaultProjectName() -> String {
        guard let mediaURL = store.mediaURL else { return "Untitled.autocutproj.json" }
        return mediaURL.deletingPathExtension().lastPathComponent + ".autocutproj.json"
    }

    private func defaultExportName() -> String {
        guard let mediaURL = store.mediaURL else { return "Untitled_cut.mp3" }
        return mediaURL.deletingPathExtension().lastPathComponent + "_cut.mp3"
    }

    private func defaultSRTName() -> String {
        guard let mediaURL = store.mediaURL else { return "Untitled.srt" }
        return mediaURL.deletingPathExtension().lastPathComponent + ".srt"
    }

    private func defaultMarkdownName() -> String {
        guard let mediaURL = store.mediaURL else { return "Untitled.md" }
        return mediaURL.deletingPathExtension().lastPathComponent + ".md"
    }
}
