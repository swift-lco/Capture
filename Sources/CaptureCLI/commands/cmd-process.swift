import Arguments

enum ProcessCommand: ArgumentCommand {
    static let name = "process"

    static let children: [ArgumentCommandType] = [
        Audio.self,
    ]

    enum Audio: ParsedArgumentCommand {
        typealias Options = ProcessAudioCommandOptions

        static let name = "audio"

        static func run(
            _ options: ProcessAudioCommandOptions,
            invocation: ParsedInvocation
        ) async throws {
            try await ProcessAudioCommandRunner.run(
                options.options
            )
        }
    }
}
