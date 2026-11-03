#!/usr/bin/env python3
"""Summarise Land's model-call telemetry (scripts/core/llm_telemetry.gd).

Reads the JSONL files the game writes to user://telemetry/ and prints, per purpose (dialogue,
agent decisions, inner voice, ...): calls, failures, latency p50/p95, prompt and output tokens,
cache hit rate, cost, and the real characters-per-token ratio (ContextBuilder budgets with 4).

Usage:
  python3 tools/llm_telemetry_report.py                 # every session in the default folder
  python3 tools/llm_telemetry_report.py --last          # the most recent session only
  python3 tools/llm_telemetry_report.py --dir PATH      # another telemetry folder
  python3 tools/llm_telemetry_report.py --json          # machine-readable
Stdlib only.
"""
import argparse
import glob
import json
import os
import statistics
import sys

DEFAULT_DIR = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Land/telemetry")


def load(paths):
    rows = []
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    print(f"warning: {path}:{n} is not JSON, skipped", file=sys.stderr)
    return rows


def pct(values, q):
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)


def summarise(rows):
    groups = {}
    for r in rows:
        groups.setdefault(r.get("purpose", "unlabelled"), []).append(r)
    groups["ALL"] = rows
    out = {}
    for purpose, rs in groups.items():
        ok = [r for r in rs if r.get("ok")]
        lat = [r["latency_ms"] for r in ok if isinstance(r.get("latency_ms"), (int, float))]
        prompt = [r.get("prompt_tokens", 0) for r in ok]
        read = sum(r.get("cache_read_input_tokens", 0) for r in ok)
        write = sum(r.get("cache_creation_input_tokens", 0) for r in ok)
        total_prompt = sum(prompt)
        costs = [r["cost_usd"] for r in rs if isinstance(r.get("cost_usd"), (int, float))]
        chars = sum(r.get("system_chars", 0) + r.get("message_chars", 0) for r in ok if r.get("prompt_tokens"))
        windows = [r["context_used"] for r in ok if isinstance(r.get("context_used"), (int, float))]
        out[purpose] = {
            "calls": len(rs),
            "failed": len(rs) - len(ok),
            "refusals": sum(1 for r in rs if r.get("refusal")),
            "fallback_served": sum(1 for r in rs if r.get("fallback_served")),
            "latency_ms_p50": pct(lat, 0.5),
            "latency_ms_p95": pct(lat, 0.95),
            "prompt_tokens_avg": statistics.mean(prompt) if prompt else None,
            "output_tokens_avg": statistics.mean([r.get("output_tokens", 0) for r in ok]) if ok else None,
            "thinking_tokens_avg": statistics.mean([r.get("thinking_tokens", 0) for r in ok]) if ok else None,
            "cache_read_share": (read / total_prompt) if total_prompt else None,
            "cache_write_share": (write / total_prompt) if total_prompt else None,
            "context_used_max": max(windows) if windows else None,
            "chars_per_token": (chars / total_prompt) if total_prompt else None,
            "cost_usd": sum(costs),
            "cost_unpriced_calls": sum(1 for r in rs if r.get("cost_usd") is None and r.get("ok")),
        }
    return out


def fmt(v, kind=""):
    if v is None:
        return "-"
    if kind == "pct":
        return f"{v * 100:.1f}%"
    if kind == "usd":
        return f"${v:.4f}"
    if isinstance(v, float):
        return f"{v:.1f}" if v >= 10 else f"{v:.2f}"
    return str(v)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--last", action="store_true", help="only the most recent session file")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    paths = sorted(glob.glob(os.path.join(args.dir, "llm_*.jsonl")), key=os.path.getmtime)
    if args.last:
        paths = paths[-1:]
    if not paths:
        print(f"No telemetry in {args.dir}")
        return 1
    summary = summarise(load(paths))
    if args.json:
        print(json.dumps({"files": paths, "by_purpose": summary}, indent=2))
        return 0
    print(f"{len(paths)} session file(s) in {args.dir}\n")
    cols = [("calls", ""), ("failed", ""), ("latency_ms_p50", ""), ("latency_ms_p95", ""), ("prompt_tokens_avg", ""),
            ("output_tokens_avg", ""), ("cache_read_share", "pct"), ("cache_write_share", "pct"),
            ("chars_per_token", ""), ("cost_usd", "usd")]
    header = ["purpose"] + [c for c, _ in cols]
    rows = [[p] + [fmt(s[c], k) for c, k in cols] for p, s in sorted(summary.items(), key=lambda kv: (kv[0] == "ALL", kv[0]))]
    widths = [max(len(str(x)) for x in col) for col in zip(header, *rows)]
    for r in [header] + rows:
        print("  ".join(str(x).ljust(w) for x, w in zip(r, widths)))
    unpriced = summary["ALL"]["cost_unpriced_calls"]
    if unpriced:
        print(f"\n{unpriced} call(s) served by a model with no price in llm_telemetry.gd: not in the cost total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
