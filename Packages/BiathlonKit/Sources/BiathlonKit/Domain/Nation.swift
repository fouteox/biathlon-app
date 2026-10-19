public enum Nation {
    /// IOC codes (used by the IBU) to ISO 3166 codes, for flags.
    private static let iso: [String: String] = [
        "ARG": "AR", "AUS": "AU", "AUT": "AT", "BEL": "BE", "BRA": "BR", "BUL": "BG", "CAN": "CA", "CHN": "CN",
        "CRO": "HR", "CZE": "CZ", "DEN": "DK", "ESP": "ES", "EST": "EE", "FIN": "FI", "FRA": "FR", "GBR": "GB",
        "GER": "DE", "GRE": "GR", "HUN": "HU", "IRL": "IE", "ISL": "IS", "ITA": "IT", "JPN": "JP", "KAZ": "KZ",
        "KOR": "KR", "LAT": "LV", "LTU": "LT", "MDA": "MD", "MGL": "MN", "NED": "NL", "NOR": "NO", "POL": "PL",
        "ROU": "RO", "SLO": "SI", "SRB": "RS", "SUI": "CH", "SVK": "SK", "SWE": "SE", "UKR": "UA", "USA": "US",
    ]

    /// Flag emoji of an IOC code, or `nil` when the code is unknown.
    public static func flag(_ code: String?) -> String? {
        guard let code, let iso = iso[code.uppercased()] else { return nil }
        return String(String.UnicodeScalarView(iso.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }
}
