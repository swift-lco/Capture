import MediaCore
import AudioToolbox
import CoreAudio
import Foundation

internal struct CoreAudioProcessAudioWriterSnapshot: Sendable, Hashable {
    internal let bufferCount: Int
    internal let frameCount: Int
    internal let peak: Float
    internal let firstSampleHostTimeSeconds: TimeInterval?

    internal init(
        bufferCount: Int,
        frameCount: Int,
        peak: Float,
        firstSampleHostTimeSeconds: TimeInterval?
    ) {
        self.bufferCount = bufferCount
        self.frameCount = frameCount
        self.peak = peak
        self.firstSampleHostTimeSeconds = firstSampleHostTimeSeconds
    }
}

internal final class CoreAudioProcessAudioWAVWriter: @unchecked Sendable {
    private let sink: any CaptureAudioSink
    private let lock = NSLock()

    private var inputFormat: AudioStreamBasicDescription?
    private var outputFormat: AudioStreamBasicDescription?
    private var bufferCount = 0
    private var frameCount = 0
    private var peak: Float = 0
    private var firstSampleHostTimeSeconds: TimeInterval?
    private var failure: Error?
    private var started = false
    private var finished = false

    internal init(
        output: URL
    ) {
        self.sink = WAVAudioSink(
            output: output
        )
    }

    internal func start(
        inputFormat: AudioStreamBasicDescription
    ) throws {
        let outputFormat = try normalizedOutputFormat(
            inputFormat
        )

        try sink.start(
            format: outputFormat
        )

        lock.lock()
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.bufferCount = 0
        self.frameCount = 0
        self.peak = 0
        self.firstSampleHostTimeSeconds = nil
        self.failure = nil
        self.started = true
        self.finished = false
        lock.unlock()
    }

    internal func append(
        inputData: UnsafePointer<AudioBufferList>?,
        inputTime: UnsafePointer<AudioTimeStamp>?
    ) {
        guard let inputData else {
            return
        }

        do {
            let buffer = try makeBuffer(
                inputData: inputData,
                inputTime: inputTime
            )

            guard !buffer.isEmpty else {
                return
            }

            try sink.append(
                buffer
            )

            record(
                buffer
            )
        } catch {
            recordFailure(
                error
            )
        }
    }

    internal func finish() throws {
        let capturedFailure = prepareFinish()

        do {
            try sink.finish()
        } catch {
            throw capturedFailure ?? error
        }

        if let capturedFailure {
            throw capturedFailure
        }
    }

    internal func cancel() {
        lock.lock()
        finished = true
        lock.unlock()

        sink.cancel()
    }

    internal func snapshot() -> CoreAudioProcessAudioWriterSnapshot {
        lock.lock()
        defer {
            lock.unlock()
        }

        return CoreAudioProcessAudioWriterSnapshot(
            bufferCount: bufferCount,
            frameCount: frameCount,
            peak: peak,
            firstSampleHostTimeSeconds: firstSampleHostTimeSeconds
        )
    }
}

