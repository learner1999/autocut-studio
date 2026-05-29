import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var scrollAnchorTime = 0.0

    private static let scrollAnchorID = "timeline-scroll-anchor"

    let onJump: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            if let project = store.project {
                let width = timelineWidth(project: project, containerWidth: geometry.size.width)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        timelineContent(project: project, containerSize: geometry.size, width: width)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let time = Double(value.location.x / width) * project.duration
                                        onJump(time)
                                    }
                            )
                    }
                    .onChange(of: store.timelineScrollRequest) { _, request in
                        guard let request else { return }
                        scrollAnchorTime = request.time
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                proxy.scrollTo(Self.scrollAnchorID, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Open an audio file to generate a waveform timeline.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func timelineContent(project: AutoCutProject, containerSize: CGSize, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            timelineCanvas(project: project, containerSize: containerSize)
                .frame(width: width, height: containerSize.height)

            scrollAnchor(project: project, width: width)
                .frame(width: width, height: containerSize.height)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: containerSize.height)
    }

    private func scrollAnchor(project: AutoCutProject, width: CGFloat) -> some View {
        let anchorX = min(
            max(0, CGFloat(scrollAnchorTime / max(project.duration, 0.001)) * width),
            max(0, width - 1)
        )
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: anchorX)
            Color.clear
                .frame(width: 1, height: 1)
                .id(Self.scrollAnchorID)
            Color.clear
                .frame(width: max(0, width - anchorX - 1))
        }
    }

    private func timelineCanvas(project: AutoCutProject, containerSize: CGSize) -> some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let waveformTop: CGFloat = 38
            let waveformHeight = max(60, height - 72)
            let midY = waveformTop + waveformHeight / 2

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(nsColor: .textBackgroundColor).opacity(0.55))
            )

            drawTicks(context: context, project: project, width: width, height: height)
            drawSegments(context: context, project: project, width: width, top: waveformTop, height: waveformHeight)
            drawWaveform(context: context, width: width, midY: midY, height: waveformHeight)
            drawPlayhead(context: context, project: project, width: width, height: height)
        }
    }

    private func drawWaveform(context: GraphicsContext, width: CGFloat, midY: CGFloat, height: CGFloat) {
        guard !store.waveform.isEmpty else {
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: width, y: midY))
            context.stroke(baseline, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            return
        }

        let step = width / CGFloat(store.waveform.count)
        var path = Path()
        for (index, peak) in store.waveform.enumerated() {
            let x = CGFloat(index) * step
            let amplitude = CGFloat(min(max(peak, 0), 1)) * height * 0.46
            path.move(to: CGPoint(x: x, y: midY - amplitude))
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        context.stroke(path, with: .color(.accentColor.opacity(0.75)), lineWidth: max(1, step * 0.6))
    }

    private func drawSegments(context: GraphicsContext, project: AutoCutProject, width: CGFloat, top: CGFloat, height: CGFloat) {
        for segment in project.segments {
            let rect = rectFor(segment: segment, project: project, width: width, top: top, height: height)
            let fill: Color
            if segment.selected {
                fill = segment.kind == .silence ? .secondary.opacity(0.08) : .green.opacity(0.08)
            } else {
                fill = .red.opacity(0.22)
            }
            context.fill(Path(rect), with: .color(fill))

            var boundary = Path()
            boundary.move(to: CGPoint(x: rect.minX, y: top))
            boundary.addLine(to: CGPoint(x: rect.minX, y: top + height))
            context.stroke(boundary, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        }
    }

    private func drawTicks(context: GraphicsContext, project: AutoCutProject, width: CGFloat, height: CGFloat) {
        let interval = tickInterval(for: store.zoomPixelsPerSecond)
        var tick = 0.0
        while tick <= project.duration {
            let x = CGFloat(tick / project.duration) * width
            var path = Path()
            path.move(to: CGPoint(x: x, y: 18))
            path.addLine(to: CGPoint(x: x, y: height - 12))
            context.stroke(path, with: .color(.secondary.opacity(tick.truncatingRemainder(dividingBy: interval * 2) == 0 ? 0.28 : 0.12)), lineWidth: 1)
            context.draw(
                Text(TimeFormatters.clock(tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary),
                at: CGPoint(x: x + 4, y: 16),
                anchor: .leading
            )
            tick += interval
        }
    }

    private func drawPlayhead(context: GraphicsContext, project: AutoCutProject, width: CGFloat, height: CGFloat) {
        let x = CGFloat(store.playheadTime / max(project.duration, 0.001)) * width
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
        context.stroke(path, with: .color(.orange), lineWidth: 2)

        context.fill(
            Path(ellipseIn: CGRect(x: x - 4, y: 5, width: 8, height: 8)),
            with: .color(.orange)
        )
    }

    private func rectFor(segment: ProjectSegment, project: AutoCutProject, width: CGFloat, top: CGFloat, height: CGFloat) -> CGRect {
        let startX = CGFloat(segment.start / max(project.duration, 0.001)) * width
        let endX = CGFloat(segment.end / max(project.duration, 0.001)) * width
        return CGRect(x: startX, y: top, width: max(1, endX - startX), height: height)
    }

    private func tickInterval(for pixelsPerSecond: Double) -> Double {
        if pixelsPerSecond >= 60 { return 2 }
        if pixelsPerSecond >= 32 { return 5 }
        if pixelsPerSecond >= 14 { return 10 }
        return 30
    }

    private func timelineWidth(project: AutoCutProject, containerWidth: CGFloat) -> CGFloat {
        max(containerWidth, project.duration * store.zoomPixelsPerSecond)
    }
}
