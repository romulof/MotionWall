import Foundation

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            box.result = .success(try await operation())
        } catch {
            box.result = .failure(error)
        }
        finished.signal()
    }
    finished.wait()
    guard let result = box.result else { throw MotionWallError.concurrencyFailure }
    return try result.get()
}
