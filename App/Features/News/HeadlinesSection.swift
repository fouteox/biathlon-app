import BiathlonKit
import SwiftUI

/// The latest headlines about an athlete or a team. Each opens its article on the outlet's site: the
/// app shows only the headline, its outlet and its date.
struct HeadlinesSection: View {
    let headlines: [Headline]

    /// The most an athlete's or a nation's screen shows.
    static let limit = 5

    var body: some View {
        if !headlines.isEmpty {
            Section("News") {
                ForEach(headlines.prefix(Self.limit)) { headline in
                    Link(destination: headline.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: headline.title)
                                .foregroundStyle(.primary)
                            Group {
                                if let date = headline.date {
                                    let day = Text(date, format: .dateTime.day().month())
                                    Text("\(Text(verbatim: headline.source)) · \(day)")
                                } else {
                                    Text(verbatim: headline.source)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
