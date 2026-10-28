import SwiftUI

/// Clock updates stay in the bar and time labels, away from focus targets.
struct NTVPlayerControls: View {
    @ObservedObject var viewModel: PlayerViewModel
    var initialControlID: String? = nil
    var onOpenPicker: (String) -> Void = { _ in }
    var onRestoreFocus: () -> Void = {}
    @FocusState private var focus: Control?

    private enum Control: String, Hashable { case timeline, play, runtime, video, speed, audio, subtitles, sources, episodes, more, info, next }
    private var pickingTracks: Bool { viewModel.overlay == .audio || viewModel.overlay == .subtitles }
    private var toolOrder: [Control] {
        var order: [Control] = [.video, .speed, .subtitles, .audio, .sources]
        if viewModel.currentVideo?.season != nil { order.append(.episodes) }
        order.append(.more)
        return order
    }
    private var detailOrder: [Control] { viewModel.nextEpisodeAvailable ? [.info, .next] : [.info] }
    private var footerOrder: [Control] { detailOrder + toolOrder }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            // Reserve the picker's real height above the entire transport.
            // An offset above the tool row still covers the timeline and time.
            if pickingTracks {
                NTVPlayerTrackPicker(viewModel: viewModel)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 28) {
                    NTVPlayerHeading(viewModel: viewModel)
                    Spacer(minLength: 28)
                }
                .frame(height: 64)

                ZStack {
                    NTVPlayerTimeline(viewModel: viewModel, clock: viewModel.clock,
                                      highlighted: viewModel.isScrubbing || focus == .timeline,
                                      scrubbing: viewModel.isScrubbing)
                    // Keep the clock's accessible value outside the focus button's label.
                    Button {
                        viewModel.noteSelectPressed()
                        if viewModel.isScrubbing { viewModel.commitScrub() }
                        else { viewModel.beginScrub() }
                    } label: { Color.clear.frame(height: 28) }
                    .buttonStyle(PlainCardButtonStyle())
                    .focused($focus, equals: .timeline)
                    .accessibilityLabel("Parcourir la vidéo")
                    .accessibilityHint("Glissez pour prévisualiser, puis relâchez pour valider. Gauche ou droite pour ajuster, OK pour confirmer, Retour pour annuler.")
                    .accessibilityIdentifier("ntv.player.timeline")
                    .onMoveCommand { direction in
                        guard !viewModel.moveSuppressed else { return }
                        viewModel.noteSelectPressed()
                        switch direction {
                        case .left, .right:
                            viewModel.beginScrub()
                            viewModel.stepNTVScrub(forward: direction == .right)
                        case .down:
                            if viewModel.isScrubbing { viewModel.cancelScrub() }
                            else { focus = .play }
                        case .up where viewModel.isScrubbing: viewModel.cancelScrub()
                        default: break
                        }
                    }
                }

                HStack(spacing: 12) {
                    NTVPlayerTimeValue(viewModel: viewModel, clock: viewModel.clock)
                    playControl
                    Spacer()
                    NTVPlayerRuntimeControl(clock: viewModel.clock) {
                        viewModel.noteSelectPressed()
                        viewModel.restartHideTimer()
                    }
                    .focused($focus, equals: .runtime)
                    .onMoveCommand { direction in
                        guard !viewModel.moveSuppressed else { return }
                        viewModel.restartHideTimer()
                        switch direction {
                        case .up: focus = .timeline
                        case .down: focus = .more
                        case .left: focus = .play
                        default: break
                        }
                    }
                }
                .frame(height: 42)
                .disabled(viewModel.isScrubbing)

