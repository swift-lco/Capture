import Foundation

public struct CaptureAudioBufferRecordingStatus:
    Sendable,
    Hashable
{
    public var durationSeconds: TimeInterval
    public var rmsAmplitude: Float?

    public init(
        durationSeconds: TimeInterval,
        rmsAmplitude: Float? = nil
    ) {
        self.durationSeconds = max(
            0,
            durationSeconds
        )
        self.rmsAmplitude = rmsAmplitude
    }
}
