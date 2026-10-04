import SwiftUI

/// Append destinations to preserve the existing tab IDs and saved focus state.
enum AppTab: Int, CaseIterable, Identifiable {
    case home, search, library, settings, liveTV, movies, series, addons
    var id: Int { rawValue }

    /// Order the rail renders in (Live TV above Settings, despite raw value).
    static let sidebarOrder: [AppTab] = [.home, .movies, .series, .search, .library, .liveTV, .addons, .settings]

    var label: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .addons: return "Add-ons"
        case .search: return "Search"
        case .library: return "Library"
        case .liveTV: return "Live TV"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "play.rectangle.on.rectangle.fill"
        case .addons: return "puzzlepiece.extension.fill"
        case .search: return "magnifyingglass"
        case .library: return "bookmark.fill"
        case .liveTV: return "tv.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The always-visible left navigation rail, drawn as Liquid Glass (tvOS 26;
/// translucent material before that). Collapsed it is a floating glass pill of
/// icons, vertically centered at the left edge. When focus enters it expands
/// rightward into a wider glass panel with the profile chip on top and
/// labeled rows; the parent dims the content behind it.
struct GlassSidebar: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var liveTV = LiveTVSettingsStore.shared
    @Binding var selected: Int
    var focusBinding: FocusState<Int?>.Binding
    var onProfileTap: () -> Void = {}
    /// Fires when a tab is tapped, BEFORE `selected` is mutated, so the root
    /// can tell whether this is actually a change of tab (vs. re-tapping the
    /// tab you're already on) and react accordingly.
    var onTabSelected: (Int) -> Void = { _ in }
    /// Which edge the rail lives on. The ONLY thing that differs between the
    /// two layouts: same items, same icons and labels, same focus bindings,
    /// same glass — laid out along the other axis.
    var position: NavigationPosition = .left

    var expanded: Bool { focusBinding.wrappedValue != nil }
    private var horizontal: Bool { position.isHorizontal }

    /// Space (inside the safe area) the content reserves so it clears the
    /// floating collapsed pill, which hugs the screen edge at absolute
    /// 28..112pt — the safe inset (~90) covers most of it.
    static let collapsedWidth: CGFloat = 60
    static let expandedWidth: CGFloat = 240

