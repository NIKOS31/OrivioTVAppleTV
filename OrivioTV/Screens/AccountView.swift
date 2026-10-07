import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: OrivioAccountManager
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var watched: WatchedStore
    @EnvironmentObject private var stremio: StremioAccountStore
    @EnvironmentObject private var trakt: TraktStore
    @EnvironmentObject private var debrid: DebridStore
    @EnvironmentObject private var plugins: PluginStore

    private enum AccountFocus: Hashable {
        case orivioSignIn
        case orivioEmailSignIn
        case stremioSignIn
        case stremioEmailSignIn
        case cancelOrivioSignIn
        case mergeSync
        case pullUpdates
        case pushDevice
        case stremioSync
        case stremioDisconnect
        case syncPanel
        case clearLog
        case exportBackup
        case importBackup
        case providerCheck
        case signOut
        case navOrivio
        case navStremio
        case navSync
        case navBackups
    }

    private enum AccountSection: CaseIterable {
        case orivio
        case stremio
        case sync
        case backups

        var title: String {
            switch self {
            case .orivio: return "Orivio"
            case .stremio: return "Stremio"
            case .sync: return "Synchronisation"
            case .backups: return "Sauvegardes"
            }
        }

        var subtitle: String {
            switch self {
            case .orivio: return "Connexion au compte"
            case .stremio: return "Stremio Link"
            case .sync: return "État et actions"
            case .backups: return "Sauvegarde locale"
            }
        }

        var icon: String {
            switch self {
            case .orivio: return "person.crop.circle"
            case .stremio: return "link.circle"
            case .sync: return "arrow.triangle.2.circlepath"
            case .backups: return "archivebox"
            }
        }

        var focus: AccountFocus {
            switch self {
            case .orivio: return .navOrivio
            case .stremio: return .navStremio
            case .sync: return .navSync
            case .backups: return .navBackups
            }
        }
    }

    @FocusState private var focusedControl: AccountFocus?
    // Email/password sign-in, the alternative to each service's QR flow. The
    // credentials live only for the length of the sheet — nothing is persisted
    // here; each manager keeps its own token once the exchange succeeds.
    @State private var showOrivioEmailSignIn = false
    @State private var orivioEmailField = ""
    @State private var orivioPasswordField = ""
    @State private var orivioEmailBusy = false
    @State private var showStremioEmailSignIn = false
    @State private var stremioEmailField = ""
    @State private var stremioPasswordField = ""
    @State private var stremioEmailBusy = false
    @State private var stremioEmailError: String?
    @State private var confirmClearHistory = false
    @State private var selectedSection: AccountSection = .orivio

    var body: some View {
        // Transparent background so the Settings workspace card shows through
        // (this pane is rendered inside that card).
        content
            .padding(.horizontal, OrivioSpacing.huge)
            .padding(.vertical, OrivioSpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onDisappear { stremioPollTask?.cancel() }
            .onChange(of: focusedControl, correctSkippedFocus)
            .fullScreenCover(isPresented: $showStremioConnect) {
                ZStack {
                    ATVBackground()
                    if let code = stremioLinkCode {
                        StremioConnectPage(code: code, status: stremioConnectStatus).id(code.code)
                    }
                }
                .environmentObject(theme)
                .onExitCommand { cancelStremioConnect() }
            }
            .fullScreenCover(isPresented: $showOrivioEmailSignIn) {
                EmailSignInView(
                    service: "Orivio",
                    email: $orivioEmailField,
                    password: $orivioPasswordField,
                    status: account.errorMessage,
                    isError: account.errorMessage != nil,
                    busy: orivioEmailBusy,
                    onSubmit: submitOrivioEmailSignIn,
                    onCancel: cancelOrivioEmailSignIn
                )
                .environmentObject(theme)
            }
            .fullScreenCover(isPresented: $showStremioEmailSignIn) {
                EmailSignInView(
                    service: "Stremio",
                    email: $stremioEmailField,
                    password: $stremioPasswordField,
                    status: stremioEmailError,
                    isError: stremioEmailError != nil,
                    busy: stremioEmailBusy,
                    onSubmit: submitStremioEmailSignIn,
                    onCancel: cancelStremioEmailSignIn
                )
                .environmentObject(theme)
            }
            .fullScreenCover(isPresented: $showBackupExport) {
                AccountBackupExportView(text: backupText, onDone: { showBackupExport = false })
                    .environmentObject(theme)
            }
            .fullScreenCover(isPresented: $showBackupImport) {
                AccountBackupImportView(
                    text: $backupImportText,
                    status: backupImportStatus,
                    importing: importingBackup,
                    onImport: importBackup,
                    onDone: { showBackupImport = false }
                )
                .environmentObject(theme)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch account.authState {
        case .loading:
            OrivioLoadingView(label: "Chargement du compte")
        case .signedIn(_, let email):
            accountShell(orivioEmail: email)
        case .signedOut:
            if let qr = account.qrLogin {
                qrLoginView(qr)
            } else {
                accountShell(orivioEmail: nil)
            }
        }
    }

    // MARK: - Account shell

    private func accountShell(orivioEmail: String?) -> some View {
        HStack(spacing: OrivioSpacing.xl) {
            accountNavigationRail(orivioEmail: orivioEmail)
                .frame(width: 360)

            accountDetailPane(orivioEmail: orivioEmail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncLog = OrivioSyncDiagnostics.entries()
            focusedControl = selectedSection.focus
        }
        .alert("Se déconnecter ?", isPresented: $confirmSignOut) {
            Button("Se déconnecter", role: .destructive) { account.signOut() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Votre progression, votre bibliothèque et vos addons restent sur cet appareil. Leur synchronisation reprendra à votre prochaine connexion.")
        }
    }

    private func accountNavigationRail(orivioEmail: String?) -> some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Comptes")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(accountRailSubtitle(orivioEmail: orivioEmail))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(.bottom, OrivioSpacing.md)

            ForEach(AccountSection.allCases, id: \.self) { section in
                AccountNavRow(
                    title: section.title,
                    subtitle: section.subtitle,
                    systemImage: section.icon,
                    selected: selectedSection == section,
                    action: {
                        selectedSection = section
                        focusedControl = section.focus
                    }
                )
                .focused($focusedControl, equals: section.focus)
            }

            Spacer(minLength: OrivioSpacing.md)

            VStack(alignment: .leading, spacing: 8) {
                AccountRailStatus(title: "Orivio", value: orivioEmail ?? "Non connecté", connected: orivioEmail != nil)
                AccountRailStatus(title: "Stremio", value: stremio.isSignedIn ? (stremio.email ?? "Connecté") : "Non connecté", connected: stremio.isSignedIn)
            }
        }
        .padding(OrivioSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrivioPrimitives.neutral750.opacity(0.65), lineWidth: 1)
        )
        .focusSection()
    }

    @ViewBuilder
    private func accountDetailPane(orivioEmail: String?) -> some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(selectedSection.title, systemImage: selectedSection.icon)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(detailSubtitle(orivioEmail: orivioEmail))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            switch selectedSection {
            case .orivio:
                orivioAccountDetail(orivioEmail: orivioEmail)
            case .stremio:
                stremioConnectionCard
            case .sync:
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                        syncActions
                        syncStatusPanel
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.bottom, OrivioSpacing.xxl)
                }
                .focusSection()
            case .backups:
                backupActions
            }
        }
        .padding(OrivioSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.background.opacity(0.24))
        )
        .focusSection()
    }

    private func accountRailSubtitle(orivioEmail: String?) -> String {
        switch (orivioEmail != nil, stremio.isSignedIn) {
        case (true, true): return "Comptes nTV et Stremio connectés"
        case (true, false): return "Compte nTV connecté"
        case (false, true): return "Stremio connecté"
        case (false, false): return "Aucun compte connecté"
        }
    }

    private func detailSubtitle(orivioEmail: String?) -> String {
        switch selectedSection {
        case .orivio:
            return orivioEmail == nil
                ? "Connectez votre compte avec le code QR ou votre adresse e-mail pour synchroniser cette Apple TV."
                : "Connecté avec \(orivioEmail ?? "votre compte")."
        case .stremio:
            return "Connectez Stremio par code QR ou par e-mail pour retrouver vos données dans nTV."
        case .sync:
            return "Synchronisez vos comptes et consultez leur état sur cette page."
        case .backups:
            return "Sauvegardez ou restaurez vos addons, plugins, bibliothèque et progression."
        }
    }

    private func orivioAccountDetail(orivioEmail: String?) -> some View {
        accountConnectionCard(
            title: "Orivio",
            subtitle: orivioEmail == nil
                ? "Synchronisez vos addons, profils, réglages, bibliothèque et progression avec votre compte."
                : "La synchronisation est automatique lorsque l’app est ouverte, en dehors de la lecture.",
            status: orivioEmail == nil ? "Non connecté" : "Connecté",
            icon: orivioEmail == nil ? "person.crop.circle.badge.plus" : "checkmark.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: OrivioSpacing.md) {
                if let orivioEmail {
                    Text(orivioEmail)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.palette.textPrimary)
                    AccountPrimaryButton(title: "Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", filled: false) {
                        confirmSignOut = true
                    }
                    .focused($focusedControl, equals: .signOut)
                } else {
                    AccountPrimaryButton(title: "Connexion par code QR", systemImage: "qrcode") {
                        account.startQRLogin()
                    }
                    .focused($focusedControl, equals: .orivioSignIn)

                    AccountPrimaryButton(title: "Connexion par e-mail", systemImage: "envelope", filled: false) {
                        beginOrivioEmailSignIn()
                    }
                    .focused($focusedControl, equals: .orivioEmailSignIn)

                    if let error = account.errorMessage {
                        errorLabel(error)
                    }
                }
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private var syncActions: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            AccountPrimaryButton(
                title: syncing ? "Synchronisation…" : "Synchroniser",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                runSyncAction(label: "Synchronisation") { sync in
                    await sync.syncNow()
                }
            }
            .focused($focusedControl, equals: .mergeSync)

            HStack(spacing: OrivioSpacing.md) {
                AccountPrimaryButton(title: "Récupérer les changements", systemImage: "arrow.down.circle", filled: false) {
                    runSyncAction(label: "Récupération des changements") { sync in
                        await sync.pullAccountUpdates()
                    }
                }
                .focused($focusedControl, equals: .pullUpdates)

                AccountPrimaryButton(title: "Envoyer les données de cette TV", systemImage: "arrow.up.circle", filled: false) {
                    runSyncAction(label: "Envoi des données de cette TV") { sync in
                        await sync.pushThisDevice()
                    }
                }
                .focused($focusedControl, equals: .pushDevice)
            }

            AccountPrimaryButton(title: "Effacer l’historique", systemImage: "trash", filled: false) {
                confirmClearHistory = true
            }
            .alert("Effacer l’historique ?", isPresented: $confirmClearHistory) {
                Button("Effacer sur tous les appareils", role: .destructive) {
                    runSyncAction(label: "Effacement de l’historique") { sync in
                        await sync.clearWatchHistoryEverywhere()
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Supprime l’historique et la progression sur cet appareil et votre compte, puis empêche Trakt de réimporter les anciennes lectures. Cette action est définitive.")
            }

            if let syncStatus {
                Text(syncStatus)
                    .font(.system(size: 20))
                    .foregroundStyle(syncStatus.hasPrefix("Sync failed")
                                     ? OrivioPrimitives.error : theme.palette.textTertiary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .padding(OrivioSpacing.xl)
        .frame(maxWidth: 980, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrivioPrimitives.neutral750.opacity(0.65), lineWidth: 1)
        )
        .focusSection()
    }

    private var backupActions: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            HStack(spacing: OrivioSpacing.md) {
                AccountPrimaryButton(title: "Exporter une sauvegarde", systemImage: "square.and.arrow.up", filled: false) {
                    backupText = OrivioLocalBackupService.exportBackup(
                        addonManager: addonManager,
                        plugins: plugins,
                        library: library,
                        progress: progress,
                        watched: watched
                    ) ?? ""
                    showBackupExport = true
                }
                .focused($focusedControl, equals: .exportBackup)

                AccountPrimaryButton(title: "Importer une sauvegarde", systemImage: "square.and.arrow.down", filled: false) {
                    backupImportText = ""
                    backupImportStatus = nil
                    showBackupImport = true
                }
                .focused($focusedControl, equals: .importBackup)
            }

            Text("Cette sauvegarde reste locale. Elle peut contenir des liens privés d’addons ou de listes de chaînes : ne la partagez pas avec d’autres personnes. Les mots de passe et sessions de connexion ne sont pas exportés.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(maxWidth: 780, alignment: .leading)
        }
        .padding(OrivioSpacing.xl)
        .frame(maxWidth: 980, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrivioPrimitives.neutral750.opacity(0.65), lineWidth: 1)
        )
        .focusSection()
    }

    private func accountConnectionCard<Controls: View>(
        title: String,
        subtitle: String,
        status: String,
        icon: String,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            HStack(alignment: .top, spacing: OrivioSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.palette.secondary)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: OrivioSpacing.sm) {
                        Text(title)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text(status)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.palette.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(theme.palette.background.opacity(0.65)))
                    }
                    Text(subtitle)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: OrivioSpacing.md)
            }

            controls()
                .padding(.leading, 62)
        }
        .padding(OrivioSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrivioPrimitives.neutral750.opacity(0.65), lineWidth: 1)
        )
    }

    private var stremioConnectionCard: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            HStack(alignment: .top, spacing: OrivioSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(theme.palette.secondary.opacity(0.18))
                    Image(systemName: stremio.isSignedIn ? "link.circle.fill" : "link.badge.plus")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(theme.palette.secondary)
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: OrivioSpacing.sm) {
                        Text("Stremio")
                            .font(.system(size: 31, weight: .heavy))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text(stremio.isSignedIn ? "Connecté" : "Facultatif")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(stremio.isSignedIn ? OrivioPrimitives.success : theme.palette.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((stremio.isSignedIn ? OrivioPrimitives.success : theme.palette.textTertiary).opacity(0.16))
                            )
                    }

                    Text(stremio.isSignedIn ? (stremio.email ?? "Compte Stremio connecté") : "Connectez Stremio par code QR pour retrouver vos addons, votre bibliothèque et votre progression.")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: OrivioSpacing.md)
            }

            HStack(spacing: OrivioSpacing.sm) {
                AccountMetricPill(title: "Addons", value: "\(addonManager.addons.count)", systemImage: "puzzlepiece.extension")
                AccountMetricPill(title: "Bibliothèque", value: "\(library.items.count)", systemImage: "bookmark")
                AccountMetricPill(title: "À reprendre", value: "\(progress.continueWatching.count)", systemImage: "play.rectangle")
                AccountMetricPill(title: "Vu", value: "\(watched.items.count)", systemImage: "checkmark.seal")
            }

            VStack(alignment: .leading, spacing: OrivioSpacing.sm) {
                HStack(spacing: OrivioSpacing.md) {
                    if stremio.isSignedIn {
                        AccountPrimaryButton(
                            title: stremio.isSyncing ? "Synchronisation…" : "Synchroniser Stremio",
                            systemImage: "arrow.triangle.2.circlepath",
                            filled: false
                        ) {
                            syncStremioNow()
                        }
                        .focused($focusedControl, equals: .stremioSync)

                        AccountPrimaryButton(title: "Déconnecter", systemImage: "xmark.circle", filled: false) {
                            stremio.signOut()
                            focusedControl = .stremioSignIn
                        }
                        .focused($focusedControl, equals: .stremioDisconnect)
                    } else {
                        AccountPrimaryButton(title: "Connexion par code QR", systemImage: "qrcode", filled: false) {
                            startStremioLogin()
                        }
                        .focused($focusedControl, equals: .stremioSignIn)

                        AccountPrimaryButton(title: "Connexion par e-mail", systemImage: "envelope", filled: false) {
                            beginStremioEmailSignIn()
                        }
                        .focused($focusedControl, equals: .stremioEmailSignIn)
                    }
                }

                if let status = stremioStatus ?? stremio.lastSyncStatus {
                    Text(status)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(status.hasPrefix("Couldn't") ? OrivioPrimitives.error : theme.palette.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(OrivioSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(stremio.isSignedIn ? OrivioPrimitives.success.opacity(0.45) : OrivioPrimitives.neutral750.opacity(0.65), lineWidth: 1)
        )
        .focusSection()
    }

    private func qrLoginView(_ qr: QRLoginState) -> some View {
        HStack(spacing: OrivioSpacing.huge) {
            QRCodeView(string: qr.webURL, side: 360)

            VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                Text("Scanner pour se connecter")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)

                stepRow(1, "Scannez le code QR avec votre téléphone")
                stepRow(2, "Connectez-vous sur la page qui s’ouvre")
                stepRow(3, "Cette TV se connectera automatiquement")

                Text(qr.webURL)
                    .font(.system(size: 19, weight: .medium).monospaced())
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520, alignment: .leading)

                HStack(spacing: OrivioSpacing.md) {
                    ProgressView().tint(theme.palette.secondary)
                    Text(qr.statusText)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .padding(.top, OrivioSpacing.sm)

                if let error = account.errorMessage {
                    errorLabel(error)
                }

                AccountPrimaryButton(title: "Annuler", systemImage: "xmark", filled: false) {
                    account.cancelQRLogin()
                }
                .focused($focusedControl, equals: .cancelOrivioSignIn)
                .padding(.top, OrivioSpacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .onAppear { focusedControl = .cancelOrivioSignIn }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: OrivioSpacing.md) {
            Text("\(number)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.palette.onSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.palette.secondary))
            Text(text)
                .font(.system(size: 24))
                .foregroundStyle(theme.palette.textPrimary)
        }
    }

    @State private var confirmSignOut = false
    @State private var syncing = false
    @State private var syncStatus: String?
    @State private var syncLog: [OrivioSyncLogEntry] = []
    @State private var providerStatus: String?
    @State private var checkingProviders = false
    @State private var showBackupExport = false
    @State private var showBackupImport = false
    @State private var backupText = ""
    @State private var backupImportText = ""
    @State private var backupImportStatus: String?
    @State private var importingBackup = false
    @State private var showStremioConnect = false
    @State private var stremioLinkCode: StremioLinkCode?
    @State private var stremioPollTask: Task<Void, Never>?
    @State private var stremioConnectStatus = "Préparation de la connexion…"
    @State private var stremioStatus: String?
    private var sync: OrivioSyncManager? { OrivioSyncManager.shared }

    private var syncStatusPanel: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            HStack {
                Label("État de la synchronisation", systemImage: "checklist.checked")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer()
                Text(sync?.isSyncing == true ? "En cours" : "En attente")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(sync?.isSyncing == true ? theme.palette.secondary : theme.palette.textTertiary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OrivioSpacing.md), count: 2), spacing: OrivioSpacing.md) {
                AccountSyncStatusRow(title: "Profil", value: activeProfileName, systemImage: "person.crop.circle")
                AccountSyncStatusRow(title: "Addons", value: "\(addonManager.addons.count) installés", systemImage: "puzzlepiece.extension")
                AccountSyncStatusRow(title: "Bibliothèque", value: "\(library.items.count) saved", systemImage: "bookmark")
                AccountSyncStatusRow(title: "Continuer à regarder", value: "\(progress.continueWatching.count) en cours", systemImage: "play.rectangle")
                AccountSyncStatusRow(title: "Vu", value: "\(watched.items.count) marked", systemImage: "checkmark.seal")
                AccountSyncStatusRow(title: "Stremio", value: stremio.isSignedIn ? (stremio.email ?? "Connecté") : "Non connecté", systemImage: "link")
                AccountSyncStatusRow(title: "Trakt", value: trakt.isSignedIn ? (trakt.username ?? "Connecté") : "Non connecté", systemImage: "checkmark.seal.fill")
                AccountSyncStatusRow(title: "Debrid", value: debridProvidersLabel, systemImage: "key")
                AccountSyncStatusRow(title: "Plugins", value: "\(plugins.repositories.count) dépôts, \(plugins.enabledScrapers.count) actifs", systemImage: "shippingbox")
                AccountSyncStatusRow(title: "Actions en attente", value: pendingQueueLabel, systemImage: "tray.and.arrow.up")
                AccountSyncStatusRow(title: "Dernière erreur", value: sync?.lastSyncError ?? "Aucun", systemImage: "exclamationmark.triangle")
            }

            if !syncLog.isEmpty {
                VStack(alignment: .leading, spacing: OrivioSpacing.sm) {
                    HStack {
                        Text("Événements récents")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer()
                        AccountMiniButton(title: "Effacer", systemImage: "trash") {
                            OrivioSyncDiagnostics.clear()
                            syncLog = []
                            focusedControl = .syncPanel
                        }
                        .focused($focusedControl, equals: .clearLog)
                    }

                    ForEach(syncLog.prefix(6)) { entry in
                        AccountSyncLogRow(entry: entry)
                    }
                }
                .padding(.top, OrivioSpacing.sm)
            }

            Button {
                Task { await runProviderCheck() }
            } label: {
                SettingsActionRow(
                    title: checkingProviders ? "Vérification des fournisseurs" : "Vérifier les fournisseurs",
                    subtitle: providerStatus ?? "Vérifier les addons, plugins, Trakt et services de débridage",
                    leadingIcon: "waveform.path.ecg"
                )
            }
            .buttonStyle(PlainCardButtonStyle())
            .focused($focusedControl, equals: .providerCheck)
        }
        .padding(OrivioSpacing.xl)
        .frame(maxWidth: 980)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    focusedControl == .syncPanel ? theme.palette.focusRing : OrivioPrimitives.neutral750.opacity(0.65),
                    lineWidth: focusedControl == .syncPanel ? 3 : 1
                )
        )
        .focusable()
        .focused($focusedControl, equals: .syncPanel)
        .focusSection()
    }

    private var activeProfileName: String {
        profiles.profiles.first { $0.id == profiles.activeProfileID }?.name ?? "Profil \(profiles.activeProfileID)"
    }

    private var debridProvidersLabel: String {
        let providers = debrid.configuredProviders.map(\.displayName)
        return providers.isEmpty ? "Aucun configuré" : providers.joined(separator: ", ")
    }

    private var pendingQueueLabel: String {
        guard let counts = sync?.pendingSyncCounts else { return "Indisponible" }
        guard counts.total > 0 else { return "Vide" }
        return "\(counts.progressDeletes) progressions, \(counts.libraryDeletes) titres enregistrés, \(counts.watchedDeletes) titres vus"
    }

    private func correctSkippedFocus(_ oldFocus: AccountFocus?, _ newFocus: AccountFocus?) {
        guard let newFocus else { return }
        if let section = railSection(for: newFocus), selectedSection != section {
            selectedSection = section
        }
    }

    private func railSection(for focus: AccountFocus?) -> AccountSection? {
        switch focus {
        case .navOrivio: return .orivio
        case .navStremio: return .stremio
        case .navSync: return .sync
        case .navBackups: return .backups
        default: return nil
        }
    }

    private func startStremioLogin() {
        let generation = stremio.beginAuthentication()
        stremioStatus = nil
        stremioConnectStatus = "Préparation de la connexion…"
        showStremioConnect = true
        Task { await loadStremioCode(generation: generation) }
    }

    private func loadStremioCode(generation: Int) async {
        do {
            let code = try await StremioAccountService.createLink()
            guard !Task.isCancelled, showStremioConnect, generation == stremio.sessionGeneration else { return }
            stremioLinkCode = code
            stremioConnectStatus = "En attente de votre autorisation…"
            beginStremioPolling(code, generation: generation)
        } catch {
            guard generation == stremio.sessionGeneration, showStremioConnect else { return }
            stremioStatus = "Impossible de démarrer la connexion à Stremio."
            showStremioConnect = false
        }
    }

    private func beginStremioPolling(_ code: StremioLinkCode, generation: Int) {
        stremioPollTask?.cancel()
        stremioPollTask = Task {
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled && Date() < deadline {
                let result = await StremioAccountService.readLink(code: code.code)
                guard !Task.isCancelled, showStremioConnect, generation == stremio.sessionGeneration else { return }
                switch result {
                case .pending:
                    stremioConnectStatus = "En attente de votre autorisation…"
                case .authorized(let authKey):
                    stremioConnectStatus = "Connexion autorisée. Synchronisation du compte…"
                    let user = await StremioAccountService.getUser(authKey: authKey)
                    guard !Task.isCancelled, showStremioConnect,
                          stremio.signIn(authKey: authKey, user: user, expectedGeneration: generation) else { return }
                    stremioLinkCode = nil
                    showStremioConnect = false
                    syncStremioNow()
                    focusedControl = .stremioSync
                    return
                case .failed(let message):
                    stremioStatus = message
                    stremioConnectStatus = message
                    stremioLinkCode = nil
                    showStremioConnect = false
                    focusedControl = .stremioSignIn
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            if !Task.isCancelled && showStremioConnect && generation == stremio.sessionGeneration {
                await loadStremioCode(generation: generation)
            }
        }
    }

    // MARK: - Email sign-in

    private func beginOrivioEmailSignIn() {
        orivioPasswordField = ""
        orivioEmailBusy = false
        account.errorMessage = nil
        showOrivioEmailSignIn = true
    }

    private func cancelOrivioEmailSignIn() {
        guard !orivioEmailBusy else { return }
        showOrivioEmailSignIn = false
        orivioPasswordField = ""
        account.errorMessage = nil
        focusedControl = .orivioEmailSignIn
    }

    private func submitOrivioEmailSignIn() {
        guard !orivioEmailBusy else { return }
        orivioEmailBusy = true
        Task {
            await account.signIn(email: orivioEmailField, password: orivioPasswordField)
            orivioEmailBusy = false
            // The manager reports failures through `errorMessage`; on success
            // it flips authState, which swaps this whole pane for the signed-in
            // shell. Only close the sheet when it actually worked, so a wrong
            // password leaves the form up with the reason on it.
            if account.authState.isSignedIn {
                showOrivioEmailSignIn = false
                orivioPasswordField = ""
            }
        }
    }

    private func beginStremioEmailSignIn() {
        stremio.cancelAuthentication()
        stremioPollTask?.cancel()
        stremioPasswordField = ""
        stremioEmailError = nil
        stremioEmailBusy = false
        showStremioEmailSignIn = true
    }

    private func cancelStremioEmailSignIn() {
        stremio.cancelAuthentication()
        stremioEmailBusy = false
        showStremioEmailSignIn = false
        stremioPasswordField = ""
        stremioEmailError = nil
        focusedControl = .stremioEmailSignIn
    }

    private func submitStremioEmailSignIn() {
        guard !stremioEmailBusy else { return }
        let generation = stremio.beginAuthentication()
        stremioEmailBusy = true
        stremioEmailError = nil
        Task {
            do {
                let result = try await StremioAccountService.login(email: stremioEmailField,
                                                                   password: stremioPasswordField)
                guard !Task.isCancelled, showStremioEmailSignIn,
                      stremio.signIn(authKey: result.authKey, user: result.user, expectedGeneration: generation) else { return }
                stremioPasswordField = ""
                stremioEmailBusy = false
                showStremioEmailSignIn = false
                // Same landing as the QR flow: pull the account straight away
                // so the panel shows real numbers instead of an empty shell.
                syncStremioNow()
                focusedControl = .stremioSync
            } catch {
                guard generation == stremio.sessionGeneration, showStremioEmailSignIn else { return }
                stremioEmailBusy = false
                stremioEmailError = (error as? LocalizedError)?.errorDescription
                    ?? "Connexion à Stremio impossible."
            }
        }
    }

    private func cancelStremioConnect() {
        stremio.cancelAuthentication()
        stremioPollTask?.cancel()
        stremioLinkCode = nil
        showStremioConnect = false
        focusedControl = .stremioSignIn
    }

    private func syncStremioNow() {
        if let manager = StremioSyncManager.shared {
            manager.syncNow(reason: "Synchronisation manuelle de Stremio")
            focusedControl = .stremioSync
            return
        }

        guard let key = stremio.authKey else { return }
        let generation = stremio.sessionGeneration
        stremio.setSyncing(true)
        stremio.setStatus("Synchronisation…")
        Task {
            let result = await StremioSync.pull(
                authKey: key,
                addonManager: addonManager,
                library: library,
                progress: progress,
                watched: watched,
                isCurrent: { stremio.sessionGeneration == generation && stremio.authKey == key }
            )
            guard !Task.isCancelled, generation == stremio.sessionGeneration, stremio.authKey == key else { return }
            stremio.setStatus(result)
            stremio.setSyncing(false)
            focusedControl = .stremioSync
        }
    }

    private func runProviderCheck() async {
        guard !checkingProviders else { return }
        focusedControl = .providerCheck
        checkingProviders = true
        defer {
            checkingProviders = false
            focusedControl = .providerCheck
        }

        let addonResults = await addonManager.healthCheck()
        let addonFailures = addonResults.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        let addonSlow = addonResults.filter { $0.status == .slow }.count

        let pluginFailures = await pluginManifestFailures()
        let traktStatus = trakt.isSignedIn ? "Trakt connecté" : "Trakt désactivé"
        let debridStatus = debrid.configuredProviders.isEmpty
            ? "no debrid"
            : "\(debrid.configuredProviders.count) debrid"

        providerStatus = "\(addonFailures) addon failed, \(addonSlow) slow · \(pluginFailures) plugin repo failed · \(traktStatus) · \(debridStatus)"
        OrivioSyncDiagnostics.record(.info, area: "Health", providerStatus ?? "Vérification des fournisseurs terminée.")
        syncLog = OrivioSyncDiagnostics.entries()
    }

    private func runSyncAction(label: String, action: @escaping (OrivioSyncManager) async -> Void) {
        guard !syncing, let sync else { return }
        syncing = true
        syncStatus = nil
        Task {
            await action(sync)
            syncing = false
            syncStatus = sync.lastSyncError.map { "\(label) failed: \($0)" }
                ?? "\(label) finished"
            syncLog = OrivioSyncDiagnostics.entries()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            syncStatus = nil
        }
    }

    private func pluginManifestFailures() async -> Int {
        var failures = 0
        for repo in plugins.repositories where repo.enabled {
            guard let url = URL(string: repo.url) else {
                failures += 1
                continue
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if !(200..<300).contains(code) { failures += 1 }
            } catch {
                failures += 1
            }
        }
        return failures
    }

    private func importBackup() {
        guard !importingBackup else { return }
        importingBackup = true
        backupImportStatus = "Importation…"
        Task {
            let result = await OrivioLocalBackupService.importBackup(
                backupImportText,
                addonManager: addonManager,
                plugins: plugins,
                library: library,
                progress: progress,
                watched: watched
            )
            backupImportStatus = result
            importingBackup = false
        }
    }

    private func errorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(OrivioPrimitives.error)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
    }
}

