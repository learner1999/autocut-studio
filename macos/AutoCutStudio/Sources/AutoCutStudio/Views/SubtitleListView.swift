import SwiftUI

struct SubtitleListView: View {
    @EnvironmentObject private var store: ProjectStore
    let onJump: (Double) -> Void

    var body: some View {
        if store.project == nil {
            VStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Transcribed subtitle segments will appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if segmentBindings.wrappedValue.isEmpty {
            VStack(spacing: 12) {
                Text("No subtitles yet")
                    .font(.headline)
                Text("Run transcription to create editable segments.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: $store.selectedSegmentID) {
                    ForEach(segmentBindings) { $segment in
                        SubtitleRow(segment: $segment, onJump: onJump)
                            .id(segment.id)
                            .tag(segment.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedSegmentID = segment.id
                                onJump(segment.start)
                            }
                            .contextMenu {
                                Button("Split at Playhead") {
                                    store.splitAtPlayhead()
                                }
                                Button("Retranscribe Segment") {
                                    store.selectedSegmentID = segment.id
                                    Task { await store.retranscribeSelectedSegment() }
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .onChange(of: store.selectedSegmentID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var segmentBindings: Binding<[ProjectSegment]> {
        Binding(
            get: { store.project?.segments ?? [] },
            set: { newValue in
                guard var project = store.project else { return }
                project.segments = newValue
                store.project = project
            }
        )
    }
}

private struct SubtitleRow: View {
    @Binding var segment: ProjectSegment
    @EnvironmentObject private var store: ProjectStore
    let onJump: (Double) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $segment.selected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(TimeFormatters.clock(segment.start)) - \(TimeFormatters.clock(segment.end))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if segment.kind == .silence {
                        Text("silence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if segment.needsRetranscribe {
                        Label("Needs review", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                TextField("Subtitle text", text: $segment.text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(segment.selected ? .primary : .secondary)
            }

            Spacer(minLength: 8)

            Button {
                onJump(segment.start)
            } label: {
                Image(systemName: "playhead.left")
            }
            .buttonStyle(.borderless)
            .help("Move playhead to segment start")
        }
        .padding(.vertical, 5)
        .opacity(segment.selected ? 1 : 0.55)
        .listRowBackground(rowBackground)
    }

    private var rowBackground: Color {
        if store.selectedSegmentID == segment.id {
            return Color.accentColor.opacity(0.14)
        }
        return Color.clear
    }
}
