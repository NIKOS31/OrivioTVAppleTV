import Foundation

/// Hands focus from the rail into a specific spot in the content — the FIRST
/// tile of the row the viewer was last in — instead of letting the focus
/// engine pick "the nearest candidate" when the rail's focus is dropped.
///
/// Dropping focus with no destination is how the engine ended up on the
/// fourth card of a row: the expanded panel overlaps the first two, so the
/// nearest candidate to the rail's centre was a card three along. Rows
/// register a "take focus at your start" handler while they are mounted and
/// note when they hold focus; the rail asks the last such row to take it back.
@MainActor
final class ContentFocusRouter {
    static let shared = ContentFocusRouter()

    /// Each mounted row's hand-off, keyed by row id. Returns true when the row
    /// took focus.
    private var handlers: [String: () -> Bool] = [:]
    /// The row that last held focus in the content.
    private(set) var lastRowID: String?
    private var landingTask: Task<Void, Never>?
    private var landingRowID: String?
    private var landingGeneration: UUID?
    private(set) var interactionGeneration: UInt64 = 0
    /// A view can be mounted again with the same task ID. The request lives
    /// here, outside that view's lifecycle, and can be claimed only once.
    enum EntryKind: Equatable { case rowStart, restoration }
    struct EntryRequest: Equatable {
        fileprivate let id = UUID()
        fileprivate let rowID: String
        fileprivate let sequence: UInt64
        fileprivate let kind: EntryKind
    }
    private var pendingEntry: EntryRequest?
    private var entrySequence: UInt64 = 0
    private var landingSequence: UInt64 = 0

    var hasCatalogRowFocus: Bool {
        lastRowID?.hasPrefix("ntv.catalog.shelf.") == true
    }

    var hasPendingRestoration: Bool { pendingEntry?.kind == .restoration }

    func isLanding(in rowID: String) -> Bool {
        landingRowID == rowID && landingGeneration != nil
    }

    func makeEntryRequest(in rowID: String, kind: EntryKind = .rowStart) -> EntryRequest {
        cancelLanding()
        entrySequence &+= 1
        let request = EntryRequest(rowID: rowID, sequence: entrySequence, kind: kind)
        pendingEntry = request
        AppProbe.focus("entry #\(request.sequence) scheduled")
        return request
    }

    func isPendingEntry(_ request: EntryRequest?) -> Bool {
        guard let request else { return false }
        return pendingEntry == request
    }

    func consumeEntry(_ request: EntryRequest) -> Bool {
        guard pendingEntry == request else {
            AppProbe.focus("entry #\(request.sequence) discarded")
            PlayerProbe.count("focus.entry.discarded")
            return false
        }
        pendingEntry = nil
        AppProbe.focus("entry #\(request.sequence) claimed")
        return true
    }

    func cancelEntry(_ request: EntryRequest?) {
        guard let request, pendingEntry == request else { return }
        pendingEntry = nil
        AppProbe.focus("entry #\(request.sequence) cancelled")
    }

    /// A fresh remote command or page/menu transition supersedes restoration
    /// too, including a task still waiting for a navigation pop to settle.
    func noteUserMovement(in rowID: String? = nil) {
        interactionGeneration &+= 1
        // onMoveCommand may arrive after UIKit has already entered another
        // row for this same gesture. The departing row must not cancel the
        // destination's newly issued correction.
        if rowID == nil || landingRowID == rowID || pendingEntry?.rowID == rowID || hasPendingRestoration { cancelLanding() }
    }

    /// Normalize an actual entry from another catalog row, never an ordinary
    /// horizontal/diagonal step or a return to a remembered detail selection.
    static func startsCatalogRow(previousItem _: String?, previousRow: String?,
                                 currentRow: String, restorationItem: String?) -> Bool {
        // SwiftUI can retain the row-local focus value across a re-entry.
        // The last row that actually received focus identifies the crossing;
        // a non-nil local old value must not turn it into a horizontal step.
        restorationItem == nil && previousRow != currentRow &&
            previousRow?.hasPrefix("ntv.catalog.shelf.") == true &&
            currentRow.hasPrefix("ntv.catalog.shelf.")
    }

    func register(_ rowID: String, handler: @escaping () -> Bool) {
        handlers[rowID] = handler
        AppProbe.focus("row registered: \(rowID)  (\(handlers.count) mounted)")
    }

    func unregister(_ rowID: String) {
        if landingRowID == rowID || pendingEntry?.rowID == rowID { cancelLanding() }
        handlers.removeValue(forKey: rowID)
        AppProbe.focus("row gone: \(rowID)  (\(handlers.count) mounted)"
                       + (lastRowID == rowID ? "  — and it was the last focused one" : ""))
    }

