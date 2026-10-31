#!/usr/bin/env python3
"""Summarize r7rs-benchmarks results as Markdown tables.

    python3 bench/summarize.py [--dir DIR] [--base SYSTEM] [SYSTEM ...]
    python3 bench/summarize.py [--dir DIR] --update FILE ...

Reads the results.<System> files in DIR (default bench/r7rs-benchmarks)
and collects the "+!CSVLINE!+impl,benchmark,seconds" lines that the
benchmark harness prints.  A system is named by its file (ChezAkku,
Quasischeme, QuasischemeRacket, RacketBase, ...), since programs that
share a prelude print the same implementation name.  The last run of a
benchmark wins.  Failures (CRASHED, ULIMITKILLED, COMPILEERROR) show as
such.

With no --update: one row per benchmark, each system's time and its
ratio to the base system (default ChezAkku), then each system's
geometric mean ratio over the benchmarks it and the base both completed.

With --update: in each FILE, every section between

    <!-- bench KIND ARGS -->  and  <!-- /bench -->

is regenerated from the results.  KIND and ARGS:

    table BASE SYSTEM ...     the per-benchmark table above
    summary BASE SYSTEM ...   per system: version, geometric mean vs
                              BASE, benchmarks completed, how many are
                              at most 1x, 1.5x and 2x BASE's time
    pairs A/B ...             per pair: A's geometric mean vs B, the
                              benchmarks A is faster on, and A's five
                              worst ratios
    geomean A/B               inline: A's geometric mean vs B, as 0.94x

Text outside the markers is left alone, so the prose around a table is
written by hand and the numbers in it are not.
"""

import glob
import math
import os
import re
import sys

LABELS = {
    "ChezAkku": "Chez Scheme",
    "Quasischeme": "Quasischeme",
    "QuasischemeR6RS": "Quasischeme `--r6rs`",
    "QuasischemeR5RS": "Quasischeme `--r5rs`",
    "QuasischemeChez": "Quasischeme `--chez`",
    "QuasischemeGuile": "Quasischeme `--guile`",
    "QuasischemeRacket": "Quasischeme `--racket`",
    "RacketBase": "Racket",
    "Guile": "Guile",
    "GaucheLocal": "Gauche",
    "Chibi": "Chibi",
}


def label(system):
    return LABELS.get(system) or system


def load(rdir):
    """{system: {bench: seconds or failure string}}, {system: version}"""
    results, versions = {}, {}
    for path in sorted(glob.glob(os.path.join(rdir, "results.*"))):
        system = path.rsplit("results.", 1)[1]
        times = results.setdefault(system, {})
        for line in open(path, errors="replace"):
            if not line.startswith("+!CSVLINE!+"):
                continue
            row = line[len("+!CSVLINE!+"):].strip().split(",")
            if len(row) < 3:
                continue
            impl, bench, value = row[:3]
            bench = bench.split(":")[0]
            try:
                times[bench] = float(value)
                # "chez-10.4.1+akku-r7rs" -> "10.4.1+akku-r7rs"
                if "-" in impl:
                    versions[system] = impl.split("-", 1)[1]
            except ValueError:
                times[bench] = value.lower()
    return results, versions


def ratios(results, a, b):
    """{bench: a's time / b's time} over the benchmarks both completed"""
    ta, tb = results.get(a, {}), results.get(b, {})
    return {k: ta[k] / tb[k] for k in ta
            if isinstance(ta[k], float) and isinstance(tb.get(k), float)
            and ta[k] > 0 and tb[k] > 0}


def geomean(rs):
    return math.exp(sum(map(math.log, rs)) / len(rs)) if rs else None


def fmt(r):
    return "" if r is None else "%.2f×" % r


def benchmarks(results, systems):
    seen = []
    for s in systems:
        for b in results.get(s, {}):
            if b not in seen:
                seen.append(b)
    return sorted(seen)


def table(results, base, systems):
    systems = [base] + [s for s in systems if s != base]
    out = ["| benchmark | " + " | ".join(label(s) for s in systems) + " |",
           "|---|" + "---:|" * len(systems)]
    for b in benchmarks(results, systems):
        cells = []
        for s in systems:
            v = results.get(s, {}).get(b)
            base_v = results.get(base, {}).get(b)
            if v is None:
                cells.append("")
            elif isinstance(v, str):
                cells.append(v)
            elif s != base and isinstance(base_v, float) and base_v > 0:
                cells.append("%.2f (%.2f×)" % (v, v / base_v))
            else:
                cells.append("%.2f" % v)
        out.append("| %s | %s |" % (b, " | ".join(cells)))
    out.append("| **geometric mean** | %s |" % " | ".join(
        "**%s**" % fmt(geomean(list(ratios(results, s, base).values())))
        for s in systems))
    return out


def summary(results, versions, base, systems):
    out = ["| implementation | version | geometric mean vs %s | completed "
           "| ≤ 1× | ≤ 1.5× | ≤ 2× |" % label(base),
           "|---|---|---:|---:|---:|---:|---:|"]
    total = len(benchmarks(results, [base] + systems))
    for s in systems:
        rs = list(ratios(results, s, base).values())
        done = sum(isinstance(v, float) for v in results.get(s, {}).values())
        out.append("| %s | %s | %s | %d/%d | %d | %d | %d |" % (
            label(s), versions.get(s, ""), fmt(geomean(rs)), done, total,
            sum(r <= 1 for r in rs), sum(r <= 1.5 for r in rs),
            sum(r <= 2 for r in rs)))
    return out


def pairs(results, specs):
    out = ["| | geometric mean | faster on | worst ratios |",
           "|---|---:|---:|---|"]
    for spec in specs:
        a, b = spec.split("/")
        rs = ratios(results, a, b)
        worst = sorted(rs.items(), key=lambda kv: -kv[1])[:5]
        out.append("| %s vs %s | %s | %d of %d | %s |" % (
            label(a), label(b), fmt(geomean(list(rs.values()))),
            sum(r < 1 for r in rs.values()), len(rs),
            ", ".join("%s %.1f×" % kv for kv in worst)))
    return out


MARKER = re.compile(r"(<!-- bench (\w+)([^>]*?) -->)(.*?)(<!-- /bench -->)",
                    re.S)


def update(path, results, versions):
    text = open(path).read()

    def section(m):
        kind, args = m.group(2), m.group(3).split()
        if kind == "geomean":
            a, b = args[0].split("/")
            body = fmt(geomean(list(ratios(results, a, b).values())))
            return m.group(1) + body + m.group(5)
        if kind == "table":
            lines = table(results, args[0], args[1:])
        elif kind == "summary":
            lines = summary(results, versions, args[0], args[1:])
        elif kind == "pairs":
            lines = pairs(results, args)
        else:
            sys.exit("%s: unknown section kind %s" % (path, kind))
        return m.group(1) + "\n" + "\n".join(lines) + "\n" + m.group(5)

    new = MARKER.sub(section, text)
    if new != text:
        open(path, "w").write(new)
        print("updated", path)


def main():
    args = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    rdir, base, files = os.path.join(here, "r7rs-benchmarks"), "ChezAkku", None
    systems = []
    while args:
        a = args.pop(0)
        if a == "--dir":
            rdir = args.pop(0)
        elif a == "--base":
            base = args.pop(0)
        elif a == "--update":
            files = args
            args = []
        else:
            systems.append(a)
    results, versions = load(rdir)
    if files is not None:
        for f in files:
            update(f, results, versions)
        return
    print("\n".join(table(results, base, systems or sorted(results))))


if __name__ == "__main__":
    main()
