import Foundation

struct AutoCutProject: Codable, Equatable {
    var version: Int
    var mediaPath: String
    var duration: Double
    var segments: [ProjectSegment]
    var settings: ProjectSettings
}

struct ProjectSettings: Codable, Equatable {
    var lang: String
    var whisperModel: String
    var padHead: Double
    var padTail: Double
    var mergeGap: Double
    var bitrate: String

    static let defaults = ProjectSettings(
        lang: "en",
        whisperModel: "base",
        padHead: 0.20,
        padTail: 0.45,
        mergeGap: 0.50,
        bitrate: "192k"
    )
}

struct ProjectSegment: Identifiable, Codable, Equatable {
    var id: String
    var start: Double
    var end: Double
    var text: String
    var selected: Bool
    var kind: SegmentKind
    var sourceIndex: Int?
    var needsRetranscribe: Bool

    var duration: Double {
        max(0, end - start)
    }
}

enum SegmentKind: String, Codable, Equatable {
    case speech
    case silence
}

struct ProbeResult: Codable, Equatable {
    var mediaPath: String
    var duration: Double
    var format: String
    var codec: String
    var sampleRate: Int
    var channels: Int
}

struct WaveformResult: Codable, Equatable {
    var mediaPath: String
    var samples: [Double]
}

struct BackendProgress: Decodable, Equatable {
    var stage: String
    var fraction: Double?
    var message: String

    enum CodingKeys: String, CodingKey {
        case stage
        case progress
        case message
    }

    init(stage: String, fraction: Double?, message: String) {
        self.stage = stage
        self.fraction = fraction
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stage = try container.decode(String.self, forKey: .stage)
        fraction = try container.decodeIfPresent(Double.self, forKey: .progress)
        message = try container.decode(String.self, forKey: .message)
    }
}

struct RetranscribeResult: Codable, Equatable {
    var text: String
    var segments: [RetranscribedSegment]
}

struct RetranscribedSegment: Codable, Equatable {
    var start: Double
    var end: Double
    var text: String
}

struct ExportResult: Codable, Equatable {
    var output: String
}

struct RangesResult: Codable, Equatable {
    var ranges: [PlaybackRange]
}

struct PlaybackRange: Codable, Equatable, Identifiable {
    var start: Double
    var end: Double

    var id: String {
        "\(start)-\(end)"
    }

    func contains(_ time: Double) -> Bool {
        time >= start && time <= end
    }
}
