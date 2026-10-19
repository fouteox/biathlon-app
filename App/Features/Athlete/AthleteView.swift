import BiathlonKit
import SwiftUI

struct AthleteView: View {
    let athleteID: String
    let name: String

    @Environment(\.ibu) private var ibu
    @State private var bio: Loadable<AthleteBio> = .loading
    @State private var results: [AthleteResult] = []

    var body: some View {
        LoadableView(state: bio, retry: load) { bio in
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
                            Text("\(Nation.flag(bio.nation)) \(bio.nation ?? "")")
                            if let birthdate = bio.birthdate {
                                Text(birthdate, format: .dateTime.day().month(.wide).year())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let nation = bio.nation {
                    Section {
                        HStack {
                            Text("Suivre l'équipe \(Nation.flag(nation)) \(nation)")
                            Spacer()
                            FavoriteButton(kind: .nation, key: nation, name: nation, nation: nation)
                        }
                    }
                }
                if !results.isEmpty {
                    Section("Derniers résultats") {
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
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            FavoriteButton(kind: .athlete, key: athleteID, name: name, nation: bio.value?.nation)
        }
        .ibuAttribution()
        .task { await load() }
    }

    private func load() async {
        do {
            async let bioTask = ibu.athlete(id: athleteID)
            async let resultsTask = ibu.athleteResults(id: athleteID)
            bio = .loaded(try await bioTask)
            results = (try? await resultsTask) ?? []
        } catch {
            bio = .failed(error)
        }
    }
}
