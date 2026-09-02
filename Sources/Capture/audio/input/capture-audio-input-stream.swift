import MediaCore
import AudioToolbox
import Foundation

internal typealias CaptureAudioInputStartHandler = @Sendable (
    AudioStreamBasicDescription
) throws -> Void

internal typealias MediaAudioBufferHandler = @Sendable (
    MediaAudioBuffer
) throws -> Void

internal protocol CaptureAudioInputStream {
    func start() throws
    func stop() throws
    func firstSampleHostTimeSeconds() -> TimeInterval?
}