private struct AccountNavRow: View {
    @ObservedObject private var perf = PerformanceSettingsStore.shared
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let subtitle: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    private var navBackground: Color {
        if isFocused { return theme.palette.focusBackground.opacity(0.55) }
        if selected { return theme.palette.secondary.opacity(0.08) }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: OrivioSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected || isFocused ? theme.palette.secondary : theme.palette.textTertiary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, OrivioSpacing.lg)
        .padding(.trailing, OrivioSpacing.md)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: OrivioRadius.md, style: .continuous)
                .fill(navBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OrivioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing.opacity(0.75) : .clear, lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            if selected || isFocused {
                Capsule(style: .continuous)
                    .fill(theme.palette.secondary.opacity(isFocused ? 0.9 : 0.5))
                    .frame(width: 3, height: 30)
                    .padding(.leading, 6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: OrivioRadius.md, style: .continuous))
        .focusable(true, interactions: .activate)
        .focusEffectDisabled()
        .onTapGesture(perform: action)
        .animation(perf.motion(FusionFocus.liftAnimation), value: isFocused)
        .animation(perf.motion(FusionMotion.focusMove), value: selected)
    }
}

private struct AccountRailStatus: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? OrivioPrimitives.success : theme.palette.textTertiary.opacity(0.65))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.palette.textTertiary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct AccountMiniButton: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isFocused ? theme.palette.focusBackground : theme.palette.background.opacity(0.52))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 2)
                )
                .focusLift(OrivioFocus.card, isFocused)
        }
        .buttonStyle(.plain)
    }
}