    /// A tile in `rowID` just took focus. Rows that carry no hand-off handler
    /// still call this (the Live Channels strip, the poster grids): it makes
    /// the record honest, so leaving the rail falls back to the engine's own
    /// pick instead of teleporting to the last ROUTED row the viewer was in —
    /// possibly several rows away.
    func noteFocused(row rowID: String) {
        // A delayed retry belongs to one row. Once focus is in another row,
        // it must not scroll the previous row and reclaim focus behind us.
        if let landingRowID, landingRowID != rowID { cancelLanding() }
        if let pendingEntry, pendingEntry.rowID != rowID,
           pendingEntry.kind != .restoration || !rowID.hasPrefix("ntv.catalog.shelf.") { cancelLanding() }
        // During a navigation pop UIKit can briefly choose a nearby shelf
        // before the remembered poster mounts. That automatic fallback alone
        // does not cancel restoration; a real move command in ANY row does.
        // Only the CHANGES: a row notes itself on every tile the viewer moves
        // to, and a tail of "still in row 3" forty times over is noise that
        // pushes the useful lines out of the ring.
        if lastRowID != rowID {
            PlayerProbe.count("focus.row.changed")
            AppProbe.focus("content focus: \(lastRowID ?? "—") → \(rowID)"
                           + (handlers[rowID] == nil ? "  (no hand-off handler)" : ""))
        }
        lastRowID = rowID
    }

    /// Ask the last-focused row to focus its first tile. False when no such
    /// row is mounted (another tab, a pushed screen, an unrouted row) — the
    /// caller then falls back to letting the engine choose.
    func focusLastRowStart() -> Bool {
        focusRowStart(lastRowID)
    }

    /// `focusLastRowStart` for a row recorded earlier — the rail's Right exit
    /// reads the row before the engine's own landing can note another one.
    func focusRowStart(_ rowID: String?) -> Bool {
        cancelLanding()
        guard let id = rowID, let handler = handlers[id] else {
            // The fallback that historically dropped focus on the wrong card:
            // worth seeing every time it happens, with the reason.
            AppProbe.focus("hand-off DECLINED — "
                           + (rowID == nil ? "no row has held focus"
                                           : "row \(rowID!) is not mounted")
                           + "; the engine will pick")
            return false
        }
        let took = handler()
        AppProbe.focus("hand-off to \(id) — \(took ? "taken" : "REFUSED by the row")")
        return took
    }

    /// Keep assigning `assign()` until `landed()` reads true — the first
    /// card of a lazily-stacked row may take several ticks to exist after
    /// `scrollTo`, and a single deferred retry lost the race on the slower
    /// boxes (focus then fell to whatever the engine picked mid-scroll).
    ///
    /// `focusToken` (the row's current focused id) lets the loop tell a
    /// mid-scroll ENGINE pick — which it exists to correct — from the VIEWER
    /// having moved on: focus resting on the same non-target tile two ticks
    /// running means someone chose it, and re-assigning would yank them back
    /// to card 1 and snap the platter raise mid-move (up to six times over
    /// 360ms — one face of the "frozen poster" fight).
    func land(in rowID: String, assign: @escaping () -> Void,
                     landed: @escaping () -> Bool,
                     focusToken: (() -> String?)? = nil) {
        cancelLanding()
        let generation = UUID()
        landingSequence &+= 1
        let sequence = landingSequence
        landingGeneration = generation
        landingRowID = rowID
        // Only local sequence numbers and fixed labels in these diagnostics:
        // no title, media identifier, addon configuration or URL.
        AppProbe.focus("landing #\(sequence) started")
        PlayerProbe.count("focus.landing.started")
        PlayerProbe.count("focus.landing.assignment")
        assign()
        guard landingGeneration == generation else { return }
        landingTask = Task { @MainActor [weak self] in
            defer {
                if self?.landingGeneration == generation {
                    self?.landingTask = nil
                    self?.landingRowID = nil
                    self?.landingGeneration = nil
                }
            }
            var previous: String?
            for attempt in 1...6 {
                do { try await Task.sleep(nanoseconds: 60_000_000) } catch { return }
                guard !Task.isCancelled, self?.landingGeneration == generation else { return }
                if landed() {
                    AppProbe.focus("landing #\(sequence) completed after \(attempt) checks")
                    PlayerProbe.count("focus.landing.completed")
                    if attempt > 1 { AppProbe.focus("land: took \(attempt) tries") }
                    return
                }
                if let token = focusToken?(), token == previous {
                    AppProbe.focus("landing #\(sequence) yielded to settled focus")
                    PlayerProbe.count("focus.landing.yielded")
                    AppProbe.focus("land: gave up after \(attempt) — focus is resting on"
                                   + " \(token), which reads as the viewer's own choice")
                    return
                }
                previous = focusToken?()
                PlayerProbe.count("focus.landing.assignment")
                assign()
            }
            // Six tries is 360ms. Reaching the end means the target never took
            // focus and nothing else claimed it either — the shape of a row
            // that scrolled but never built its first card.
            AppProbe.focus("land: NEVER LANDED after 6 tries")
            PlayerProbe.count("focus.landing.exhausted")
        }
    }

    /// A page/menu transition also supersedes any delayed row hand-off.
    func cancelLanding() {
        if landingGeneration != nil {
            AppProbe.focus("landing #\(landingSequence) cancelled")
            PlayerProbe.count("focus.landing.cancelled")
        }
        if let pendingEntry { AppProbe.focus("entry #\(pendingEntry.sequence) cancelled") }
        pendingEntry = nil
        landingTask?.cancel()
        landingTask = nil
        landingRowID = nil
        landingGeneration = nil
    }
}
