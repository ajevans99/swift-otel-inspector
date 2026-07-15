import Foundation

public struct LogStoreConfiguration: Hashable, Sendable {
    public let maximumLogCount: Int
    public let maximumEstimatedBytes: Int
    public let maximumAge: Duration
    public let maximumAttributeValueBytes: Int

    public init(
        maximumLogCount: Int = 2_000,
        maximumEstimatedBytes: Int = 5_000_000,
        maximumAge: Duration = .seconds(3_600),
        maximumAttributeValueBytes: Int = 4_096
    ) {
        precondition(maximumLogCount > 0, "maximumLogCount must be greater than zero")
        precondition(maximumEstimatedBytes > 0, "maximumEstimatedBytes must be greater than zero")
        precondition(maximumAge > .zero, "maximumAge must be greater than zero")
        precondition(
            maximumAttributeValueBytes > 0,
            "maximumAttributeValueBytes must be greater than zero"
        )
        self.maximumLogCount = maximumLogCount
        self.maximumEstimatedBytes = maximumEstimatedBytes
        self.maximumAge = maximumAge
        self.maximumAttributeValueBytes = maximumAttributeValueBytes
    }
}

public struct LogStoreStatistics: Equatable, Sendable {
    public let logCount: Int
    public let estimatedBytes: Int

    public init(logCount: Int, estimatedBytes: Int) {
        self.logCount = logCount
        self.estimatedBytes = estimatedBytes
    }
}

public actor LogStore {
    public typealias Clock = @Sendable () -> TelemetryTimestamp

    public let configuration: LogStoreConfiguration

    private let redactor: AttributeRedactor
    private let clock: Clock
    private var logsByID: [UUID: LogSnapshot] = [:]
    private var continuations: [UUID: AsyncStream<[LogSnapshot]>.Continuation] = [:]
    private var expirationTask: Task<Void, Never>?
    private var expirationGeneration: UInt64 = 0

    public init(
        configuration: LogStoreConfiguration = LogStoreConfiguration(),
        redactor: @escaping AttributeRedactor = { _, value in value },
        clock: @escaping Clock = { TelemetryTimestamp(date: Date()) }
    ) {
        self.configuration = configuration
        self.redactor = redactor
        self.clock = clock
    }

    public func insert(_ logs: [LogSnapshot]) {
        for log in logs {
            let sanitized = sanitize(log)
            logsByID[sanitized.id] = sanitized
        }
        _ = evictExpired()
        evictToLimits()
        scheduleExpiration()
        publish()
    }

    public func removeAll() {
        expirationGeneration &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        logsByID.removeAll(keepingCapacity: true)
        publish()
    }

    public func logs() -> [LogSnapshot] {
        if evictExpired() {
            publish()
        }
        return orderedLogs()
    }

    public func logs(traceID: TraceID) -> [LogSnapshot] {
        logs().filter { $0.traceID == traceID }
    }

    public func statistics() -> LogStoreStatistics {
        if evictExpired() {
            publish()
        }
        return LogStoreStatistics(
            logCount: logsByID.count,
            estimatedBytes: estimatedByteCount
        )
    }

    public func changes() -> AsyncStream<[LogSnapshot]> {
        if evictExpired() {
            publish()
        }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(orderedLogs())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    private var estimatedByteCount: Int {
        logsByID.values.reduce(0) { $0 + $1.estimatedByteCount }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish() {
        let logs = orderedLogs()
        for continuation in continuations.values {
            continuation.yield(logs)
        }
    }

    private func orderedLogs() -> [LogSnapshot] {
        logsByID.values.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp > $1.timestamp
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func sanitize(_ log: LogSnapshot) -> LogSnapshot {
        LogSnapshot(
            id: log.id,
            timestamp: log.timestamp,
            observedTimestamp: log.observedTimestamp,
            traceID: log.traceID,
            spanID: log.spanID,
            severity: log.severity,
            body: log.body?.truncated(to: configuration.maximumAttributeValueBytes),
            eventName: log.eventName,
            attributes: sanitize(log.attributes),
            resource: ResourceSnapshot(
                attributes: sanitize(log.resource.attributes),
                schemaURL: log.resource.schemaURL
            ),
            instrumentationScope: InstrumentationScopeSnapshot(
                name: log.instrumentationScope.name,
                version: log.instrumentationScope.version,
                schemaURL: log.instrumentationScope.schemaURL,
                attributes: sanitize(log.instrumentationScope.attributes)
            )
        )
    }

    private func sanitize(
        _ attributes: [String: TelemetryAttributeValue]
    ) -> [String: TelemetryAttributeValue] {
        attributes.reduce(into: [:]) { result, entry in
            guard let redacted = redactor(entry.key, entry.value) else {
                return
            }
            result[entry.key] = redacted.truncated(to: configuration.maximumAttributeValueBytes)
        }
    }

    private func evictToLimits() {
        while
            logsByID.count > configuration.maximumLogCount
                || estimatedByteCount > configuration.maximumEstimatedBytes
        {
            guard let oldest = logsByID.values.min(by: evictionOrdering) else {
                return
            }
            logsByID.removeValue(forKey: oldest.id)
        }
    }

    private func evictionOrdering(_ lhs: LogSnapshot, _ rhs: LogSnapshot) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    @discardableResult
    private func evictExpired() -> Bool {
        let previousCount = logsByID.count
        let now = clock().nanosecondsSinceEpoch
        let age = configuration.maximumAge.nanosecondsClamped
        let cutoff = now > age ? now - age : 0
        logsByID = logsByID.filter { $0.value.timestamp.nanosecondsSinceEpoch >= cutoff }
        return logsByID.count != previousCount
    }

    private func scheduleExpiration() {
        expirationGeneration &+= 1
        let generation = expirationGeneration
        expirationTask?.cancel()
        expirationTask = nil
        guard let oldestTimestamp = logsByID.values.map(\.timestamp.nanosecondsSinceEpoch).min() else {
            return
        }

        let now = clock().nanosecondsSinceEpoch
        let age = configuration.maximumAge.nanosecondsClamped
        let expiration = oldestTimestamp.addingReportingOverflow(age)
        let firstExpired = expiration.partialValue.addingReportingOverflow(1)
        let expirationTime = expiration.overflow || firstExpired.overflow
            ? UInt64.max
            : firstExpired.partialValue
        let delay = expirationTime > now ? expirationTime - now : 1

        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(Int64(clamping: delay)))
            guard !Task.isCancelled else {
                return
            }
            await self?.expireAndReschedule(generation: generation)
        }
    }

    private func expireAndReschedule(generation: UInt64) {
        guard generation == expirationGeneration else {
            return
        }
        expirationTask = nil
        if evictExpired() {
            publish()
        }
        scheduleExpiration()
    }
}