private struct AccountMetricPill: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.palette.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(theme.palette.textPrimary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(theme.palette.background.opacity(0.46))
        )
    }
}

private struct AccountSyncStatusRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: OrivioSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.palette.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.palette.textTertiary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OrivioSpacing.md)
        .padding(.vertical, OrivioSpacing.sm)
        .frame(height: 74)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.palette.background.opacity(0.42))
        )
    }
}

private struct AccountSyncLogRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let entry: OrivioSyncLogEntry

    var body: some View {
        HStack(spacing: OrivioSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(entry.timeLabel)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.palette.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(entry.area)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.palette.secondary)
                .frame(width: 90, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OrivioSpacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.palette.background.opacity(0.32))
        )
    }

    private var icon: String {
        switch entry.level {
        case .info: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: return theme.palette.textTertiary
        case .success: return OrivioPrimitives.success
        case .warning: return theme.palette.secondary
        case .failure: return OrivioPrimitives.error
        }
    }
}

private struct AccountBackupExportView: View {
    @EnvironmentObject private var theme: ThemeManager
    let text: String
    let onDone: () -> Void

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                Text("Sauvegarde locale")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("\(text.count) caractères · peut contenir des liens privés, à conserver pour vous")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)

                ScrollView {
                    Text(text.isEmpty ? "Sauvegarde indisponible." : text)
                        .font(.system(size: 17, weight: .medium).monospaced())
                        .foregroundStyle(theme.palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OrivioSpacing.lg)
                }
                .frame(maxHeight: 560)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.palette.backgroundElevated)
                )

                HStack(spacing: OrivioSpacing.md) {
                    Button("Terminé", action: onDone)
                }
                .font(.system(size: 24, weight: .bold))
            }
            .padding(OrivioSpacing.huge)
        }
        .onExitCommand(perform: onDone)
    }
}

