import Foundation

/// Items that share a calendar period, as a list shows them under one header.
public struct DatedGroup<Item: Identifiable & Sendable>: Identifiable, Sendable {
    /// The first instant of the period in the calendar the items were grouped with.
    public let start: Date
    public let items: [Item]

    public var id: Date { start }
}

extension Sequence where Element: Identifiable & Sendable {
    /// The items by the period their date falls in, periods and items in date order.
    func grouped(by components: Set<Calendar.Component>, date: (Element) -> Date, calendar: Calendar)
        -> [DatedGroup<Element>]
    {
        let periods = Dictionary(grouping: self) {
            calendar.date(from: calendar.dateComponents(components, from: date($0)))!
        }
        return periods.keys.sorted().map { start in
            DatedGroup(start: start, items: periods[start]!.sorted { date($0) < date($1) })
        }
    }
}

extension Sequence<BiathlonEvent> {
    /// The events by month of their first day, as the calendar lists a season.
    public func groupedByMonth(calendar: Calendar) -> [DatedGroup<BiathlonEvent>] {
        grouped(by: [.year, .month], date: \.startDate, calendar: calendar)
    }
}

extension Sequence<Competition> {
    /// The races by day, as an event's schedule lists them: the day in the header, the time on the row.
    public func groupedByDay(calendar: Calendar) -> [DatedGroup<Competition>] {
        grouped(by: [.year, .month, .day], date: \.startTime, calendar: calendar)
    }
}

extension BiathlonEvent {
    public enum Phase: Sendable {
        case past, underway, upcoming
    }

    /// Where the event stands at `now`: underway from the start of its first day to the end of
    /// its last one, since the IBU gives its dates without times.
    public func phase(at now: Date, calendar: Calendar) -> Phase {
        if now < calendar.startOfDay(for: startDate) { return .upcoming }
        guard let lastDayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)),
            now < lastDayEnd
        else { return .past }
        return .underway
    }
}

extension Collection<BiathlonEvent> {
    /// The event a season's calendar opens on: the one underway, otherwise the next; after the
    /// last one, that last one.
    public func eventToShow(at now: Date, calendar: Calendar) -> BiathlonEvent? {
        let ordered = sorted { $0.startDate < $1.startDate }
        return ordered.first { $0.phase(at: now, calendar: calendar) != .past } ?? ordered.last
    }
}
