import BiathlonKit
import EventKit
import EventKitUI
import SwiftUI

/// What a race puts in the person's calendar, through the system's event editor.
struct RaceCalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let location: String?

    init(race: Competition, event: BiathlonEvent?) {
        id = race.id
        title = race.title
        start = race.startTime
        location = event?.shortDescription
    }

    /// The IBU gives a race's start, not its end: the entry ends when it starts, and the
    /// person can change that in the editor. EventKit only refuses an end before the start.
    func event(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start
        event.location = location
        return event
    }
}

/// The system's event editor. Since iOS 17 it runs outside the app and saves to the calendar
/// the person picks, without the app asking for calendar access.
struct RaceCalendarEditor: UIViewControllerRepresentable {
    let entry: RaceCalendarEntry
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = entry.event(in: store)
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        /// Saved or cancelled alike, the editor has done its job.
        func eventEditViewController(
            _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
        ) {
            dismiss()
        }
    }
}
