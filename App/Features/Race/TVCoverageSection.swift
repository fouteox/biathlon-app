import BiathlonKit
import SwiftUI

/// Who shows the race on TV: the viewer's own country, then the others the server lists,
/// folded away but always there to look up, whatever the app's language. Each broadcaster
/// opens its live stream.
struct TVCoverageSection: View {
    let listings: TVGuide.Listings

    var body: some View {
        if !listings.isEmpty {
            Section {
                if let home = listings.home {
                    rows(of: home)
                }
                if !listings.others.isEmpty {
                    DisclosureGroup("Other countries") {
                        ForEach(listings.others) { listing in rows(of: listing) }
                    }
                }
            } header: {
                Text("On TV")
            } footer: {
                Text("Live on TV or on the broadcaster's stream. Schedules can change.")
            }
        }
    }

    private func rows(of listing: TVGuide.Listing) -> some View {
        ForEach(listing.broadcasters, id: \.self) { coverage in
            LabeledContent {
                Link(coverage.broadcaster, destination: coverage.url)
            } label: {
                Text(verbatim: Self.name(of: listing.country))
            }
        }
    }

    private static func name(of country: String) -> String {
        Nation.titled(Locale.current.localizedString(forRegionCode: country) ?? country, region: country)
    }
}