                HStack(spacing: 14) {
                    pillControl(.info, title: "Infos", label: "Informations") { viewModel.showInfoPanel() }
                    if viewModel.nextEpisodeAvailable {
                        pillControl(.next, title: "Suivant", label: "Épisode suivant") { viewModel.playNextEpisodeFromControls() }
                    }
                    Spacer()
                    // Nuvio's lower action rail: keep tools next to the
                    // timeline instead of a second floating cluster by the title.
                    HStack(spacing: 14) {
                        circleControl(.video, symbol: "arrow.up.left.and.arrow.down.right",
                                      label: viewModel.aspectMode == .fit ? "Remplir l’écran" : "Ajuster à l’écran") {
                            viewModel.setAspect(viewModel.aspectMode == .fit ? .zoom : .fit)
                        }
                        circleControl(.speed, symbol: "speedometer", label: "Vitesse de lecture") {
                            openPicker(.speed, overlay: .speed)
                        }
                        .accessibilityValue(String(format: "%gx", viewModel.playbackSpeed))
                        circleControl(.subtitles, symbol: "captions.bubble", label: "Sous-titres") { viewModel.overlay = .subtitles }
                        circleControl(.audio, symbol: "speaker.wave.2", label: "Audio") { viewModel.overlay = .audio }
                        circleControl(.sources, symbol: "cloud", label: "Sources") {
                            viewModel.loadSourcesIfNeeded()
                            openPicker(.sources, overlay: .sources)
                        }
                        if viewModel.currentVideo?.season != nil {
                            circleControl(.episodes, symbol: "rectangle.stack", label: "Épisodes") {
                                openPicker(.episodes, overlay: .episodes)
                            }
                        }
                        circleControl(.more, symbol: "ellipsis", label: "Options de lecture") { viewModel.showInfoPanel() }
                    }
                }
                .frame(height: 52)
                .focusSection()
                .disabled(viewModel.isScrubbing)
                .opacity(viewModel.isScrubbing ? 0 : 1)
                .accessibilityHidden(viewModel.isScrubbing)
                .overlay(alignment: .leading) {
                    if viewModel.isScrubbing {
                        Text("Glisser pour parcourir   ·   Relâcher ou OK Valider   ·   Retour Annuler")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .disabled(pickingTracks)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ntv.player.transport")
        }
        // PlayerScreen supplies the single bottom gradient for all overlays.
        .padding(.horizontal, 72)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .defaultFocus($focus, viewModel.isScrubbing ? .timeline : .play)
        .onAppear {
            focus = viewModel.isScrubbing ? .timeline : initialControlID.flatMap(Control.init(rawValue:)) ?? .play
            onRestoreFocus()
        }
        .onChange(of: viewModel.isScrubbing) { _, scrubbing in
            if scrubbing { focus = .timeline }
        }
        .onChange(of: viewModel.controlsSession) { _, _ in focus = .play }
        .onChange(of: focus) { _, selected in
            viewModel.controlsFocusOnBar = selected == .timeline
            viewModel.restartHideTimer()
        }
        .onChange(of: viewModel.overlay) { old, new in
            if new == .controls {
                if old == .audio { focus = .audio }
                if old == .subtitles { focus = .subtitles }
            }
        }
    }

    private func openPicker(_ control: Control, overlay: PlayerOverlay) {
        onOpenPicker(control.rawValue)
        viewModel.overlay = overlay
    }

    private var playControl: some View {
        Button {
            viewModel.noteSelectPressed()
            viewModel.togglePlayPause()
            viewModel.restartHideTimer()
        } label: {
            NTVPlayerCircleLabel(symbol: viewModel.isPlaying ? "pause.fill" : "play.fill", size: 42, bare: true)
        }
        .buttonStyle(PlainCardButtonStyle())
        .focused($focus, equals: .play)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Lecture")
        .accessibilityHint("Haut pour parcourir la vidéo. Gauche ou droite pour un saut rapide.")
        .accessibilityIdentifier("ntv.player.play")
        .onMoveCommand { direction in
            guard !viewModel.moveSuppressed else { return }
            viewModel.noteSelectPressed()
            viewModel.restartHideTimer()
            switch direction {
            case .up: focus = .timeline
            case .down: focus = .info
            case .left, .right:
                viewModel.nudgeSeek(Double(viewModel.settings.skipSeconds) * (direction == .right ? 1 : -1))
                focus = .play
            default: break
            }
        }
    }

    private func circleControl(_ control: Control, symbol: String, label: String,
                               action: @escaping () -> Void) -> some View {
        Button {
            viewModel.noteSelectPressed()
            action()
            viewModel.restartHideTimer()
        } label: { NTVPlayerCircleLabel(symbol: symbol) }
        .buttonStyle(PlainCardButtonStyle())
        .focused($focus, equals: control)
        .accessibilityLabel(label)
        .accessibilityIdentifier("ntv.player.\(control.rawValue)")
        .onMoveCommand { direction in
            guard !viewModel.moveSuppressed else { return }
            viewModel.noteSelectPressed()
            viewModel.restartHideTimer()
            switch direction {
            case .up: focus = control == .more ? .runtime : .timeline
            case .left, .right:
                if let index = footerOrder.firstIndex(of: control) {
                    let next = index + (direction == .right ? 1 : -1)
                    if footerOrder.indices.contains(next) { focus = footerOrder[next] }
                }
            default: break
            }
        }
    }

