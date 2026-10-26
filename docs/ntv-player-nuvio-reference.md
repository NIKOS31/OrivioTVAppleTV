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

## Focused seek comparison for build 49

The installed JAR was rebound through REA and its SHA-256 checked again on
27 October 2026: the identity above is unchanged. REA's exact inventory view
for `PlayerScreenRuntimeUiKt.class` and
`PlayerScreenRuntimeGestureActionsKt.class` is
`ev_158018ec297f811c584b13c3aaf51ac48d077cf8f2aae18234f2653396b3a58e`.
Inventory verifies those bytes; the following rules come from fresh local
`javap -c -p` reads, not from inventory names or a running Nuvio session.
Fourteen focused class dumps and their hashes are retained in the workspace
under `outputs/nTV-feedback-2026-10-26/nuvio-seek-rea-49/`, with the comparison
in `comparaison-seek.md` and identities in `manifest.json`.

| Installed Nuvio rule and bytecode entry | nTV correspondence and remaining adaptation |
| --- | --- |
| `PlayerTimelineKt.PlayerTimeline$lambda$7$1$0` clamps and reports a proposed position; `$lambda$7$2$0` reports its final value. `PlayerScreenRuntimeUiKt.handlePlayerControlsScrubChange` only stores preview state, without pausing. | Both nTV timeline entry points now call `beginScrub()` without imposing a pause. A running video keeps running; a paused one stays paused. The Siri Remote still uses a dedicated preview HUD. |
| `handlePlayerControlsScrubFinished` calls `finishTimelineScrub`, `seekTo` and progress sync, without calling `play`. | Commit keeps the current pause/play intent, including a buffer transition. Explicit physical Play during a preview still commits and resumes as a TV adaptation. |
| `PlayerScreenRuntimeGestureActionsKt.handleDoubleTapSeek` stores direction, a fixed playback-snapshot baseline and accumulated 10-second steps. Its reset coroutine clears that state after 800 ms without input. Direction reversal starts from the current playback snapshot. | `NTVAccumulatedSeek` ports that rule for nTV's configured directional skip. The anchor survives the existing internal debounce commits, so an old engine clock cannot lose a same-direction step. The pending timeline/time labels read the absolute target. A reversal uses the current playback position, matching Nuvio; it does not subtract from an unconfirmed previous target. The existing 280 ms discrete-click debounce remains a TV adaptation. |
| `togglePlayback` updates `shouldPlay` before calling the engine. `updatePlaybackSnapshot` rejects a snapshot whose `PlaybackKey` belongs to another source. | nTV keeps its existing source-generation and KSPlayer completion guards. Its nTV seek defaults now use the current pause intent, including when an older playing-state callback has not caught up. These guards are nTV implementations, not a copied Nuvio engine. |
| Horizontal surface preview and final seek are separate callbacks. | UIKit's initial nonzero pan translation is now delivered even if no `.changed` follows. A contact rejected or interrupted by a blocking panel cannot later revive; detaching its window delivers cancellation. Loading before first playback, source replacement and exit block input; buffering after playback has begun remains usable. |
| `clearLiveGestureFeedback` clears feedback without starting playback. | Cancelling nTV's running preview no longer restarts the engine. A timeline preview returns to its controls; a blocking panel keeps ownership. Source changes, explicit seeks, new scrubs, end and exit retire old accumulated targets. |
| `BindPlayerUiVisibilityEffects$1$1` hides controls after 3500 ms only while playing, not loading or scrubbing, without an error or parental guide. `requestBack` releases the retained player before navigation. | nTV retains its five-second idle policy, native focus/pickers and Back hierarchy: cancel preview, close a panel or controls, then exit. These TV choices and native lifecycle are not claimed as identical Nuvio implementations. |

The native journey now checks that the **real playback clock** advances during
a running timeline preview, then cancels without applying its proposed target.
The preview's French accessibility value distinguishes current playback from
the target; it is not an FPS measurement. The paused preview/cancel/commit,
explicit Play, advancing post-commit clock and picker checks are preserved.
Five focused model/input tests cover the burst anchor, direction and expiry,
bounds and invalid input, reset, initial pan delivery and cancellation.
These are prepared assertions; native execution and physical Siri Remote
calibration remain required before claiming the new build is validated.
