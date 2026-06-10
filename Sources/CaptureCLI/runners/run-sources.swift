import AVFoundation
import AudioToolbox
import Capture
import CoreMedia
import Foundation
import Terminal

enum SourcesCommandRunner {
    static func run(
        _ options: SourcesCommandOptions
    ) async throws {
        let output = options.output
        let videoDirectory = output.appendingPathComponent(
            "video",
            isDirectory: true
        )
        let audioDirectory = output.appendingPathComponent(
            "audio",
            isDirectory: true
        )
        let rawDirectory = output.appendingPathComponent(
            "raw",
            isDirectory: true
        )
        let rawVideoDirectory = rawDirectory.appendingPathComponent(
            "video",
            isDirectory: true
        )
        let rawAudioDirectory = rawDirectory.appendingPathComponent(
            "audio",
            isDirectory: true
        )

        try prepareDirectory(
            output
        )
        try prepareDirectory(
            videoDirectory
        )
        try prepareDirectory(
            audioDirectory
        )

        if options.alignStart {
            try prepareDirectory(
                rawDirectory
            )
            try prepareDirectory(
                rawVideoDirectory
            )
            try prepareDirectory(
                rawAudioDirectory
            )
        }

        let recordingVideoDirectory = options.alignStart
            ? rawVideoDirectory
            : videoDirectory
        let recordingAudioDirectory = options.alignStart
            ? rawAudioDirectory
            : audioDirectory

        let stopSignal = CaptureStopSignal()
        let mode = try CaptureRecordMode(
            durationSeconds: options.durationSeconds
        )
        let listener: CaptureCLIStopListener?
        let timedStop: Task<Void, Never>?

        switch mode {
        case .live:
            listener = CaptureCLIStopListener(
                stopSignal: stopSignal
            )
            timedStop = nil

        case .duration(let duration):
            listener = nil
            timedStop = Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        duration.seconds
                    ) * 1_000_000_000
                )