private extension CoreAudioProcessAudioWAVWriter {
    func normalizedOutputFormat(
        _ inputFormat: AudioStreamBasicDescription
    ) throws -> AudioStreamBasicDescription {
        guard inputFormat.mFormatID == kAudioFormatLinearPCM else {
            throw CaptureError.audioCapture(
                "Process audio capture expected linear PCM from Core Audio. FormatID=\(inputFormat.mFormatID)."
            )
        }

        guard inputFormat.mBitsPerChannel == 32,
              (inputFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0 else {
            throw CaptureError.audioCapture(
                "Process audio capture expected Float32 PCM from Core Audio. Bits=\(inputFormat.mBitsPerChannel) flags=\(inputFormat.mFormatFlags)."
            )
        }

        let channels = max(
            UInt32(1),
            inputFormat.mChannelsPerFrame
        )
        let bytesPerSample = UInt32(
            MemoryLayout<Float>.size
        )
        let bytesPerFrame = bytesPerSample * channels

        return AudioStreamBasicDescription(
            mSampleRate: inputFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    func makeBuffer(
        inputData: UnsafePointer<AudioBufferList>,
        inputTime: UnsafePointer<AudioTimeStamp>?
    ) throws -> MediaAudioBuffer {
        let state = currentFormats()

        guard let inputFormat = state.input,
              let outputFormat = state.output else {
            throw CaptureError.audioCapture(
                "Process audio writer is not started."
            )
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(
                mutating: inputData
            )
        )

        let channels = Int(
            max(
                UInt32(1),
                outputFormat.mChannelsPerFrame
            )
        )
        let bytesPerSample = MemoryLayout<Float>.size
        let sampleRate = Int(
            outputFormat.mSampleRate.rounded()
        )
        let hostTimeSeconds = Self.audioHostTimeSeconds(
            from: inputTime
        )

        if buffers.count == 1,
           Int(buffers[0].mNumberChannels) == channels,
           inputFormat.mBytesPerFrame == outputFormat.mBytesPerFrame {
            return makeInterleavedBuffer(
                buffers[0],
                channels: channels,
                bytesPerSample: bytesPerSample,
                sampleRate: sampleRate,
                hostTimeSeconds: hostTimeSeconds
            )
        }

        return makeInterleavedBufferFromPlanarBuffers(
            buffers,
            channels: channels,
            bytesPerSample: bytesPerSample,
            sampleRate: sampleRate,
            hostTimeSeconds: hostTimeSeconds
        )
    }

    func makeInterleavedBuffer(
        _ audioBuffer: AudioBuffer,
        channels: Int,
        bytesPerSample: Int,
        sampleRate: Int,
        hostTimeSeconds: TimeInterval?
    ) -> MediaAudioBuffer {
        guard let data = audioBuffer.mData,
              audioBuffer.mDataByteSize > 0 else {
            return emptyBuffer(
                sampleRate: sampleRate,
                channels: channels,
                hostTimeSeconds: hostTimeSeconds
            )
        }

        let byteCount = Int(
            audioBuffer.mDataByteSize
        )
        let bytesPerFrame = max(
            1,
            channels * bytesPerSample
        )
        let frames = byteCount / bytesPerFrame

        return MediaAudioBuffer(
            data: Data(
                bytes: data,
                count: frames * bytesPerFrame
            ),
            frameCount: frames,
            packetCount: UInt32(
                frames
            ),
            sampleRate: sampleRate,
            channelCount: channels,
            sample: .float32,
            hostTimeSeconds: hostTimeSeconds
        )
    }

    func makeInterleavedBufferFromPlanarBuffers(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        channels: Int,
        bytesPerSample: Int,
        sampleRate: Int,
        hostTimeSeconds: TimeInterval?
    ) -> MediaAudioBuffer {
        guard buffers.count > 0 else {
            return emptyBuffer(
                sampleRate: sampleRate,
                channels: channels,
                hostTimeSeconds: hostTimeSeconds
            )
        }

        let usableChannels = min(
            channels,
            buffers.count
        )

        let resolvedFrameCount = (0..<usableChannels)
            .compactMap { index -> Int? in
                guard buffers[index].mData != nil else {
                    return nil
                }

                return Int(
                    buffers[index].mDataByteSize
                ) / bytesPerSample
            }
            .min() ?? 0

        guard resolvedFrameCount > 0 else {
            return emptyBuffer(
                sampleRate: sampleRate,
                channels: channels,
                hostTimeSeconds: hostTimeSeconds
            )
        }

        var samples = Array(
            repeating: Float(0),
            count: resolvedFrameCount * channels
        )

        for channelIndex in 0..<usableChannels {
            guard let data = buffers[channelIndex].mData else {
                continue
            }

            let source = data.assumingMemoryBound(
                to: Float.self
            )

            for frameIndex in 0..<resolvedFrameCount {
                samples[frameIndex * channels + channelIndex] = source[frameIndex]
            }
        }

        return samples.withUnsafeBufferPointer { pointer in
            MediaAudioBuffer(
                data: Data(
                    buffer: pointer
                ),
                frameCount: resolvedFrameCount,
                packetCount: UInt32(
                    resolvedFrameCount
                ),
                sampleRate: sampleRate,
                channelCount: channels,
                sample: .float32,
                hostTimeSeconds: hostTimeSeconds
            )
        }
    }

    func emptyBuffer(
        sampleRate: Int,
        channels: Int,
        hostTimeSeconds: TimeInterval?
    ) -> MediaAudioBuffer {
        MediaAudioBuffer(
            data: Data(),
            frameCount: 0,
            packetCount: 0,
            sampleRate: sampleRate,
            channelCount: channels,
            sample: .float32,
            hostTimeSeconds: hostTimeSeconds
        )
    }

    func currentFormats() -> (
        input: AudioStreamBasicDescription?,
        output: AudioStreamBasicDescription?
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }

        return (
            inputFormat,
            outputFormat
        )
    }

    func record(
        _ buffer: MediaAudioBuffer
    ) {
        let bufferPeak = buffer.monoFloatSamples().reduce(
            Float(0)
        ) { current, sample in
            max(
                current,
                abs(
                    sample
                )
            )
        }

        lock.lock()

        bufferCount += 1
        frameCount += buffer.frameCount
        peak = max(
            peak,
            bufferPeak
        )

        if firstSampleHostTimeSeconds == nil {
            firstSampleHostTimeSeconds = buffer.hostTimeSeconds
        }

        lock.unlock()
    }

    func recordFailure(
        _ error: Error
    ) {
        lock.lock()

        if failure == nil {
            failure = error
        }

        lock.unlock()
    }

    func prepareFinish() -> Error? {
        lock.lock()

        let capturedFailure = failure

        finished = true

        lock.unlock()

        return capturedFailure
    }

    static func audioHostTimeSeconds(
        from timestamp: UnsafePointer<AudioTimeStamp>?
    ) -> TimeInterval? {
        guard let timestamp else {
            return nil
        }

        let value = timestamp.pointee
        let flags = value.mFlags.rawValue
        let hostTimeValidFlag: UInt32 = 1 << 1

        guard (flags & hostTimeValidFlag) != 0,
              value.mHostTime > 0 else {
            return nil
        }

        let nanoseconds = AudioConvertHostTimeToNanos(
            value.mHostTime
        )

        return TimeInterval(
            nanoseconds
        ) / 1_000_000_000
    }
}
