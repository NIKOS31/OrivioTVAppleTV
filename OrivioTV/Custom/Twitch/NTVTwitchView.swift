import SwiftUI

struct NTVTwitchView: View {
    private let embedded: Bool
    private let onClose: (() -> Void)?

    init(embedded: Bool = false, onClose: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onClose = onClose
    }

    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var account: OrivioAccountManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = NTVTwitchViewModel()
    @State private var searching = false
    @State private var query = ""
    @State private var playing: NTVTwitchPlaybackTarget?
    @State private var preparedScope: String?
    private enum Focus: Hashable { case connect, cancel, followed, search, query, submit, stream(String), channel(String) }
    @State private var returnFocus: Focus?
    @FocusState private var focused: Focus?
    private var owner: String { account.currentUserID ?? "local" }
    private var scope: String { "\(owner).profile.\(profiles.activeProfileID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Twitch").font(.system(size: 42, weight: .semibold))
                        .accessibilityIdentifier("ntv.twitch.heading")
                    Text(model.identity.map { "Connecté à @\($0.login ?? "Twitch")" } ?? "Retrouvez vos chaînes suivies")
                        .font(.system(size: 22)).foregroundStyle(NTVDesign.textSecondary)
                }
                Spacer()
                if model.phase == .connected {
                    Button("Déconnecter") { model.disconnect() }
                        .buttonStyle(NTVActionButtonStyle())
                        .accessibilityIdentifier("ntv.twitch.disconnect")
                }
                if !embedded {
                    Button("Fermer") { close() }
                        .buttonStyle(NTVActionButtonStyle())
                        .accessibilityIdentifier("ntv.twitch.close")
                }
            }
            if let message = model.message {
                Text(message).font(.system(size: 22)).foregroundStyle(NTVDesign.textSecondary)
                    .accessibilityIdentifier("ntv.twitch.message")
            }
            switch model.phase {
            case .loading:
                ProgressView("Vérification de la connexion…")
                Spacer()
            case .failed:
                Button("Réessayer") { Task { await prepare() } }
                    .buttonStyle(NTVActionButtonStyle())
                Spacer()
            case .disconnected:
                Text("Connectez votre compte avec votre téléphone. Twitch vous demandera l’autorisation de consulter vos chaînes suivies.")
                    .font(.system(size: 25)).frame(maxWidth: 960, alignment: .leading)
                Button("Connecter Twitch") { model.connect() }
                    .buttonStyle(NTVActionButtonStyle())
                    .focused($focused, equals: .connect)
                    .accessibilityIdentifier("ntv.twitch.connect")
                Text("Les directs publics se lisent dans nTV. La lecture Twitch est expérimentale et peut être temporairement indisponible.")
                    .font(.system(size: 21)).foregroundStyle(NTVDesign.textSecondary)
                Spacer()
            case .authorizing:
                connectionCode
                Spacer()
            case .connected:
                browser
            }
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .padding(.horizontal, embedded ? NTVViewport.horizontalInset : 60)
        .padding(.vertical, embedded ? 20 : 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NTVDesign.background.ignoresSafeArea())
        .defaultFocus($focused, .connect)
        .task(id: scope) {
            if preparedScope != scope {
                await prepare()
                guard !Task.isCancelled else { return }
                preparedScope = scope
            } else { await model.resumeVisibleSession() }
            await model.monitorSession()
        }
        .onDisappear {
            if playing == nil { model.leave(); preparedScope = nil; returnFocus = nil }
        }
        .fullScreenCover(item: $playing) { target in
            NTVTwitchPlayer(target: target, scope: scope) { playing = nil }
        }
        .onChange(of: scope) { _, _ in returnFocus = nil; playing = nil; preparedScope = nil }
        .onChange(of: playing?.id) { old, new in
            if old != nil, new == nil, let returnFocus { focused = returnFocus }
        }
        .onExitCommand {
            if playing != nil { playing = nil }
            else if model.phase == .authorizing { model.cancelConnection() }
            else { close() }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .connected: focused = .followed
            case .disconnected: focused = .connect
            case .authorizing: focused = .cancel
            default: break
            }
        }
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    private func prepare() async {
        searching = false
        query = ""
        await model.prepare(profileID: profiles.activeProfileID, ownerScope: owner)
    }

    @ViewBuilder private var connectionCode: some View {
        if let ticket = model.ticket {
            HStack(alignment: .center, spacing: 48) {
                QRCodeView(string: ticket.code.verificationURI, side: 300)
                    .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("ntv.twitch.qr")
                VStack(alignment: .leading, spacing: 22) {
                    Text("Scannez avec votre téléphone").font(.system(size: 32, weight: .semibold))
                    Text("Ou ouvrez twitch.tv/activate et saisissez ce code :").font(.system(size: 23))
                    Text(ticket.code.userCode).font(.system(size: 40, weight: .bold, design: .monospaced))
                        .accessibilityIdentifier("ntv.twitch.code")
                    Text("Validez la connexion sur le site Twitch. Cet écran se mettra à jour automatiquement.")
                        .font(.system(size: 23)).foregroundStyle(NTVDesign.textSecondary)
                        .frame(maxWidth: 700, alignment: .leading)
                    Button("Annuler") { model.cancelConnection() }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($focused, equals: .cancel)
                        .accessibilityIdentifier("ntv.twitch.cancel")
                }
            }
        } else { ProgressView("Préparation du code…") }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Button("Chaînes suivies") { searching = false; model.loadFollowed() }
                    .focused($focused, equals: .followed)
                    .accessibilityIdentifier("ntv.twitch.followed")
                Button("Rechercher") { searching = true }
                    .focused($focused, equals: .search)
                    .accessibilityIdentifier("ntv.twitch.search")
                Spacer()
                Text("Directs publics · lecture expérimentale")
                    .font(.system(size: 19)).foregroundStyle(NTVDesign.textSecondary)
            }
            .buttonStyle(NTVActionButtonStyle())
            if searching {
                HStack(spacing: 20) {
                    TextField("Nom d’une chaîne en direct", text: $query)
                        .focused($focused, equals: .query)
                        .accessibilityIdentifier("ntv.twitch.query")
                        .onSubmit { model.search(query) }
                    Button("Chercher") { model.search(query) }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($focused, equals: .submit)
                        .accessibilityIdentifier("ntv.twitch.submit")
                }
            }
            if model.loadingPage { ProgressView("Chargement des chaînes…") }
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 410), spacing: 24)], spacing: 28) {
                    if searching {
                        ForEach(model.channels) { channel in
                            Button {
                                returnFocus = .channel(channel.id)
                                playing = .init(login: channel.broadcasterLogin, name: channel.displayName, title: channel.title)
                            } label: {
                                NTVTwitchCard(name: channel.displayName, title: channel.title,
                                    subtitle: channel.gameName, thumbnail: channel.thumbnailURL)
                            }
                                .buttonStyle(PlainCardButtonStyle())
                                .focused($focused, equals: .channel(channel.id))
                                .accessibilityIdentifier("ntv.twitch.channel.\(channel.id)")
                        }
                    } else {
                        ForEach(model.streams) { stream in
                            Button {
                                returnFocus = .stream(stream.id)
                                playing = .init(login: stream.userLogin, name: stream.userName, title: stream.title)
                            } label: {
                                NTVTwitchCard(name: stream.userName, title: stream.title,
                                    subtitle: "\(stream.gameName) · \(stream.viewerCount) spectateurs",
                                    thumbnail: stream.previewURL?.absoluteString ?? "")
                            }
                                .buttonStyle(PlainCardButtonStyle())
                                .focused($focused, equals: .stream(stream.id))
                                .accessibilityIdentifier("ntv.twitch.stream.\(stream.id)")
                        }
                    }
                }
                .padding(8)
                if !model.loadingPage, (searching ? model.channels.isEmpty : model.streams.isEmpty) {
                    Text(searching ? (query.isEmpty ? "Saisissez une recherche pour trouver une chaîne en direct." : "Aucune chaîne en direct ne correspond à cette recherche.") : "Aucune de vos chaînes suivies n’est en direct pour le moment.")
                        .font(.system(size: 23)).foregroundStyle(NTVDesign.textSecondary).padding(.vertical, 32)
                }
                if (searching ? model.searchCursor != nil : model.followedCursor != nil) {
                    Button("Afficher la suite") {
                        if searching { model.search(query, append: true) }
                        else { model.loadFollowed(append: true) }
                    }
                    .buttonStyle(NTVActionButtonStyle())
                    .disabled(model.loadingPage)
                }
            }
        }
    }
}

private struct NTVTwitchCard: View {
    @Environment(\.isFocused) private var focused
    let name: String
    let title: String
    let subtitle: String
    let thumbnail: String
    private var imageURL: String? {
        guard let url = URL(string: thumbnail), url.scheme == "https", url.user == nil, url.password == nil,
              ["static-cdn.jtvnw.net", "static-cdn.twitch.tv"].contains(url.host ?? "") else { return nil }
        return url.absoluteString
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: imageURL, maxDimension: 410)
                .frame(height: 210).clipped()
                .overlay(alignment: .topLeading) {
                    Text("EN DIRECT").font(.system(size: 15, weight: .bold))
                        .padding(8).background(.red, in: Capsule()).padding(12)
                }
            Text(name).font(.system(size: 24, weight: .semibold)).lineLimit(1)
            Text(title).font(.system(size: 20)).lineLimit(2)
            Text(subtitle).font(.system(size: 18)).foregroundStyle(NTVDesign.textSecondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTVDesign.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 3))
        .accessibilityElement(children: .combine)
    }
}
