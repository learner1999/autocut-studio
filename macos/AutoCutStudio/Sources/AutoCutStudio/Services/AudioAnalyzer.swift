import AVFoundation
import CoreMedia
import Foundation

enum AudioAnalyzerError: LocalizedError {
    case noAudioTrack
    case cannotReadAudio
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The selected file does not contain an audio track."
        case .cannotReadAudio:
            return "Could not read audio samples from the selected file."
        case .readerFailed(let message):
            return message
        }
    }
}

struct AudioAnalyzer {
    private static let waveformSampleRate = 8_000.0

    func probe(mediaURL: URL) async throws -> ProbeResult {
        let asset = AVURLAsset(url: mediaURL)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.load(.tracks)
        guard let audioTrack = tracks.first(where: { $0.mediaType == .audio }) else {
            throw AudioAnalyzerError.noAudioTrack
        }

        let descriptions = try await audioTrack.load(.formatDescriptions)
        let audioInfo = Self.audioInfo(from: descriptions.first)
        return ProbeResult(
            mediaPath: mediaURL.path,
            duration: duration.isFinite ? duration : 0,
            format: mediaURL.pathExtension.lowercased(),
            codec: audioInfo.codec,
            sampleRate: audioInfo.sampleRate,
            channels: audioInfo.channels
        )
    }

    func waveform(mediaURL: URL, samples: Int) async throws -> [Double] {
        try await Task.detached(priority: .userInitiated) {
            try Self.readWaveform(mediaURL: mediaURL, samples: samples)
        }.value
    }

    private static func readWaveform(mediaURL: URL, samples: Int) throws -> [Double] {
        let targetSamples = max(1, samples)
        let asset = AVURLAsset(url: mediaURL)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AudioAnalyzerError.noAudioTrack
        }

        let duration = asset.duration.seconds
        let estimatedSampleCount = max(1, Int(ceil(max(0, duration) * waveformSampleRate)))
        let bucketSize = max(1, Int(ceil(Double(estimatedSampleCount) / Double(targetSamples))))

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: waveformSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioAnalyzerError.cannotReadAudio
        }
        reader.add(output)

        guard reader.startReading() else {
            throw AudioAnalyzerError.readerFailed(reader.error?.localizedDescription ?? "Could not start reading audio.")
        }

        var peaks: [Double] = []
        peaks.reserveCapacity(targetSamples)
        var bucketPeak = 0.0
        var bucketCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else {
                continue
            }

            let sampleCount = totalLength / MemoryLayout<Int16>.stride
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { values in
                for index in 0..<sampleCount {
                    let rawValue = values[index]
                    let magnitude = rawValue == Int16.min ? 32_768 : abs(Int(rawValue))
                    bucketPeak = max(bucketPeak, min(1.0, Double(magnitude) / 32_768.0))
                    bucketCount += 1

                    if bucketCount >= bucketSize {
                        if peaks.count < targetSamples {
                            peaks.append(bucketPeak)
                        }
                        bucketPeak = 0
                        bucketCount = 0
                    }
                }
            }
        }

        if bucketCount > 0, peaks.count < targetSamples {
            peaks.append(bucketPeak)
        }

        if reader.status == .failed {
            throw AudioAnalyzerError.readerFailed(reader.error?.localizedDescription ?? "Could not read audio.")
        }
        return peaks
    }

    private static func audioInfo(from description: CMFormatDescription?) -> (codec: String, sampleRate: Int, channels: Int) {
        guard let description else {
            return ("", 0, 0)
        }
        let codec = fourCharacterCodeString(CMFormatDescriptionGetMediaSubType(description))
        guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return (codec, 0, 0)
        }
        return (
            codec,
            Int(basicDescription.mSampleRate),
            Int(basicDescription.mChannelsPerFrame)
        )
    }

    private static func fourCharacterCodeString(_ code: FourCharCode) -> String {
        let scalars = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: scalars.filter { $0 >= 32 && $0 <= 126 }, encoding: .ascii) ?? ""
    }
}
