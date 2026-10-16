import SwiftUI

/// A small Home-only leaf. No playback clock, background sweep, automatic
/// focus assignment or direct use of a saved (potentially expired) stream URL.
struct NTVResumePrompt: View {
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var profiles: ProfileStore
    let onResume: (WatchProgress) -> Void
    let includes: (WatchProgress) -> Bool
    @State private var candidate: WatchProgress?
    @State private var candidateProfile: Int?
    @State private var ready = false

    var body: some View {
        Group {
            if let candidate, candidateProfile == profiles.activeProfileID,
               progress.scopedProfileID == candidateProfile {
                NTVResumePromptCard(item: candidate, onPlay: {
                    self.candidate = nil
                    onResume(candidate)
                }, onDismiss: { self.candidate = nil })
                .padding(.horizontal, NTVViewport.horizontalInset)
                .padding(.bottom, 38)
            }
        }
        .task(id: profiles.activeProfileID) {
            ready = false
            candidate = nil
            candidateProfile = nil
            // Let Home establish its normal focus and the profile load finish.
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard !Task.isCancelled else { return }
            ready = true
            consider(progress.items)
        }
        .onReceive(progress.$items) { items in consider(items) }
    }

    private func consider(_ items: [String: WatchProgress]) {
        let profile = profiles.activeProfileID
        guard ready, progress.scopedProfileID == profile else { return }
        if let candidate {
            // Clearing history or finishing a title also dismisses its offer.
            if !includes(candidate) || !items.values.contains(where: { $0.id == candidate.id && $0.fraction < 0.95 }) {
                self.candidate = nil
            }
            return
        }
        guard !NTVResumeSuggestion.shared.hasPresented(profile: profile) else { return }
        if let suggestion = NTVResumeSuggestion.shared.claim(profile: profile, items: items.values.filter(includes)) {
            candidateProfile = profile
            candidate = suggestion
        }
    }
}

private struct NTVResumePromptCard: View {
    let item: WatchProgress
    let onPlay: () -> Void
    let onDismiss: () -> Void
    private enum Action: Hashable { case play, dismiss }
    @FocusState private var focused: Action?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 22) {
                RemoteImage(url: item.poster, maxDimension: 180)
                    .frame(width: 74, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reprendre où vous en étiez")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(NTVDesign.textSecondary)
                    Text(item.name).font(.system(size: 29, weight: .semibold)).lineLimit(1)
                    if let season = item.season, let episode = item.episode {
                        Text("S\(season) · E\(episode)").font(.system(size: 25))
                            .foregroundStyle(NTVDesign.textSecondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onPlay) {
                    Image(systemName: "play.fill").frame(width: 32)
                }
                .buttonStyle(NTVActionButtonStyle())
                .focused($focused, equals: .play)
                .accessibilityLabel("Reprendre \(item.name)")
                .accessibilityIdentifier("ntv.resume.prompt.play")
                Button(action: onDismiss) {
                    Image(systemName: "xmark").frame(width: 24)
                }
                .buttonStyle(NTVActionButtonStyle())
                .focused($focused, equals: .dismiss)
                .accessibilityLabel("Fermer la suggestion de reprise")
                .accessibilityIdentifier("ntv.resume.prompt.dismiss")
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.9)).frame(width: geometry.size.width * item.fraction)
                    }
            }.frame(height: 5).accessibilityHidden(true)
        }
        .padding(22)
        .frame(maxWidth: 780)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 24)) }
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        .focusSection()
        .accessibilityIdentifier("ntv.resume.prompt")
        // Never remove a control under the remote's focus. Leaving the card
        // starts a fresh quiet interval; focused users can take their time.
        .task(id: focused) {
            guard focused == nil else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard !Task.isCancelled, focused == nil else { return }
            onDismiss()
        }
        .onExitCommand { if focused != nil { onDismiss() } }
    }
}
