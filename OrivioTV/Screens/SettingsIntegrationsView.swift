import SwiftUI

/// Settings → Integrations: the external services Orivio talks to — TMDB,
/// MDBList, the debrid providers, and a self-hosted TorrServer for P2P.
/// Trakt and the Orivio/Stremio accounts have their own panes.
struct IntegrationsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var tmdb: TMDBSettingsStore
    @EnvironmentObject private var mdblist: MDBListSettingsStore
    @EnvironmentObject private var debrid: DebridStore
    @EnvironmentObject private var torrent: TorrentSettingsStore
    @EnvironmentObject private var mediaServers: MediaServerStore
    @State private var sheet: IntegrationSheet?

    enum IntegrationSheet: String, Identifiable { case tmdb, mdblist, debrid, p2p, plex, jellyfin, twitch; var id: String { rawValue } }

    var body: some View {
        // APK layout: a single list of drill-in rows, each opening a sub-screen.
        DetailScaffold(title: SettingsCategory.integration.title, subtitle: SettingsCategory.integration.subtitle) {
            SettingsGroupCard(title: "") {
                // Orivio account moved to Settings → Account.
                integrationRow(title: "Twitch", subtitle: "Connexion, chaînes suivies et recherche", icon: "bubble.left.and.bubble.right") { sheet = .twitch }
                    .accessibilityIdentifier("ntv.integration.twitch")
                integrationRow(title: "TMDB", subtitle: "Compléter les informations des titres", icon: "film.stack") { sheet = .tmdb }
                integrationRow(title: "MDBList", subtitle: "Services de notes externes", icon: "star.circle.fill") { sheet = .mdblist }
                integrationRow(title: "Debrid", subtitle: "Sources en cache disponibles en lecture directe", icon: "bolt.horizontal.circle.fill") { sheet = .debrid }
                integrationRow(title: "P2P (TorrServer)", subtitle: "Lire les sources non mises en cache avec votre TorrServer", icon: "point.3.connected.trianglepath.dotted") { sheet = .p2p }
                integrationRow(title: "Plex", subtitle: mediaServers.account(for: .plex) == nil
                               ? "Retrouver la bibliothèque de votre serveur Plex" : "Connecté · \(mediaServers.plex?.serverName ?? "Plex")",
                               icon: MediaServerKind.plex.icon) { sheet = .plex }
                integrationRow(title: "Jellyfin", subtitle: mediaServers.account(for: .jellyfin) == nil
                               ? "Retrouver la bibliothèque de votre serveur Jellyfin" : "Connecté · \(mediaServers.jellyfin?.serverName ?? "Jellyfin")",
                               icon: MediaServerKind.jellyfin.icon) { sheet = .jellyfin }
            }
        }
        .fullScreenCover(item: $sheet) { s in
            ZStack {
                ATVBackground()
                integrationSheet(s)
            }
            .environmentObject(theme)
            .environmentObject(tmdb)
            .environmentObject(mdblist)
            .environmentObject(debrid)
            .environmentObject(torrent)
            .environmentObject(mediaServers)
            .onExitCommand { sheet = nil }
        }
    }

    private func integrationRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsValueCard(title: title, subtitle: subtitle, value: "", icon: icon)
        }
        .buttonStyle(PlainCardButtonStyle())
    }

    @ViewBuilder
    private func integrationSheet(_ s: IntegrationSheet) -> some View {
        switch s {
        case .twitch:
            NTVTwitchView()
        case .tmdb:
            DetailScaffold(title: "TMDB", subtitle: "Compléter les informations des titres") {
                SettingsGroupCard(title: "") { tmdbSection }
            }
        case .mdblist:
            DetailScaffold(title: "MDBList", subtitle: "Services de notes externes") {
                SettingsGroupCard(title: "") { mdblistSection }
            }
        case .debrid:
            DetailScaffold(title: "Debrid", subtitle: "Sources en cache disponibles en lecture directe") {
                SettingsGroupCard(title: "") { debridSection }
            }
        case .p2p:
            DetailScaffold(title: "P2P (TorrServer)", subtitle: "Lire les torrents avec votre instance TorrServer") {
                SettingsGroupCard(title: "") { P2PSection() }
            }
        case .plex:
            DetailScaffold(title: "Plex", subtitle: "Afficher votre serveur Plex dans la bibliothèque") {
                SettingsGroupCard(title: "") { MediaServerSection(kind: .plex) }
            }
        case .jellyfin:
            DetailScaffold(title: "Jellyfin", subtitle: "Afficher votre serveur Jellyfin dans la bibliothèque") {
                SettingsGroupCard(title: "") { MediaServerSection(kind: .jellyfin) }
            }
        }
    }

    // MARK: - MDBList

    private var mdblistSection: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            SettingsToggleCard(
                title: "Activer les notes MDBList",
                subtitle: "Regrouper les notes de plusieurs services",
                isOn: Binding(get: { mdblist.settings.enabled }, set: { mdblist.settings.enabled = $0 })
            )

            if mdblist.settings.enabled {
                MDBListKeyRow()
                ForEach(MDBListProvider.allCases) { provider in
                    MDBListProviderToggle(provider: provider)
                }
            }

            Text("Obtenez votre clé sur mdblist.com/preferences.")
                .font(.system(size: 18))
                .foregroundStyle(theme.palette.textTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Debrid

    private var debridSection: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            ForEach(DebridProvider.allCases) { provider in
                DebridProviderRow(provider: provider)
            }

            if debrid.configuredProviders.count > 1 {
                PreferredProviderRow()
                    .padding(.top, OrivioSpacing.sm)
            }
        }
    }

    // MARK: - TMDB

    private var tmdbSection: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            // ABOVE the switch, and always visible: the key is the thing that
            // turns TMDB on. Hiding it behind the switch meant the one control
            // that matters was the one you couldn't reach.
            TMDBKeyRow()

            SettingsToggleCard(
                title: "Activer TMDB",
                subtitle: tmdb.hasAPIKey
                    ? "Utiliser TMDB pour les contenus de vos collections"
                    : "Ajoutez votre clé API pour activer cette option",
                isOn: Binding(get: { tmdb.settings.enabled },
                              set: { tmdb.settings.enabled = $0 && tmdb.hasAPIKey })
            )

            if tmdb.settings.enabled {
                SettingsToggleCard(
                    title: "Compléter les titres à reprendre",
                    subtitle: "Compléter les titres et illustrations manquants des lectures synchronisées",
                    isOn: Binding(get: { tmdb.settings.enrichContinueWatching }, set: { tmdb.settings.enrichContinueWatching = $0 })
                )

                OrivioDropdown(
                    title: "Langue",
                    subtitle: "TMDB metadata language",
                    selection: tmdb.settings.language,
                    options: TMDBLanguages.options.map { OrivioDropdownOption($0, TMDBLanguages.displayName($0)) }
                ) { tmdb.settings.language = $0 }

                SettingsToggleCard(
                    title: "Distribution et équipe",
                    subtitle: "Afficher la distribution, l’équipe et le réalisateur depuis TMDB",
                    isOn: Binding(get: { tmdb.settings.useCredits }, set: { tmdb.settings.useCredits = $0 })
                )
                SettingsToggleCard(
                    title: "Bandes-annonces",
                    subtitle: "Afficher les bandes-annonces TMDB sur les fiches",
                    isOn: Binding(get: { tmdb.settings.useTrailers }, set: { tmdb.settings.useTrailers = $0 })
                )
                SettingsToggleCard(
                    title: "Titres similaires",
                    subtitle: "Afficher les recommandations TMDB sur les fiches",
                    isOn: Binding(get: { tmdb.settings.useMoreLikeThis }, set: { tmdb.settings.useMoreLikeThis = $0 })
                )
                SettingsToggleCard(
                    title: "Détails",
                    subtitle: "Afficher les pays et langues du titre depuis TMDB",
                    isOn: Binding(get: { tmdb.settings.useDetails }, set: { tmdb.settings.useDetails = $0 })
                )
                SettingsToggleCard(
                    title: "Dates de sortie",
                    subtitle: "Afficher la date de sortie depuis TMDB",
                    isOn: Binding(get: { tmdb.settings.useReleaseDates }, set: { tmdb.settings.useReleaseDates = $0 })
                )
                SettingsToggleCard(
                    title: "Sociétés de production",
                    subtitle: "Afficher les sociétés de production depuis TMDB",
                    isOn: Binding(get: { tmdb.settings.useProductions }, set: { tmdb.settings.useProductions = $0 })
                )
                SettingsToggleCard(
                    title: "Collections",
                    subtitle: "Afficher la collection du titre et ses autres films",
                    isOn: Binding(get: { tmdb.settings.useCollections }, set: { tmdb.settings.useCollections = $0 })
                )
                SettingsToggleCard(
                    title: "Épisodes",
                    subtitle: "Afficher les notes et dates de diffusion des épisodes depuis TMDB",
                    isOn: Binding(get: { tmdb.settings.useEpisodes }, set: { tmdb.settings.useEpisodes = $0 })
                )
            }

            Text("Les clés TMDB sont gratuites. Connectez-vous sur themoviedb.org, ouvrez Réglages → API et copiez la clé API v3.")
                .font(.system(size: 18))
                .foregroundStyle(theme.palette.textTertiary)
                .padding(.top, 2)
        }
    }

}

