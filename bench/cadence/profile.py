"""Summarize a macOS `sample` call graph: the app's main thread only.

Output is code symbols and sample counts (1 sample = 1 ms at the 1 ms
interval run.sh asks for), nothing from the app's content.
`sample` replaced `xctrace`, which never started recording when attached to
a simulator app (runs 45802547277 and 45831603069).
"""
import collections
import json
import re
import sys

path, label, test = sys.argv[1], sys.argv[2], sys.argv[3]
NODE = re.compile(r"^(?P<prefix>[ +!:|]*?)(?P<count>\d+) (?P<rest>.*)$")


def split(rest):
    """'name  (in binary) + 12  [0x..]  file.swift:3' -> (name, binary)."""
    m = re.search(r"\s{2}\(in (?P<bin>[^)]*)\)", rest)
    if m:
        return rest[:m.start()].strip(), m.group("bin")
    return re.sub(r"\s+\[0x[0-9a-f]+\].*$", "", rest).strip() or "?", "?"


def main_thread_lines(text):
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("Call graph:")) + 1
    except StopIteration:
        raise SystemExit("No call graph in the sample output.")
    threads, current = [], None
    for line in lines[start:]:
        if not line.strip():
            break
        m = NODE.match(line)
        if not m:
            continue
        if "+" not in m.group("prefix"):  # thread header at the top indent
            current = (m.group("rest"), int(m.group("count")), [])
            threads.append(current)
        elif current is not None:
            current[2].append((len(m.group("prefix")), int(m.group("count")), *split(m.group("rest"))))
    if not threads:
        raise SystemExit("No thread in the call graph.")
    main = next((t for t in threads if "com.apple.main-thread" in t[0]), threads[0])
    return main, sum(t[1] for t in threads)


(header, main_samples, nodes), all_samples = main_thread_lines(open(path, encoding="utf-8", errors="replace").read())
self_c, incl_c, app_incl_c, app_self_c = (collections.Counter() for _ in range(4))
stack = []  # [depth, name, binary, count, children]


def close(entry):
    depth, name, binary, count, children = entry
    own = count - children
    if own > 0:
        self_c[name] += own
        for _, n, b, _, _ in reversed(stack + [entry]):
            if "OrivioTV" in b:
                app_self_c[n] += own
                break


for depth, count, name, binary in nodes:
    while stack and stack[-1][0] >= depth:
        close(stack.pop())
    if stack:
        stack[-1][4] += count
    names_on_path = {e[1] for e in stack}
    if name not in names_on_path:
        incl_c[name] += count
        if "OrivioTV" in binary:
            app_incl_c[name] += count
    stack.append([depth, name, binary, count, 0])
while stack:
    close(stack.pop())


def top(counter, n):
    return [{"symbol": k[:240], "samples": v, "share": round(v / main_samples, 3) if main_samples else None}
            for k, v in counter.most_common(n)]


print(json.dumps({
    "label": label, "test": test, "tool": "sample, 1 ms interval",
    "environment": "simulateur tvOS, build Debug, GitHub Actions; pas une mesure Apple TV",
    "mainThreadSamples": main_samples, "allThreadsSamples": all_samples,
    "topSelf": top(self_c, 40),
    "topInclusive": top(incl_c, 120),
    "appInclusive": top(app_incl_c, 60),
    "appInnermost": top(app_self_c, 40),
}, indent=1, ensure_ascii=False))
if not main_samples:
    raise SystemExit("No main-thread sample found.")
