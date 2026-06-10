import Arguments
import Capture
import Foundation
import Methods

struct SourcesCommandOptions: Sendable, ArgumentParsed {
    typealias ArgumentPayload = Payload

    let output: URL
    let workspace: CaptureWorkspaceOptions
    let durationSeconds: Int?
    let video: CaptureVideoOptions
    let audio: CaptureAudioOptions?
    let audioSourceName: String?
    let systemAudio: CaptureSystemAudioOptions
    let microphoneChain: AudioChain
    let screenEnabled: Bool
    let cameras: [SourcesCameraInput]
    let alignStart: Bool

    init(
        arguments: Payload
    ) throws {
        let output = try arguments.output.directoryURL()
        let video = try arguments.video.video(
            defaultFPS: 24
        )
        let audioSourceName = arguments.microphone.sourceName
        let audio = try audioSourceName.map { _ in
            try arguments.microphone.audio(
                sampleRate: arguments.sampleRate,
                channel: arguments.channel,
                codec: .pcm
            )
        }

        self.output = output
        self.workspace = arguments.workspace.workspace()
        self.durationSeconds = try arguments.duration.optional()
        self.video = video
        self.audio = audio
        self.audioSourceName = audioSourceName
        self.systemAudio = try arguments.systemAudio.systemAudio()
        self.microphoneChain = arguments.microphoneChain.chain
        self.screenEnabled = arguments.screen
        self.cameras = arguments.cameras()
        self.alignStart = arguments.alignStart
    }

    struct Payload: ArgumentGroup {
        @Group("output")
        var output: CaptureOutputOptions

        @Group("workspace")
        var workspace: CaptureWorkspaceCLIOptions

        @Group("duration")
        var duration: CaptureDurationOptions

        @Group("video")
        var video: CaptureVideoCLIOptions

        @Group("audio")
        var microphone: CaptureMicrophoneOptions

        @Group("mic-chain")
        var microphoneChain: CaptureMicrophoneChainOptions

        @Group("system-audio")
        var systemAudio: CaptureSystemAudioCLIOptions

        @Flag("screen")
        var screen: Bool

        @Flag("align-start")
        var alignStart: Bool

        @Opt(
            "camera",
            short: "c"
        )
        var camera: String?

        @Opt("camera-2")
        var camera2: String?

        @Opt("camera-3")
        var camera3: String?

        @Opt("camera-4")
        var camera4: String?

        @Opt(
            "sample-rate",
            default: 48_000
        )
        var sampleRate: Int

        @Opt(
            "channel",
            default: 2
        )
        var channel: Int

        init() {}

        func cameras() -> [SourcesCameraInput] {
            [
                camera,
                camera2,
                camera3,
                camera4,
            ]
                .compactMap {
                    trimmedOrNil(
                        $0
                    )
                }
                .map {
                    SourcesCameraInput(
                        name: $0
                    )
                }
        }
    }
}

struct SourcesCameraInput: Sendable, Codable, Hashable {
    let name: String

    var input: CaptureVideoInput {
        .name(
            name
        )
    }
}