// MARK: - Debrid rows

private struct DebridProviderRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var debrid: DebridStore
    let provider: DebridProvider

    @State private var showEditor = false

    private var isConfigured: Bool { !debrid.key(for: provider).isEmpty }

    var body: some View {
        Button { showEditor = true } label: {
            HStack(spacing: OrivioSpacing.lg) {
                Text(provider.shortName)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(theme.palette.onSecondary)
                    .frame(width: 54, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isConfigured ? OrivioPrimitives.success : theme.palette.surfaceVariant)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(isConfigured ? "Connecté · clé enregistrée" : "Clé disponible sur \(provider.keyHint)")
                        .font(.system(size: 19))
                        .foregroundStyle(isConfigured ? OrivioPrimitives.success : theme.palette.textSecondary)
                }
                Spacer()
                if debrid.preferred == provider && debrid.configuredProviders.count > 1 {
                    MetaBadge(text: "PREFERRED", tint: theme.palette.secondary.opacity(0.2), textColor: theme.palette.secondary)
                }
                Image(systemName: isConfigured ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isConfigured ? OrivioPrimitives.success : theme.palette.textTertiary)
            }
            .integrationRowBackground(theme)
        }
        .buttonStyle(PlainCardButtonStyle())
        .fullScreenCover(isPresented: $showEditor) {
            DebridKeyEditor(provider: provider) { showEditor = false }
                .environmentObject(theme)
                .environmentObject(debrid)
        }
    }
}

