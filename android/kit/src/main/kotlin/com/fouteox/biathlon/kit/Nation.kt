package com.fouteox.biathlon.kit

import java.util.Locale

object Nation {
    /**
     * IOC codes (used by the IBU) to ISO 3166 codes, for flags: the 206 National Olympic
     * Committees, with Kosovo's `XK` (not an ISO code, but a Unicode flag emoji), and Greenland,
     * which the IBU names `GRL` though it has no Olympic committee.
     */
    private val ISO = mapOf(
        "AFG" to "AF", "ALB" to "AL", "ALG" to "DZ", "AND" to "AD", "ANG" to "AO", "ANT" to "AG",
        "ARG" to "AR", "ARM" to "AM", "ARU" to "AW", "ASA" to "AS", "AUS" to "AU", "AUT" to "AT",
        "AZE" to "AZ", "BAH" to "BS", "BAN" to "BD", "BAR" to "BB", "BDI" to "BI", "BEL" to "BE",
        "BEN" to "BJ", "BER" to "BM", "BHU" to "BT", "BIH" to "BA", "BIZ" to "BZ", "BLR" to "BY",
        "BOL" to "BO", "BOT" to "BW", "BRA" to "BR", "BRN" to "BH", "BRU" to "BN", "BUL" to "BG",
        "BUR" to "BF", "CAF" to "CF", "CAM" to "KH", "CAN" to "CA", "CAY" to "KY", "CGO" to "CG",
        "CHA" to "TD", "CHI" to "CL", "CHN" to "CN", "CIV" to "CI", "CMR" to "CM", "COD" to "CD",
        "COK" to "CK", "COL" to "CO", "COM" to "KM", "CPV" to "CV", "CRC" to "CR", "CRO" to "HR",
        "CUB" to "CU", "CYP" to "CY", "CZE" to "CZ", "DEN" to "DK", "DJI" to "DJ", "DMA" to "DM",
        "DOM" to "DO", "ECU" to "EC", "EGY" to "EG", "ERI" to "ER", "ESA" to "SV", "ESP" to "ES",
        "EST" to "EE", "ETH" to "ET", "FIJ" to "FJ", "FIN" to "FI", "FRA" to "FR", "FSM" to "FM",
        "GAB" to "GA", "GAM" to "GM", "GBR" to "GB", "GBS" to "GW", "GEO" to "GE", "GEQ" to "GQ",
        "GER" to "DE", "GHA" to "GH", "GRE" to "GR", "GRL" to "GL", "GRN" to "GD", "GUA" to "GT",
        "GUI" to "GN", "GUM" to "GU", "GUY" to "GY", "HAI" to "HT", "HKG" to "HK", "HON" to "HN",
        "HUN" to "HU", "INA" to "ID", "IND" to "IN", "IRI" to "IR", "IRL" to "IE", "IRQ" to "IQ",
        "ISL" to "IS", "ISR" to "IL", "ISV" to "VI", "ITA" to "IT", "IVB" to "VG", "JAM" to "JM",
        "JOR" to "JO", "JPN" to "JP", "KAZ" to "KZ", "KEN" to "KE", "KGZ" to "KG", "KIR" to "KI",
        "KOR" to "KR", "KOS" to "XK", "KSA" to "SA", "KUW" to "KW", "LAO" to "LA", "LAT" to "LV",
        "LBA" to "LY", "LBN" to "LB", "LBR" to "LR", "LCA" to "LC", "LES" to "LS", "LIE" to "LI",
        "LTU" to "LT", "LUX" to "LU", "MAD" to "MG", "MAR" to "MA", "MAS" to "MY", "MAW" to "MW",
        "MDA" to "MD", "MDV" to "MV", "MEX" to "MX", "MGL" to "MN", "MHL" to "MH", "MKD" to "MK",
        "MLI" to "ML", "MLT" to "MT", "MNE" to "ME", "MON" to "MC", "MOZ" to "MZ", "MRI" to "MU",
        "MTN" to "MR", "MYA" to "MM", "NAM" to "NA", "NCA" to "NI", "NED" to "NL", "NEP" to "NP",
        "NGR" to "NG", "NIG" to "NE", "NOR" to "NO", "NRU" to "NR", "NZL" to "NZ", "OMA" to "OM",
        "PAK" to "PK", "PAN" to "PA", "PAR" to "PY", "PER" to "PE", "PHI" to "PH", "PLE" to "PS",
        "PLW" to "PW", "PNG" to "PG", "POL" to "PL", "POR" to "PT", "PRK" to "KP", "PUR" to "PR",
        "QAT" to "QA", "ROU" to "RO", "RSA" to "ZA", "RUS" to "RU", "RWA" to "RW", "SAM" to "WS",
        "SEN" to "SN", "SEY" to "SC", "SGP" to "SG", "SKN" to "KN", "SLE" to "SL", "SLO" to "SI",
        "SMR" to "SM", "SOL" to "SB", "SOM" to "SO", "SRB" to "RS", "SRI" to "LK", "SSD" to "SS",
        "STP" to "ST", "SUD" to "SD", "SUI" to "CH", "SUR" to "SR", "SVK" to "SK", "SWE" to "SE",
        "SWZ" to "SZ", "SYR" to "SY", "TAN" to "TZ", "TGA" to "TO", "THA" to "TH", "TJK" to "TJ",
        "TKM" to "TM", "TLS" to "TL", "TOG" to "TG", "TPE" to "TW", "TTO" to "TT", "TUN" to "TN",
        "TUR" to "TR", "TUV" to "TV", "UAE" to "AE", "UGA" to "UG", "UKR" to "UA", "URU" to "UY",
        "USA" to "US", "UZB" to "UZ", "VAN" to "VU", "VEN" to "VE", "VIE" to "VN", "VIN" to "VC",
        "YEM" to "YE", "ZAM" to "ZM", "ZIM" to "ZW",
    )

