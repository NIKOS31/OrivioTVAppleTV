import SwiftUI

/// Settings → Plugins: install scraper repositories (manifest URL), then toggle
/// individual scrapers. Runs the Orivio JS scrapers alongside Stremio addons on
/// the source page.
struct PluginsSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var plugins: PluginStore
    @State private var repoInput = ""

    var body: some View {
        DetailScaffold(title: SettingsCategory.plugins.title, subtitle: SettingsCategory.plugins.subtitle) {
            SettingsGroupCard(title: "Ajouter un dépôt", subtitle: "Coller le lien d’installation d’un dépôt") {
                HStack(spacing: OrivioSpacing.md) {
                    TextField("https://…/manifest.json", text: $repoInput)
                        .font(.system(size: 22))
                    Button {
                        let url = repoInput.trimmingCharacters(in: .whitespaces)
                        guard !url.isEmpty, !plugins.isBusy else { return }
                        // Guard re-entry here rather than with `.disabled`:
                        // disabling the button the user just pressed removes it
                        // from the tvOS focus tree mid-action and drops focus to
                        // an arbitrary row.
                        guard !plugins.isBusy else { return }
                        Task {
                            await plugins.addRepository(url)
                            if plugins.lastError == nil { repoInput = "" }
                        }
                    } label: {
                        if plugins.isBusy { ProgressView() } else { SeeAllLabel(text: "Ajouter") }
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .disabled(repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = plugins.lastError {
                    Text(error)
                        .font(.system(size: 18))
                        .foregroundStyle(OrivioPrimitives.error)
                }
                // Informational, NOT an error: some scraper bodies failed to
                // download and will be retried on the next stream search. This
                // used to ride in `lastError`, so a transient CDN hiccup during
                // a background account sync surfaced as a red failure.
                if let notice = plugins.lastNotice {
                    Text(notice)
                        .font(.system(size: 18))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Text("Les plugins compatibles utilisent des API JSON. L’analyse HTML et les extensions Android CloudStream ne sont pas encore prises en charge sur cette Apple TV.")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.palette.textTertiary)
            }

            if plugins.repositories.isEmpty {
                OrivioEmptyState(
                    icon: "puzzlepiece.extension",
                    title: "Aucun dépôt de plugins",
                    message: "Ajoutez un dépôt de plugins pour obtenir des sources supplémentaires."
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ForEach(plugins.repositories) { repo in
                    SettingsGroupCard(title: repo.name, subtitle: repo.url) {
                        SettingsToggleCard(
                            title: "Activer ce dépôt",
                            subtitle: "\(repo.scraperCount) scraper\(repo.scraperCount == 1 ? "" : "s")",
                            isOn: Binding(
                                get: { repo.enabled },
                                set: { plugins.setRepositoryEnabled($0, id: repo.id) }
                            )
                        )
                        ForEach(plugins.scrapers.filter { $0.repoID == repo.id }) { scraper in
                            SettingsToggleCard(
                                title: scraper.name,
                                subtitle: "v\(scraper.version) · \(scraper.supportedTypes.joined(separator: ", "))",
                                isOn: Binding(
                                    get: { scraper.enabled },
                                    set: { plugins.setScraperEnabled($0, id: scraper.id) }
                                )
                            )
                        }
                        Button { plugins.removeRepository(repo.id) } label: {
                            SettingsValueCard(title: "Supprimer ce dépôt", subtitle: "Supprimer ce dépôt et ses plugins", value: "", icon: "trash.fill")
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
            }
        }
    }
}
