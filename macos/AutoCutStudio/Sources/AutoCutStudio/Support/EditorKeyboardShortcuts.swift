import AppKit
import SwiftUI

struct EditorKeyboardShortcuts: NSViewRepresentable {
    var isEnabled: Bool
    var onTogglePlayback: () -> Void
    var onSplit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            onTogglePlayback: onTogglePlayback,
            onSplit: onSplit
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTogglePlayback = onTogglePlayback
        context.coordinator.onSplit = onSplit
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var view: NSView?
        var isEnabled: Bool
        var onTogglePlayback: () -> Void
        var onSplit: () -> Void

        private var monitor: Any?

        init(isEnabled: Bool, onTogglePlayback: @escaping () -> Void, onSplit: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onTogglePlayback = onTogglePlayback
            self.onSplit = onSplit
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled, event.window === view?.window else { return event }
            guard !isTextEditing(in: event.window) else { return event }

            let shortcutModifiers = event.modifierFlags.intersection([.command, .option, .control])
            guard shortcutModifiers.isEmpty else { return event }

            if event.keyCode == 49 {
                onTogglePlayback()
                return nil
            }

            if event.charactersIgnoringModifiers?.lowercased() == "b" {
                onSplit()
                return nil
            }

            return event
        }

        private func isTextEditing(in window: NSWindow?) -> Bool {
            guard let firstResponder = window?.firstResponder else { return false }
            return firstResponder is NSTextView || firstResponder is NSTextField
        }
    }
}
