import SwiftUI

/// Settings → Playback: post-play / auto-next controls, mirroring the Android
/// autoplay settings section (next episode, still-watching gate, threshold
/// mode/value, countdown timeout, binge-group preference). Every row here is
/// wired to `PlayerSettingsStore` and actually changes player behavior.
struct PlaybackSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: PlayerSettingsStore
    @State private var showAudioLanguages = false
    @State private var showSubtitleLanguages = false

    private var s: Binding<PlayerSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        settingsScaffold
            .fullScreenCover(isPresented: $showAudioLanguages) { audioLanguagesSheet }
            .fullScreenCover(isPresented: $showSubtitleLanguages) { subtitleLanguagesSheet }
    }

    /// The pane itself. Kept apart from `body` so the (large) card tree and the
    /// two sheet modifiers are type-checked separately — together they were too
    /// much for the checker, which failed on the first `.fullScreenCover`.
    @ViewBuilder
    private var settingsScaffold: some View {
        DetailScaffold(title: SettingsCategory.playback.title, subtitle: SettingsCategory.playback.subtitle) {
            SettingsGroupCard(title: "Lecture automatique", subtitle: "Comportement à la fin d’un épisode") {
                autoPlayControls
            }
            SettingsGroupCard(title: "Avance et retour", subtitle: "Distance d’un saut dans la vidéo") {
                OrivioDropdown(
                    title: "Durée d’un saut",
                    subtitle: "Durée d’un clic gauche ou droit. Les clics répétés accélèrent le déplacement.",
                    icon: "goforward",
                    selection: String(store.settings.skipSeconds),
                    options: PlayerSettings.skipValues.map { OrivioDropdownOption(String($0), "\($0) seconds") }
                ) { store.settings.skipSeconds = Int($0) ?? 10 }

                OrivioDropdown(
                    title: "Pas de déplacement sur la barre",
                    subtitle: "Durée d’un clic pendant le parcours de la barre",
                    icon: "forward.frame.fill",
                    selection: String(store.settings.scrubJumpSeconds),
                    options: PlayerSettings.scrubJumpValues.map {
                        OrivioDropdownOption(String($0), $0 < 60 ? "\($0) seconds" : "\($0 / 60) minute\($0 >= 120 ? "s" : "")")
                    }
                ) { store.settings.scrubJumpSeconds = Int($0) ?? 10 }

                PlaybackToggleRow(
                    icon: "forward.frame.fill",
                    title: "Bouton Passer l’introduction",
                    subtitle: "Afficher le bouton pendant les chapitres d’introduction ou de résumé",
                    isOn: s.skipIntroEnabled
                )

                PlaybackToggleRow(
                    icon: "forward.fill",
                    title: "Passer les introductions automatiquement",
                    subtitle: "Passer automatiquement les chapitres d’introduction et de résumé, lorsque la vidéo les indique",
                    isOn: s.autoSkipSegments
                )

                PlaybackToggleRow(
                    icon: "sparkles.tv",
                    title: "AniSkip pour les animés",
                    subtitle: "Utiliser AniSkip pour repérer les introductions et génériques des animés sans chapitres. Aucun compte nécessaire.",
                    isOn: s.animeSkipEnabled
                )
            }

            SettingsGroupCard(title: "Sources", subtitle: "Choisir les sources affichées") {
                PlaybackToggleRow(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    title: "Tri des sources",
                    subtitle: "Classer les sources par qualité et disponibilité. Désactivé : conserver l’ordre des addons, avec les sources en cache d’abord, jusqu’à \(PlayerSettings.unfilteredPerAddonCap) par addon.",
                    isOn: s.sourceFiltersEnabled
                )

                if store.settings.sourceFiltersEnabled {
                    OrivioDropdown(
                        title: "Sources par résolution",
                        subtitle: "Nombre de meilleures sources conservées par résolution et par addon",
                        icon: "square.stack.3d.up.fill",
                        selection: String(store.settings.sourcesPerSizeTier),
                        options: PlayerSettings.sourcesPerTierValues.filter { $0 > 0 }.map {
                            OrivioDropdownOption(String($0), "\($0) links")
                        }
                    ) { store.settings.sourcesPerSizeTier = Int($0) ?? 6 }
                }

                OrivioDropdown(
                    title: "Délai de recherche des sources",
                    subtitle: "Temps accordé à chaque addon. Augmentez-le pour les addons qui prennent plus de temps ; les premières réponses restent affichées immédiatement.",
                    icon: "clock.arrow.circlepath",
                    selection: String(store.settings.sourceSearchTimeoutSeconds),
                    options: [45, 60, 90, 120].map {
                        OrivioDropdownOption(String($0), "\($0) seconds")
                    }
                ) { store.settings.sourceSearchTimeoutSeconds = Int($0) ?? 45 }

                OrivioDropdown(
                    title: "Résolution minimale",
                    subtitle: "Masquer les sources de qualité inférieure. Les sources sans résolution précisée restent affichées.",
                    icon: "arrow.up.right.video.fill",
                    selection: store.settings.streamMinResolution,
                    options: [OrivioDropdownOption("", "Aucun minimum")]
                        + ["2160p", "1080p", "720p", "480p"].map { OrivioDropdownOption($0, $0) }
                ) { store.settings.streamMinResolution = $0 }

                PlaybackToggleRow(
                    icon: "cpu.fill",
                    title: "Masquer les sources AV1",
                    subtitle: "Éviter les sources AV1 si elles manquent de fluidité sur votre Apple TV",
                    isOn: s.streamExcludeAV1
                )

                PlaybackToggleRow(
                    icon: "sparkles",
                    title: "HDR only",
                    subtitle: "Afficher uniquement les sources HDR10, HLG ou Dolby Vision",
                    isOn: s.streamHDROnly
                )

                PlaybackToggleRow(
                    icon: "sparkles.tv.fill",
                    title: "Dolby Vision uniquement",
                    subtitle: "Afficher uniquement les sources Dolby Vision",
                    isOn: s.streamDolbyVisionOnly
                )

                PlaybackToggleRow(
                    icon: "bolt.fill",
                    title: "Disponibles immédiatement",
                    subtitle: "Afficher uniquement les sources déjà disponibles chez votre service de débridage",
                    isOn: s.streamCachedOnly
                )
            }

            SettingsGroupCard(title: "Contenu", subtitle: "Informations de contenu sur les fiches") {
                PlaybackToggleRow(
                    icon: "exclamationmark.shield.fill",
                    title: "Guide parental",
                    subtitle: "Afficher les avertissements IMDb concernant le contenu des films et séries",
                    isOn: s.parentalGuideEnabled
                )
            }

            // Advanced-only cards (hidden in Essential experience mode).
            if theme.experienceMode.isAdvanced {
            SettingsGroupCard(title: "Choix automatique de la source", subtitle: "Lancer la lecture sans passer par la liste des sources") {
                PlaybackToggleRow(
                    icon: "play.circle.fill",
                    title: "Lire la meilleure source automatiquement",
                    subtitle: "Lancer directement la source la mieux classée à l’ouverture d’un titre",
                    isOn: s.autoPlaySourceEnabled
                )

                if store.settings.autoPlaySourceEnabled {
                    PlaybackToggleRow(
                        icon: "bolt.fill",
                        title: "Sources immédiatement disponibles",
                        subtitle: "Lancer automatiquement seulement les sources disponibles immédiatement",
                        isOn: s.autoPlaySourceCachedOnly
                    )

                    HStack(spacing: OrivioSpacing.md) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 26))
                            .foregroundStyle(theme.palette.textSecondary)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filtre de nom, facultatif")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(theme.palette.textPrimary)
                            TextField("e.g. 2160p|remux", text: s.autoPlaySourceRegex)
                                .font(.system(size: 22))
                            Text("Le nom de la source doit contenir ce texte. Laissez vide pour choisir la première source.")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.palette.textTertiary)
                        }
                    }
                }

                PlaybackToggleRow(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Réutiliser la dernière source",
                    subtitle: "Reprendre la dernière source utilisée pour ce titre sans relancer la recherche",
                    isOn: s.reuseLastLinkEnabled
                )

                if store.settings.reuseLastLinkEnabled {
                    OrivioDropdown(
                        title: "Durée de conservation d’une source",
                        subtitle: "Durée pendant laquelle une source peut être réutilisée",
                        icon: "clock.fill",
                        selection: String(store.settings.reuseLastLinkCacheHours),
                        options: PlayerSettings.reuseLastLinkHoursValues.map {
                            OrivioDropdownOption(String($0), $0 < 24 ? "\($0) hours" : "\($0 / 24) day\($0 >= 48 ? "s" : "")")
                        }
                    ) { store.settings.reuseLastLinkCacheHours = Int($0) ?? 24 }
                }
            }

            SettingsGroupCard(title: "Lecteur", subtitle: "Choisir le moteur de lecture") {
                OrivioDropdown(
                    title: "Moteur de lecture",
                    subtitle: store.settings.playerEngine.footnote,
                    icon: "play.rectangle.on.rectangle.fill",
                    selection: store.settings.playerEngine.rawValue,
                    options: PlayerEngine.allCases.map { OrivioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.playerEngine = PlayerEngine(rawValue: $0) ?? .auto }

                OrivioDropdown(
                    title: "Mode de lecture",
                    subtitle: "Automatique adapte la lecture. Fidélité maximale privilégie la qualité, avec un coût plus élevé sur les anciens appareils. Compatibilité privilégie la lecture des sources difficiles.",
                    icon: "dial.high.fill",
                    selection: store.settings.playbackMode.rawValue,
                    options: PlaybackMode.allCases.map { OrivioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.playbackMode = PlaybackMode(rawValue: $0) ?? .automatic }

                PlaybackToggleRow(
                    icon: "sun.max.fill",
                    title: "Adapter le Dolby Vision profil 7",
                    subtitle: "Convertir le profil 7 vers le profil 8.1 pour préserver la luminosité. Désactivez cette option si la lecture manque de fluidité.",
                    isOn: s.convertProfile7ForBrightness
                )

                PlaybackToggleRow(
                    icon: "speedometer",
                    title: "Adapter la fréquence d’images",
                    subtitle: "Adapter la TV à la cadence du film, par exemple 24 Hz. Cette option peut provoquer un changement de mode HDMI ; activez-la si votre TV le gère correctement.",
                    isOn: s.matchFrameRate
                )

                PlaybackToggleRow(
                    icon: "waveform.badge.plus",
                    title: "Sortie Dolby Atmos, expérimentale",
                    subtitle: "Transmettre le Dolby Atmos des pistes E-AC-3 compatibles à votre équipement HDMI. La lecture habituelle est utilisée dans les autres cas.",
                    isOn: s.atmosPassthrough
                )

                PlaybackToggleRow(
                    icon: "internaldrive.fill",
                    title: "Cache vidéo sur le stockage",
                    subtitle: "Télécharger la vidéo pendant la lecture pour accélérer les déplacements dans les parties déjà reçues. Le cache s’adapte à l’espace libre et est supprimé après lecture. Sources de fichiers directs uniquement.",
                    isOn: s.hybridDiskCacheEnabled
                )

                // External engine: pick WHICH installed app receives streams.
                // canOpenURL only sees apps actually on this Apple TV, so the
                // list is exactly what's installed — and when nothing is, the
                // section stays blank.
                if store.settings.playerEngine == .external {
                    let installed = ExternalPlayers.installed
                    if !installed.isEmpty {
                        OrivioDropdown(
                            title: "Lecteur externe",
                            subtitle: "Confier la lecture, la reprise et l’historique à une autre app",
                            icon: "arrow.up.forward.app.fill",
                            selection: store.settings.externalPlayerID,
                            options: installed.map { OrivioDropdownOption($0.id, $0.name) }
                        ) { store.settings.externalPlayerID = $0 }

                        PlaybackToggleRow(
                            icon: "captions.bubble.fill",
                            title: "Transmettre les sous-titres",
                            subtitle: "Envoyer au lecteur externe les sous-titres de vos addons dans la langue choisie",
                            isOn: s.externalPlayerForwardSubtitles
                        )

                        // Only Infuse takes a playlist; the row would be a lie
                        // for the players whose scheme carries one url.
                        if (ExternalPlayers.player(id: store.settings.externalPlayerID)
                            ?? installed.first)?.supportsPlaylist == true {
                            PlaybackToggleRow(
                                icon: "list.and.film",
                                title: "Transmettre les épisodes suivants",
                                subtitle: "Préparer une liste d’épisodes pour le lecteur externe. Leur recherche peut retarder légèrement le démarrage.",
                                isOn: s.externalPlayerSendPlaylist
                            )
                        }
                    }
                }

                OrivioDropdown(
                    title: "Taille de l’image",
                    subtitle: "Format par défaut, également réglable pendant la lecture",
                    icon: "aspectratio.fill",
                    selection: store.settings.aspectModeRaw,
                    options: AspectMode.allCases.map { OrivioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.aspectModeRaw = $0 }
            }

            SettingsGroupCard(title: "Affichage du lecteur", subtitle: "Commandes et informations de lecture") {
                PlaybackToggleRow(
                    icon: "photo.fill",
                    title: "Fond pendant le chargement",
                    subtitle: "Afficher l’illustration et l’indicateur pendant l’ouverture d’une source",
                    isOn: s.loadingOverlayEnabled
                )
                if store.settings.loadingOverlayEnabled {
                    PlaybackToggleRow(
                        icon: "text.append",
                        title: "État du chargement",
                        subtitle: "Afficher la progression du chargement et du cache",
                        isOn: s.showPlayerLoadingStatus
                    )
                }
            }

            SettingsGroupCard(title: "Audio", subtitle: "Choix des pistes et sortie audio") {
                OrivioDropdown(
                    title: "Langue préférée",
                    subtitle: "Choisir automatiquement une piste dans cette langue lorsqu’elle existe",
                    icon: "waveform",
                    selection: store.settings.preferredAudioLanguage,
                    options: PlayerSettings.audioLanguageOptions(
                        showAll: store.settings.allAudioLanguages,
                        enabled: Set(store.settings.enabledAudioLanguages),
                        current: store.settings.preferredAudioLanguage
                    ).map { OrivioDropdownOption($0.0, $0.1) }
                ) { store.settings.preferredAudioLanguage = $0 }

                Button { showAudioLanguages = true } label: {
                    SettingsActionRow(
                        title: "Langues audio",
                        subtitle: "Choisir les langues proposées dans la liste",
                        value: audioLanguagesSummary,
                        leadingIcon: "globe"
                    )
                }
                .buttonStyle(PlainCardButtonStyle())

                OrivioDropdown(
                    title: "Son multicanal et Dolby Atmos",
                    subtitle: "Adapter la sortie audio aux capacités de votre TV ou ampli. Le changement s’applique à la prochaine lecture.",
                    icon: "hifispeaker.2.fill",
                    selection: store.settings.audioOutputMode.rawValue,
                    options: AudioOutputMode.allCases.map { OrivioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.audioOutputMode = AudioOutputMode(rawValue: $0) ?? .auto }
            }
            } // end advanced-only cards

            SettingsGroupCard(title: "Sous-titres", subtitle: "Style et activation des sous-titres") {
                PlaybackToggleRow(
                    icon: "captions.bubble.fill",
                    title: "Activer les sous-titres par défaut",
                    subtitle: "Activer les sous-titres dans votre langue préférée lorsqu’ils sont disponibles",
                    isOn: s.subtitlesOnByDefault
                )

                PlaybackToggleRow(
                    icon: "textformat.alt",
                    title: "Styles complets des sous-titres ASS/SSA",
                    subtitle: "Préserver les polices, positions et effets avec VLC. Les aperçus de déplacement ne sont alors pas disponibles. Désactivé : utiliser le rendu de texte simple.",
                    isOn: s.fullAssSubtitles
                )

                if store.settings.subtitlesOnByDefault {
                    OrivioDropdown(
                        title: "Langue préférée",
                        subtitle: "Choisir cette langue lorsqu’elle existe, sinon la première piste disponible",
                        icon: "globe",
                        selection: store.settings.preferredSubtitleLanguage,
                        options: PlayerSettings.subtitleLanguageOptions(
                            showAll: store.settings.allSubtitleLanguages,
                            enabled: Set(store.settings.enabledSubtitleLanguages),
                            current: store.settings.preferredSubtitleLanguage
                        ).map { OrivioDropdownOption($0.0, $0.1) }
                    ) { store.settings.preferredSubtitleLanguage = $0 }

                    OrivioDropdown(
                        title: "Langue secondaire",
                        subtitle: "Langue utilisée si la langue préférée est absente",
                        icon: "globe.badge.chevron.backward",
                        selection: store.settings.subtitleSecondaryLanguage,
                        options: PlayerSettings.subtitleLanguageOptions(
                            showAll: store.settings.allSubtitleLanguages,
                            enabled: Set(store.settings.enabledSubtitleLanguages),
                            current: store.settings.subtitleSecondaryLanguage
                        ).map { OrivioDropdownOption($0.0, $0.1) }
                    ) { store.settings.subtitleSecondaryLanguage = $0 }

                    PlaybackToggleRow(
                        icon: "exclamationmark.bubble.fill",
                        title: "Privilégier les sous-titres forcés",
                        subtitle: "Choisir les sous-titres des dialogues étrangers lorsqu’ils existent dans votre langue",
                        isOn: s.subtitlePreferForced
                    )
                }

                Button { showSubtitleLanguages = true } label: {
                    SettingsActionRow(
                        title: "Langues des sous-titres",
                        subtitle: "Afficher toutes les langues ou sélectionner celles qui vous intéressent",
                        value: subtitleLanguagesSummary,
                        leadingIcon: "globe"
                    )
                }
                .buttonStyle(PlainCardButtonStyle())

                OrivioDropdown(
                    title: "Taille du texte",
                    icon: "textformat.size",
                    selection: String(store.settings.subtitleSize),
                    options: PlayerSettings.subtitleSizeValues.map {
                        OrivioDropdownOption(String($0), sizeLabel($0))
                    }
                ) { store.settings.subtitleSize = Int($0) ?? 36 }

                OrivioDropdown(
                    title: "Police",
                    subtitle: "Également réglable pendant la lecture",
                    icon: "textformat",
                    selection: store.settings.subtitleFontName,
                    options: PlayerSettings.subtitleFontOptions.map { OrivioDropdownOption($0.0, $0.1) }
                ) { store.settings.subtitleFontName = $0 }

                OrivioDropdown(
                    title: "Décalage des sous-titres",
                    subtitle: "Afficher les sous-titres plus tôt (−) ou plus tard (+)",
                    icon: "timer",
                    selection: String(store.settings.subtitleDelaySeconds),
                    options: PlayerSettings.subtitleDelayValues.map {
                        OrivioDropdownOption(String($0), PlayerViewModel.formatDelay($0))
                    }
                ) { store.settings.subtitleDelaySeconds = Double($0) ?? 0 }

                OrivioDropdown(
                    title: "Couleur du texte",
                    icon: "paintpalette.fill",
                    selection: store.settings.subtitleTextColorHex,
                    options: PlayerSettings.subtitleColorOptions.map { OrivioDropdownOption($0.0, $0.1) }
                ) { store.settings.subtitleTextColorHex = $0 }

                PlaybackToggleRow(
                    icon: "bold",
                    title: "Texte en gras",
                    subtitle: "Renforcer l’épaisseur du texte",
                    isOn: s.subtitleBold
                )

                PlaybackToggleRow(
                    icon: "a.square.fill",
                    title: "Contour",
                    subtitle: "Améliorer la lisibilité sur tous les fonds",
                    isOn: s.subtitleOutlineEnabled
                )

                if store.settings.subtitleOutlineEnabled {
                    OrivioDropdown(
                        title: "Couleur du contour",
                        icon: "scribble",
                        selection: store.settings.subtitleOutlineColorHex,
                        options: PlayerSettings.subtitleColorOptions.map { OrivioDropdownOption($0.0, $0.1) }
                    ) { store.settings.subtitleOutlineColorHex = $0 }

                    OrivioDropdown(
                        title: "Épaisseur du contour",
                        icon: "lineweight",
                        selection: String(store.settings.subtitleOutlineWidth),
                        options: PlayerSettings.subtitleOutlineWidthValues.map {
                            OrivioDropdownOption(String($0), $0 == 1 ? "Fin, 1 pt" : "\($0) pt")
                        }
                    ) { store.settings.subtitleOutlineWidth = Int($0) ?? 2 }
                }

                PlaybackToggleRow(
                    icon: "rectangle.fill.on.rectangle.fill",
                    title: "Fond des sous-titres",
                    subtitle: "Améliorer la lisibilité dans les scènes claires",
                    isOn: s.subtitleBackground
                )

                if store.settings.subtitleBackground {
                    OrivioDropdown(
                        title: "Opacité du fond",
                        icon: "circle.lefthalf.filled",
                        selection: String(store.settings.subtitleBackgroundOpacity),
                        options: PlayerSettings.subtitleBackgroundOpacityValues.map {
                            OrivioDropdownOption(String($0), "\($0)%")
                        }
                    ) { store.settings.subtitleBackgroundOpacity = Int($0) ?? 45 }
                }

                OrivioDropdown(
                    title: "Position verticale",
                    subtitle: "Monter ou descendre les sous-titres",
                    icon: "arrow.up.and.down.text.horizontal",
                    selection: String(store.settings.subtitleVerticalOffset),
                    options: PlayerSettings.subtitleOffsetValues.map {
                        OrivioDropdownOption(String($0), $0 == 0 ? "Par défaut" : ($0 > 0 ? "Plus haut +\($0)" : "Plus bas \($0)"))
                    }
                ) { store.settings.subtitleVerticalOffset = Int($0) ?? 0 }
            }

            SettingsGroupCard(title: "Bandes-annonces", subtitle: "Aperçu des bandes-annonces pendant la navigation") {
                OrivioDropdown(
                    title: "Lire les bandes-annonces automatiquement",
                    subtitle: "Lancer la bande-annonce après un moment sur un titre",
                    icon: "play.tv.fill",
                    selection: String(store.settings.autoPlayTrailerSeconds),
                    options: PlayerSettings.trailerDelayValues.map {
                        OrivioDropdownOption(String($0), $0 == 0 ? "Désactivé" : "Après \($0) s")
                    }
                ) { store.settings.autoPlayTrailerSeconds = Int($0) ?? 0 }
            }
        }
    }

    @ViewBuilder
    private var autoPlayControls: some View {
        PlaybackToggleRow(
            icon: "forward.end.fill",
            title: "Lire l’épisode suivant automatiquement",
            subtitle: "Lancer l’épisode suivant après un compte à rebours. Désactivé : attendre votre validation.",
            isOn: s.autoPlayNextEpisode
        )

        // Shown regardless of auto-play — the Up Next card always appears.
        OrivioDropdown(
            title: "Afficher l’épisode suivant",
            subtitle: "Afficher la proposition au générique, ou avant la fin selon ce délai",
            icon: "clock.fill",
            selection: String(store.settings.upNextLeadSeconds),
            options: PlayerSettings.upNextLeadValues.map {
                OrivioDropdownOption(String($0), $0 < 60 ? "\($0) seconds before end" : "\($0 / 60) min before end")
            }
        ) { store.settings.upNextLeadSeconds = Int($0) ?? 30 }

        if store.settings.autoPlayNextEpisode {
            PlaybackToggleRow(
                icon: "eye.fill",
                title: "Vous regardez toujours ?",
                subtitle: "Demander confirmation après plusieurs épisodes",
                isOn: s.stillWatchingEnabled
            )

            if store.settings.stillWatchingEnabled {
                OrivioDropdown(
                    title: "Demander après",
                    icon: "repeat",
                    selection: String(store.settings.stillWatchingEpisodeThreshold),
                    options: (2...6).map { OrivioDropdownOption(String($0), "\($0) episodes") }
                ) { store.settings.stillWatchingEpisodeThreshold = Int($0) ?? 3 }
            }

            OrivioDropdown(
                title: "Compte à rebours",
                icon: "timer",
                selection: String(store.settings.autoPlayTimeoutSeconds),
                options: PlayerSettings.timeoutValues.map { OrivioDropdownOption(String($0), timeoutLabel($0)) }
            ) { store.settings.autoPlayTimeoutSeconds = Int($0) ?? 3 }

            PlaybackToggleRow(
                icon: "square.stack.3d.up.fill",
                title: "Privilégier le même groupe de sources",
                subtitle: "Choisir une source du même groupe pour l’épisode suivant",
                isOn: s.preferBingeGroupForNextEpisode
            )

            if store.settings.preferBingeGroupForNextEpisode {
                PlaybackToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Privilégier le même addon",
                    subtitle: "Utiliser le même addon et le même groupe pour l’épisode suivant",
                    isOn: s.reuseBingeGroup
                )
            }
        }
    }

    private var audioLanguagesSheet: some View {
        LanguageSelectionDetail(
            title: "Langues audio",
            subtitle: "Afficher toutes les langues audio ou sélectionner celles de votre choix",
            allLabel: "Toutes les langues",
            allHint: "Afficher toutes les langues. Désactivé : afficher seulement votre sélection.",
            all: s.allAudioLanguages,
            enabled: s.enabledAudioLanguages,
            options: Array(PlayerSettings.allAudioLanguageOptions.dropFirst())
        )
        .environmentObject(theme)
        .environmentObject(store)
        .onExitCommand { showAudioLanguages = false }
    }

    private var subtitleLanguagesSheet: some View {
        LanguageSelectionDetail(
            title: "Langues des sous-titres",
            subtitle: "Afficher toutes les langues de sous-titres ou sélectionner celles de votre choix",
            allLabel: "Toutes les langues",
            allHint: "Afficher toutes les langues. Désactivé : afficher seulement votre sélection.",
            all: s.allSubtitleLanguages,
            enabled: s.enabledSubtitleLanguages,
            options: Array(PlayerSettings.allSubtitleLanguageOptions.dropFirst())
        )
        .environmentObject(theme)
        .environmentObject(store)
        .onExitCommand { showSubtitleLanguages = false }
    }

    /// "All languages" or "N selected" for the drill-in rows.
    private var audioLanguagesSummary: String {
        store.settings.allAudioLanguages
            ? "Tous" : "\(store.settings.enabledAudioLanguages.count) sélectionnées"
    }
    private var subtitleLanguagesSummary: String {
        store.settings.allSubtitleLanguages
            ? "Tous" : "\(store.settings.enabledSubtitleLanguages.count) sélectionnées"
    }

    private func sizeLabel(_ size: Int) -> String {
        switch size {
        case ..<32: return "Petit (\(size) pt)"
        case ..<40: return "Standard (\(size) pt)"
        case ..<50: return "Grand (\(size) pt)"
        default: return "Très grand (\(size) pt)"
        }
    }

    private func timeoutLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "Immédiat" }
        if seconds == PlayerSettings.timeoutUnlimited { return "Attendre ma validation" }
        return "\(seconds)s"
    }

}

