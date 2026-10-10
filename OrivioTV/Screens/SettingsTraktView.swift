import SwiftUI

/// Settings → Trakt & SIMKL: device-code sign-in, scrobble toggle, and account
/// status for Trakt, plus SIMKL's PIN login in its own section below.
struct TraktDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var trakt: TraktStore
    @EnvironmentObject private var simkl: SimklStore
    @EnvironmentObject private var profiles: ProfileStore

    @State private var deviceCode: TraktDeviceCode?
    @State private var polling = false
    @State private var statusMessage: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var showConnect = false
    @State private var confirmClearPlayback = false
    @State private var codeExpiresAt: Date?

    // SIMKL's PIN login runs the same shape of flow on its own state, so a
    // Trakt code left mid-poll can't be confused for a SIMKL one.
    @State private var simklCode: SimklDeviceCode?
    @State private var simklPollTask: Task<Void, Never>?
    @State private var simklStatus: String?
    @State private var showSimklConnect = false
    @State private var simklExpiresAt: Date?

    var body: some View {
        DetailScaffold(title: SettingsCategory.trakt.title, subtitle: SettingsCategory.trakt.subtitle) {
            // Shown above BOTH states: a profile that hasn't connected Trakt
            // sees the signed-out view, and this is how someone turns the
            // per-profile behaviour on (or back off) from there. Only worth
            // showing once there is more than one profile. ONE switch scopes
            // both services — the stores share the UserDefaults key, and the
            // setter writes both so each runs its own adopt/reload.
            if profiles.profiles.count > 1 {
                SettingsToggleCard(
                    title: "Comptes Trakt et SIMKL propres à chaque profil",
                    subtitle: "Chaque profil connecte ses comptes Trakt et SIMKL. Désactivé : partager un compte de chaque service sur cette TV.",
                    isOn: Binding(
                        get: { trakt.perProfileAccounts },
                        set: { trakt.perProfileAccounts = $0; simkl.perProfileAccounts = $0 }
                    )
                )
                .padding(.bottom, OrivioSpacing.sm)
            }
            if trakt.isSignedIn {
                signedInView
            } else {
                signedOutView
            }

            SettingsGroupCard(
                title: "SIMKL",
                subtitle: "Un service de suivi distinct de Trakt"
            ) {
                simklSection
            }
            .padding(.top, OrivioSpacing.md)
        }
        .onDisappear { pollTask?.cancel(); simklPollTask?.cancel() }
        // The device-code QR gets its OWN full-screen page (APK-style) instead
        // of squeezing into the settings pane.
        .fullScreenCover(isPresented: $showConnect) {
            ZStack {
                ATVBackground()
                if let code = deviceCode {
                    TraktConnectPage(code: code, expiresAt: codeExpiresAt ?? Date())
                        // Rebuild when the code changes (auto-refresh) so the QR
                        // + code + countdown all reset to the new code.
                        .id(code.userCode)
                } else {
                    // While the device code loads the page was BLANK with
                    // nothing focusable — and with no focus, Menu falls
                    // through to the system and suspends the app instead of
                    // cancelling. The anchor keeps onExitCommand reachable.
                    VStack(spacing: OrivioSpacing.md) {
                        FocusAnchor()
                        ProgressView().tint(theme.palette.secondary)
                        Text("Connexion à Trakt…")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            .environmentObject(theme)
            .onExitCommand { cancelConnect() }
        }
        .fullScreenCover(isPresented: $showSimklConnect) {
            ZStack {
                ATVBackground()
                if let code = simklCode {
                    SimklConnectPage(code: code, expiresAt: simklExpiresAt ?? Date())
                        .id(code.userCode)
                } else {
                    // Same as the Trakt cover: focus must live SOMEWHERE or
                    // Menu suspends the app instead of cancelling.
                    VStack(spacing: OrivioSpacing.md) {
                        FocusAnchor()
                        ProgressView().tint(theme.palette.secondary)
                        Text("Connexion à SIMKL…")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            .environmentObject(theme)
            .onExitCommand { cancelSimklConnect() }
        }
    }

    // MARK: SIMKL

    private var simklSection: some View {
        // SettingsGroupCard's content stack is centre-aligned (its rows are all
        // full-width, so it never showed). The account row and the note are
        // not, and sat centred while Trakt's identical row above sat leading.
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            simklSectionContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var simklSectionContent: some View {
        if simkl.isSignedIn {
            HStack(spacing: OrivioSpacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(OrivioPrimitives.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(simkl.username ?? "Connecté")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("SIMKL account linked")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .integrationRowBackground(theme)

            SettingsToggleCard(
                title: "Synchroniser l’historique",
                subtitle: "Synchroniser les films et épisodes vus avec SIMKL",
                isOn: Binding(
                    get: { simkl.syncWatchHistory },
                    set: { simkl.syncWatchHistory = $0; simkl.onSyncSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser les titres à reprendre",
                subtitle: "Retrouver les prochains épisodes suivis dans SIMKL. Ce service ne conserve pas la position de lecture : ils commencent au début.",
                isOn: Binding(
                    get: { simkl.syncContinueWatching },
                    set: { simkl.syncContinueWatching = $0; simkl.onSyncSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser la liste à voir",
                subtitle: "Synchroniser votre bibliothèque avec la liste à voir de SIMKL. Les suppressions restent locales.",
                isOn: Binding(
                    get: { simkl.syncWatchlist },
                    set: { simkl.syncWatchlist = $0; simkl.onSyncSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser les notes",
                subtitle: "Synchroniser vos notes de 1 à 10 avec SIMKL",
                isOn: Binding(
                    get: { simkl.syncRatings },
                    set: { simkl.syncRatings = $0; simkl.onSyncSettingChange?() }
                )
            )

            Button {
                simkl.onSyncSettingChange?()
                simkl.setSyncStatus("Synchronisation avec SIMKL…")
            } label: {
                SettingsActionRow(
                    title: "Synchroniser maintenant",
                    subtitle: simkl.lastSyncStatus ?? "Lancer une synchronisation avec SIMKL",
                    leadingIcon: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            // Said once, here, rather than leaving a viewer to wonder why the
            // Trakt section above has a Continue Watching switch and this one
            // does not.
            Text("SIMKL ne conserve pas la position des lectures en cours. Les films et épisodes terminés sont bien marqués comme vus.")
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button { simkl.signOut() } label: {
                DestructivePillLabel(title: "Déconnecter SIMKL")
            }
            .buttonStyle(PlainCardButtonStyle())
            .padding(.top, OrivioSpacing.sm)
        } else if SimklStore.isConfigured {
            Button(action: startSimklLogin) {
                SettingsActionRow(
                    title: "Connexion",
                    subtitle: "Se connecter avec un code sur simkl.com/pin",
                    leadingIcon: "link"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            if let simklStatus {
                Text(simklStatus)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        } else {
            // No client id in this build. Say so plainly rather than offering a
            // Login button whose only possible outcome is an error.
            Text("La connexion à SIMKL n’est pas encore configurée dans cette version de nTV.")
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startSimklLogin() {
        showSimklConnect = true
        Task { await loadSimklCode() }
    }

    /// Request a fresh PIN and (re)start polling. Also the auto-refresh path
    /// when a code expires while the page is still open.
    private func loadSimklCode() async {
        simklStatus = nil
        do {
            let code = try await SimklService.startDeviceCode()
            simklCode = code
            simklExpiresAt = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            beginSimklPolling(code)
        } catch {
            simklStatus = "Connexion à SIMKL impossible : \(error.localizedDescription)"
            showSimklConnect = false
        }
    }

    private func cancelSimklConnect() {
        simklPollTask?.cancel()
        simklCode = nil
        simklExpiresAt = nil
        showSimklConnect = false
    }

    private func beginSimklPolling(_ code: SimklDeviceCode) {
        simklPollTask?.cancel()
        simklPollTask = Task {
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while !Task.isCancelled && Date() < deadline {
                switch await SimklService.pollToken(userCode: code.userCode) {
                case .authorized(let access):
                    // Before storing: the manager watches `accessToken` and
                    // reads this flag to decide between syncing now and
                    // deferring behind the first screen.
                    simkl.markSignedInHere()
                    simkl.store(access: access)
                    let name = await SimklService.fetchUsername(accessToken: access)
                    simkl.setUsername(name)
                    simklCode = nil
                    simklExpiresAt = nil
                    showSimklConnect = false
                    return
                case .expired:
                    if !Task.isCancelled && showSimklConnect { await loadSimklCode() }
                    return
                case .failed(let message):
                    simklCode = nil
                    simklExpiresAt = nil
                    showSimklConnect = false
                    simklStatus = message
                    return
                case .pending:
                    try? await Task.sleep(nanoseconds: UInt64(max(code.interval, 1)) * 1_000_000_000)
                }
            }
            if !Task.isCancelled && showSimklConnect { await loadSimklCode() }
        }
    }

    // MARK: Signed in

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            HStack(spacing: OrivioSpacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(OrivioPrimitives.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trakt.username ?? "Connecté")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("Compte Trakt connecté")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .integrationRowBackground(theme)

            SettingsToggleCard(
                title: "Enregistrer les lectures dans Trakt",
                subtitle: "Signaler automatiquement vos lectures à Trakt",
                isOn: $trakt.scrobbleEnabled
            )
            SettingsToggleCard(
                title: "Synchroniser l’historique",
                subtitle: "Synchroniser les films et épisodes vus avec Trakt",
                isOn: Binding(
                    get: { trakt.syncWatchHistory },
                    set: { trakt.syncWatchHistory = $0; trakt.onTraktSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser les titres à reprendre",
                subtitle: "Retrouver les lectures en cours de Trakt dans vos titres à reprendre",
                isOn: Binding(
                    get: { trakt.syncPlayback },
                    set: { trakt.syncPlayback = $0; trakt.onTraktSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser la liste à voir",
                subtitle: "Synchroniser votre bibliothèque et votre liste à voir Trakt",
                isOn: Binding(
                    get: { trakt.syncWatchlist },
                    set: { trakt.syncWatchlist = $0; trakt.onTraktSettingChange?() }
                )
            )
            SettingsToggleCard(
                title: "Synchroniser les notes",
                subtitle: "Synchroniser vos notes de 1 à 10 avec Trakt",
                isOn: Binding(
                    get: { trakt.syncRatings },
                    set: { trakt.syncRatings = $0; trakt.onTraktSettingChange?() }
                )
            )

            Button {
                trakt.onTraktSettingChange?()
                trakt.setSyncStatus("Synchronisation avec Trakt…")
            } label: {
                SettingsActionRow(
                    title: "Synchroniser maintenant",
                    subtitle: trakt.lastSyncStatus ?? "Lancer une synchronisation avec Trakt",
                    leadingIcon: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            Button { confirmClearPlayback = true } label: {
                SettingsActionRow(
                    title: "Effacer les lectures en cours de Trakt",
                    subtitle: "Effacer les lectures partielles de Trakt sans supprimer votre historique de titres vus",
                    leadingIcon: "trash"
                )
            }
            .buttonStyle(PlainCardButtonStyle())
            .alert("Effacer les lectures en cours de Trakt ?", isPresented: $confirmClearPlayback) {
                Button("Effacer", role: .destructive) {
                    trakt.setSyncStatus("Effacement des lectures en cours de Trakt…")
                    trakt.onClearContinueWatching?()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Supprime les lectures partielles directement dans Trakt. Votre historique de titres vus reste conservé. Cette action est définitive.")
            }

            Button { trakt.signOut() } label: {
                DestructivePillLabel(title: "Se déconnecter")
            }
            .buttonStyle(PlainCardButtonStyle())
            .padding(.top, OrivioSpacing.sm)
        }
    }

    // MARK: Signed out

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            Button(action: startLogin) {
                SettingsActionRow(
                    title: "Connexion",
                    subtitle: "Se connecter avec un code sur trakt.tv/activate",
                    leadingIcon: "link"
                )
            }
            .buttonStyle(PlainCardButtonStyle())

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    // MARK: Actions

    private func startLogin() {
        showConnect = true
        Task { await loadCode() }
    }

    /// Request a fresh device code and (re)start polling. Called on Login and
    /// automatically whenever the current code expires, so a new code always
    /// replaces the old one without leaving the page.
    private func loadCode() async {
        statusMessage = nil
        do {
            let code = try await TraktService.startDeviceCode()
            deviceCode = code
            codeExpiresAt = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            beginPolling(code)
        } catch {
            statusMessage = "Connexion à Trakt impossible : \(error.localizedDescription)"
            showConnect = false
        }
    }

    /// Cancel from the QR page (Menu/back): stop polling and close.
    private func cancelConnect() {
        pollTask?.cancel()
        polling = false
        deviceCode = nil
        codeExpiresAt = nil
        showConnect = false
    }

    private func beginPolling(_ code: TraktDeviceCode) {
        polling = true
        pollTask?.cancel()
        pollTask = Task {
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while !Task.isCancelled && Date() < deadline {
                let result = await TraktService.pollToken(deviceCode: code.deviceCode, clientSecret: TraktStore.clientSecret)
                switch result {
                case .authorized(let access, let refresh):
                    trakt.markSignedInHere()
                    trakt.store(access: access, refresh: refresh)
                    let name = await TraktService.fetchUsername(accessToken: access)
                    trakt.setUsername(name)
                    polling = false
                    deviceCode = nil
                    codeExpiresAt = nil
                    showConnect = false
                    return
                case .needsSecret:
                    // No client secret configured yet — keep the QR page up and
                    // keep waiting instead of closing it. Wait the poll interval
                    // so we don't spin.
                    try? await Task.sleep(nanoseconds: UInt64(max(code.interval, 5)) * 1_000_000_000)
                case .expired:
                    // Code expired mid-poll: fetch a fresh one and keep going.
                    if !Task.isCancelled && showConnect { await loadCode() }
                    return
                case .failed(let message):
                    polling = false
                    deviceCode = nil
                    codeExpiresAt = nil
                    showConnect = false
                    statusMessage = message
                    return
                case .pending:
                    try? await Task.sleep(nanoseconds: UInt64(max(code.interval, 1)) * 1_000_000_000)
                }
            }
            // Deadline reached without a terminal result → auto-refresh the code
            // (a new one pops up) as long as the page is still open.
            if !Task.isCancelled && showConnect {
                await loadCode()
            }
        }
    }
}

/// A destructive text-pill matching the app's own design system (font,
/// focus ring, capsule fill) instead of tvOS's native bordered button chrome
/// — a bare `Button(role: .destructive)` renders with the system font/style,
/// which looks out of place next to the app's custom controls.
private struct DestructivePillLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isFocused ? .white : OrivioPrimitives.red300)
            .padding(.horizontal, OrivioSpacing.xl)
            .padding(.vertical, OrivioSpacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(isFocused ? OrivioPrimitives.red500 : OrivioPrimitives.red500.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .focusLift(OrivioFocus.card, isFocused)
    }
}

/// Full-screen Trakt device-code page: big centered QR + code + status, the
/// APK's dedicated login page. Menu/Back cancels (handled by the presenter).
struct TraktConnectPage: View {
    @EnvironmentObject private var theme: ThemeManager
    let code: TraktDeviceCode
    /// When the current code stops being valid — drives the countdown.
    let expiresAt: Date

    var body: some View {
        VStack(spacing: OrivioSpacing.xl) {
            VStack(spacing: OrivioSpacing.sm) {
                Text("Connecter Trakt")
                    .font(FusionType.pageTitle(theme.font))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Scannez le code avec votre téléphone, ou ouvrez \(code.verificationURL) puis saisissez le code ci-dessous.")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    // Without this the line TRUNCATES at 900pt instead of
                    // wrapping — the verification URL is interpolated, so how
                    // close it runs to the edge depends on the service.
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Scanning opens the Trakt authorize page with the code pre-filled.
            QRCodeView(string: "https://trakt.tv/activate/authorize?user_code=\(code.userCode)", side: 360)

            Text(code.userCode)
                .font(.system(size: 68, weight: .heavy, design: .monospaced))
                .tracking(10)
                .foregroundStyle(theme.palette.secondary)

            HStack(spacing: OrivioSpacing.sm) {
                ProgressView().tint(theme.palette.secondary)
                Text("En attente de votre autorisation…")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textTertiary)
            }

            // Live countdown; a new code is fetched automatically when it hits 0.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = expiresAt.timeIntervalSince(context.date)
                let remaining = seconds.isFinite ? Int(min(max(seconds, 0), 86_400)) : 0
                Text(remaining > 0
                     ? "Expiration du code dans \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                     : "Renouvellement du code…")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textTertiary)
            }

            Text("Retour pour annuler")
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textTertiary)
            // Nothing else here is focusable; without this Menu never reaches
            // the presenter's onExitCommand.
            FocusAnchor()
        }
        .padding(OrivioSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-screen SIMKL PIN page — the same shape as `TraktConnectPage`.
///
/// SIMKL's own verification URL is the bare `simkl.com/pin`, but the site also
/// accepts the code in the path, so the QR carries `/pin/<code>` and scanning
/// lands on the page with the code already filled in. The typed-in fallback
/// underneath is what the returned URL is for.
struct SimklConnectPage: View {
    @EnvironmentObject private var theme: ThemeManager
    let code: SimklDeviceCode
    let expiresAt: Date

    var body: some View {
        VStack(spacing: OrivioSpacing.xl) {
            VStack(spacing: OrivioSpacing.sm) {
                Text("Connecter SIMKL")
                    .font(FusionType.pageTitle(theme.font))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Scannez le code avec votre téléphone, ou ouvrez \(code.verificationURL) puis saisissez le code ci-dessous.")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    // Without this the line TRUNCATES at 900pt instead of
                    // wrapping — the verification URL is interpolated, so how
                    // close it runs to the edge depends on the service.
                    .fixedSize(horizontal: false, vertical: true)
            }

            QRCodeView(string: "https://simkl.com/pin/\(code.userCode)", side: 360)

            Text(code.userCode)
                .font(.system(size: 68, weight: .heavy, design: .monospaced))
                .tracking(10)
                .foregroundStyle(theme.palette.secondary)

            HStack(spacing: OrivioSpacing.sm) {
                ProgressView().tint(theme.palette.secondary)
                Text("En attente de votre autorisation…")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textTertiary)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = expiresAt.timeIntervalSince(context.date)
                let remaining = seconds.isFinite ? Int(min(max(seconds, 0), 86_400)) : 0
                Text(remaining > 0
                     ? "Expiration du code dans \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                     : "Renouvellement du code…")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textTertiary)
            }

            Text("Retour pour annuler")
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textTertiary)
            // Nothing else here is focusable; without this Menu never reaches
            // the presenter's onExitCommand.
            FocusAnchor()
        }
        .padding(OrivioSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
