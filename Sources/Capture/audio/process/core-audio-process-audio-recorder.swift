import CoreAudio
import Foundation

public struct CoreAudioProcessAudioRecorder: Sendable {
    public init() {}

    public func record(
        options: CaptureProcessAudioRecordingOptions
    ) async throws -> CaptureProcessAudioRecordingResult {
        guard #available(macOS 14.2, *) else {
            throw CaptureError.audioCapture(
                "Core Audio process audio capture requires macOS 14.2 or later."
            )
        }

        let resolved = try CoreAudioProcessResolver().resolve(
            options.selection
        )

        let session = try CoreAudioProcessAudioRecordingSession(
            resolved: resolved,
            output: options.output
        )

        let powerAssertion = try CapturePowerAssertion(
            reason: "Capture process audio recording active"
        )

        defer {
            powerAssertion.release()
        }

        do {
            try session.start()

            try await Task.sleep(
                nanoseconds: UInt64(
                    options.duration.seconds
                ) * 1_000_000_000
            )

            let snapshot = try session.stop()

            return CaptureProcessAudioRecordingResult(
                output: options.output,
                processID: Int32(
                    resolved.processID
                ),
                processObjectID: UInt32(
                    resolved.processObjectID
                ),
                processName: resolved.processName,
                bundleIdentifier: resolved.bundleIdentifier,
                durationSeconds: options.duration.seconds,
                bufferCount: snapshot.bufferCount,
                frameCount: snapshot.frameCount,
                peak: snapshot.peak,
                firstSampleHostTimeSeconds: snapshot.firstSampleHostTimeSeconds
            )
        } catch {
            session.cancel()
            throw error
        }
    }
}

@available(macOS 14.2, *)
private final class CoreAudioProcessAudioRecordingSession: @unchecked Sendable {
    private let resolved: CoreAudioProcessResolution
    private let output: URL
    private let writer: CoreAudioProcessAudioWAVWriter
    private let lock = NSLock()

    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID(
        kAudioObjectUnknown
    )
    private var aggregateDeviceID = AudioObjectID(
        kAudioObjectUnknown
    )
    private var ioProcID: AudioDeviceIOProcID?
    private var started = false

    fileprivate init(
        resolved: CoreAudioProcessResolution,
        output: URL
    ) throws {
        self.resolved = resolved
        self.output = output
        self.writer = CoreAudioProcessAudioWAVWriter(
            output: output
        )
    }

    fileprivate func start() throws {
        try prepareOutputDirectory()

        let description = CATapDescription(
            stereoMixdownOfProcesses: [
                resolved.processObjectID,
            ]
        )

        description.uuid = UUID()
        description.name = "Capture process audio: \(resolved.processName)"
        description.isPrivate = true
        description.isExclusive = false
        description.muteBehavior = CATapMuteBehavior.unmuted

        var createdTapID = AudioObjectID(
            kAudioObjectUnknown
        )

        try check(
            AudioHardwareCreateProcessTap(
                description,
                &createdTapID
            ),
            message: "Could not create Core Audio process tap for \(resolved.processName)."
        )

        tapDescription = description
        tapID = createdTapID

        let tapFormat = try readTapFormat(
            tapID: createdTapID
        )

        try writer.start(
            inputFormat: tapFormat
        )

        let createdAggregateDeviceID = try createAggregateDevice(
            tapDescription: description
        )

        aggregateDeviceID = createdAggregateDeviceID

        var createdIOProcID: AudioDeviceIOProcID?

        try check(
            AudioDeviceCreateIOProcID(
                createdAggregateDeviceID,
                Self.ioProc,
                Unmanaged.passUnretained(
                    self
                ).toOpaque(),
                &createdIOProcID
            ),
            message: "Could not create process audio IOProc."
        )

        guard let createdIOProcID else {
            throw CaptureError.audioCapture(
                "Process audio IOProc was not created."
            )
        }

        ioProcID = createdIOProcID

        try check(
            AudioDeviceStart(
                createdAggregateDeviceID,
                createdIOProcID
            ),
            message: "Could not start process audio aggregate device."
        )

        lock.lock()
        started = true
        lock.unlock()
    }

