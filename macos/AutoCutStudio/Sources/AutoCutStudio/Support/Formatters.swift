import Foundation

enum TimeFormatters {
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func clockWithTenths(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let remainder = clamped - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, remainder)
    }
}

enum TextSplitter {
    static func split(_ text: String, ratio: Double) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1, trimmed.lowercased() != "< no speech >" else {
            return (trimmed, trimmed)
        }

        let boundedRatio = min(max(ratio, 0.05), 0.95)
        let target = max(1, min(trimmed.count - 1, Int((Double(trimmed.count) * boundedRatio).rounded())))
        let characters = Array(trimmed)
        let whitespaceIndices = characters.indices.filter { characters[$0].isWhitespace }
        let splitIndex = whitespaceIndices.min { abs($0 - target) < abs($1 - target) } ?? target

        let left = String(characters[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(characters[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty {
            return (trimmed, "")
        }
        return (left, right)
    }
}
