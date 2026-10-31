import BiathlonKit
import SwiftData
import SwiftUI

/// A finished race's rankings of the times on the course, on the range and on the shooting mat,
/// over the whole race or a single lap or shooting.
struct RaceAnalysisView: View {
    let race: Competition
    @Environment(\.ibu) private var ibu
    @State private var analysis = RaceAnalysis(measure: .course)
    @State private var loader = Loader<RaceResults>()
    @Query private var favorites: [Favorite]

    var body: some View {
        LoadableView(state: loader.state, retry: load) { ranking in
            let favoriteSet = FavoriteSet(favorites)
            List(ranking.rows) { row in
                ResultLink(row: row, highlighted: favoriteSet.contains(row))
            }
            .refreshable { await load() }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        // Pop-up buttons in the toolbar, which show their values, as on the standings.
        .toolbar {
            Picker("Measure", selection: measure) {
                ForEach(RaceAnalysis.Measure.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("measure")
            Picker("Lap or shooting", selection: segment) {
                Text("Whole race").tag(Int?.none)
                ForEach(race.segments(of: analysis.measure), id: \.self) { segment in
                    Text(Self.title(of: segment, in: analysis.measure)).tag(Optional(segment))
                }
            }
            .accessibilityIdentifier("segment")
        }
        .onChange(of: analysis) { loader.reset() }
        .task(id: analysis) { await load() }
    }

    /// Another measure keeps the lap or shooting it also has.
    private var measure: Binding<RaceAnalysis.Measure> {
        Binding {
            analysis.measure
        } set: {
            analysis = analysis.measuring($0, in: race)
        }
    }

    private var segment: Binding<Int?> {
        Binding {
            analysis.segment
        } set: {
            analysis = RaceAnalysis(measure: analysis.measure, segment: $0)
        }
    }

    private static func title(of segment: Int, in measure: RaceAnalysis.Measure) -> LocalizedStringResource {
        switch measure {
        case .course: "Lap \(segment)"
        case .range, .shooting: "Shooting \(segment)"
        }
    }

    private func load() async {
        await loader.load { try await ibu.analysis(analysis, raceID: race.id) }
    }
}

extension RaceAnalysis.Measure {
    var title: LocalizedStringResource {
        switch self {
        case .course: LocalizedStringResource("Course", comment: "Analysis ranking of the skiing times.")
        case .range: LocalizedStringResource("Range", comment: "Analysis ranking of the times on the shooting range.")
        case .shooting:
            LocalizedStringResource("Shooting", comment: "Analysis ranking of the times on the shooting mat.")
        }
    }
}