private struct AccountBackupImportView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var text: String
    let status: String?
    let importing: Bool
    let onImport: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            ATVBackground()
            VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                Text("Importer une sauvegarde")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)

                TextField("Collez votre sauvegarde JSON", text: $text, axis: .vertical)
                    .font(.system(size: 20, weight: .medium).monospaced())
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(OrivioSpacing.md)
                    .frame(height: 520)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.palette.backgroundElevated)
                    )

                if let status {
                    Text(status)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(status.hasPrefix("Couldn't") ? OrivioPrimitives.error : theme.palette.textSecondary)
                }

                HStack(spacing: OrivioSpacing.md) {
                    Button(importing ? "Importation…" : "Importer", action: onImport)
                        // Stays enabled while importing (disabling the focused
                        // button drops focus); importBackup() guards re-entry.
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Terminé", action: onDone)
                }
                .font(.system(size: 24, weight: .bold))
            }
            .padding(OrivioSpacing.huge)
        }
        .onExitCommand(perform: onDone)
    }
}

/// Focusable pill button matching the app's focus visuals.
/// Internal, not private: `EmailSignInView` is a separate file and uses the
/// same pill so the sign-in page matches the panels it is opened from.
struct AccountPrimaryButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let systemImage: String
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AccountButtonLabel(title: title, systemImage: systemImage, filled: filled)
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

struct AccountButtonLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused

    let title: String
    let systemImage: String
    let filled: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(filled ? theme.palette.onSecondary : theme.palette.textPrimary)
            .padding(.horizontal, OrivioSpacing.xxl)
            .padding(.vertical, OrivioSpacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3)
            )
            .focusLift(OrivioFocus.card, isFocused)
    }

    private var background: Color {
        if filled {
            return isFocused ? theme.palette.secondary : theme.palette.secondary.opacity(0.8)
        }
        return isFocused ? theme.palette.focusBackground : .white.opacity(0.12)
    }
}
