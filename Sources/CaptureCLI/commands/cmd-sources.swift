import Arguments

enum SourcesCommand: ParsedArgumentCommand {
    typealias Options = SourcesCommandOptions

    static let name = "sources"

    static func run(
        _ options: SourcesCommandOptions,
        invocation: ParsedInvocation
    ) async throws {
        try await SourcesCommandRunner.run(
            options
        )
    }
}
