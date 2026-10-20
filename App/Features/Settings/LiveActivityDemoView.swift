#if DEBUG
    import ActivityKit
    import BiathlonKit
    import SwiftUI
    import UIKit

    /// Plays `RaceLiveState.demo` in a Live Activity, to try it without a race the way Apple
    /// suggests testing ActivityKit pushes: the activity subscribes to a channel created in the
    /// Push Notifications Console, in the development environment, which can then broadcast the
    /// payloads copied here; each state can also be shown locally. Debug builds only, its text
    /// stays out of the String Catalog.
    struct LiveActivityDemoView: View {
        @AppStorage("liveActivityDemoChannelID") private var channelID = ""
        /// The start of the race the demo activity plays; `nil` without one.
        @State private var startTime: Date?
        @State private var failure: String?

        var body: some View {
            Form {
                Section {
                    TextField(text: $channelID, prompt: Text(verbatim: "Channel ID")) {
                        Text(verbatim: "Channel ID")
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } footer: {
                    Text(
                        verbatim:
                            "Create a channel in the Push Notifications Console: development environment, No Message Storage."
                    )
                }

                if let startTime {
                    Section {
                        ForEach(RaceLiveState.demo(startTime: startTime), id: \.self) { state in
                            HStack {
                                Button {
                                    Task {
                                        await LiveActivities.update(raceID: Self.raceID, state: state, timestamp: .now)
                                    }
                                } label: {
                                    LabeledContent {
                                        Text(verbatim: state.leaders.first?.name ?? "")
                                    } label: {
                                        Text(state.phase.label)
                                    }
                                }
                                Button {
                                    copyPayload(state)
                                } label: {
                                    Label {
                                        Text(verbatim: "Copy payload")
                                    } icon: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } footer: {
                        Text(
                            verbatim:
                                "Tap a state to show it, or copy its payload right before broadcasting it from the console: ActivityKit ignores a payload older than the last update."
                        )
                    }

                    Section {
                        Button(role: .destructive) {
                            Task {
                                await LiveActivities.end(raceID: Self.raceID)
                                self.startTime = nil
                            }
                        } label: {
                            Text(verbatim: "End")
                        }
                    }
                } else {
                    Section {
                        Button {
                            start(startTime: .now + 10 * 60)
                        } label: {
                            Text(verbatim: "Start now")
                        }
                        Button {
                            // Shown a minute from now, the lead before the start.
                            start(startTime: .now + 60 + RaceLiveState.activityLead)
                        } label: {
                            Text(verbatim: "Schedule in 1 minute")
                        }
                    }
                    .disabled(channelID.isEmpty)
                }

                if let failure {
                    Section {
                        Text(verbatim: failure).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Live Activity demo"))
            .onAppear {
                startTime =
                    Activity<RaceActivityAttributes>.activities
                    .first {
                        $0.attributes.raceID == Self.raceID && LiveActivities.shownStates.contains($0.activityState)
                    }?
                    .content.state.startTime
            }
        }

        private static let raceID = RaceActivityAttributes.demoRaceID

        private func start(startTime: Date) {
            do {
                try LiveActivities.request(
                    raceID: Self.raceID, name: RaceActivityAttributes.demoName, channelID: channelID,
                    state: RaceLiveState.demo(startTime: startTime)[0])
                self.startTime = startTime
                failure = nil
            } catch {
                failure = String(describing: error)
            }
        }

        /// Copies a broadcast showing `state` for the console: its `content-state` has ActivityKit's
        /// default coding, as the server sends it.
        private func copyPayload(_ state: RaceLiveState) {
            let broadcast = Broadcast(
                aps: .init(
                    timestamp: Int(Date.now.timeIntervalSince1970), event: "update",
                    relevanceScore: state.relevanceScore, contentState: state))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                UIPasteboard.general.string = String(decoding: try encoder.encode(broadcast), as: UTF8.self)
                failure = nil
            } catch {
                failure = String(describing: error)
            }
        }

        private struct Broadcast: Encodable {
            let aps: APS

            struct APS: Encodable {
                let timestamp: Int
                let event: String
                let relevanceScore: Double
                let contentState: RaceLiveState

                enum CodingKeys: String, CodingKey {
                    case timestamp, event
                    case relevanceScore = "relevance-score"
                    case contentState = "content-state"
                }
            }
        }
    }
#endif
