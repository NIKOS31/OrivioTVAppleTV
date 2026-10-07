import Foundation

/// Display text only: addon names, content IDs and persisted enum values stay
/// owned by their providers and stores.
enum NTVFrench {
    static func label(_ value: String) -> String {
        let names: [String:String] = [
            "Auto":"Automatique", "Automatic":"Automatique", "None":"Aucun",
            "Off":"Désactivé", "On":"Activé", "Default":"Par défaut",
            "Normal":"Normal", "Fit":"Ajuster", "Zoom":"Remplir", "Stretch":"Étirer",
            "Crop":"Recadrer", "Maximum Fidelity":"Fidélité maximale", "Compatibility":"Compatibilité",
            "Native":"Natif", "External":"Externe", "Portrait":"Vertical", "Landscape":"Horizontal",
            "Square":"Carré", "Poster":"Affiche", "Modern":"Moderne", "Classic":"Classique",
            "Horizontal":"Horizontal", "Vertical":"Vertical", "Custom":"Personnalisé",
            "Recently Watched":"Vus récemment", "Last Watched":"Dernière lecture",
            "Recently Added":"Ajoutés récemment", "Recently Updated":"Mis à jour récemment",
            "Alphabetical":"Ordre alphabétique", "Release Date":"Date de sortie",
            "Name":"Nom", "Added":"Date d’ajout", "Small":"Petit", "Medium":"Moyen", "Large":"Grand",
            "Low":"Faible", "High":"Élevé", "White":"Blanc", "Black":"Noir", "Gray":"Gris",
            "Blue":"Bleu", "Red":"Rouge", "Green":"Vert", "Yellow":"Jaune", "Purple":"Violet",
            "English":"Anglais", "French":"Français", "Spanish":"Espagnol", "German":"Allemand",
            "Italian":"Italien", "Japanese":"Japonais", "Original":"Original",
            "All":"Tous", "Movies":"Films", "Series":"Séries", "Shows":"Séries",
            "Presets":"Suggestions", "Discover":"Découvrir", "Trakt List":"Liste Trakt",
            "Company / Person":"Studio ou personne", "Network / List / Collection":"Chaîne, liste ou collection",
            "Streaming Services":"Plateformes", "Major Studios":"Grands studios",
            "Trending & Top Rated":"Tendances et meilleures notes", "Dark":"Sombre", "Bright":"Clair"
        ]
        return names[value] ?? value
    }

    static func catalogTitle(_ title: String) -> String {
        let prefixes = [
            ("Popular - Movie", "Films populaires"), ("Popular - Series", "Séries populaires"),
            ("Popular - Séries", "Séries populaires"), ("Top - Movie", "Films les mieux notés"),
            ("Top - Series", "Séries les mieux notées"), ("Top - Séries", "Séries les mieux notées"),
            ("New - Movie", "Nouveaux films"), ("New - Series", "Nouvelles séries")
        ]
        for (source, translated) in prefixes where title == source || title.hasPrefix(source + " · ") {
            return translated + String(title.dropFirst(source.count))
        }
        let names = ["Popular":"Populaires", "Trending":"Tendances", "New Releases":"Dernières sorties",
                     "Latest":"Dernières sorties", "Top Rated":"Les mieux notés", "Featured":"À découvrir"]
        return names[title] ?? title
    }

    static func genre(_ value: String) -> String {
        let names = ["Biography":"Biographie", "Crime":"Policier", "Drama":"Drame", "Comedy":"Comédie",
                     "Thriller":"Thriller", "Adventure":"Aventure", "Documentary":"Documentaire",
                     "Horror":"Horreur", "Fantasy":"Fantastique", "Science Fiction":"Science-fiction",
                     "Sci-Fi":"Science-fiction", "History":"Histoire", "War":"Guerre", "Family":"Famille",
                     "Mystery":"Mystère", "Music":"Musique", "Sport":"Sport"]
        return names[value] ?? value
    }
}
