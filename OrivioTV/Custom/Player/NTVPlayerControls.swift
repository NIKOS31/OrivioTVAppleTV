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

                Button {
                    viewModel.noteSelectPressed()
                    viewModel.beginScrub(pausing: true)
                } label: {
                    NTVPlayerTimeline(viewModel: viewModel, clock: viewModel.clock, highlighted: focus == .timeline)
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($focus, equals: .timeline)
                .accessibilityLabel("Parcourir la vidéo")
                .accessibilityHint("Glissez sur le pavé tactile pour parcourir la vidéo. Un geste rapide avance plus loin. OK pour reprendre, Retour pour annuler.")
                .accessibilityIdentifier("ntv.player.timeline")
                .onMoveCommand { direction in
                    guard !viewModel.moveSuppressed else { return }
                    viewModel.noteSelectPressed()
                    switch direction {
                    case .left, .right:
                        viewModel.beginScrub(pausing: true)
                        viewModel.stepNTVScrub(forward: direction == .right)
                    case .down: focus = .play
                    default: break
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
        .defaultFocus($focus, .play)
        .onAppear {
            focus = initialControlID.flatMap(Control.init(rawValue:)) ?? .play
            onRestoreFocus()
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
            case .left: viewModel.nudgeSeek(-Double(viewModel.settings.skipSeconds))
            case .right: viewModel.nudgeSeek(Double(viewModel.settings.skipSeconds))
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

struct NTVPlayerSeekOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var scrubbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                NTVPlayerHeading(viewModel: viewModel)
                Spacer()
                if !scrubbing {
                    Text(TimeFormat.signedDelta(viewModel.pendingSeekDelta))
                        .font(.system(size: 25, weight: .medium).monospacedDigit())
                        .padding(.bottom, 4)
                }
            }
            .frame(height: 64)
            NTVPlayerTimeline(viewModel: viewModel, clock: viewModel.clock, highlighted: true, scrubbing: scrubbing)
            HStack {
                NTVPlayerTimeValue(viewModel: viewModel, clock: viewModel.clock)
                Spacer()
                NTVPlayerTimeValue(viewModel: viewModel, clock: viewModel.clock, totalDuration: true)
            }
            .frame(height: 42)
            Text(scrubbing ? "Glisser pour parcourir   ·   OK Reprendre   ·   Retour Annuler" : "← → Sauts rapides")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(height: 52, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 72)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
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
    var totalDuration = false

    private var target: Double {
        min(max(clock.scrubTarget ?? clock.position + viewModel.pendingSeekDelta, 0), max(clock.duration, 1))
    }

    var body: some View {
        Text(TimeFormat.clock(totalDuration ? max(clock.duration, 0) : target))
            .font(.system(size: 20, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .accessibilityIdentifier(totalDuration ? "ntv.player.duration" : "ntv.player.position")
    }
}

private struct NTVPlayerTimeline: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var clock: PlaybackClock
    var highlighted = false
    var scrubbing = false

    private var duration: Double { max(clock.duration, 1) }
    private var target: Double { min(max(clock.scrubTarget ?? clock.position + viewModel.pendingSeekDelta, 0), duration) }

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
        .accessibilityValue(TimeFormat.clock(target))
    }
}

// Track choices retain their readable panel; only the transport is minimal.
private struct NTVTransportLabel: View {
    @Environment(\.isFocused) private var focused
    let symbol: String
    let title: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .medium))
            if let title { Text(title).font(.system(size: 23, weight: .medium)) }
        }
        .padding(.horizontal, title == nil ? 24 : 20)
        .frame(height: 58)
        .foregroundStyle(focused ? .black : .white)
        .background(focused ? .white : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NTVPlayerTrackPicker: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var selected: String?
    private var subtitles: Bool { viewModel.overlay == .subtitles }
    private var options: [TrackOption] { subtitles ? viewModel.subtitleOptions : viewModel.audioOptions }
    private var current: String? { subtitles ? viewModel.selectedSubtitleID : viewModel.selectedAudioID }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(subtitles ? "Sous-titres" : "Audio").font(.system(size: 30, weight: .semibold))
            ScrollView {
                VStack(spacing: 8) {
                    if options.isEmpty {
                        Text(subtitles ? "Aucune piste disponible" : "Aucune piste audio disponible")
                            .font(.system(size: 25)).foregroundStyle(.white.opacity(0.7))
                    }
                    ForEach(options) { option in
                        Button {
                            viewModel.noteSelectPressed()
                            if subtitles { viewModel.selectSubtitle(option) } else { viewModel.selectAudio(option) }
                            viewModel.overlay = .controls
                        } label: {
                            NTVTransportLabel(symbol: option.id == current ? "checkmark.circle.fill" : "circle",
                                              title: option.id == "sub-off" ? "Désactivés" : option.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($selected, equals: option.id)
                    }
                }
                .padding(6)
            }
            .frame(height: min(CGFloat(max(options.count, 1)) * 72, 360))
            Button {
                viewModel.showInfoPanel(initialTab: subtitles ? 3 : 2)
            } label: {
                NTVTransportLabel(symbol: "slider.horizontal.3", title: subtitles ? "Réglages des sous-titres" : "Réglages audio")
            }
            .buttonStyle(PlainCardButtonStyle())
            .focused($selected, equals: "settings")
            .accessibilityIdentifier("ntv.player.tracks.settings")
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 600)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 24), emphasized: true) }
        // Identify the whole panel, not the heading SwiftUI otherwise exports
        // for an ungrouped stack. Children remain individually navigable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ntv.player.trackPicker")
        .focusSection()
        .defaultFocus($selected, current ?? options.first?.id ?? "settings")
        .onAppear { selected = current ?? options.first?.id ?? "settings" }
        // Share the window catcher's Back handling so the same physical press
        // cannot close this picker, then immediately hide the transport too.
        .onExitCommand { _ = viewModel.handleExit() }
    }
}
