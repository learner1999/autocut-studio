import Foundation

enum PlaybackRateOptions {
    static let values = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func title(for rate: Double) -> String {
        if abs(rate.rounded() - rate) < 0.001 {
            return String(format: "%.0fx", rate)
        }
        if abs((rate * 10).rounded() / 10 - rate) < 0.001 {
            return String(format: "%.1fx", rate)
        }
        return String(format: "%.2fx", rate)
    }
}
