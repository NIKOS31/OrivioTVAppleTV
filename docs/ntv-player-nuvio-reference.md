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

The supplied desktop screenshot also shows direct aspect, speed, subtitle, audio
and source controls. nTV exposes those tools in its lower rail, plus episodes
for a series with a known season. The native Siri Remote keeps volume control;
advanced playback settings remain available. nTV speed/source/episode pickers
use a bounded panel near the lower actions and return focus to their origin.
The separate legacy player presentation retains its existing full-screen picker.

The explicit French new-episode badge uses nTV existing release/history
calculation; changing the label does not assert that a source has been checked.