private struct PreferredProviderRow: View {
    @EnvironmentObject private var debrid: DebridStore

    var body: some View {
        OrivioDropdown(
            title: "Service préféré",
            subtitle: "Utilisé en priorité lorsque plusieurs services proposent la source",
            selection: debrid.preferred?.id ?? "",
            options: debrid.configuredProviders.map { OrivioDropdownOption($0.id, $0.displayName) }
        ) { picked in
            debrid.preferred = DebridProvider.allCases.first { $0.id == picked }
        }
    }
}

private struct DebridKeyEditor: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var debrid: DebridStore
    let provider: DebridProvider
    let onDone: () -> Void

    @State private var key = ""
    @State private var validating = false
    @State private var status: String?
    @State private var showQR = false

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(spacing: OrivioSpacing.xl) {
                Text("Connecter \(provider.displayName)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)

                // QR sign-in — scan on your phone, like the APK. All four
                // providers support it (RD/PM OAuth device, AD/TB device flows).
                if provider.supportsQRAuth {
                    Button { showQR = true } label: {
                        HStack(spacing: OrivioSpacing.sm) {
                            Image(systemName: "qrcode")
                            Text("Connexion par code QR")
                        }
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.palette.onSecondary)
                        .padding(.horizontal, OrivioSpacing.xl)
                        .padding(.vertical, OrivioSpacing.md)
                        .background(Capsule().fill(theme.palette.secondary))
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    Text("ou collez une clé API disponible sur \(provider.keyHint)")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textTertiary)
                } else {
                    Text("Obtenez votre clé sur \(provider.keyHint)")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                SecureField("Coller la clé API", text: $key)
                    .font(.system(size: 24))
                    .frame(maxWidth: 760)

                if let status {
                    Text(status)
                        .font(.system(size: 20))
                        .foregroundStyle(status.hasPrefix("Valid") ? OrivioPrimitives.success : OrivioPrimitives.error)
                }

                HStack(spacing: OrivioSpacing.lg) {
                    Button(action: verifyAndSave) {
                        if validating { ProgressView().tint(theme.palette.onSecondary) }
                        else { Text("Vérifier et enregistrer") }
                    }
                    // Not disabled while validating: that disables the button
                    // you just pressed and drops focus. The action guards.
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !debrid.key(for: provider).isEmpty {
                        Button("Supprimer", role: .destructive) {
                            debrid.setKey("", for: provider)
                            onDone()
                        }
                    }
                    Button("Annuler", role: .cancel, action: onDone)
                }
                .font(.system(size: 24, weight: .semibold))
            }
            .padding(OrivioSpacing.huge)
        }
        .onAppear { key = debrid.key(for: provider) }
        // Same as Cancel — dismiss without saving.
        .onExitCommand { onDone() }
        .fullScreenCover(isPresented: $showQR) {
            DebridConnectPage(provider: provider) { linked in
                showQR = false
                if linked { onDone() }
            }
            .environmentObject(theme)
            .environmentObject(debrid)
        }
    }

    private func verifyAndSave() {
        guard !validating else { return }
        validating = true
        status = nil
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        Task {
            let valid = await DebridService.validate(provider: provider, apiKey: trimmed)
            validating = false
            if valid {
                debrid.setKey(trimmed, for: provider)
                status = "Clé valide et enregistrée."
                onDone()
            } else {
                status = "Clé invalide ou problème de réseau."
            }
        }
    }
}

