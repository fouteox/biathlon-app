import Testing

@testable import Biathlon

struct KeyedTasksTests {
    /// Runs until cancelled, then reports `name` on `stopped`.
    private static func untilCancelled(
        reporting name: String, to stopped: AsyncStream<String>.Continuation
    ) -> @MainActor () async -> Void {
        {
            // `Task.sleep` throws as soon as the task is cancelled.
            try? await Task.sleep(for: .seconds(3600))
            stopped.yield(name)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aGroupLeavesOnceOneOfItsTasksReturns() async {
        let tasks = KeyedTasks<String>()
        let (stopped, continuation) = AsyncStream.makeStream(of: String.self)
        tasks.run("activity", {}, Self.untilCancelled(reporting: "observer", to: continuation))

        var events = stopped.makeAsyncIterator()
        #expect(await events.next() == "observer")
        #expect(tasks.keys.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func runningAKeyAgainReplacesItsGroup() async {
        let tasks = KeyedTasks<String>()
        let (stopped, continuation) = AsyncStream.makeStream(of: String.self)
        tasks.run("activity", Self.untilCancelled(reporting: "first", to: continuation))
        tasks.run("activity", Self.untilCancelled(reporting: "second", to: continuation))

        var events = stopped.makeAsyncIterator()
        #expect(await events.next() == "first")
        // The replaced group's end leaves the new one running.
        #expect(tasks.keys == ["activity"])

        tasks.cancel("activity")
        #expect(await events.next() == "second")
        #expect(tasks.keys.isEmpty)
    }
}
