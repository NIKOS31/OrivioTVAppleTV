import Foundation

/// A provider error is not evidence that a title has no sources. Only known
/// release dates can label it as unreleased; unknown dates remain unknown.
enum NTVSourceStatus: Equatable {
    case unreleased, noCompatibleAddon, unavailable, incomplete, empty, filtered

    static func resolve(unreleased: Bool, requests: Int, failures: Int,
                        unavailableManifests: Int = 0, filtered: Bool = false) -> Self {
        if unreleased { return .unreleased }
        if filtered { return .filtered }
        if requests == 0 { return unavailableManifests > 0 ? .unavailable : .noCompatibleAddon }
        if failures >= requests { return .unavailable }
        if failures > 0 { return .incomplete }
        return .empty
    }

    var title: String {
        switch self {
        case .unreleased: return "Pas encore sorti"
        case .noCompatibleAddon: return "Aucun addon de sources compatible"
        case .unavailable: return "Addon injoignable ou en erreur"
        case .incomplete: return "Recherche de sources incomplète"
        case .empty: return "Aucune source trouvée"
        case .filtered: return "Aucune source avec ces filtres"
        }
    }

    var message: String {
        switch self {
        case .unreleased:
            return "La date de sortie indiquée pour ce titre ou cet épisode est à venir. Une source pourra être proposée après sa sortie."
        case .noCompatibleAddon:
            return "Aucun addon activé ne prend en charge ce titre. Vérifiez vos addons de sources dans les réglages."
        case .unavailable:
            return "Les addons sollicités n’ont pas pu répondre correctement. Leur indisponibilité ne signifie pas qu’aucune source n’existe. Réessayez dans un moment."
        case .incomplete:
            return "Les addons qui ont répondu n’ont fourni aucun lien lisible. D’autres sont injoignables ou en erreur : réessayez pour terminer la recherche."
        case .empty:
            return "Les addons sollicités ont répondu sans fournir de lien lisible. Le titre peut être sorti sans être disponible dans vos sources."
        case .filtered:
            return "Des liens ont été reçus, mais aucun ne correspond aux filtres de lecture actifs. Ajustez-les pour afficher les autres sources."
        }
    }
}
