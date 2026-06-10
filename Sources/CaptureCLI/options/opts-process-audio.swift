import Arguments
import Capture
import Foundation
import Methods

struct ProcessAudioCommandOptions: Sendable, ArgumentParsed {
    typealias ArgumentPayload = Payload

    let options: CaptureProcessAudioRecordingOptions

    init(
        arguments: Payload
    ) throws {
        self.options = try CaptureProcessAudioRecordingOptions(
            selection: arguments.selection(),
            output: arguments.output.url(),
            durationSeconds: arguments.durationSeconds
        )
    }

    struct Payload: ArgumentGroup {
        @Group("output")
        var output: CaptureOutputOptions

        @Opt(
            "app",
            default: "FaceTime"
        )
        var app: String

        @Opt("bundle-id")
        var bundleIdentifier: String?

        @Opt("pid")
        var pid: Int?

        @Opt(
            "duration",
            short: "d",
            default: 10
        )
        var durationSeconds: Int

        init() {}

        func selection() throws -> CaptureProcessAudioSelection {
            if let pid {
                return .pid(
                    Int32(
                        pid
                    )
                )
            }

            if let bundleIdentifier = trimmedOrNil(
                bundleIdentifier
            ) {
                return .bundle_identifier(
                    bundleIdentifier
                )
            }

            return .application_name(
                app
            )
        }
    }
}