    /** The first regional indicator symbol, 🇦, minus `A`. */
    private const val REGIONAL_INDICATOR_OFFSET = 0x1F1E6 - 'A'.code

    /** Flag emoji of an IOC code, or `null` when the code is unknown. */
    fun flag(code: String?): String? = code?.let { ISO[it.uppercase(Locale.ROOT)] }?.let(::regionFlag)

    /** Flag emoji of an ISO 3166 code, or `null` when the code isn't two letters. */
    fun regionFlag(code: String): String? {
        val letters = code.uppercase(Locale.ROOT)
        if (letters.length != 2 || !letters.all { it in 'A'..'Z' }) return null
        return letters.map { String(Character.toChars(it.code + REGIONAL_INDICATOR_OFFSET)) }.joinToString("")
    }

    /**
     * The nation's name in the locale's language, from its ISO code, or the IOC code when it has
     * none (`AIN`, Individual Neutral Athletes).
     */
    fun localizedName(code: String, locale: Locale = Locale.getDefault()): String {
        val iso = ISO[code.uppercase(Locale.ROOT)] ?: return code
        val name = Locale.Builder().setRegion(iso).build().getDisplayCountry(locale)
        return name.takeUnless { it.isEmpty() || it == iso } ?: code
    }

    /** The nation's localized name preceded by its flag. */
    fun namedTitle(code: String, locale: Locale = Locale.getDefault()): String = titled(localizedName(code, locale), code)

    /** The text preceded by the nation's flag, or the text alone when the flag is unknown. */
    fun titled(text: String, nation: String?): String = titledWithFlag(text, flag(nation))

    /** The text preceded by the flag of an ISO 3166 code, or the text alone when it has none. */
    fun titledByRegion(text: String, region: String): String = titledWithFlag(text, regionFlag(region))

    private fun titledWithFlag(text: String, flag: String?) = listOfNotNull(flag, text).joinToString(" ")
}
