"""Aggregate NTVCadenceBenchmark attachments per version and segment (simulator only)."""
import json
import pathlib
import statistics
import sys

out = pathlib.Path(sys.argv[1])
SCOPES = ("body.catalog", "body.posterRow", "body.posterCell", "body.posterContainer",
          "body.catalogSpotlight", "body.homeSpotlight", "body.focusBackdrop", "action.catalogVerticalMove")
data = {}
for round_dir in sorted((out / "attachments").glob("round*-*")):
    label = round_dir.name.split("-", 1)[1]
    for path in round_dir.rglob("*"):
        if not path.is_file() or path.stat().st_size > 2_000_000:
            continue
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(doc, dict) or "segment" not in doc or "passes" not in doc:
            continue
        for p in doc["passes"]:
            p["round"] = round_dir.name
        data.setdefault(label, {}).setdefault(doc["segment"], []).extend(doc["passes"])

summary = {"environment": "simulateur tvOS, build Debug, GitHub Actions; pas une mesure Apple TV",
           "order": "56, 57, 57c, 57c, 57, 56 (57c: 57 + poster cells gated by == with a stable callback box, diagnostic only)", "versions": {}}
for label, segments in sorted(data.items()):
    summary["versions"][label] = {}
    for segment, passes in sorted(segments.items()):
        seconds = sum(p["seconds"] for p in passes)
        late = sum(p["lateCallbacks"] for p in passes)
        keys = list(SCOPES) + sorted({k for p in passes for k in p["workDelta"] if k.split(".")[0] in ("container", "collection", "cell")})
        work = {s: statistics.mean(p["workDelta"].get(s, {}).get("evaluations", 0) for p in passes) for s in keys}
        work_ms = {s: statistics.mean(p["workDelta"].get(s, {}).get("milliseconds", 0) for p in passes) for s in keys if s not in SCOPES}
        summary["versions"][label][segment] = {
            "passes": len(passes),
            "worstGapMsMedian": round(statistics.median(p["worstGapMs"] for p in passes), 2),
            "worstGapMsMax": round(max(p["worstGapMs"] for p in passes), 2),
            "lateCallbacksTotal": late,
            "lateCallbacksPerPass": round(late / len(passes), 2),
            "lateCallbacksPerSecond": round(late / seconds, 3) if seconds else None,
            "callbacksPerSecond": round(sum(p["callbacks"] for p in passes) / seconds, 2) if seconds else None,
            "meanEvaluationsPerPass": {k: round(v, 1) for k, v in work.items()},
            "meanContainerMillisecondsPerPass": {k: round(v, 2) for k, v in work_ms.items()},
            "rounds": sorted({p["round"] for p in passes}),
        }
print(json.dumps(summary, indent=2, sort_keys=True, ensure_ascii=False))
if not data:
    raise SystemExit("No benchmark attachment found.")