// MARK: - Language selection

/// A drill-in language picker: an "All languages" master switch plus one
/// toggle per language. Keeps the audio/subtitle dropdowns short by default
/// while still making an uncommon language reachable — the alternative was a
/// ~180-entry dropdown or a language that simply could not be chosen.
struct LanguageSelectionDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String
    let allLabel: String
    let allHint: String
    @Binding var all: Bool
    @Binding var enabled: [String]
    /// Every selectable (code, name), WITHOUT the "no preference" first entry.
    let options: [(String, String)]

    var body: some View {
        DetailScaffold(title: title, subtitle: subtitle) {
            SettingsGroupCard(title: allLabel, subtitle: allHint) {
                PlaybackToggleRow(icon: "globe", title: allLabel,
                                  subtitle: allHint, isOn: allBinding)
            }
            if !all {
                SettingsGroupCard(
                    title: "Langues",
                    subtitle: "Activer une langue pour la proposer dans les listes. Vous pouvez réactiver toutes les langues à tout moment."
                ) {
                    ForEach(options, id: \.0) { code, name in
                        PlaybackToggleRow(icon: "character.bubble", title: name,
                                          subtitle: "", isOn: binding(for: code))
                    }
                }
            }
        }
    }

    /// Turning "All" off with nothing selected would leave an empty picker —
    /// seed the common set so there is always something to choose.
    private var allBinding: Binding<Bool> {
        Binding(
            get: { all },
            set: { on in
                if !on, enabled.isEmpty { enabled = PlayerSettings.commonLanguageCodes.sorted() }
                all = on
            }
        )
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(code) },
            set: { on in
                if on {
                    if !enabled.contains(code) { enabled.append(code); enabled.sort() }
                } else {
                    enabled.removeAll { $0 == code }
                }
            }
        )
    }
}

