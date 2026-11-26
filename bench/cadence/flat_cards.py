"""Benchmark-only variant "57f": the native card platter's tilt/parallax off.

Same as Settings > Performance > "Inclinaison des cartes" off: cards take
FlatCardButtonStyle (scale-only focus lift) instead of CardButtonStyle, whose
HighlightRotation/Translation effects ran every animation frame in the
run 45872064535 profiles. Not a product change.
"""
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = "    var cardParallaxEffective: Bool { settings.cardParallax && !reduceMotion }\n"
if text.count(anchor) != 1:
    raise SystemExit("Expected exactly one cardParallaxEffective.")
open(path, "w", encoding="utf-8").write(
    text.replace(anchor, "    var cardParallaxEffective: Bool { false } // bench 57f: tilt off\n"))
