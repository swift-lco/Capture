import Foundation
import MediaCore

public struct CaptureAudioBufferRecordingResult: Sendable {
    public let start: CaptureAudioInputStartResult
    public let buffers: [MediaAudioBuffer]
    public let firstSampleHostTimeSeconds: TimeInterval?

    public init(
        start: CaptureAudioInputStartResult,
        buffers: [MediaAudioBuffer],
        firstSampleHostTimeSeconds: TimeInterval?
    ) {
        self.start = start
        self.buffers = buffers
        self.firstSampleHostTimeSeconds = firstSampleHostTimeSeconds
    }

    public var isEmpty: Bool {
        buffers.isEmpty
    }

    public var bufferCount: Int {
        buffers.count
    }

    public var frameCount: Int {
        buffers.reduce(
            0
        ) { total, buffer in
            total + buffer.frameCount
        }
    }

    public var durationSeconds: TimeInterval {
        buffers.reduce(
            0
        ) { total, buffer in
            guard buffer.sampleRate > 0 else {
                return total
            }

            return total
                + Double(
                    buffer.frameCount
                )
                / Double(
                    buffer.sampleRate
                )
        }
    }
}
