---
name: measure-perf
description: How to measure QuasiScheme performance, start-up time and executable size so the numbers count as evidence. Covers instructions retired, r7rs-benchmarks (bench/run.sh, summarize.py), ctak and fibc, continuation microbenchmarks, executable sizes per mode, zstd sizes, and comparisons against Chez, Guile and Racket. Use for any ticket that claims a speed, start-up or size change (Milestones 1, 2 and 8), and at every milestone gate.
---

# measure-perf

## Principles (non-negotiable)
1. **Instructions retired first, time second.**
   - Wall-clock times on the development machine vary by about 30%
     between runs (ROADMAP §1).
   - On macOS, use `/usr/bin/time -l CMD` and read "instructions retired"
     and "peak memory footprint". On Linux, use `perf stat -e instructions`
     where available.
2. **Same machine, same day, before and after.** Record the commit, SBCL
   version, machine and date. Never compare with numbers from another
   machine.
3. **Report the median of at least 5 runs** for start-up and microbenchmarks,
   and the spread.
4. **Compare with the reference implementations** when the claim is
   relative: `chez`/`petite`, `guile`, `racket`/`raco exe`.
5. **No parallel load while measuring.** Do not run suites at the same
   time.

## Benchmarks
- r7rs-benchmarks:
  - `bench/run.sh` (QuasiScheme, all), `bench/run.sh quasischeme -- ctak fibc`,
    `bench/run.sh modes` (every mode),
    `bench/run.sh quasischeme chez-akku guile -- fib tak`.
  - Tables: `python3 bench/summarize.py`.
  - README numbers are regenerated, never edited:
    `python3 bench/summarize.py --update bench/RESULTS.md README.md`.
  - `BENCH_TEMP` sets where programs are assembled. Point it at your
    scratch directory.
- **Gate set:** the geomean of all 57, plus `ctak`, `fibc`, `ack`,
  `divrec`, `browse`, `lattice`, `matrix`, `conform` and `quicksort`
  individually, in full and escape-only continuations.
- **Continuation microbenchmarks:** `bench/cont/` (planned in QSM-2.1).

## Start-up and size
- **Build an executable:**
  `bin/quasischeme --compile hello.scm -o hello [--chez|--guile|--racket]`.
  The mode flag goes last.
- **Size:** `ls -l` in bytes. Compressed reference:
  `zstd -q -9 -c FILE | wc -c`.
- **Start-up:** run the executable 5 times with `/usr/bin/time -l`.
- **Baseline (2026-11-12):**

  | Program | Size | Start-up |
  |---|---|---|
  | R7RS hello | 159,866,624 B (zstd 32,197,180) | 1.34 s |
  | Chez hello | 160,063,264 B | 1.31 s |
  | Guile hello | 159,932,168 B | 1.77 s |
  | `racket/base` hello | 476,650,440 B (zstd 77,471,091) | 2.21 s |
  | `raco exe` (Racket 9.3), same program | 56,304,949 B | 0.43 s |

- **Planned:** `scripts/measure-exe` (QSM-1.1) automates all of this into
  `bench/SIZES.md`.

## Recording evidence
- Put raw outputs in `notes/<ID>/` and a before/after table in the
  handoff note, with columns: benchmark, before, after, ratio, unit
  (instructions or ms).
- Update the mode document's numbers (`docs/optimizations.md`,
  `docs/continuations.md`, `docs/executables.md`) with a date.

## Pitfalls
- **Racket's first run** after a rebuild fills its cache and saves a core
  (minutes cold). Measure warm runs, and report the cold time separately.
- **`bench/` reports the benchmark's own loop time.** Compile time is
  excluded but still counts against `CPU_LIMIT`.
- **The arm64 VOP layer** is on locally and off on CI (x86-64). State
  which was measured.
- **Compressed executables** trade start-up time for size. Always report
  both.
