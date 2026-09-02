import MediaCore
import AudioToolbox
import Foundation

internal protocol CaptureAudioSink: AnyObject, Sendable {
    func start(
        format: AudioStreamBasicDescription
    ) throws

    func append(
        _ buffer: MediaAudioBuffer
    ) throws

    func finish() throws

    func cancel()
}