    /// Transparent leading extension added to every rail item's focus frame.
    ///
    /// The rail is an OVERLAY, so the content's focus region runs UNDERNEATH it.
    /// The content's leading-edge focus filler (a `UIKitFocusableFillerItem` at
    /// x≈0, the vertical scroll's own region) is therefore a valid LEFT
    /// candidate from a rail item — the engine steps onto it, the panel
    /// collapses (it expands only while `sidebarFocus != nil`), the rows scroll,
    /// and on the pinned-Hybrid pin/unpin swap the screen blanks. Extending each
    /// item's focus frame to the screen edge leaves LEFT with no candidate, so
    /// the press is swallowed exactly like a LEFT at the content's own edge.
    ///
    /// The gutter is TRANSPARENT and sits inside the button (its content is
    /// pushed back by the same amount via the container's negative leading
    /// padding), so nothing moves and nothing is drawn — only the focus frame
    /// grows. Up/Down are unaffected: the gutter is part of each item, not a
    /// separate item the engine can land on.
    private static let focusGuard: CGFloat = 40
    /// Clearance a tab gives the TOP bar, applied as SAFE-AREA padding rather
    /// than plain padding.
    ///
    /// That distinction is the whole behaviour: plain padding shrinks the
    /// page's frame, so a scroll view's viewport starts below the bar and its
    /// content is CLIPPED at that line — a black band under the bar with rows
    /// disappearing into it. As safe-area padding the page still fills the
    /// screen and draws under the glass; only its content's resting inset
    /// moves, so rows slide up under the bar the way they should.
    ///
    /// Sized to sit just under the bar (28pt offset + ~100pt of bar) minus the
    /// top title-safe inset the system already gives, then trimmed so headings
    /// sit CLOSE to the bar rather than marooned below it.
    static let topBarClearance: CGFloat = 52

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: expanded ? 34 : 42, style: .continuous)
    }

    var body: some View {
        // Two orientations of ONE layout. The horizontal bar keeps the profile
        // chip ahead of the items on the same line, exactly as the vertical
        // panel keeps it above them.
        Group {
            if horizontal {
                horizontalBody
            } else if theme.palette.id == NTVDesign.palette.id {
                ntvVerticalBody
            } else {
                verticalBody
            }
        }
    }

    /// The top bar is ALWAYS fully drawn — every tab's word and the profile
    /// chip, focused or not. The left rail collapses to icons because it is a
    /// narrow column against the screen edge and labels would cost content
    /// width; a horizontal bar has the width to spare, and a row of unlabelled
    /// icons reads as a toolbar rather than as navigation. Focus still expands
    /// nothing here, so there is no widening lurch when you step into it.
    private var horizontalBody: some View {
        HStack(alignment: .center, spacing: 0) {
            NTVWordmark(size: 24)
                .padding(.trailing, OrivioSpacing.lg)
            Button(action: onProfileTap) {
                GlassProfileHeader(profile: profiles.active, compact: true)
            }
            .buttonStyle(PlainCardButtonStyle())
            .focused(focusBinding, equals: -1)
            .padding(.trailing, OrivioSpacing.sm)

            HStack(alignment: .center, spacing: 10) {
                ForEach(AppTab.sidebarOrder.filter { $0 != .liveTV || liveTV.enabled }) { tab in
                    Button {
                        onTabSelected(tab.rawValue)
                        selected = tab.rawValue
                    } label: {
                        if theme.palette.id == NTVDesign.palette.id {
                            NTVNavigationLabel(title: NTVBrand.navigationTitle(for: tab),
                                               symbol: tab.icon, selected: selected == tab.rawValue)
                        } else {
                            GlassItemLabel(tab: tab, selected: selected == tab.rawValue,
                                           expanded: true, horizontal: true)
                        }
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: tab.rawValue)
                    .accessibilityIdentifier("ntv.navigation.\(tab.rawValue)")
                }
            }
            .padding(.vertical, 12)
            .defaultFocus(focusBinding, selected)
        }
        .padding(.horizontal, OrivioSpacing.md)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            if theme.palette.id == NTVDesign.palette.id {
                NTVGlassSurface(shape: panelShape)
            } else {
                Color.clear.liquidGlass(in: panelShape)
            }
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .center)
        // Hug the top edge the way the vertical rail hugs the left one.
        .ignoresSafeArea(edges: .vertical)
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.34, dampingFraction: 0.86) : nil, value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue != selected {
                focusBinding.wrappedValue = selected
            }
        }
    }

    /// One glass surface carries the rail; item highlights use lightweight fills.
    /// The root's existing focus routing, Back and Right hand-off remain in charge.
    private var ntvVerticalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            NTVWordmark(size: 22)
                .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
                .padding(.horizontal, expanded ? OrivioSpacing.md : 0)
                .frame(height: 64)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(AppTab.sidebarOrder.filter { $0 != .liveTV || liveTV.enabled }) { tab in
                    Button {
                        onTabSelected(tab.rawValue)
                        selected = tab.rawValue
                    } label: {
                        NTVSidebarLabel(tab: tab, selected: selected == tab.rawValue,
                                        expanded: expanded)
                            .padding(.leading, Self.focusGuard)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: tab.rawValue)
                    .accessibilityIdentifier("ntv.navigation.\(tab.rawValue)")
                    .disabled(!expanded && tab.rawValue != selected)
                }
            }
            .padding(.leading, (expanded ? OrivioSpacing.sm : 12) - Self.focusGuard)
            .padding(.trailing, expanded ? OrivioSpacing.sm : 12)
            .defaultFocus(focusBinding, selected)

            Spacer(minLength: 24)

            if expanded {
                Button(action: onProfileTap) {
                    GlassProfileHeader(profile: profiles.active)
                        .padding(.leading, Self.focusGuard)
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused(focusBinding, equals: -1)
                .padding(.leading, OrivioSpacing.sm - Self.focusGuard)
                .padding(.trailing, OrivioSpacing.sm)
            } else {
                Color.clear.frame(height: 64)
            }
        }
        .padding(.vertical, 24)
        .frame(width: expanded ? NTVDesign.sidebarExpandedWidth : 84, alignment: .leading)
        .clipped()
        .frame(maxHeight: .infinity)
        .background {
            NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .padding(.leading, 18)
        .padding(.vertical, 24)
        .ignoresSafeArea()
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.34, dampingFraction: 0.86) : nil, value: expanded)
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue != selected {
                focusBinding.wrappedValue = selected
            }
        }
    }

    private var verticalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded { Spacer(minLength: 0) }

            // Profile chip — expanded panel only, sitting DIRECTLY above the
            // nav items (one centered group, not pinned to the panel top).
            if expanded {
                Button(action: onProfileTap) {
                    GlassProfileHeader(profile: profiles.active)
                        // Transparent focus extension — see `focusGuard`.
                        .padding(.leading, Self.focusGuard)
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused(focusBinding, equals: -1)
                .transition(.opacity)
                .padding(.leading, OrivioSpacing.sm - Self.focusGuard)
                .padding(.trailing, OrivioSpacing.sm)
                .padding(.bottom, 14)
            }

            VStack(alignment: .leading, spacing: expanded ? 10 : 24) {
                ForEach(AppTab.sidebarOrder.filter { $0 != .liveTV || liveTV.enabled }) { tab in
                    Button {
                        // Fire BEFORE mutating `selected` so the root can still
                        // see which tab we're coming FROM.
                        onTabSelected(tab.rawValue)
                        selected = tab.rawValue
                        // NOTE: do NOT clear focusBinding here — unfocusing
                        // with no destination makes the engine grab the nearest
                        // candidate. The root force-moves focus into content.
                    } label: {
                        GlassItemLabel(tab: tab, selected: selected == tab.rawValue,
                                       expanded: expanded, horizontal: false)
                            // Transparent focus extension — see `focusGuard`.
                            .padding(.leading, Self.focusGuard)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused(focusBinding, equals: tab.rawValue)
                    // COLLAPSED, only the current tab can take focus, so a Left
                    // press or a swipe from any card enters the rail ON the tab
                    // you're on. With every icon focusable the engine picked
                    // the one geometrically nearest the card, and the snap to
                    // the current tab below then moved focus a second time —
                    // the jump on every entry, all the way to the top when the
                    // current tab is Home. Never disables the focused item:
                    // collapsed means nothing in the rail holds focus, and the
                    // others unlock the moment it opens.
                    .disabled(!expanded && tab.rawValue != selected)
                }
            }
            // Negative leading cancels the transparent extension inside each
            // button, so the visible items stay exactly where they were.
            .padding(.leading, (expanded ? OrivioSpacing.sm : 12) - Self.focusGuard)
            .padding(.trailing, expanded ? OrivioSpacing.sm : 12)
            // Entering the sidebar lands on the tab you're on, not a stale row.
            .defaultFocus(focusBinding, selected)
            .padding(.vertical, expanded ? 0 : 20)

            if expanded { Spacer(minLength: 0) }
        }
        .frame(width: expanded ? Self.expandedWidth : 84, alignment: .leading)
        // Clip to the ANIMATING width so labels are revealed by the expanding
        // edge instead of rendering at their final position over the content.
        .clipped()
        // The pill hugs its icons vertically; the expanded panel stretches.
        .frame(maxHeight: expanded ? .infinity : nil)
        // Background-style glass: glassEffect WRAPPING focusable content hides
        // it from the focus engine (see liquidGlassIf).
        .background(Color.clear.liquidGlass(in: panelShape))
        .padding(.vertical, expanded ? OrivioSpacing.xl : 0)
        .padding(.leading, 28)
        .frame(maxHeight: .infinity, alignment: .center)
        // Hug the screen edge: the rail sits INSIDE the TV safe inset, not
        // pushed to the content's title-safe column.
        .ignoresSafeArea(edges: .horizontal)
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? .spring(response: 0.34, dampingFraction: 0.86) : nil, value: expanded)
        // On ENTRY (collapsed → expanded), snap focus to the current tab —
        // tvOS otherwise lands on the geometrically nearest row. A backstop
        // now: collapsed, the current tab is the only candidate.
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && focusBinding.wrappedValue != selected {
                focusBinding.wrappedValue = selected
            }
        }
    }
}