/// Full-screen QR device-login for a debrid provider (Real-Debrid & Premiumize
/// OAuth device flows, AllDebrid PIN flow, TorBox device flow) — the APK's
/// scan-to-connect. Menu/Back cancels.
private struct DebridConnectPage: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var debrid: DebridStore
    let provider: DebridProvider
    /// `true` when the account was linked.
    let onDone: (Bool) -> Void

    @State private var code: DebridDeviceCode?
    @State private var errorText: String?
    @State private var expiresAt = Date()
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(spacing: OrivioSpacing.xl) {
                Text("Connecter \(provider.displayName)")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(theme.palette.textPrimary)

                if let code {
                    Text("Scannez le code avec votre téléphone, ou ouvrez \(code.verificationURL) puis saisissez le code ci-dessous.")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)

                    QRCodeView(string: code.qrURL, side: 360)

                    Text(code.userCode)
                        .font(.system(size: 60, weight: .heavy, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(theme.palette.secondary)

                    HStack(spacing: OrivioSpacing.sm) {
                        ProgressView().tint(theme.palette.secondary)
                        Text("En attente de votre autorisation…")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.palette.textTertiary)
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let seconds = expiresAt.timeIntervalSince(ctx.date)
                        let remaining = seconds.isFinite ? Int(min(max(seconds, 0), 86_400)) : 0
                        Text(remaining > 0
                             ? "Expiration du code dans \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                             : "Renouvellement du code…")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.palette.textTertiary)
                    }
                } else if let errorText {
                    Text(errorText)
                        .font(.system(size: 24))
                        .foregroundStyle(OrivioPrimitives.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                    Button("Réessayer") { Task { await begin() } }
                        .font(.system(size: 24, weight: .semibold))
                } else {
                    ProgressView().tint(theme.palette.secondary)
                    Text("Préparation de la connexion…")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                Text("Retour pour annuler")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textTertiary)
                // The QR / starting states have no focusable view, so the
                // onExitCommand below could never fire for them.
                if errorText == nil { FocusAnchor() }
            }
            .padding(OrivioSpacing.huge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await begin() }
        .onDisappear { pollTask?.cancel() }
        .onExitCommand { pollTask?.cancel(); onDone(false) }
    }

    private func begin(renewal: Bool = false) async {
        // Only cancel when NOT renewing: the renewal call runs INSIDE pollTask
        // itself, so cancelling here cancelled the very task doing the renewal
        // — the fresh startDeviceAuth then ran in a cancelled context, its
        // URLSession threw, and the user got an error instead of a new code.
        if !renewal { pollTask?.cancel() }
        errorText = nil
        code = nil
        guard let c = await DebridService.startDeviceAuth(provider) else {
            errorText = "Impossible de préparer le code QR. Vérifiez votre connexion ou collez une clé API."
            return
        }
        code = c
        expiresAt = Date().addingTimeInterval(TimeInterval(c.expiresIn))
        startPolling(c)
    }

    /// Codes renewed since the screen opened — cap so an abandoned QR screen
    /// doesn't hit the provider's device-auth endpoint forever.
    @State private var renewals = 0

    private func startPolling(_ c: DebridDeviceCode) {
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(c.interval, 3)) * 1_000_000_000)
                if Task.isCancelled { return }
                if Date() >= expiresAt {   // expired → fresh code (bounded)
                    renewals += 1
                    guard renewals <= 3 else {
                        errorText = "Le code QR a expiré. Revenez en arrière puis rouvrez cet écran."
                        code = nil
                        return
                    }
                    await begin(renewal: true)
                    return
                }
                switch await DebridService.pollDeviceAuth(provider, c) {
                case .pending:
                    continue
                case .success(let s):
                    debrid.applyDeviceAuth(s, for: provider)
                    onDone(true)
                    return
                case .failed(let msg):
                    errorText = msg
                    code = nil
                    return
                }
            }
        }
    }
}

