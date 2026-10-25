import Foundation

/// Groups of tasks run by key, each group as long as all its tasks run: once one returns,
/// the others are cancelled and the group leaves. Running a key again replaces its group,
/// like `task(id:)`. Only the groups still running are kept.
final class KeyedTasks<Key: Hashable> {
    private struct Group {
        let id = UUID()
        var tasks: [Task<Void, Never>] = []
    }

    private var groups: [Key: Group] = [:]

    /// The keys whose group still runs.
    var keys: Set<Key> { Set(groups.keys) }

    func run(_ key: Key, _ operations: (@MainActor () async -> Void)...) {
        cancel(key)
        var group = Group()
        let id = group.id
        group.tasks = operations.map { operation in
            Task { [weak self] in
                await operation()
                // A replaced group's task leaves the group running in its place alone.
                if self?.groups[key]?.id == id { self?.cancel(key) }
            }
        }
        groups[key] = group
    }

    func cancel(_ key: Key) {
        for task in groups.removeValue(forKey: key)?.tasks ?? [] { task.cancel() }
    }

    isolated deinit {
        for task in groups.values.flatMap(\.tasks) { task.cancel() }
    }
}
