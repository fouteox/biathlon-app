#if DEBUG
    import Foundation

    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif

    extension IBUClient {
        /// A client answering from `SampleWorldCup` instead of the network, so that the UI tests depend
        /// on neither the network nor the IBU's calendar. The data is fictional: the IBU's terms forbid
        /// redistributing theirs.
        public static func sample(now: Date) -> IBUClient {
            let worldCup = SampleWorldCup(now: now)
            return IBUClient(baseURL: ibuBaseURL) { request in try worldCup.respond(to: request) }
        }
    }

    /// A fictional World Cup, the same every season: three events of four races, and ten athletes per
    /// category, ranked in the same order everywhere. The races before `now` are over, with results.
    struct SampleWorldCup: Sendable {
        let now: Date

        func respond(to request: URLRequest) throws -> (Data, URLResponse) {
            guard let url = request.url else { throw URLError(.badURL) }
            let query = Dictionary(
                (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                },
                uniquingKeysWith: { $1 })
            let body = response(path: url.lastPathComponent, query: query)
            let status = body == nil ? 404 : 200
            let data = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
            return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }

        /// The JSON object of an IBU API response, `nil` for what the API wouldn't find.
        private func response(path: String, query: [String: String]) -> Any? {
            switch path {
            case "Events": query["SeasonId"].map { events(of: SeasonID(rawValue: $0)).map(\.json) }
            case "Competitions": query["EventId"].flatMap(event(id:)).map { races(of: $0).map(\.json) }
            case "Results": query["RaceId"].flatMap(race(id:)).map(results)
            case "CupResults": query["CupId"].flatMap(standings(cupID:))
            case "CISBios": query["IBUId"].flatMap(athlete(id:)).map(\.bio)
            case "AllResults": query["IBUId"].flatMap(athlete(id:)).map { ["Results": history(of: $0)] }
            case "Athletes": ["Athletes": Self.athletes(matching: query).map(\.match)]
            default: nil
            }
        }

        // MARK: Calendar

        struct Event {
            let season: SeasonID
            let number: Int
            let place: String
            let nation: String
            let start: Date

            var id: String { "BT\(season.rawValue)SWRLCP\(String(format: "%02d", number))" }

            var json: [String: Any] {
                [
                    "EventId": id, "ShortDescription": place, "Nat": nation,
                    "StartDate": start.formatted(.iso8601),
                    "EndDate": start.addingTimeInterval(6 * 86_400).formatted(.iso8601),
                ]
            }
        }

        struct Race {
            let event: Event
            let kind: RaceKind
            let start: Date
            let isOver: Bool

            var id: String { event.id + kind.rawValue }
            /// A kind starts with its category's `catId`.
            var category: RaceCategory { RaceCategory(rawValue: String(kind.rawValue.prefix(2)))! }

            var json: [String: Any] {
                [
                    "RaceId": id, "catId": category.rawValue, "ShortDescription": "\(kind)",
                    "StartTime": start.formatted(.iso8601), "IsLive": false,
                    "StatusId": isOver ? 11 : 1, "ScheduleStatus": isOver ? "FINISHED" : "SCHEDULED",
                ]
            }
        }

        /// Places, nations and start dates (month, day, in the season's first or second year).
        private static let calendar: [(place: String, nation: String, month: Int, day: Int, year: Int)] = [
            ("Nordvik", "NOR", 12, 1, 0), ("Lac-Blanc", "FRA", 1, 12, 1), ("Hohenwald", "GER", 3, 9, 1),
        ]

        /// Each race's kind, and its start in days and hours after its event's.
        private static let program: [(kind: RaceKind, days: Int, hours: Int)] = [
            (.menSprint, 2, 3), (.womenSprint, 3, 3), (.menPursuit, 4, 0), (.womenPursuit, 4, 2),
        ]

        private func events(of season: SeasonID) -> [Event] {
            Self.calendar.enumerated().map { index, stage in
                Event(
                    season: season, number: index + 1, place: stage.place, nation: stage.nation,
                    start: Self.noon(year: season.start + stage.year, month: stage.month, day: stage.day))
            }
        }

        private func races(of event: Event) -> [Race] {
            Self.program.map { race in
                let start = event.start.addingTimeInterval(TimeInterval(race.days * 86_400 + race.hours * 3_600))
                return Race(event: event, kind: race.kind, start: start, isOver: start < now)
            }
        }

        private func event(id: String) -> Event? {
            guard id.count == 14 else { return nil }
            return events(of: SeasonID(rawValue: String(id.dropFirst(2).prefix(4)))).first { $0.id == id }
        }

        private func race(id: String) -> Race? {
            event(id: Competition.eventID(ofRace: id)).flatMap { races(of: $0).first { $0.id == id } }
        }

        private func results(of race: Race) -> [String: Any] {
            let rows =
                race.isOver
                ? Self.athletes(of: race.category).enumerated().map { rank, athlete in
                    athlete.row.merging([
                        "Rank": "\(rank + 1)", "Shootings": "0+1",
                        "TotalTime": "24:\(String(format: "%02d", 10 + rank)).0",
                        "Behind": rank == 0 ? "0.0" : "+\(rank).0",
                    ]) { $1 }
                } : []
            return [
                "IsResult": race.isOver, "IsStartList": false, "Competition": race.json, "SportEvt": race.event.json,
                "Results": rows,
            ]
        }

        // MARK: Athletes

        struct Athlete {
            let id: String
            let givenName: String
            let familyName: String
            let nation: String
            let category: RaceCategory

            var row: [String: Any] {
                [
                    "IBUId": id, "Name": "\(familyName) \(givenName)",
                    "ShortName": "\(familyName) \(givenName.prefix(1)).", "Nat": nation,
                ]
            }

            /// As the IBU's search finds the athlete.
            var match: [String: Any] {
                ["IBUId": id, "FamilyName": familyName, "GivenName": givenName, "NAT": nation, "Functions": "Athlete"]
            }

            var bio: [String: Any] {
                [
                    "IBUId": id, "FullName": "\(givenName) \(familyName)", "NAT": nation, "Functions": "Athlete",
                    "Birthdate": "2000-01-15T00:00:00", "GenderId": category == .men ? "M" : "W",
                ]
            }
        }

        /// The nations of the athletes, in the order of the nations standings, with their English names.
        private static let nations = [
            ("NOR", "Norway"), ("FRA", "France"), ("GER", "Germany"), ("SWE", "Sweden"), ("ITA", "Italy"),
        ]

        private static let names: [RaceCategory: [(String, String)]] = [
            .men: [
                ("Aksel", "VANGEN"), ("Hugo", "MARTEL"), ("Lukas", "BRANDT"), ("Erik", "LUNDQVIST"),
                ("Marco", "FERRATI"), ("Sindre", "HOLTE"), ("Louis", "DUVERNAY"), ("Felix", "KESSLER"),
                ("Oskar", "STRAND"), ("Luca", "BENZONI"),
            ],
            .women: [
                ("Ingrid", "SOLBERG"), ("Chloé", "BERTIN"), ("Lena", "HARTMANN"), ("Elsa", "NYGREN"),
                ("Giulia", "ROSSETTI"), ("Maren", "LIEN"), ("Manon", "AUBRY"), ("Anna", "WEBER"),
                ("Klara", "EKMAN"), ("Sara", "COLOMBO"),
            ],
        ]

        /// The category's athletes, in the order of every standings table and result.
        private static func athletes(of category: RaceCategory) -> [Athlete] {
            (names[category] ?? []).enumerated().map { index, name in
                let nation = nations[index % nations.count].0
                return Athlete(
                    id: "BT\(nation)\(category.rawValue)\(String(format: "%02d", index + 1))", givenName: name.0,
                    familyName: name.1, nation: nation, category: category)
            }
        }

        /// The athletes whose names start like the search's, whatever their case, as the IBU finds them.
        private static func athletes(matching query: [String: String]) -> [Athlete] {
            func starts(_ name: String, with prefix: String?) -> Bool {
                prefix.map { name.lowercased().hasPrefix($0.lowercased()) } ?? true
            }
            return [RaceCategory.men, .women].flatMap(athletes(of:)).filter {
                starts($0.familyName, with: query["FamilyName"]) && starts($0.givenName, with: query["GivenName"])
            }
        }

        private func athlete(id: String) -> Athlete? {
            [RaceCategory.men, .women].lazy.flatMap(Self.athletes(of:)).first { $0.id == id }
        }

        /// The athlete's results of the current season and the previous one, newest first, as `AllResults` lists them.
        private func history(of athlete: Athlete) -> [[String: Any]] {
            let rank = Self.athletes(of: athlete.category).firstIndex { $0.id == athlete.id }.map { $0 + 1 } ?? 0
            let current = SeasonID.containing(now)
            return [current, current.previous].flatMap { season in
                events(of: season).flatMap(races(of:)).filter { $0.isOver && $0.category == athlete.category }
            }
            .sorted { $0.start > $1.start }
            .map { race in
                [
                    "RaceId": race.id,
                    "Season": "\(race.event.season.rawValue.prefix(2))/\(race.event.season.rawValue.suffix(2))",
                    "Comp": "\(race.kind)", "Place": race.event.place, "Rank": "\(rank)", "Level": "WC",
                ]
            }
        }

        // MARK: Standings

        /// Any World Cup table, of any season: the athletes', or the nations' for `NC`.
        private func standings(cupID: String) -> [String: Any]? {
            guard cupID.count == 18, let category = RaceCategory(rawValue: String(cupID.dropFirst(14).prefix(2))),
                let discipline = StandingsDiscipline(rawValue: String(cupID.suffix(2))), category != .mixed
            else { return nil }
            let rows: [[String: Any]] =
                discipline == .nations
                ? Self.nations.map { ["IBUId": $0.0, "Name": $0.1, "Nat": $0.0] }
                : Self.athletes(of: category).map(\.row)
            let ranked = rows.enumerated().map { index, row in
                row.merging(["Rank": "\(index + 1)", "Score": "\(1_000 - 60 * index)"]) { $1 }
                    .merging(index == 0 ? ["Bibs": [["Color": "yellow"]]] : [:]) { $1 }
            }
            return ["CupId": cupID, "Rows": ranked]
        }

        private static func noon(year: Int, month: Int, day: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
    }
#endif