                stopSignal.stop()
            }
        }

        let timer = CaptureCLI.recordingTimer(
            limitSeconds: mode.durationSeconds,
            output: output,
            audioName: options.audioSourceName,
            systemAudioEnabled: options.systemAudio.enabled,
            audioSampleRate: options.audio?.sampleRate,
            audioChannelCount: options.audio?.channel,
            title: "capture: recording sources"
        )

        var exportStatusLine: TerminalLiveStatusLine?
        var recordingTimerStopped = false
        let startedAt = Date()

        func stopRecordingTimer(
            finalLine: String
        ) async {
            guard !recordingTimerStopped else {
                return
            }

            await timer.stop(
                finalLine: finalLine
            )

            recordingTimerStopped = true
        }

        func stopExportStatusLine(
            finalLine: String
        ) async {
            guard let statusLine = exportStatusLine else {
                return
            }

            await statusLine.stop(
                finalLine: finalLine
            )

            exportStatusLine = nil
        }

        listener?.start()
        await timer.start()

        do {
            var tasks: [Task<SourcesManifest.Source, Error>] = []

            if options.screenEnabled {
                tasks.append(
                    Task {
                        try await recordScreen(
                            options: options,
                            output: recordingVideoDirectory.appendingPathComponent(
                                "screen-main.mov"
                            ),
                            stopSignal: stopSignal
                        )
                    }
                )
            }

            if options.systemAudio.enabled {
                tasks.append(
                    Task {
                        try await recordSystemAudio(
                            options: options,
                            output: recordingAudioDirectory.appendingPathComponent(
                                "system-audio.m4a"
                            ),
                            stopSignal: stopSignal
                        )
                    }
                )
            }

            for camera in options.cameras {
                tasks.append(
                    Task {
                        try await recordCamera(
                            camera,
                            options: options,
                            output: recordingVideoDirectory.appendingPathComponent(
                                "camera-\(slug(camera.name)).mov"
                            ),
                            stopSignal: stopSignal
                        )
                    }
                )
            }

            if let audio = options.audio {
                let sourceName = options.audioSourceName ?? "input-device"

                tasks.append(
                    Task {
                        try await recordAudioInput(
                            audio,
                            sourceName: sourceName,
                            video: options.video,
                            output: recordingAudioDirectory.appendingPathComponent(
                                "\(slug(sourceName)).wav"
                            ),
                            chain: options.microphoneChain,
                            stopSignal: stopSignal
                        )
                    }
                )
            }

            guard !tasks.isEmpty else {
                throw CaptureError.audioCapture(
                    "No sources enabled. Add --screen, --camera, --audio, or --system-audio."
                )
            }

            var recordedSources: [SourcesManifest.Source] = []

            for task in tasks {
                recordedSources.append(
                    try await task.value
                )
            }

            listener?.stop()
            timedStop?.cancel()

            let recordingDuration = Date().timeIntervalSince(
                startedAt
            )

            await stopRecordingTimer(
                finalLine: "recording: stopped at \(TerminalDurationFormatter.format(recordingDuration))"
            )

            let alignment: SourcesAlignmentResult

            if options.alignStart {
                exportStatusLine = TerminalLiveStatusLine(
                    leadingLines: [
                        "export: rendering aligned sources",
                    ]
                ) { frame in
                    "export: rendering    time: \(frame.elapsedText)"
                }

                await exportStatusLine?.start()

                do {
                    alignment = try await alignSourcesAtStart(
                        recordedSources,
                        videoDirectory: videoDirectory,
                        audioDirectory: audioDirectory
                    )

                    await stopExportStatusLine(
                        finalLine: "export: exported \(output.path)"
                    )
                } catch {
                    await stopExportStatusLine(
                        finalLine: "export: failed"
                    )

                    throw error
                }
            } else {
                alignment = SourcesAlignmentResult(
                    metadata: nil,
                    sources: recordedSources
                )
            }

            let manifest = SourcesManifest(
                startedAt: startedAt,
                finishedAt: Date(),
                output: output.path,
                alignment: alignment.metadata,
                sources: alignment.sources.sorted {
                    $0.output < $1.output
                }
            )

            try writeManifest(
                manifest,
                output: output.appendingPathComponent(
                    "capture.json"
                )
            )

            print(
                "sources: wrote"
            )

            for source in manifest.sources {
                print(
                    "  output      \(source.output)"
                )

                if let rawOutput = source.rawOutput {
                    print(
                        "  raw         \(rawOutput)"
                    )
                }

                if let headPaddingSeconds = source.headPaddingSeconds,
                   headPaddingSeconds > 0 {
                    print(
                        "  padding     \(String(format: "%.3f", headPaddingSeconds))s"
                    )
                }
            }

            print(
                "  manifest    \(output.appendingPathComponent("capture.json").path)"
            )
        } catch {
            listener?.stop()
            timedStop?.cancel()

            await stopRecordingTimer(
                finalLine: "recording: failed"
            )

            await stopExportStatusLine(
                finalLine: "export: failed"
            )

            throw error
        }
    }
}

private extension SourcesCommandRunner {
    static func recordScreen(
        options: SourcesCommandOptions,
        output: URL,
        stopSignal: CaptureStopSignal
    ) async throws -> SourcesManifest.Source {
        let configuration = try CaptureConfiguration(
            video: options.video,
            audio: options.audio ?? CaptureAudioOptions(),
            systemAudio: options.systemAudio,
            audioMix: CaptureAudioMixOptions(),
            container: .mov,
            output: output
        )

        let result = try await ScreenCaptureVideoRecorder().recordVideoUntilStopped(
            configuration: configuration,
            stopSignal: stopSignal,
            deviceProvider: MacCaptureDeviceProvider()
        )

        return SourcesManifest.Source(
            kind: "screen",
            name: "main",
            output: result.output.path,
            rawOutput: nil,
            durationSeconds: result.durationSeconds,
            frameCount: result.frameCount,
            sampleBufferCount: nil,
            firstHostTimeSeconds: result.startedHostTimeSeconds,
            headPaddingSeconds: nil
        )
    }

