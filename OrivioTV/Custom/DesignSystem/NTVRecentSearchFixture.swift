#if DEBUG
import Foundation

@MainActor
enum NTVRecentSearchFixture {
    static let store: NTVRecentSearches = {
        // A dedicated test domain: never clear or seed the viewer's history.
        let suite = "ntv.ui.recent-searches.fixture"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Search fixture unavailable") }
        defaults.removePersistentDomain(forName: suite)
        let store = NTVRecentSearches(defaults: defaults)
        store.record("Silo")
        store.record("Dune")
        return store
    }()
}
#endif