// MARK: - MDBList rows

/// TMDB API key row — the same shape as the MDBList and debrid key rows.
private struct TMDBKeyRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var tmdb: TMDBSettingsStore
    @State private var showEditor = false

    var body: some View {
        Button { showEditor = true } label: {
            HStack(spacing: OrivioSpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clé API")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(tmdb.hasAPIKey
                         ? "Connecté · clé enregistrée"
                         : "Envoyez la clé depuis votre téléphone avec le QR, ou collez-la ici")
                        .font(.system(size: 19))
                        .foregroundStyle(tmdb.hasAPIKey ? OrivioPrimitives.success : theme.palette.textSecondary)
                }
                Spacer()
                Image(systemName: tmdb.hasAPIKey ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(tmdb.hasAPIKey ? OrivioPrimitives.success : theme.palette.textTertiary)
            }
            .integrationRowBackground(theme)
        }
        .buttonStyle(PlainCardButtonStyle())
        .fullScreenCover(isPresented: $showEditor) {
            TMDBKeyEditor { showEditor = false }
                .environmentObject(theme)
                .environmentObject(tmdb)
        }
    }
}

private struct TMDBKeyEditor: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var tmdb: TMDBSettingsStore
    let onDone: () -> Void

    @State private var key = ""
    @State private var validating = false
    @State private var status: String?
    @State private var showQR = false

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(spacing: OrivioSpacing.xl) {
                Text("Clé API TMDB")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Connectez-vous sur themoviedb.org → Réglages → API puis copiez votre clé v3 gratuite.")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    .fixedSize(horizontal: false, vertical: true)

                // The key already lives in a browser tab on the phone. Scanning
                // beats retyping 32 hex characters on a remote.
                Button { showQR = true } label: {
                    HStack(spacing: OrivioSpacing.sm) {
                        Image(systemName: "qrcode")
                        Text("Envoyer depuis mon téléphone")
                    }
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.palette.onSecondary)
                    .padding(.horizontal, OrivioSpacing.xl)
                    .padding(.vertical, OrivioSpacing.md)
                    .background(Capsule().fill(theme.palette.secondary))
                }
                .buttonStyle(PlainCardButtonStyle())

                Text("or type it here")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textTertiary)

                SecureField("Coller la clé API", text: $key)
                    .font(.system(size: 24))
                    .frame(maxWidth: 760)

                if let status {
                    Text(status)
                        .font(.system(size: 20))
                        .foregroundStyle(status.hasPrefix("Valid") ? OrivioPrimitives.success : OrivioPrimitives.error)
                }

                HStack(spacing: OrivioSpacing.lg) {
                    Button(action: verifyAndSave) {
                        if validating { ProgressView().tint(theme.palette.onSecondary) }
                        else { Text("Vérifier et enregistrer") }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if tmdb.hasAPIKey {
                        Button("Supprimer", role: .destructive) {
                            tmdb.setAPIKey("")
                            onDone()
                        }
                    }
                    Button("Annuler", role: .cancel, action: onDone)
                }
                .font(.system(size: 24, weight: .semibold))
            }
            .padding(OrivioSpacing.huge)
        }
        .onAppear { key = tmdb.settings.trimmedAPIKey }
        // Same as Cancel — dismiss without saving.
        .onExitCommand { onDone() }
        .fullScreenCover(isPresented: $showQR) {
            TMDBKeyHandoffPage { saved in
                showQR = false
                if saved { onDone() }
            }
            .environmentObject(theme)
            .environmentObject(tmdb)
        }
    }

    private func verifyAndSave() {
        guard !validating else { return }
        validating = true
        status = nil
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        Task {
            let valid = await TMDBService.validate(apiKey: trimmed)
            validating = false
            if valid {
                tmdb.setAPIKey(trimmed)
                status = "Clé valide et enregistrée."
                onDone()
            } else {
                status = "Clé invalide ou problème de réseau."
            }
        }
    }
}

