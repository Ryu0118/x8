import ArgumentParser
import X8Core
import X8Kit
import X8Storage

struct CachePurgeCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "purge",
        abstract: "Plan or delete old cache objects."
    )

    private static let shortGraceThreshold = Duration.seconds(3600)

    @Option(name: .long, help: "The cache scope: staging, action-cache, or cas.")
    var scope: CachePurgeScopeArgument

    @Option(
        name: .long,
        help: "Age threshold for staging and Action Cache objects, e.g. \"30m\", \"2h\", \"7d\"."
    )
    var olderThan: String?

    @Option(
        name: .long,
        help: """
        Grace period for unreachable CAS objects, e.g. "30m", "2h", "7d". \
        Must exceed the longest build that may be running against this cache.
        """
    )
    var gracePeriod: String?

    @Flag(name: .long, help: "Show the plan without deleting anything.")
    var dryRun = false

    @Flag(name: .long, help: "Allow deletion of the objects in the generated plan.")
    var confirm = false

    @Flag(
        name: .long,
        help: """
        Allow a --grace-period under one hour for the cas scope. \
        A short grace period can select objects a currently running build has not finished writing.
        """
    )
    var allowShortGrace = false

    mutating func validate() throws {
        try validateOptions(for: scope.value)
        try validateDurations()
    }

    func run(context: X8CommandContext) async throws {
        let request = try makeRequest(scope: scope.value)
        let configured = try await context.loadConfiguration()
        try await configured.withStorage { storage in
            guard let administration = storage.administration else {
                throw ValidationError("This storage does not support cache administration.")
            }
            let outcome = try await CachePurgeRunner(
                administration: administration,
                referenceReader: storage.referenceReader,
                retentionStore: storage.retentionStore,
                actionCacheStore: storage.actionCacheStore
            ).run(request: request, dryRun: dryRun, confirm: confirm)
            Self.log(
                outcome,
                configuration: configured.configuration,
                confirmed: confirm && !dryRun,
                context: context
            )
        }
    }

    private func validateOptions(for scope: CachePurgeScope) throws {
        switch scope {
        case .staging, .actionCache:
            try require(
                olderThan,
                message: "--older-than is required for this scope."
            )
            try reject(
                gracePeriod,
                message: "--grace-period is valid only for the cas scope."
            )
        case .cas:
            try require(
                gracePeriod,
                message: "--grace-period is required for the cas scope."
            )
            try reject(
                olderThan,
                message: "--older-than is valid only for staging and action-cache."
            )
        }
    }

    private func validateDurations() throws {
        if let olderThan {
            _ = try parseDuration(olderThan)
        }
        guard let gracePeriod else { return }
        let parsed = try parseDuration(gracePeriod)
        guard allowShortGrace || parsed >= Self.shortGraceThreshold else {
            throw ValidationError(
                "--grace-period under one hour can select objects a currently running build "
                    + "has not finished writing. Pass --allow-short-grace to override."
            )
        }
    }

    private func require(
        _ value: String?,
        message: String
    ) throws {
        guard value != nil else {
            throw ValidationError(message)
        }
    }

    private func reject(_ value: String?, message: String) throws {
        guard value == nil else {
            throw ValidationError(message)
        }
    }

    private func parseDuration(_ source: String) throws -> Duration {
        do {
            return try CachePurgeDurationParser.parse(source)
        } catch let error as CachePurgeDurationError {
            throw ValidationError(error.description)
        }
    }

    private func makeRequest(scope: CachePurgeScope) throws -> CachePurgeRequest {
        try CachePurgeRequest(
            scope: scope,
            olderThan: olderThan.map(parseDuration) ?? .zero,
            gracePeriod: gracePeriod.map(parseDuration)
        )
    }

    private static func log(
        _ outcome: CachePurgeOutcome,
        configuration: X8CLIConfiguration<Void>,
        confirmed: Bool,
        context: X8CommandContext
    ) {
        context.logger.info(
            "Cache purge profile=\(configuration.profileID) \(configuration.storageDescription).",
            metadata: .color(.blue)
        )
        context.logger.warning(
            "⚠️ This cache may be shared by multiple projects.",
            metadata: .color(.yellow)
        )
        context.logger.info(
            "Selected \(outcome.plan.candidates.count) objects (\(outcome.plan.candidateBytes) bytes).",
            metadata: .color(.cyan)
        )
        if let result = outcome.result {
            context.logger.info(
                "✅ Deleted \(result.deletedCount) objects; skipped \(result.skippedCount); failed \(result.failedCount).",
                metadata: .color(.green)
            )
            return
        }
        if confirmed {
            context.logger.warning("⚠️ No objects were deleted.", metadata: .color(.yellow))
        } else {
            context.logger.info(
                "Plan only. Re-run with --confirm to delete the selected objects.",
                metadata: .color(.yellow)
            )
        }
    }
}
