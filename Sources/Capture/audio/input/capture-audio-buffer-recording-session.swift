import Foundation
import MediaCore

public final class CaptureAudioBufferRecordingSession: @unchecked Sendable {
    public let audio: CaptureAudioOptions
    public let deviceProvider: any CaptureDeviceProvider

    private let collector: CaptureAudioBufferCollector
    private let input: CaptureAudioInputSession

    public init(
        audio: CaptureAudioOptions,
        deviceProvider: any CaptureDeviceProvider = MacCaptureDeviceProvider(),
        chain: AudioChain = .raw
    ) {
        let collector = CaptureAudioBufferCollector()

        self.audio = audio
        self.deviceProvider = deviceProvider
        self.collector = collector
        self.input = CaptureAudioInputSession(
            audio: audio,
            deviceProvider: deviceProvider,
            chain: chain
        ) { buffer in
            collector.append(
                buffer
            )
        }
    }

    @discardableResult
    public func start() async throws -> CaptureAudioInputStartResult {
        guard input.currentStartResult() == nil else {
            throw CaptureError.audioCapture(
                "Audio buffer recording session is already running."
            )
        }

        collector.reset()

        do {
            return try await input.start()
        } catch {
            collector.reset()
            throw error
        }
    }

    public func stop() throws -> CaptureAudioBufferRecordingResult {
        guard let start = input.currentStartResult() else {
            throw CaptureError.audioCapture(
                "Audio buffer recording session is not running."
            )
        }

        let firstSampleHostTimeSeconds = input.firstSampleHostTimeSeconds()

        try input.stop()

        return CaptureAudioBufferRecordingResult(
            start: start,
            buffers: collector.snapshot(),
            firstSampleHostTimeSeconds: firstSampleHostTimeSeconds
        )
    }

    public func cancel() {
        input.cancel()
        collector.reset()
    }

    public func currentStartResult() -> CaptureAudioInputStartResult? {
        input.currentStartResult()
    }

    public func firstSampleHostTimeSeconds() -> TimeInterval? {
        input.firstSampleHostTimeSeconds()
    }

    public func status() -> CaptureAudioBufferRecordingStatus? {
        guard input.currentStartResult() != nil else {
            return nil
        }

        return collector.status()
    }
}

private final class CaptureAudioBufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [MediaAudioBuffer] = []
    private var durationSeconds: TimeInterval = 0
    private var rmsAmplitude: Float?

    func append(
        _ buffer: MediaAudioBuffer
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }

        buffers.append(
            buffer
        )

        if buffer.sampleRate > 0 {
            durationSeconds += Double(
                buffer.frameCount
            ) / Double(
                buffer.sampleRate
            )
        }

        rmsAmplitude = buffer.rmsAmplitude
    }

    func reset() {
        lock.lock()
        defer {
            lock.unlock()
        }

        buffers.removeAll(
            keepingCapacity: true
        )
        durationSeconds = 0
        rmsAmplitude = nil
    }

    func snapshot() -> [MediaAudioBuffer] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return buffers
    }

    func status() -> CaptureAudioBufferRecordingStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        return CaptureAudioBufferRecordingStatus(
            durationSeconds: durationSeconds,
            rmsAmplitude: rmsAmplitude
        )
    }
}
