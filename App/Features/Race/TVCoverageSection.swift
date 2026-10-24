import BiathlonKit
import SwiftUI

/// Who shows the race on TV in each country the server lists, whatever the app's language:
/// the viewer's own country first, each broadcaster opening its live stream.
struct TVCoverageSection: View {
    let listings: [TVGuide.Listing]

    var body: some View {
        if !listings.isEmpty {
            Section {
                ForEach(listings) { listing in
                    ForEach(listing.broadcasters, id: \.self) { coverage in
                        LabeledContent {
                            Link(coverage.broadcaster, destination: coverage.url)
                        } label: {
                            Text(verbatim: Self.name(of: listing.country))
                        }
                    }
                }
            } header: {
                Text("On TV")
            } footer: {
                Text("Live on TV or on the broadcaster's stream. Schedules can change.")
            }
        }
    }

    private static func name(of country: String) -> String {
        Nation.titled(Locale.current.localizedString(forRegionCode: country) ?? country, region: country)
    }
}

extension TVGuide {
    /// The guide the server keeps, `nil` for a build without a server.
    static func load() async throws -> TVGuide? {
        guard let serverURL = Bundle.main.serverURL else { return nil }
        let (data, response) = try await URLSession.shared.data(from: serverURL.appending(path: "v1/tv-coverage"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try TVGuide(json: data)
    }
}