    private func pillControl(_ control: Control, title: String, label: String,
                             action: @escaping () -> Void) -> some View {
        Button {
            viewModel.noteSelectPressed()
            action()
            viewModel.restartHideTimer()
        } label: { NTVPlayerPillLabel(title: title) }
        .buttonStyle(PlainCardButtonStyle())
        .focused($focus, equals: control)
        .accessibilityLabel(label)
        .accessibilityIdentifier("ntv.player.\(control.rawValue)")
        .onMoveCommand { direction in
            guard !viewModel.moveSuppressed else { return }
            viewModel.noteSelectPressed()
            viewModel.restartHideTimer()
            switch direction {
            case .up: focus = .play
            case .left, .right:
                if let index = footerOrder.firstIndex(of: control) {
                    let next = index + (direction == .right ? 1 : -1)
                    if footerOrder.indices.contains(next) { focus = footerOrder[next] }
                }
            default: break
            }
        }
    }
}

private struct NTVPlayerCircleLabel: View {
    @Environment(\.isFocused) private var focused
    let symbol: String
    var size: CGFloat = 52
    var bare = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: bare ? 20 : 22, weight: .medium))
            .foregroundStyle(focused ? .black : .white)
            .frame(width: size, height: size)
            .background {
                if focused { Circle().fill(.white) }
            }
            .contentShape(Circle())
    }
}

private struct NTVPlayerPillLabel: View {
    @Environment(\.isFocused) private var focused
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background {
                if focused { Capsule().fill(.white) }
                else { NTVGlassSurface(shape: Capsule(), clear: true) }
            }
            .overlay(Capsule().strokeBorder(focused ? .clear : .white.opacity(0.18), lineWidth: 1))
    }
}

private struct NTVPlayerHeading: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.displayTitle).font(.system(size: 32, weight: .semibold)).lineLimit(1)
                .accessibilityIdentifier("ntv.player.heading")
            if let episode = viewModel.episodeLine {
                Text(episode).font(.system(size: 20)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 64, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }
}

/// Nuvio's runtime toggle, adapted to the remote. Only this leaf observes
/// the playback clock; ticking time does not rebuild the action/focus rail.
private struct NTVPlayerRuntimeControl: View {
    let clock: PlaybackClock
    let onInteraction: () -> Void
    @AppStorage("ntv.player.remainingTime") private var remaining = false

    var body: some View {
        Button {
            remaining.toggle()
            onInteraction()
        } label: { NTVPlayerRuntimeLabel(clock: clock, remaining: remaining) }
        .buttonStyle(PlainCardButtonStyle())
        .accessibilityHint(remaining ? "Afficher le temps écoulé et la durée totale." : "Afficher le temps restant.")
        .accessibilityValue(remaining ? "Temps restant" : "Temps écoulé et durée totale")
        .accessibilityIdentifier("ntv.player.runtime")
    }
}