    static func recordSystemAudio(
        options: SourcesCommandOptions,
        output: URL,
        stopSignal: CaptureStopSignal
    ) async throws -> SourcesManifest.Source {
        let configuration = try CaptureConfiguration(
            video: options.video,
            audio: options.audio ?? CaptureAudioOptions(),
            systemAudio: options.systemAudio,
            audioMix: CaptureAudioMixOptions(),
            container: .mov,
            output: output
        )

        let result = try await ScreenCaptureSystemAudioRecorder().recordSystemAudioUntilStopped(
            configuration: configuration,
            stopSignal: stopSignal,
            deviceProvider: MacCaptureDeviceProvider()
        )

        return SourcesManifest.Source(
            kind: "system_audio",
            name: "system-audio",
            output: result.output.path,
            rawOutput: nil,
            durationSeconds: result.durationSeconds,
            frameCount: nil,
            sampleBufferCount: result.sampleBufferCount,
            firstHostTimeSeconds: result.firstPresentationTimeSeconds
                ?? result.startedHostTimeSeconds,
            headPaddingSeconds: nil
        )
    }

    static func recordCamera(
        _ camera: SourcesCameraInput,
        options: SourcesCommandOptions,
        output: URL,
        stopSignal: CaptureStopSignal
    ) async throws -> SourcesManifest.Source {
        let configuration = try CaptureCameraConfiguration(
            camera: camera.input,
            video: options.video,
            audio: options.audio ?? CaptureAudioOptions(),
            audioMix: CaptureAudioMixOptions(),
            container: .mov,
            output: output
        )

        let result = try await CameraVideoRecorder().recordVideoUntilStopped(
            configuration: configuration,
            stopSignal: stopSignal,
            deviceProvider: MacCaptureDeviceProvider()
        )

        return SourcesManifest.Source(
            kind: "camera",
            name: camera.name,
            output: result.output.path,
            rawOutput: nil,
            durationSeconds: result.durationSeconds,
            frameCount: result.frameCount,
            sampleBufferCount: nil,
            firstHostTimeSeconds: result.startedHostTimeSeconds,
            headPaddingSeconds: nil
        )
    }

    static func recordAudioInput(
        _ audio: CaptureAudioOptions,
        sourceName: String,
        video: CaptureVideoOptions,
        output: URL,
        chain: AudioChain,
        stopSignal: CaptureStopSignal
    ) async throws -> SourcesManifest.Source {
        let configuration = try CaptureConfiguration(
            video: video,
            audio: audio,
            output: output
        )

        let result = try await CoreAudioRecorder().recordAudioUntilStopped(
            configuration: configuration,
            stopSignal: stopSignal,
            deviceProvider: MacCaptureDeviceProvider(),
            chain: chain
        )

        return SourcesManifest.Source(
            kind: "audio_input",
            name: sourceName,
            output: result.output.path,
            rawOutput: nil,
            durationSeconds: result.durationSeconds,
            frameCount: nil,
            sampleBufferCount: nil,
            firstHostTimeSeconds: result.firstSampleHostTimeSeconds
                ?? result.startedHostTimeSeconds,
            headPaddingSeconds: nil
        )
    }
}

