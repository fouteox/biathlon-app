import Foundation

/// The language codes to look for content in, best first: those of `preferred`
/// (`Locale.preferredLanguages`, such as `fr-FR`) in their order, then English.
func readerLanguageCodes(_ preferred: [String]) -> [String] {
    preferred.compactMap { Locale.Language(identifier: $0).languageCode?.identifier } + ["en"]
}
