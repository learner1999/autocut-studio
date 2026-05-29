import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AutoCutStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()
    @StateObject private var player = AudioPreviewPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(player)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    togglePlayback()
                }
                .disabled(store.project == nil)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Audio...") {
                    Task {
                        if let url = FilePanels.openAudio() {
                            await store.importAudio(url)
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Project...") {
                    Task {
                        if let url = FilePanels.openProject() {
                            await store.loadProject(url)
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Editing") {
                Button("Split at Playhead (B)") {
                    store.splitAtPlayhead()
                    store.requestTimelineScroll(to: store.playheadTime)
                }

                Button("Retranscribe Segment") {
                    Task { await store.retranscribeSelectedSegment() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else if let mediaURL = store.mediaURL, let duration = store.project?.duration {
            player.play(mediaURL: mediaURL, from: store.playheadTime, ranges: store.playbackRanges(), duration: duration)
        }
    }
}