private extension SourcesCommandRunner {
    static func alignSourcesAtStart(
        _ sources: [SourcesManifest.Source],
        videoDirectory: URL,
        audioDirectory: URL
    ) async throws -> SourcesAlignmentResult {
        let timedSources = sources.compactMap { source -> (
            source: SourcesManifest.Source,
            firstHostTimeSeconds: TimeInterval
        )? in
            guard let firstHostTimeSeconds = source.firstHostTimeSeconds else {
                return nil
            }

            return (
                source,
                firstHostTimeSeconds
            )
        }

        guard let baseline = timedSources.map(\.firstHostTimeSeconds).min() else {
            return SourcesAlignmentResult(
                metadata: SourcesManifest.Alignment(
                    mode: "start",
                    baselineHostTimeSeconds: nil
                ),
                sources: sources
            )
        }

        var alignedSources: [SourcesManifest.Source] = []

        for source in sources {
            let rawURL = URL(
                fileURLWithPath: source.output
            )
            let finalURL = finalOutputURL(
                for: source,
                videoDirectory: videoDirectory,
                audioDirectory: audioDirectory
            )
            let headPaddingSeconds = max(
                0,
                (source.firstHostTimeSeconds ?? baseline) - baseline
            )

            try FileManager.default.removeItemIfExists(
                finalURL
            )

            if headPaddingSeconds <= 0.001 {
                try copyItem(
                    from: rawURL,
                    to: finalURL
                )
            } else if rawURL.pathExtension.localizedCaseInsensitiveCompare("wav") == .orderedSame {
                try padWAVAudio(
                    input: rawURL,
                    output: finalURL,
                    headPaddingSeconds: headPaddingSeconds
                )
            } else {
                try await padAsset(
                    input: rawURL,
                    output: finalURL,
                    headPaddingSeconds: headPaddingSeconds
                )
            }

            alignedSources.append(
                source.normalized(
                    output: finalURL.path,
                    rawOutput: rawURL.path,
                    headPaddingSeconds: headPaddingSeconds
                )
            )
        }

        return SourcesAlignmentResult(
            metadata: SourcesManifest.Alignment(
                mode: "start",
                baselineHostTimeSeconds: baseline
            ),
            sources: alignedSources
        )
    }

    static func finalOutputURL(
        for source: SourcesManifest.Source,
        videoDirectory: URL,
        audioDirectory: URL
    ) -> URL {
        let sourceURL = URL(
            fileURLWithPath: source.output
        )
        let fileExtension = sourceURL.pathExtension

        switch source.kind {
        case "screen":
            return videoDirectory.appendingPathComponent(
                "screen-\(slug(source.name)).\(fileExtension)"
            )

        case "camera":
            return videoDirectory.appendingPathComponent(
                "camera-\(slug(source.name)).\(fileExtension)"
            )

        case "system_audio":
            return audioDirectory.appendingPathComponent(
                "system-audio.\(fileExtension)"
            )

        case "audio_input":
            return audioDirectory.appendingPathComponent(
                "\(slug(source.name)).\(fileExtension)"
            )

        default:
            return audioDirectory.appendingPathComponent(
                "\(slug(source.name)).\(fileExtension)"
            )
        }
    }

    static func copyItem(
        from input: URL,
        to output: URL
    ) throws {
        try prepareDirectory(
            output.deletingLastPathComponent()
        )

        try FileManager.default.copyItem(
            at: input,
            to: output
        )
    }