/// The tappable profile chip at the top of the expanded panel.
private struct GlassProfileHeader: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile
    /// The top bar's chip hugs its content instead of filling a panel width.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: OrivioSpacing.sm) {
            ProfileAvatarView(profile: profile, size: compact ? 44 : 52)
            Text(profile.name)
                .font(.system(size: compact ? 22 : 26, weight: .medium))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            if !compact { Spacer(minLength: 0) }
        }
        .padding(.horizontal, OrivioSpacing.sm)
        .frame(height: compact ? 56 : 64)
        .background(
            Capsule(style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.18) : .clear)
        )
    }
}

/// A single rail entry: icon (+ label when expanded). Focused/selected shows a
/// soft translucent capsule fill — no border, no scale; the glass carries it.
private struct GlassItemLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let tab: AppTab
    let selected: Bool
    let expanded: Bool
    /// Laid out in the top bar: the tile hugs its content rather than
    /// stretching to a panel's width, and there is no trailing `Spacer`.
    var horizontal: Bool = false

    private var highlighted: Bool { isFocused || selected }

    var body: some View {
        HStack(spacing: OrivioSpacing.sm) {
            Image(systemName: tab.icon)
                .font(.system(size: expanded ? 30 : 36, weight: .semibold))
                .foregroundStyle(highlighted ? theme.palette.textPrimary : theme.palette.textSecondary)
                .frame(width: expanded ? 44 : 60, height: expanded ? nil : 60, alignment: .center)

            if expanded {
                Text(tab.label)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(highlighted ? theme.palette.textPrimary : theme.palette.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
                if !horizontal { Spacer(minLength: 0) }
            }
        }
        .padding(.leading, expanded ? OrivioSpacing.md : 0)
        .padding(.trailing, expanded ? OrivioSpacing.md : 0)
        .frame(height: expanded ? 76 : 60)
        .frame(maxWidth: (expanded && !horizontal) ? .infinity : nil, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(highlighted ? Color.white.opacity(isFocused ? 0.22 : 0.10) : .clear)
        )
    }
}
