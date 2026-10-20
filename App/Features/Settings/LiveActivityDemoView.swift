#if DEBUG
    import ActivityKit
    import BiathlonKit
    import SwiftUI
    import UIKit

    /// Plays `RaceLiveState.demo` in a Live Activity, to try it without a race the way Apple
    /// suggests testing ActivityKit pushes: the activity subscribes to a channel created in the
    /// Push Notifications Console, in the development environment, which can then broadcast the
    /// payloads copied here; each state can also be shown locally. The console can also start it
    /// with the push-to-start token, from the start payload the server sends for a favorite's race
    /// (server/src/liveStarts.ts). Debug builds only, its text stays out of the String Catalog.
    struct LiveActivityDemoView: View {
        @Environment(LiveActivityStarts.self) private var liveActivityStarts
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

                    Section {
                        Button {
                            UIPasteboard.general.string = liveActivityStarts.token
                        } label: {
                            Text(verbatim: "Copy push-to-start token")
                        }
                        .disabled(liveActivityStarts.token == nil)
                        Button {
                            copyStartPayload()
                        } label: {
                            Text(verbatim: "Copy start payload")
                        }
                        .disabled(channelID.isEmpty)
                    } header: {
                        Text(verbatim: "Push to start")
                    } footer: {
                        Text(
                            verbatim:
                                "Send the start payload from the console to the push-to-start token, push type liveactivity: the activity starts with an alert and subscribes to the channel above."
                        )
                    }
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

        /// Copies a broadcast showing `state` for the console, as the server sends it: an end event
        /// once the race is over, and a `content-state` with ActivityKit's default coding.
        private func copyPayload(_ state: RaceLiveState) {
            copy(
                Push(
                    aps: .init(
                        timestamp: Int(Date.now.timeIntervalSince1970),
                        event: state.phase.canBeFollowedLive ? "update" : "end",
                        relevanceScore: state.relevanceScore, contentState: state)))
        }

        /// Copies the start payload the server sends for a favorite's race 30 minutes before it,
        /// on the demo race: its attributes, its channel and Apple's required alert.
        private func copyStartPayload() {
            let state = RaceLiveState.demo(startTime: .now + RaceLiveState.activityLead)[0]
            let name = RaceActivityAttributes.demoName
            copy(
                Push(
                    aps: .init(
                        timestamp: Int(Date.now.timeIntervalSince1970), event: "start",
                        relevanceScore: state.relevanceScore, contentState: state,
                        attributesType: String(describing: RaceActivityAttributes.self),
                        attributes: RaceActivityAttributes(
                            raceID: Self.raceID, name: name, channelID: channelID, scheduledStart: nil),
                        inputPushChannel: channelID,
                        alert: .init(
                            title: .init(locKey: "push.liveActivity.title"),
                            body: .init(locKey: "push.liveActivity.body", locArgs: [name]),
                            sound: "default"))))
        }

        private func copy(_ push: Push) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                UIPasteboard.general.string = String(decoding: try encoder.encode(push), as: UTF8.self)
                failure = nil
            } catch {
                failure = String(describing: error)
            }
        }

        /// A broadcast, or with what only a start carries.
        private struct Push: Encodable {
            let aps: APS

            struct APS: Encodable {
                let timestamp: Int
                let event: String
                let relevanceScore: Double
                let contentState: RaceLiveState
                var attributesType: String?
                var attributes: RaceActivityAttributes?
                var inputPushChannel: String?
                var alert: Alert?

                enum CodingKeys: String, CodingKey {
                    case timestamp, event, attributes, alert
                    case relevanceScore = "relevance-score"
                    case contentState = "content-state"
                    case attributesType = "attributes-type"
                    case inputPushChannel = "input-push-channel"
                }
            }

            struct Alert: Encodable {
                let title: Localized
                let body: Localized
                let sound: String

                struct Localized: Encodable {
                    let locKey: String
                    var locArgs: [String]?

                    enum CodingKeys: String, CodingKey {
                        case locKey = "loc-key"
                        case locArgs = "loc-args"
                    }
                }
            }
        }
    }
#endif