    static func padAsset(
        input: URL,
        output: URL,
        headPaddingSeconds: TimeInterval
    ) async throws {
        try prepareDirectory(
            output.deletingLastPathComponent()
        )

        let asset = AVURLAsset(
            url: input
        )
        let duration = try await asset.load(
            .duration
        )
        let padding = CMTime(
            seconds: headPaddingSeconds,
            preferredTimescale: 600
        )
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(
            withMediaType: .video
        )
        let audioTracks = try await asset.loadTracks(
            withMediaType: .audio
        )

        for track in videoTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: .zero,
                    duration: duration
                ),
                of: track,
                at: padding
            )

            compositionTrack.preferredTransform = try await track.load(
                .preferredTransform
            )
        }

        for track in audioTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: .zero,
                    duration: duration
                ),
                of: track,
                at: padding
            )
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CaptureError.videoCapture(
                "Could not create start-alignment exporter for \(input.path)."
            )
        }

        exporter.outputURL = output
        exporter.outputFileType = fileType(
            for: output
        )
        exporter.shouldOptimizeForNetworkUse = false

        await exporter.export()

        guard exporter.status == .completed else {
            throw CaptureError.videoCapture(
                "Could not export start-aligned asset \(output.path): \(exporter.error?.localizedDescription ?? "unknown error")"
            )
        }
    }

    static func padWAVAudio(
        input: URL,
        output: URL,
        headPaddingSeconds: TimeInterval
    ) throws {
        try prepareDirectory(
            output.deletingLastPathComponent()
        )

        var sourceFile: AudioFileID?
        var destinationFile: AudioFileID?

        try checkAudio(
            AudioFileOpenURL(
                input as CFURL,
                .readPermission,
                0,
                &sourceFile
            ),
            message: "Could not open WAV input \(input.path)."
        )

        guard let sourceFile else {
            throw CaptureError.audioCapture(
                "Could not open WAV input \(input.path)."
            )
        }

        defer {
            AudioFileClose(
                sourceFile
            )
        }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(
            MemoryLayout<AudioStreamBasicDescription>.size
        )

        try checkAudio(
            AudioFileGetProperty(
                sourceFile,
                kAudioFilePropertyDataFormat,
                &formatSize,
                &format
            ),
            message: "Could not read WAV format for \(input.path)."
        )

        guard format.mBytesPerPacket > 0,
              format.mFramesPerPacket > 0 else {
            throw CaptureError.audioCapture(
                "Cannot start-align variable-packet WAV file \(input.path)."
            )
        }

        try checkAudio(
            AudioFileCreateWithURL(
                output as CFURL,
                kAudioFileWAVEType,
                &format,
                .eraseFile,
                &destinationFile
            ),
            message: "Could not create padded WAV output \(output.path)."
        )

        guard let destinationFile else {
            throw CaptureError.audioCapture(
                "Could not create padded WAV output \(output.path)."
            )
        }

        defer {
            AudioFileClose(
                destinationFile
            )
        }

        let paddingFrames = Int64(
            max(
                0,
                (headPaddingSeconds * format.mSampleRate).rounded()
            )
        )
        let paddingPackets = paddingFrames / Int64(
            format.mFramesPerPacket
        )
        let packetByteCount = Int(
            format.mBytesPerPacket
        )
        let silenceChunkPackets: Int64 = 4096
        let silenceChunk = Data(
            repeating: 0,
            count: Int(
                silenceChunkPackets
            ) * packetByteCount
        )

        var outputPacketIndex: Int64 = 0
        var remainingSilencePackets = paddingPackets

        while remainingSilencePackets > 0 {
            let packetsToWrite = min(
                silenceChunkPackets,
                remainingSilencePackets
            )
            var packetCount = UInt32(
                packetsToWrite
            )

            try silenceChunk.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    throw CaptureError.audioCapture(
                        "Could not access WAV silence buffer for \(output.path)."
                    )
                }

                try checkAudio(
                    AudioFileWritePackets(
                        destinationFile,
                        false,
                        UInt32(
                            Int(
                                packetsToWrite
                            ) * packetByteCount
                        ),
                        nil,
                        outputPacketIndex,
                        &packetCount,
                        baseAddress
                    ),
                    message: "Could not write WAV start padding to \(output.path)."
                )
            }

            outputPacketIndex += packetsToWrite
            remainingSilencePackets -= packetsToWrite
        }

        var sourcePacketCount: UInt64 = 0
        var sourcePacketCountSize = UInt32(
            MemoryLayout<UInt64>.size
        )

        try checkAudio(
            AudioFileGetProperty(
                sourceFile,
                kAudioFilePropertyAudioDataPacketCount,
                &sourcePacketCountSize,
                &sourcePacketCount
            ),
            message: "Could not read WAV packet count for \(input.path)."
        )

        let copyChunkPackets: Int64 = 4096
        var inputPacketIndex: Int64 = 0
        var remainingPackets = Int64(
            sourcePacketCount
        )

        while remainingPackets > 0 {
            let packetsToRead = min(
                copyChunkPackets,
                remainingPackets
            )
            var packetCount = UInt32(
                packetsToRead
            )
            var byteCount = UInt32(
                Int(
                    packetsToRead
                ) * packetByteCount
            )
            var buffer = Data(
                repeating: 0,
                count: Int(
                    byteCount
                )
            )

            try buffer.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    throw CaptureError.audioCapture(
                        "Could not access WAV read buffer for \(input.path)."
                    )
                }

                try checkAudio(
                    AudioFileReadPacketData(
                        sourceFile,
                        false,
                        &byteCount,
                        nil,
                        inputPacketIndex,
                        &packetCount,
                        baseAddress
                    ),
                    message: "Could not read WAV packets from \(input.path)."
                )
            }

            if byteCount < buffer.count {
                buffer.removeSubrange(
                    Int(
                        byteCount
                    )..<buffer.count
                )
            }

            var packetsToWrite = packetCount

            try buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    throw CaptureError.audioCapture(
                        "Could not access WAV copy buffer for \(output.path)."
                    )
                }

                try checkAudio(
                    AudioFileWritePackets(
                        destinationFile,
                        false,
                        byteCount,
                        nil,
                        outputPacketIndex,
                        &packetsToWrite,
                        baseAddress
                    ),
                    message: "Could not copy WAV packets to \(output.path)."
                )
            }

            inputPacketIndex += Int64(
                packetCount
            )
            outputPacketIndex += Int64(
                packetsToWrite
            )
            remainingPackets -= Int64(
                packetCount
            )

            guard packetCount > 0 else {
                break
            }
        }
    }

    static func fileType(
        for output: URL
    ) -> AVFileType {
        switch output.pathExtension.lowercased() {
        case "mp4":
            return .mp4

        case "m4a":
            return .m4a

        default:
            return .mov
        }
    }

    static func checkAudio(
        _ status: OSStatus,
        message: String
    ) throws {
        guard status == noErr else {
            throw CaptureError.audioCapture(
                "\(message) OSStatus=\(status)"
            )
        }
    }

    static func prepareDirectory(
        _ url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    static func writeManifest(
        _ manifest: SourcesManifest,
        output: URL
    ) throws {
        let encoder = JSONEncoder()

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(
            manifest
        )

        try data.write(
            to: output,
            options: .atomic
        )
    }

    static func slug(
        _ value: String
    ) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(
                scalar
            )
                ? Character(
                    scalar
                )
                : "-"
        }

        let collapsed = String(
            scalars
        )
            .split(
                separator: "-"
            )
            .joined(
                separator: "-"
            )

        return collapsed.isEmpty
            ? "source"
            : collapsed
    }
}

