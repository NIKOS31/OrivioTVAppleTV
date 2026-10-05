import SwiftUI

/// Clock updates stay inside the timeline; they never rebuild a focus target.
struct NTVPlayerControls: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var focus: Control?

    private enum Control: Hashable { case timeline, back, play, forward, audio, subtitles, info, next }
    private var pickingTracks: Bool { viewModel.overlay == .audio || viewModel.overlay == .subtitles }
    private var controlOrder: [Control] {
        var order: [Control] = [.back, .play, .forward]
        if !viewModel.audioOptions.isEmpty { order.append(.audio) }
        if !viewModel.subtitleOptions.isEmpty { order.append(.subtitles) }
        order.append(.info)
        if viewModel.nextEpisodeAvailable { order.append(.next) }
        return order
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 20) {
                NTVPlayerHeading(viewModel: viewModel)
                Button {
                    viewModel.noteSelectPressed()
                    viewModel.beginScrub(pausing: true)
                } label: {
                    NTVPlayerTimeline(viewModel: viewModel, clock: viewModel.clock,
                                      highlighted: focus == .timeline)
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($focus, equals: .timeline)
                .accessibilityLabel("Parcourir la vidéo")
                .accessibilityHint("Droite ou gauche pour choisir une position. OK pour reprendre, Retour pour annuler.")
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

                HStack(spacing: 14) {
                    control(.back, symbol: "gobackward", label: "Reculer de \(viewModel.settings.skipSeconds) secondes") {
                        viewModel.nudgeSeek(-Double(viewModel.settings.skipSeconds))
                    }
                    control(.play, symbol: viewModel.isPlaying ? "pause.fill" : "play.fill",
                            label: viewModel.isPlaying ? "Pause" : "Lecture") { viewModel.togglePlayPause() }
                    control(.forward, symbol: "goforward", label: "Avancer de \(viewModel.settings.skipSeconds) secondes") {
                        viewModel.nudgeSeek(Double(viewModel.settings.skipSeconds))
                    }
                    Spacer(minLength: 24)
                    if !viewModel.audioOptions.isEmpty {
                        control(.audio, symbol: "speaker.wave.2", label: "Audio", title: "Audio") { viewModel.overlay = .audio }
                    }
                    if !viewModel.subtitleOptions.isEmpty {
                        control(.subtitles, symbol: "captions.bubble", label: "Sous-titres", title: "Sous-titres") { viewModel.overlay = .subtitles }
                    }
                    control(.info, symbol: "info.circle", label: "Informations", title: "Infos") { viewModel.showInfoPanel() }
                    if viewModel.nextEpisodeAvailable {
                        control(.next, symbol: "forward.end", label: "Épisode suivant", title: "Suivant") { viewModel.playNextEpisodeFromControls() }
                    }
                }
                .frame(height: 62)
                .focusSection()
            }
            .padding(28)
            .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous), emphasized: true) }
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .disabled(pickingTracks)

            if pickingTracks {
                NTVPlayerTrackPicker(viewModel: viewModel)
                    .padding(.bottom, 100)
                    .padding(.trailing, 20)
            }
        }
        .padding(.horizontal, 72)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .defaultFocus($focus, .play)
        .onAppear { focus = .play }
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

    private func control(_ control: Control, symbol: String, label: String,
                         title: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            viewModel.noteSelectPressed()
            action()
            viewModel.restartHideTimer()
        } label: {
            NTVTransportLabel(symbol: symbol, title: title)
        }
        .buttonStyle(PlainCardButtonStyle())
        .focused($focus, equals: control)
        .accessibilityLabel(label)
        .accessibilityIdentifier("ntv.player.\(control)")
        .onMoveCommand { direction in
            guard !viewModel.moveSuppressed else { return }
            viewModel.noteSelectPressed()
            viewModel.restartHideTimer()
            switch direction {
            case .up: focus = .timeline
            case .left, .right:
                if let index = controlOrder.firstIndex(of: control) {
                    let next = index + (direction == .right ? 1 : -1)
                    if controlOrder.indices.contains(next) { focus = controlOrder[next] }
                }
            default: break
            }
        }
    }
}

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
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? .white : .clear, lineWidth: 2))
    }
}

private struct NTVPlayerHeading: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.displayTitle).font(.system(size: 32, weight: .semibold)).lineLimit(1)
            if let episode = viewModel.episodeLine {
                Text(episode).font(.system(size: 21)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 64, alignment: .leading)
        .allowsHitTesting(false)
    }
}

struct NTVPlayerSeekOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    var scrubbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                if !scrubbing {
                    Image(systemName: viewModel.pendingSeekDelta < 0 ? "gobackward" : "goforward")
                    Text(TimeFormat.signedDelta(viewModel.pendingSeekDelta)).monospacedDigit()
                }
            }
            .font(.system(size: 32, weight: .semibold))
            .frame(height: 64)
            NTVPlayerTimeline(viewModel: viewModel, clock: viewModel.clock,
                              highlighted: true, scrubbing: scrubbing)
            Text(scrubbing ? "← → Choisir la position   ·   OK Reprendre   ·   Retour Annuler" : "← → Sauts rapides")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 62)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous), emphasized: true) }
        .padding(.horizontal, 72)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
        VStack(spacing: 16) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * CGFloat(target / duration)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 8)
                    ForEach(clock.cachedSpans, id: \.lowerBound) { span in
                        let start = width * CGFloat(span.lowerBound)
                        Capsule().fill(.white.opacity(0.28))
                            .frame(width: max(width * CGFloat(span.upperBound) - start, 0), height: 8)
                            .offset(x: start)
                    }
                    Capsule().fill(.white).frame(width: max(x, 8), height: 8)
                    Circle().fill(.white)
                        .frame(width: highlighted ? 24 : 14, height: highlighted ? 24 : 14)
                        .offset(x: min(max(x - (highlighted ? 12 : 7), 0), max(width - (highlighted ? 24 : 14), 0)))
                }
                .frame(height: 30)
                .overlay(alignment: .topLeading) {
                    if scrubbing, let preview = viewModel.thumbnail(at: target) {
                        Image(uiImage: preview).resizable().scaledToFill()
                            .frame(width: 256, height: 144)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.6), lineWidth: 2))
                            .offset(x: min(max(x - 128, 0), max(width - 256, 0)), y: -174)
                    }
                }
            }
            .frame(height: 30)
            HStack {
                Text(TimeFormat.clock(target))
                    .accessibilityIdentifier("ntv.player.position")
                Spacer()
                if highlighted && !scrubbing { Text("OK pour parcourir").font(.system(size: 19)) }
                Spacer()
                Text("−" + TimeFormat.clock(max(duration - target, 0)))
            }
            .font(.system(size: 24, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
        }
        .frame(height: 92)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityValue(TimeFormat.clock(target))
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
            .frame(height: min(CGFloat(options.count) * 72, 360))
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 600)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 24), emphasized: true) }
        .focusSection()
        .defaultFocus($selected, current ?? options.first?.id ?? "")
        .onAppear { selected = current ?? options.first?.id }
        .onExitCommand { viewModel.overlay = .controls }
    }
}
