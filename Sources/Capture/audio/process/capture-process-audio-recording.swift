import Foundation

public struct CaptureProcessAudioRecordingOptions: Sendable, Codable, Hashable {
    public let selection: CaptureProcessAudioSelection
    public let output: URL
    public let duration: CaptureRecordDuration

    public init(
        selection: CaptureProcessAudioSelection,
        output: URL,
        duration: CaptureRecordDuration = .standard
    ) throws {
        guard output.pathExtension.localizedCaseInsensitiveCompare(
            "wav"
        ) == .orderedSame else {
            throw CaptureError.audioCapture(
                "Process audio capture currently writes .wav output."
            )
        }

        self.selection = selection
        self.output = output
        self.duration = duration
    }

    public init(
        selection: CaptureProcessAudioSelection,
        output: URL,
        durationSeconds: Int
    ) throws {
        try self.init(
            selection: selection,
            output: output,
            duration: CaptureRecordDuration(
                seconds: durationSeconds
            )
        )
    }
}

public struct CaptureProcessAudioRecordingResult: Sendable, Codable, Hashable {
    public let output: URL
    public let processID: Int32
    public let processObjectID: UInt32
    public let processName: String
    public let bundleIdentifier: String?
    public let durationSeconds: Int
    public let bufferCount: Int
    public let frameCount: Int
    public let peak: Float
    public let firstSampleHostTimeSeconds: TimeInterval?

    public init(
        output: URL,
        processID: Int32,
        processObjectID: UInt32,
        processName: String,
        bundleIdentifier: String?,
        durationSeconds: Int,
        bufferCount: Int,
        frameCount: Int,
        peak: Float,
        firstSampleHostTimeSeconds: TimeInterval?
    ) {
        self.output = output
        self.processID = processID
        self.processObjectID = processObjectID
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
        self.durationSeconds = durationSeconds
        self.bufferCount = bufferCount
        self.frameCount = frameCount
        self.peak = peak
        self.firstSampleHostTimeSeconds = firstSampleHostTimeSeconds
    }

    public var capturedAudio: Bool {
        bufferCount > 0
            && frameCount > 0
            && peak > 0.000_01
    }
}