// MARK: - Rows

/// A toggle row with a leading icon and Orivio pill switch (focus = fill + ring,
/// same treatment as every other settings row).
private struct PlaybackToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    /// Non-nil = this Apple TV can't do it. The row still shows (so the
    /// feature is discoverable and the limit is explained rather than
    /// mysterious) but reads as off and refuses to toggle.
    var unavailable: String?

    var body: some View {
        Button { if unavailable == nil { isOn.toggle() } } label: {
            PlaybackToggleLabel(
                icon: icon, title: title,
                subtitle: unavailable.map { "\(subtitle)\n\nUnavailable: \($0)." } ?? subtitle,
                isOn: isOn && unavailable == nil,
                dimmed: unavailable != nil
            )
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

private struct PlaybackToggleLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let title: String
    let subtitle: String
    let isOn: Bool
    var dimmed = false

    var body: some View {
        HStack(alignment: .top, spacing: OrivioSpacing.md) {
            SettingsIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)   // full text, wraps
                    .frame(maxWidth: 1000, alignment: .leading)
            }
            Spacer(minLength: OrivioSpacing.lg)
            OrivioSwitch(isOn: isOn)
                .padding(.top, 4)
        }
        .padding(.horizontal, OrivioSpacing.md)
        .padding(.vertical, OrivioSpacing.md)
        .frame(minHeight: 76)
        .frame(maxWidth: .infinity)
        .background(SettingsRowBackground(isFocused: isFocused))
        .opacity(dimmed ? 0.5 : 1)
    }
}

