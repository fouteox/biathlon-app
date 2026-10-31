import AppIntents
import BiathlonKit
import Foundation

/// Siri and Shortcuts: the live race, otherwise the next one.
struct NextRaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Next race"
    static let description = IntentDescription("The live race, otherwise the next one.")

    @Dependency private var ibu: IBUClient

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let feed = try await ibu.featuredRaces(now: .now)
        return .result(dialog: IntentDialog(SiriAnswer.nextRace(in: feed)))
    }
}

/// Siri and Shortcuts: the podium of the latest finished race.
struct LatestResultIntent: AppIntent {
    static let title: LocalizedStringResource = "Latest result"
    static let description = IntentDescription("The podium of the latest finished race.")

    @Dependency private var ibu: IBUClient

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let feed = try await ibu.homeFeed(now: .now)
        return .result(dialog: IntentDialog(SiriAnswer.latestResult(in: feed)))
    }
}

/// The phrases that run the intents, each with the app's name as App Shortcuts require; their
/// translations are in AppShortcuts.xcstrings.
struct BiathlonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextRaceIntent(),
            phrases: [
                "Next race in \(.applicationName)",
                "When is the next race in \(.applicationName)",
                "What's the next \(.applicationName) race",
            ],
            shortTitle: "Next race",
            systemImageName: "calendar")
        AppShortcut(
            intent: LatestResultIntent(),
            phrases: [
                "Latest result in \(.applicationName)",
                "Who won the last race in \(.applicationName)",
                "Last \(.applicationName) result",
            ],
            shortTitle: "Latest result",
            systemImageName: "trophy")
    }
}

/// What Siri says, as a sentence a voice reads well: race and place first, then the answer.
enum SiriAnswer {
    static func nextRace(in feed: HomeFeed) -> LocalizedStringResource {
        guard let race = feed.upcomingRace else { return "No race scheduled." }
        let heading = RaceSummary.heading(of: race, at: feed.event(of: race))
        if race.state == .live { return "Live now: \(heading)." }
        let start = race.startTime.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        return "Next race: \(heading), \(start)."
    }

    static func latestResult(in feed: HomeFeed) -> LocalizedStringResource {
        guard let race = feed.latestFinished, let results = feed.latestResults,
            let podium = RaceSummary.podium(of: race, at: feed.event(of: race), results: results)
        else { return "No results yet." }
        return podium
    }
}
