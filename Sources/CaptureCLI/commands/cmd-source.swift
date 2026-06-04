import Arguments

enum SourceCommand: ArgumentCommand {
    static let name = "source"

    static let children: [ArgumentCommandType] = [
        ProcessAudio.self,
    ]

    enum ProcessAudio: ParsedArgumentCommand {
        typealias Options = SourceProcessAudioCommandOptions

        static let name = "process-audio"

        static func run(
            _ options: SourceProcessAudioCommandOptions,
            invocation: ParsedInvocation
        ) async throws {
            try await SourceProcessAudioCommandRunner.run(
                options.options
            )
        }
    }
}
