import Capture
import Foundation

enum SourceProcessAudioCommandRunner {
    static func run(
        _ options: CaptureProcessAudioRecordingOptions
    ) async throws {
        print(
            "process audio: recording"
        )
        print(
            "  output      \(options.output.path)"
        )
        print(
            "  duration    \(options.duration.seconds)s"
        )
        print(
            "  source      \(sourceDescription(options.selection))"
        )

        let result = try await CoreAudioProcessAudioRecorder().record(
            options: options
        )

        print(
            "process audio: stopped"
        )
        print(
            "  process     \(result.processName)"
        )

        if let bundleIdentifier = result.bundleIdentifier {
            print(
                "  bundle id   \(bundleIdentifier)"
            )
        }

        print(
            "  pid         \(result.processID)"
        )
        print(
            "  object id   \(result.processObjectID)"
        )
        print(
            "  buffers     \(result.bufferCount)"
        )
        print(
            "  frames      \(result.frameCount)"
        )
        print(
            "  peak        \(String(format: "%.6f", result.peak))"
        )
        print(
            "  captured    \(result.capturedAudio ? "yes" : "silent")"
        )
        print(
            "  wrote       \(result.output.path)"
        )

        guard result.bufferCount > 0,
              result.frameCount > 0 else {
            throw CaptureError.audioCapture(
                "Process audio captured no buffers from \(result.processName)."
            )
        }
    }
}

private extension SourceProcessAudioCommandRunner {
    static func sourceDescription(
        _ selection: CaptureProcessAudioSelection
    ) -> String {
        switch selection {
        case .pid(let pid):
            return "pid \(pid)"

        case .application_name(let name):
            return "app \(name)"

        case .bundle_identifier(let bundleIdentifier):
            return "bundle \(bundleIdentifier)"
        }
    }
}