/// Scan-to-enter for the TMDB key: this Apple TV serves a one-field page on the
/// local network and shows its address as a QR. TMDB itself has no device/QR
/// login — every v3 request is authenticated by the key, so there is no flow
/// that hands one out — hence the hand-off happens between the phone and the
/// TV rather than through TMDB.
private struct TMDBKeyHandoffPage: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var tmdb: TMDBSettingsStore
    /// `true` when a key was accepted and saved.
    let onDone: (Bool) -> Void

    @StateObject private var server = KeyHandoffServer(
        title: "TMDB API key",
        blurb: "Open <a href=\"https://www.themoviedb.org/settings/api\" target=\"_blank\" "
             + "rel=\"noopener\">themoviedb.org/settings/api</a>, copy your "
             + "<strong>API Key (v3 auth)</strong>, and paste it below.",
        placeholder: "Collez votre clé API TMDB"
    )

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(spacing: OrivioSpacing.lg) {
                Text("Envoyer votre clé TMDB")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)

                if server.accepted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(OrivioPrimitives.success)
                    Text("Clé enregistrée.")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(theme.palette.textPrimary)
                } else if let address = server.address {
                    Text("Scannez le QR avec votre téléphone, ou ouvrez \(address) dans son navigateur. Les deux appareils doivent être sur le même réseau.")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                        .fixedSize(horizontal: false, vertical: true)
                    QRCodeView(string: address, side: 360)
                    Text(address)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.palette.secondary)
                } else if let error = server.lastError {
                    Text(error)
                        .font(.system(size: 22))
                        .foregroundStyle(OrivioPrimitives.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    OrivioLoadingView(label: "Préparation")
                        .frame(height: 360)
                }

                Button(server.accepted ? "Terminé" : "Annuler") { onDone(server.accepted) }
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.top, OrivioSpacing.sm)
            }
            .padding(OrivioSpacing.huge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            server.onSubmit = { value in
                // Verified before saving, exactly like on-TV entry — a typo
                // should say so on the phone, where it can be fixed, rather
                // than quietly emptying every TMDB-backed row.
                guard await TMDBService.validate(apiKey: value) else {
                    return (false, "Cette clé est invalide. Vérifiez que vous avez copié la clé API v3.")
                }
                tmdb.setAPIKey(value)
                return (true, "Clé enregistrée. Vous pouvez fermer cette page.")
            }
            server.start()
        }
        .onDisappear { server.stop() }
        .onExitCommand { onDone(server.accepted) }
    }
}

