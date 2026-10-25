import BiathlonKit
import SwiftUI

struct AthleteView: View {
    let athleteID: String
    let name: String

    @Environment(\.ibu) private var ibu
    @State private var bio = Loader<AthleteBio>()
    /// Loaded on its own: the profile shows without waiting for it, and without it. Only the
    /// World Cup, World Championships and Olympic races, which the rest of the app follows.
    @State private var history = Loader<[AthleteResult]>()
    @ScaledMetric private var photoSize = 72.0

    var body: some View {
        LoadableView(state: bio.state, retry: load) { bio in
            let results = history.state.value ?? []
            List {
                Section {
                    HStack(spacing: 16) {
                        AsyncImage(url: bio.photoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: photoSize, height: photoSize)
                        .clipShape(.circle)
                        // The name beside it says who it is.
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bio.fullName).font(.title3.bold())
                            if bio.isDeceased {
                                Text("Deceased").foregroundStyle(.secondary)
                            }
                            if let nation = bio.nation {
                                Text(Nation.titled(nation, nation: nation))
                            }
                            if let birthdate = bio.birthdate {
                                Text(birthdate, format: Self.birthdateStyle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let nation = bio.nation {
                    Section {
                        FavoriteButton(
                            kind: .nation, key: nation, name: nation, nation: nation,
                            subject: Nation.titled(nation, nation: nation))
                    }
                }
                if !results.isEmpty {
                    Section("Latest results") {
                        ForEach(results.prefix(30)) { result in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(RaceKind.title(ofRace: result.raceID ?? "", ibuName: result.competition ?? ""))
                                    Text([result.place, result.season].compactMap(\.self).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                RankText(rank: result.rank)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            FavoriteButton(kind: .athlete, key: athleteID, name: name, nation: bio.state.value?.nation)
        }
        .task { await load() }
    }

    /// Birthdates arrive at midnight UTC, so they are formatted in UTC.
    private static let birthdateStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.day().month(.wide).year()
        style.timeZone = .gmt
        return style
    }()

    private func load() async {
        async let bioLoad: Void = bio.load { try await ibu.athlete(id: athleteID) }
        async let historyLoad: Void = history.load {
            try await ibu.athleteResults(id: athleteID).filter(\.isWorldCupCircuit)
        }
        _ = await (bioLoad, historyLoad)
    }
}
