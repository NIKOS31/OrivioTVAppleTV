# Player reference: Nuvio

The nTV transport keeps its existing tvOS playback engines, source handling,
progress, thumbnails and remote input. Its lower toolbar uses the visual
hierarchy of Nuvio's modern player: title, timeline, then compact actions below.
No Nuvio executable, assets, account storage or playback backend is bundled.

Reference: [Nuvio Desktop 0.1.30-alpha](https://github.com/NuvioMedia/NuvioDesktop/tree/d2e21f20782f4516b62bbdcb4764d6271db1d614),
published under GPL-3.0. Files consulted under
`composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/`:

- `PlayerControls.kt`: modern lower transport hierarchy.
- `PlayerTimeline.kt`: thin progress track that thickens for interaction.
- `PlayerControlActions.kt`: compact lower action rail.
- `AudioTrackModal.kt`, `SubtitleModal.kt`: separate track selection surfaces.
- `PlayerLayout.kt`: `formatPlaybackTime` and `formatPlaybackRuntime`.

`NTVNuvioRuntime.swift` contains a Swift port of those two formatting functions
under GPLv3, using seconds instead of milliseconds and explicitly handling
non-finite or malformed engine durations. `NTVPlayerRuntimeControl` implements
the corresponding elapsed/remaining toggle from `PlayerControlActions.kt`.
The updating time label observes the clock independently of the focus rail.
On tvOS the button is reached by Up from the rightmost tool, and returns to
Play with Left. This is a documented partial port, not the entire Nuvio player.

nTV implements that arrangement in SwiftUI, with its own colours and focus
navigation. The native remote retains discrete skips, a separate scrub mode,
Play/Pause and Back. A quick skip over bare video stays discreet; explicitly
opened controls keep their five-second idle delay after the final skip.

The existing player was archived before this adaptation, including the installed
build38 package and a full independently cloned source-history backup. The Nuvio
source tag is a reference, not proof that its source reproduces every byte or
behaviour of the installed desktop JAR.

Validation must include a native screenshot of the lower toolbar and a remote
round trip from play to timeline, Infos, the video/audio/subtitle tools, and back.
Windows playback or a passing screenshot check does not establish Apple TV
frame pacing.

The revised track picker reserves its measured height above the **whole**
transport, rather than offsetting a panel above the tools while covering the
timeline. The previous native attempt compiled but failed the adjacency test
(49.5pt gap with a 48pt limit). The local correction reduces actual stack
spacing; the test tolerance is unchanged. It still requires a fresh native run.

The supplied desktop screenshot also shows direct aspect, speed, subtitle, audio
and source controls. nTV exposes those tools in its lower rail, plus episodes
for a series with a known season. The native Siri Remote keeps volume control;
advanced playback settings remain available. nTV speed/source/episode pickers
use a bounded panel near the lower actions and return focus to their origin.
The separate legacy player presentation retains its existing full-screen picker.

The explicit French new-episode badge uses nTV existing release/history
calculation; changing the label does not assert that a source has been checked.

Build 47 corrects nTV's own remote behaviour: repeated directional clicks on
the timeline use the same configured skip as quick seeks, without the old
fourfold/twelvefold acceleration. Continuous touch scrubbing, thumbnails,
confirmation/cancellation, source selection and playback engines are retained.
Track pickers show three rows at a time in a narrower scrolling panel; advanced
options and source/episode pickers retain all their entries in bounded panels.
These are tvOS adaptations, not a port of Nuvio's complete input state machine.

## Gesture behaviour verified against the installed package

REA identified the installed desktop JAR as SHA-256
`2afe8fa47dd19fae1cb0d395e40440a92ae2efb7248d0c26025e4355de18ebda`.
Its retained inventory is
`ev_85cc25d7b7c48d1a2cd969ea059621cfa96327ec0015b73a05851dc7dc4f9535`.
Focused `javap` inspection of that JAR establishes the following static rules;
it does not claim a runtime gesture recording:

| Nuvio rule | Siri Remote adaptation in nTV |
| --- | --- |
| A surface tap toggles the controls | A light tap opens or hides the controls; clicking bare video opens them without pausing. The physical Play/Pause key controls playback. |
| Horizontal drag previews a target from a fixed anchor | Drag on bare video or the timeline uses the same linear displacement rule. Toolbar gestures keep their focus navigation. |
| Full-width movement represents 60, 90 or 120 seconds for durations below 30 minutes, 30–60 minutes or at least 60 minutes | Use the window's point width and cap projected remote translation to one window per contact. This cap is a remote calibration safeguard. |
| Releasing a horizontal gesture commits its target | Commit once on release. Interrupted gestures cancel; Back also cancels a preview. A later lift cannot revive a cancelled seek. |
| Seeking leaves the playback state intact | Preserve paused/playing intent, including during buffering. An explicit Play key resumes. |
| Repeated side double-taps add ten seconds from a baseline | Directional remote clicks use the configured skip (ten seconds by default), without acceleration. |

The relevant installed classes are `PlayerSurfaceGesturesKt` and its drag
callback, plus `PlayerScreenRuntimeGestureActionsKt` (surface taps,
`handleDoubleTapSeek` and the seek-commit callback). nTV keeps its existing
source selection, engines, thumbnails and progress handling. Native volume
keys and the existing speed control serve their TV roles; touch brightness
and hold-to-speed are not introduced on the remote. The circular scrub wheel
is not part of this nTV gesture mode.

Validation covers linear targets, duration ranges, bounds, invalid inputs,
normal release versus cancellation, paused seeks and explicit playback
resumption. Actual touch sensitivity and frame pacing still require a
physical Siri Remote test.