private struct MDBListKeyRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var mdblist: MDBListSettingsStore
    @State private var showEditor = false

    private var isConfigured: Bool {
        !mdblist.settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Button { showEditor = true } label: {
            HStack(spacing: OrivioSpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clé API")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(isConfigured ? "Connecté · clé enregistrée" : "Coller votre clé MDBList")
                        .font(.system(size: 19))
                        .foregroundStyle(isConfigured ? OrivioPrimitives.success : theme.palette.textSecondary)
                }
                Spacer()
                Image(systemName: isConfigured ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isConfigured ? OrivioPrimitives.success : theme.palette.textTertiary)
            }
            .integrationRowBackground(theme)
        }
        .buttonStyle(PlainCardButtonStyle())
        .fullScreenCover(isPresented: $showEditor) {
            MDBListKeyEditor { showEditor = false }
                .environmentObject(theme)
                .environmentObject(mdblist)
        }
    }
}

private struct MDBListProviderToggle: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var mdblist: MDBListSettingsStore
    let provider: MDBListProvider

    private var binding: Binding<Bool> {
        Binding(
            get: {
                switch provider {
                case .trakt: return mdblist.settings.showTrakt
                case .imdb: return mdblist.settings.showImdb
                case .tmdb: return mdblist.settings.showTmdb
                case .letterboxd: return mdblist.settings.showLetterboxd
                case .tomatoes: return mdblist.settings.showTomatoes
                case .audience: return mdblist.settings.showAudience
                case .metacritic: return mdblist.settings.showMetacritic
                }
            },
            set: { newValue in
                switch provider {
                case .trakt: mdblist.settings.showTrakt = newValue
                case .imdb: mdblist.settings.showImdb = newValue
                case .tmdb: mdblist.settings.showTmdb = newValue
                case .letterboxd: mdblist.settings.showLetterboxd = newValue
                case .tomatoes: mdblist.settings.showTomatoes = newValue
                case .audience: mdblist.settings.showAudience = newValue
                case .metacritic: mdblist.settings.showMetacritic = newValue
                }
            }
        )
    }

    var body: some View {
        SettingsToggleCard(title: provider.fullName, subtitle: "", isOn: binding)
    }
}

private struct MDBListKeyEditor: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var mdblist: MDBListSettingsStore
    let onDone: () -> Void

    @State private var key = ""
    @State private var validating = false
    @State private var status: String?

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(spacing: OrivioSpacing.xl) {
                Text("Clé API MDBList")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Obtenez votre clé sur mdblist.com/preferences")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textSecondary)

                SecureField("Coller la clé API", text: $key)
                    .font(.system(size: 24))
                    .frame(maxWidth: 760)

                if let status {
                    Text(status)
                        .font(.system(size: 20))
                        .foregroundStyle(status.hasPrefix("Valid") ? OrivioPrimitives.success : OrivioPrimitives.error)
                }

                HStack(spacing: OrivioSpacing.lg) {
                    Button(action: verifyAndSave) {
                        if validating { ProgressView().tint(theme.palette.onSecondary) }
                        else { Text("Vérifier et enregistrer") }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !mdblist.settings.apiKey.isEmpty {
                        Button("Supprimer", role: .destructive) {
                            mdblist.settings.apiKey = ""
                            onDone()
                        }
                    }
                    Button("Annuler", role: .cancel, action: onDone)
                }
                .font(.system(size: 24, weight: .semibold))
            }
            .padding(OrivioSpacing.huge)
        }
        .onAppear { key = mdblist.settings.apiKey }
        // Same as Cancel — dismiss without saving.
        .onExitCommand { onDone() }
    }

    private func verifyAndSave() {
        guard !validating else { return }
        validating = true
        status = nil
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        Task {
            let valid = await MDBListService.validate(apiKey: trimmed)
            validating = false
            if valid {
                mdblist.settings.apiKey = trimmed
                status = "Clé valide et enregistrée."
                onDone()
            } else {
                status = "Clé invalide ou problème de réseau."
            }
        }
    }
}

