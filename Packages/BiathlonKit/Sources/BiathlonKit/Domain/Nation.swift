import Foundation

public enum Nation {
    /// IOC codes (used by the IBU) to ISO 3166 codes, for flags: the 206 National Olympic
    /// Committees, with Kosovo's `XK` (not an ISO code, but a Unicode flag emoji), and
    /// Greenland, which the IBU names `GRL` though it has no Olympic committee.
    private static let iso: [String: String] = [
        "AFG": "AF", "ALB": "AL", "ALG": "DZ", "AND": "AD", "ANG": "AO", "ANT": "AG", "ARG": "AR", "ARM": "AM",
        "ARU": "AW", "ASA": "AS", "AUS": "AU", "AUT": "AT", "AZE": "AZ", "BAH": "BS", "BAN": "BD", "BAR": "BB",
        "BDI": "BI", "BEL": "BE", "BEN": "BJ", "BER": "BM", "BHU": "BT", "BIH": "BA", "BIZ": "BZ", "BLR": "BY",
        "BOL": "BO", "BOT": "BW", "BRA": "BR", "BRN": "BH", "BRU": "BN", "BUL": "BG", "BUR": "BF", "CAF": "CF",
        "CAM": "KH", "CAN": "CA", "CAY": "KY", "CGO": "CG", "CHA": "TD", "CHI": "CL", "CHN": "CN", "CIV": "CI",
        "CMR": "CM", "COD": "CD", "COK": "CK", "COL": "CO", "COM": "KM", "CPV": "CV", "CRC": "CR", "CRO": "HR",
        "CUB": "CU", "CYP": "CY", "CZE": "CZ", "DEN": "DK", "DJI": "DJ", "DMA": "DM", "DOM": "DO", "ECU": "EC",
        "EGY": "EG", "ERI": "ER", "ESA": "SV", "ESP": "ES", "EST": "EE", "ETH": "ET", "FIJ": "FJ", "FIN": "FI",
        "FRA": "FR", "FSM": "FM", "GAB": "GA", "GAM": "GM", "GBR": "GB", "GBS": "GW", "GEO": "GE", "GEQ": "GQ",
        "GER": "DE", "GHA": "GH", "GRE": "GR", "GRL": "GL", "GRN": "GD", "GUA": "GT", "GUI": "GN", "GUM": "GU",
        "GUY": "GY", "HAI": "HT", "HKG": "HK", "HON": "HN", "HUN": "HU", "INA": "ID", "IND": "IN", "IRI": "IR",
        "IRL": "IE", "IRQ": "IQ", "ISL": "IS", "ISR": "IL", "ISV": "VI", "ITA": "IT", "IVB": "VG", "JAM": "JM",
        "JOR": "JO", "JPN": "JP", "KAZ": "KZ", "KEN": "KE", "KGZ": "KG", "KIR": "KI", "KOR": "KR", "KOS": "XK",
        "KSA": "SA", "KUW": "KW", "LAO": "LA", "LAT": "LV", "LBA": "LY", "LBN": "LB", "LBR": "LR", "LCA": "LC",
        "LES": "LS", "LIE": "LI", "LTU": "LT", "LUX": "LU", "MAD": "MG", "MAR": "MA", "MAS": "MY", "MAW": "MW",
        "MDA": "MD", "MDV": "MV", "MEX": "MX", "MGL": "MN", "MHL": "MH", "MKD": "MK", "MLI": "ML", "MLT": "MT",
        "MNE": "ME", "MON": "MC", "MOZ": "MZ", "MRI": "MU", "MTN": "MR", "MYA": "MM", "NAM": "NA", "NCA": "NI",
        "NED": "NL", "NEP": "NP", "NGR": "NG", "NIG": "NE", "NOR": "NO", "NRU": "NR", "NZL": "NZ", "OMA": "OM",
        "PAK": "PK", "PAN": "PA", "PAR": "PY", "PER": "PE", "PHI": "PH", "PLE": "PS", "PLW": "PW", "PNG": "PG",
        "POL": "PL", "POR": "PT", "PRK": "KP", "PUR": "PR", "QAT": "QA", "ROU": "RO", "RSA": "ZA", "RUS": "RU",
        "RWA": "RW", "SAM": "WS", "SEN": "SN", "SEY": "SC", "SGP": "SG", "SKN": "KN", "SLE": "SL", "SLO": "SI",
        "SMR": "SM", "SOL": "SB", "SOM": "SO", "SRB": "RS", "SRI": "LK", "SSD": "SS", "STP": "ST", "SUD": "SD",
        "SUI": "CH", "SUR": "SR", "SVK": "SK", "SWE": "SE", "SWZ": "SZ", "SYR": "SY", "TAN": "TZ", "TGA": "TO",
        "THA": "TH", "TJK": "TJ", "TKM": "TM", "TLS": "TL", "TOG": "TG", "TPE": "TW", "TTO": "TT", "TUN": "TN",
        "TUR": "TR", "TUV": "TV", "UAE": "AE", "UGA": "UG", "UKR": "UA", "URU": "UY", "USA": "US", "UZB": "UZ",
        "VAN": "VU", "VEN": "VE", "VIE": "VN", "VIN": "VC", "YEM": "YE", "ZAM": "ZM", "ZIM": "ZW",
    ]

    /// Flag emoji of an IOC code, or `nil` when the code is unknown.
    public static func flag(_ code: String?) -> String? {
        guard let code, let iso = iso[code.uppercased()] else { return nil }
        return flag(region: iso)
    }

    /// Flag emoji of an ISO 3166 code, or `nil` when the code isn't two letters.
    public static func flag(region code: String) -> String? {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    /// The nation's name in the locale's language, from its ISO code, or the IOC code when
    /// it has none (`AIN`, Individual Neutral Athletes).
    public static func localizedName(_ code: String, locale: Locale = .current) -> String {
        iso[code.uppercased()].flatMap { locale.localizedString(forRegionCode: $0) } ?? code
    }

    /// The nation's localized name preceded by its flag.
    public static func namedTitle(_ code: String, locale: Locale = .current) -> String {
        titled(localizedName(code, locale: locale), nation: code)
    }

    /// The text preceded by the nation's flag, or the text alone when the flag is unknown.
    public static func titled(_ text: String, nation: String?) -> String {
        titled(text, flag: flag(nation))
    }

    /// The text preceded by the flag of an ISO 3166 code, or the text alone when it has none.
    public static func titled(_ text: String, region: String) -> String {
        titled(text, flag: flag(region: region))
    }

    private static func titled(_ text: String, flag: String?) -> String {
        [flag, text].compactMap(\.self).joined(separator: " ")
    }
}
