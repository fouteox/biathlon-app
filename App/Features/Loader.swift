import Foundation
import Observation
import os

/// Generic loading state for screens.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(any Error)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }
}

/// Loads a screen's data with one policy for every screen:
/// - a cancelled load (the screen went away or its input changed) changes nothing;
/// - a failed refresh keeps the data already shown, only a first load shows the error;
/// - every failure is logged.
@Observable
final class Loader<Value> {
    private(set) var state: Loadable<Value> = .loading

    /// Back to the loading state, when the screen's input changes (another season…).
    func reset() {
        state = .loading
    }

    /// Whether the value shown is the one just fetched.
    @discardableResult
    func load(_ fetch: () async throws -> Value) async -> Bool {
        do {
            let value = try await fetch()
            guard !Task.isCancelled else { return false }
            state = .loaded(value)
            return true
        } catch {
            // Cancellation surfaces as `CancellationError` or `URLError(.cancelled)`;
            // `Task.isCancelled` covers both.
            guard !Task.isCancelled else { return false }
            Logger.data.error("Load failed: \(String(describing: error), privacy: .public)")
            if state.value == nil { state = .failed(error) }
            return false
        }
    }
}