private extension FileManager {
    func removeItemIfExists(
        _ url: URL
    ) throws {
        guard fileExists(
            atPath: url.path
        ) else {
            return
        }

        try removeItem(
            at: url
        )
    }
}

private struct SourcesAlignmentResult: Sendable {
    let metadata: SourcesManifest.Alignment?
    let sources: [SourcesManifest.Source]
}

struct SourcesManifest: Sendable, Codable, Hashable {
    let startedAt: Date
    let finishedAt: Date
    let output: String
    let alignment: Alignment?
    let sources: [Source]

    struct Alignment: Sendable, Codable, Hashable {
        let mode: String
        let baselineHostTimeSeconds: TimeInterval?
    }

    struct Source: Sendable, Codable, Hashable {
        let kind: String
        let name: String
        let output: String
        let rawOutput: String?
        let durationSeconds: Int
        let frameCount: Int?
        let sampleBufferCount: Int?
        let firstHostTimeSeconds: TimeInterval?
        let headPaddingSeconds: TimeInterval?

        func normalized(
            output: String,
            rawOutput: String,
            headPaddingSeconds: TimeInterval
        ) -> Source {
            Source(
                kind: kind,
                name: name,
                output: output,
                rawOutput: rawOutput,
                durationSeconds: durationSeconds,
                frameCount: frameCount,
                sampleBufferCount: sampleBufferCount,
                firstHostTimeSeconds: firstHostTimeSeconds,
                headPaddingSeconds: headPaddingSeconds
            )
        }
    }
}