private struct NTVPlayerRuntimeLabel: View {
    @Environment(\.isFocused) private var focused
    @ObservedObject var clock: PlaybackClock
    let remaining: Bool
    var body: some View {
        Text(NTVNuvioRuntime.text(position: clock.scrubTarget ?? clock.position,
                                 duration: clock.duration, remaining: remaining))
            .font(.system(size: 20, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(minWidth: 220).frame(height: 42)
            .background(Capsule().fill(.white.opacity(focused ? 0.18 : 0)))
    }
}

private struct NTVPlayerTimeValue: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var clock: PlaybackClock

    private var target: Double {
        min(max(clock.scrubTarget ?? viewModel.pendingNTVSeekTarget ?? (clock.position + viewModel.pendingSeekDelta), 0), max(clock.duration, 1))
    }

    var body: some View {
        Text(TimeFormat.clock(target))
            .font(.system(size: 20, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .accessibilityIdentifier("ntv.player.position")
    }
}

private struct NTVPlayerTimeline: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var clock: PlaybackClock
    var highlighted = false
    var scrubbing = false

    private var duration: Double { max(clock.duration, 1) }
    private var target: Double { min(max(clock.scrubTarget ?? viewModel.pendingNTVSeekTarget ?? (clock.position + viewModel.pendingSeekDelta), 0), duration) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = width * CGFloat(target / duration)
            let thickness: CGFloat = highlighted ? 10 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: thickness)
                ForEach(clock.cachedSpans, id: \.lowerBound) { span in
                    let start = width * CGFloat(span.lowerBound)
                    Capsule().fill(.white.opacity(0.32))
                        .frame(width: max(width * CGFloat(span.upperBound) - start, 0), height: thickness)
                        .offset(x: start)
                }
                Capsule().fill(.white).frame(width: max(x, thickness), height: thickness)
                if scrubbing {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .offset(x: min(max(x - 7, 0), max(width - 14, 0)))
                }
            }
            .frame(height: 28)
            .overlay(alignment: .topLeading) {
                if scrubbing, let preview = viewModel.thumbnail(at: target) {
                    Image(uiImage: preview).resizable().scaledToFill()
                        .frame(width: 256, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        .offset(x: min(max(x - 128, 0), max(width - 256, 0)), y: -240)
                }
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scrubbing ? "Aperçu de la recherche" : "Progression de lecture")
        .accessibilityValue(scrubbing
            ? "Lecture \(TimeFormat.clock(clock.position)), cible \(TimeFormat.clock(target))"
            : TimeFormat.clock(target))
        .accessibilityIdentifier(scrubbing ? "ntv.player.seek.preview" : "ntv.player.seek.progress")
        // The playhead follows the requested position, never an overlay's fade transaction.
        .transaction { $0.animation = nil }
    }
}

// Track choices retain their readable panel; only the transport is minimal.
private struct NTVTransportLabel: View {
    @Environment(\.isFocused) private var focused
    let symbol: String
    let title: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium))
            if let title { Text(title).font(.system(size: 25, weight: .medium)).lineLimit(2) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .foregroundStyle(focused ? .black : .white)
        .background(focused ? .white : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Value grouping is done outside the focus-owning leaf, never on clock ticks.
struct NTVTrackLanguageGroup: Identifiable {
    let id: String
    let title: String
    let options: [TrackOption]

    static func build(_ options: [TrackOption]) -> [Self] {
        var grouped: [String: [TrackOption]] = [:]
        for option in options where option.id != "sub-off" {
            let code: String
            if let tag = option.languageCode, !tag.isEmpty, tag != "und" {
                code = AudioLanguageMatch.normalizedCode(tag)
            } else {
                // Addon labels append their name after ·; that provider name
                // is not evidence of a track's language.
                let label = String(option.displayName.split(separator: "·", maxSplits: 1).first ?? "")
                code = PlayerSettings.allAudioLanguageOptions.first {
                    !$0.0.isEmpty && AudioLanguageMatch.matches(code: nil, label: label, preferred: $0.0)
                }?.0 ?? "und"
            }
            grouped[code, default: []].append(option)
        }
        return grouped.keys.sorted { a, b in
            if a == "und" { return false }
            if b == "und" { return true }
            return a < b
        }.map { code in
            Self(id: code, title: code == "und" ? "Langue non précisée" :
                (AudioLanguageMatch.displayName(for: code) ?? code), options: grouped[code] ?? [])
        }
    }
}

private struct NTVPlayerTrackPicker: View {
    @ObservedObject var viewModel: PlayerViewModel
    private var subtitles: Bool { viewModel.overlay == .subtitles }
    var body: some View {
        let options = subtitles ? viewModel.subtitleOptions : viewModel.audioOptions
        NTVTrackPickerContent(groups: subtitles ? viewModel.subtitleLanguageGroups : viewModel.audioLanguageGroups,
            off: options.first { $0.id == "sub-off" }, subtitles: subtitles,
            current: subtitles ? viewModel.selectedSubtitleID : viewModel.selectedAudioID,
            language: $viewModel.trackPickerLanguage, delay: viewModel.subtitleDelay,
            onSelect: { option in
                viewModel.noteSelectPressed()
                if subtitles { viewModel.selectSubtitle(option) } else { viewModel.selectAudio(option) }
                viewModel.trackPickerLanguage = nil
                viewModel.overlay = .controls
                viewModel.restartHideTimer()
            }, onDelay: { viewModel.nudgeSubtitleDelay(by: $0) },
            onReset: { viewModel.resetSubtitleDelay() },
            onSettings: { viewModel.showInfoPanel(initialTab: subtitles ? 3 : 2) },
            onExit: { _ = viewModel.handleExit() })
        .onAppear { viewModel.trackPickerLanguage = nil }
    }
}

private struct NTVTrackPickerContent: View {
    let groups: [NTVTrackLanguageGroup]
    let off: TrackOption?
    let subtitles: Bool
    let current: String?
    @Binding var language: String?
    let delay: Double
    let onSelect: (TrackOption) -> Void
    let onDelay: (Double) -> Void
    let onReset: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void
    @FocusState private var selected: String?
    private var group: NTVTrackLanguageGroup? { groups.first { $0.id == language } }
    private var visibleRows: Int { group.map { $0.options.count + 1 } ?? groups.count + (off == nil ? 0 : 1) }
    private var initialFocus: String {
        if let group { return group.options.first { $0.id == current }?.id ?? group.options.first?.id ?? "languages" }
        if current == "sub-off", off != nil { return "sub-off" }
        let preferred = groups.first { $0.options.contains { $0.id == current } } ?? groups.first
        return preferred.map { "language:" + $0.id } ?? (off == nil ? "settings" : "sub-off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subtitles ? "Sous-titres" : "Audio").font(.system(size: 30, weight: .semibold))
            ScrollView {
                VStack(spacing: 8) {
                    if let group {
                        Button { language = nil } label: {
                            NTVTransportLabel(symbol: "chevron.left", title: group.title + " · Langues")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainCardButtonStyle()).focused($selected, equals: "languages")
                        .accessibilityIdentifier("ntv.player.tracks.languages")
                        ForEach(group.options) { option in trackButton(option) }
                    } else {
                        if let off { trackButton(off) }
                        if groups.isEmpty {
                            Text("Aucune piste disponible").font(.system(size: 25)).foregroundStyle(.white.opacity(0.7))
                        }
                        ForEach(groups) { group in
                            Button { language = group.id } label: {
                                NTVTransportLabel(symbol: group.options.contains { $0.id == current } ? "checkmark.circle.fill" : "globe",
                                    title: "\(group.title) · \(group.options.count) piste\(group.options.count > 1 ? "s" : "")")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainCardButtonStyle())
                            .focused($selected, equals: "language:" + group.id)
                            .accessibilityIdentifier("ntv.player.tracks.language." + group.id)
                        }
                    }
                }.padding(6)
            }
            .frame(height: CGFloat(min(max(visibleRows, 1), 3)) * 56 + 12)
            if subtitles {
                HStack(spacing: 10) {
                    delayButton("−0,5 s", id: "earlier") { onDelay(-0.5) }
                    delayButton(PlayerViewModel.formatDelay(delay), id: "reset") { onReset() }
                    delayButton("+0,5 s", id: "later") { onDelay(0.5) }
                }
                .accessibilityLabel("Décalage des sous-titres, valeur centrale pour remettre à zéro")
            }
            Button(action: onSettings) {
                NTVTransportLabel(symbol: "slider.horizontal.3", title: subtitles ? "Réglages des sous-titres" : "Réglages audio")
            }
            .buttonStyle(PlainCardButtonStyle()).focused($selected, equals: "settings")
            .accessibilityIdentifier("ntv.player.tracks.settings")
        }
        .foregroundStyle(.white).padding(24).frame(width: 520)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 24), emphasized: true) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("ntv.player.trackPicker")
        .focusSection().defaultFocus($selected, initialFocus)
        .task(id: language) { selected = initialFocus }
        .onChange(of: groups.map(\.id)) { _, ids in
            if let language, !ids.contains(language) { self.language = nil }
        }
        .onExitCommand(perform: onExit)
    }
    private func trackButton(_ option: TrackOption) -> some View {
        Button { onSelect(option) } label: {
            NTVTransportLabel(symbol: option.id == current ? "checkmark.circle.fill" : "circle",
                title: option.id == "sub-off" ? "Désactivés" : option.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainCardButtonStyle()).focused($selected, equals: option.id)
    }
    private func delayButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 24, weight: .medium)).monospacedDigit()
                .frame(maxWidth: .infinity).frame(height: 48)
        }
        .buttonStyle(NTVActionButtonStyle(capsule: true)).focused($selected, equals: "delay:" + id)
        .accessibilityLabel(id == "reset" ? "Remettre le décalage à zéro, \(label)" : "Décalage \(label)")
        .accessibilityIdentifier("ntv.player.tracks.delay." + id)
    }
}
