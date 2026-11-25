"""Benchmark-only: count and time the 57 UIKit catalog container's work.

Variant "57b" additionally disables the collection's self-sizing invalidation,
a diagnostic for the hypothesis that a focused card changing its row's size
re-lays out the whole collection. Not a product fix: rows that load after
their first sizing may keep a wrong height.
"""
import sys

path, variant = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()


def timed(key):
    return ("let benchStart = CACurrentMediaTime(); defer { NTVBenchCounters.count(\"%s\", "
            "milliseconds: (CACurrentMediaTime() - benchStart) * 1000) }" % key)


edits = [
    ("            loadViewIfNeeded()\n            precondition(Set(identifiers).count == identifiers.count)\n",
     "            " + timed("container.update") + "\n"
     "            loadViewIfNeeded()\n            precondition(Set(identifiers).count == identifiers.count)\n"),
    ("            guard let content, let scope else { return }\n",
     "            guard let content, let scope else { return }\n            " + timed("container.configure") + "\n"),
    ("        func reveal(_ identifier: String, anchor: UnitPoint?) {\n",
     "        func reveal(_ identifier: String, anchor: UnitPoint?) {\n            " + timed("container.reveal") + "\n"),
    ("        didSet { if oldValue != contentSize { allowVerticalScrolling() } }",
     "        didSet { if oldValue != contentSize { NTVBenchCounters.count(\"collection.contentSizeChange\"); allowVerticalScrolling() } }"),
    ("    func allowVerticalScrolling() { horizontalRow = nil }\n",
     "    func allowVerticalScrolling() { horizontalRow = nil }\n\n"
     "    override func layoutSubviews() {\n        " + timed("collection.layoutSubviews") + "\n"
     "        super.layoutSubviews()\n    }\n"),
    ("    override var canBecomeFocused: Bool { false }\n",
     "    override var canBecomeFocused: Bool { false }\n\n"
     "    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {\n"
     "        " + timed("cell.selfSizing") + "\n"
     "        return super.preferredLayoutAttributesFitting(attributes)\n    }\n"),
]
if variant == "57b":
    edits.append(("            collection.selfSizingInvalidation = .enabledIncludingConstraints\n",
                  "            collection.selfSizingInvalidation = .disabled\n"))
elif variant != "57":
    raise SystemExit("Unknown variant.")

for old, new in edits:
    if text.count(old) != 1:
        raise SystemExit("Anchor not found exactly once: " + old.strip()[:60])
    text = text.replace(old, new)
open(path, "w", encoding="utf-8").write(text)
print("Container instrumented for", variant)
