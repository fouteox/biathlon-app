import BiathlonKit
import SwiftUI
import os

struct AthleteView: View {
    let athleteID: String
    let name: String

    @Environment(\.ibu) private var ibu
    @State private var loader = Loader<Profile>()

    private struct Profile {
        let bio: AthleteBio
        /// Empty when the history can't be loaded: the profile still shows.
        let results: [AthleteResult]
    }

    var body: some View {
        LoadableView(state: loader.state, retry: load) { profile in
            let bio = profile.bio
            let results = profile.results
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
                        .frame(width: 72, height: 72)
                        .clipShape(.circle)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bio.fullName).font(.title3.bold())
                            Text(verbatim: "\(Nation.flag(bio.nation) ?? "") \(bio.nation ?? "")")
                            if let birthdate = bio.birthdate {
                                Text(birthdate, format: Self.birthdateStyle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let nation = bio.nation {
                    Section {
                        HStack {
                            Text("Follow team \(Nation.flag(nation) ?? "") \(nation)")
                            Spacer()
                            FavoriteButton(kind: .nation, key: nation, name: nation, nation: nation)
                        }
                    }
                }
                if !results.isEmpty {
                    Section("Latest results") {
                        ForEach(results.prefix(30)) { result in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(result.competition ?? "")
                                    Text([result.place, result.season].compactMap(\.self).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(result.rank ?? "–").font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            FavoriteButton(kind: .athlete, key: athleteID, name: name, nation: loader.state.value?.bio.nation)
        }
        .ibuAttribution()
        .task { await load() }
    }

    /// Birthdates arrive at midnight UTC, so they are formatted in UTC.
    private static let birthdateStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.day().month(.wide).year()
        style.timeZone = .gmt
        return style
    }()

    private func load() async {
        await loader.load {
            async let results = ibu.athleteResults(id: athleteID)
            let bio = try await ibu.athlete(id: athleteID)
            do {
                return Profile(bio: bio, results: try await results)
            } catch {
                Logger.data.error("Athlete history failed: \(String(describing: error), privacy: .public)")
                return Profile(bio: bio, results: [])
            }
        }
    }
}