    fileprivate func stop() throws -> CoreAudioProcessAudioWriterSnapshot {
        stopAudioObjects()

        try writer.finish()

        return writer.snapshot()
    }

    fileprivate func cancel() {
        stopAudioObjects()

        writer.cancel()
    }
}

@available(macOS 14.2, *)
private extension CoreAudioProcessAudioRecordingSession {
    static let ioProc: AudioDeviceIOProc = {
        inDevice,
        inNow,
        inInputData,
        inInputTime,
        outOutputData,
        inOutputTime,
        inClientData in

        guard let inClientData else {
            return noErr
        }

        let session = Unmanaged<CoreAudioProcessAudioRecordingSession>
            .fromOpaque(
                inClientData
            )
            .takeUnretainedValue()

        session.writer.append(
            inputData: inInputData,
            inputTime: inInputTime
        )

        return noErr
    }

    func prepareOutputDirectory() throws {
        let directory = output.deletingLastPathComponent()

        guard !directory.path.isEmpty else {
            return
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func readTapFormat(
        tapID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var byteCount = UInt32(
            MemoryLayout<AudioStreamBasicDescription>.size
        )

        try check(
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &byteCount,
                &format
            ),
            message: "Could not read process audio format."
        )

        return format
    }

    func createAggregateDevice(
        tapDescription: CATapDescription
    ) throws -> AudioObjectID {
        let tapUID = tapDescription.uuid.uuidString

        let tapList: [[String: Any]] = [
            [
                kAudioSubTapUIDKey as String: tapUID,
                kAudioSubTapDriftCompensationKey as String: true,
            ],
        ]

        let aggregateUID = "com.levi.capture.process-audio.\(UUID().uuidString)"

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Capture Process Audio",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceTapListKey as String: tapList,
            kAudioAggregateDeviceTapAutoStartKey as String: false,
            kAudioAggregateDeviceIsPrivateKey as String: true,
        ]

        var createdAggregateDeviceID = AudioObjectID(
            kAudioObjectUnknown
        )

        try check(
            AudioHardwareCreateAggregateDevice(
                description as CFDictionary,
                &createdAggregateDeviceID
            ),
            message: "Could not create process audio aggregate device."
        )

        guard createdAggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw CaptureError.audioCapture(
                "Process audio aggregate device was not created."
            )
        }

        return createdAggregateDeviceID
    }

    func stopAudioObjects() {
        lock.lock()

        let capturedStarted = started
        let capturedAggregateDeviceID = aggregateDeviceID
        let capturedIOProcID = ioProcID
        let capturedTapID = tapID

        started = false
        aggregateDeviceID = AudioObjectID(
            kAudioObjectUnknown
        )
        ioProcID = nil
        tapID = AudioObjectID(
            kAudioObjectUnknown
        )
        tapDescription = nil

        lock.unlock()

        if capturedStarted,
           capturedAggregateDeviceID != AudioObjectID(kAudioObjectUnknown),
           let capturedIOProcID {
            AudioDeviceStop(
                capturedAggregateDeviceID,
                capturedIOProcID
            )
        }

        if capturedAggregateDeviceID != AudioObjectID(kAudioObjectUnknown),
           let capturedIOProcID {
            AudioDeviceDestroyIOProcID(
                capturedAggregateDeviceID,
                capturedIOProcID
            )
        }

        if capturedAggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(
                capturedAggregateDeviceID
            )
        }

        if capturedTapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(
                capturedTapID
            )
        }
    }

    func check(
        _ status: OSStatus,
        message: String
    ) throws {
        guard status == noErr else {
            throw CaptureError.audioCapture(
                "\(message) OSStatus=\(status)."
            )
        }
    }
}
