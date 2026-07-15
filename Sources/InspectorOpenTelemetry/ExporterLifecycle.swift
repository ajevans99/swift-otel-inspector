import Foundation

final class ExporterLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let pendingExports = DispatchGroup()
    private var isShutdown = false

    func begin() -> Bool {
        lock.withLock {
            guard !isShutdown else {
                return false
            }
            pendingExports.enter()
            return true
        }
    }

    func complete() {
        pendingExports.leave()
    }

    func markShutdown() {
        lock.withLock {
            isShutdown = true
        }
    }

    func wait(explicitTimeout: TimeInterval?) -> Bool {
        pendingExports.wait(timeout: deadline(for: explicitTimeout)) == .success
    }

    func wait(explicitTimeout: TimeInterval?) async -> Bool {
        let waiter = ExportWaiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.install(continuation)
                pendingExports.notify(queue: .global()) {
                    waiter.resume(returning: true)
                }
                if let explicitTimeout {
                    DispatchQueue.global().asyncAfter(deadline: deadline(for: explicitTimeout)) {
                        waiter.resume(returning: false)
                    }
                }
            }
        } onCancel: {
            waiter.resume(returning: false)
        }
    }

    private func deadline(for timeout: TimeInterval?) -> DispatchTime {
        guard let timeout else {
            return .distantFuture
        }
        return .now() + max(0, timeout)
    }
}

private final class ExportWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var pendingResult: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        let result = lock.withLock {
            guard let pendingResult else {
                self.continuation = continuation
                return nil as Bool?
            }
            return pendingResult
        }
        if let result {
            continuation.resume(returning: result)
        }
    }

    func resume(returning result: Bool) {
        let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard let continuation = self.continuation else {
                pendingResult = pendingResult ?? result
                return nil
            }
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
}