/// A small curated ISO-639-1 language list for the TMDB language picker.
enum TMDBLanguages {
    static let options = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "hi", "ru", "ar"]

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

/// Shared card background for integration rows. Reads `isFocused` so that when
/// the row is the label of a focusable Button (which `PlainCardButtonStyle`
/// otherwise strips of all focus chrome) it still shows the fill + accent ring.
/// On non-focusable rows `isFocused` stays false, giving a plain static card.
private struct IntegrationRowBackground: ViewModifier {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OrivioSpacing.lg)
            .frame(minHeight: 68)
            // Leading, not the default centre: every other row in these panes
            // is left-aligned, so a connected-account row (Trakt's and SIMKL's
            // both use this) sat centred in the middle of a left-aligned list.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OrivioRadius.md, style: .continuous)
                    .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrivioRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 4)
            )
    }
}

extension View {
    /// Shared, focus-aware card background for integration rows.
    func integrationRowBackground(_ theme: ThemeManager) -> some View {
        modifier(IntegrationRowBackground())
    }
}

/// P2P via a TorrServer instance. tvOS can't run a torrent engine on-device
/// (no subprocess / no BitTorrent library), so peering is offloaded to a
/// TorrServer the user runs on their network.
private struct P2PSection: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var torrent: TorrentSettingsStore
    @State private var testing = false
    @State private var testResult: String?

    private var s: Binding<TorrentSettings> {
        Binding(get: { torrent.settings }, set: { torrent.settings = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            SettingsToggleCard(
                title: "Activer le P2P",
                subtitle: "Utiliser TorrServer lorsqu’aucun service de débridage n’est configuré",
                isOn: s.p2pEnabled
            )

            if torrent.settings.p2pEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse TorrServer")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.palette.textPrimary)
                    TextField("http://192.168.1.10:8090", text: s.serverURL)
                        .font(.system(size: 22))
                    Text("Lancez TorrServer sur un ordinateur, un NAS ou un Raspberry Pi de votre réseau, puis saisissez son adresse.")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.palette.textTertiary)
                }
                .padding(.vertical, 4)

                HStack(spacing: OrivioSpacing.md) {
                    Button {
                        guard !testing, !torrent.settings.serverURL.isEmpty else { return }
                        testing = true; testResult = nil
                        Task {
                            let ok = await TorrServerService.ping(torrent.settings)
                            testResult = ok ? "Connecté ✓" : "TorrServer est inaccessible"
                            testing = false
                        }
                    } label: {
                        if testing { ProgressView() } else { SeeAllLabel(text: "Tester la connexion") }
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 19))
                            .foregroundStyle(testResult.contains("✓") ? OrivioPrimitives.success : OrivioPrimitives.error)
                    }
                }

                SettingsToggleCard(
                    title: "Masquer les statistiques des torrents",
                    subtitle: "Masquer le nombre de pairs et de sources pendant la lecture",
                    isOn: s.hideTorrentStats
                )
            }

            Text("Le P2P utilise votre serveur TorrServer. Le débridage reste prioritaire lorsqu’il est configuré.")
                .font(.system(size: 17))
                .foregroundStyle(theme.palette.textTertiary)
                .padding(.top, 2)
        }
    }
}
