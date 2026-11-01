# Results

Apple M4 MacBook Air (4 performance and 6 efficiency cores), macOS,
SBCL 2.6.9. Single runs of `r7rs-benchmarks` with its standard inputs,
one implementation at a time. Times are in seconds, of each benchmark's
own loop: Quasischeme's expansion and SBCL compilation are not
included, nor are other implementations' compile steps. Lower is
better. Quasischeme runs with full, re-entrant continuations, the
default; escape-only mode is not used for these figures.

The tables between `<!-- bench ... -->` markers are generated from the
local `r7rs-benchmarks/results.*` files: after a run, regenerate them
with

```sh
python3 bench/summarize.py --update bench/RESULTS.md README.md
```

Quasischeme's columns (R7RS, `--guile`, `--racket`) and Racket's are
from 2026-10-31. Chez, Gauche and Chibi are from 2026-10-03, and Guile
from 2026-10-23; their versions have not changed since.

## Against Chez Scheme

Chez runs with Akku's `akku-r7rs` libraries at `--optimize-level 2`.
Racket runs the programs as `racket/base` modules with a prelude of the
R7RS names they use (`src/QuasischemeRacket-prelude.scm`), as
Quasischeme's `--racket` does.

<!-- bench summary ChezAkku Quasischeme RacketBase Guile GaucheLocal Chibi -->
| implementation | version | geometric mean vs Chez Scheme | completed | ≤ 1× | ≤ 1.5× | ≤ 2× |
|---|---|---:|---:|---:|---:|---:|
| Quasischeme | 1.0 | 0.96× | 57/57 | 23 | 46 | 52 |
| Racket | 9.3 | 1.17× | 57/57 | 28 | 47 | 49 |
| Guile | 3.0.11 | 2.78× | 56/57 | 4 | 8 | 17 |
| Gauche | 0.9.15 | 9.15× | 57/57 | 2 | 5 | 5 |
| Chibi | 0.12.0 | 35.68× | 49/57 | 0 | 0 | 1 |
<!-- /bench -->

## Each mode against its own system

Quasischeme's Guile and Racket modes run the same programs as Guile
3.0.11 and Racket CS do, and are measured against them; R7RS mode is
measured against Chez.

<!-- bench pairs Quasischeme/ChezAkku QuasischemeGuile/Guile QuasischemeRacket/RacketBase -->
| | geometric mean | faster on | worst ratios |
|---|---:|---:|---|
| Quasischeme vs Chez Scheme | 0.96× | 23 of 57 | scheme 3.0×, ctak 3.0×, fibc 2.8×, matrix 2.2×, browse 2.1× |
| Quasischeme `--guile` vs Guile | 0.58× | 43 of 56 | string 5.8×, pi 2.5×, slatex 2.1×, read1 1.9×, compiler 1.8× |
| Quasischeme `--racket` vs Racket | 1.03× | 24 of 57 | matrix 3.0×, scheme 2.6×, conform 2.5×, compiler 2.4×, gcbench 2.0× |
<!-- /bench -->

Racket (`racket prog.rkt`) compiles each program as it loads it, Guile
runs programs compiled with `guild compile -O3`; either way the
compilation is outside the timed loop.

## All benchmarks

<!-- bench table ChezAkku Quasischeme RacketBase QuasischemeRacket Guile QuasischemeGuile GaucheLocal Chibi -->
| benchmark | Chez Scheme | Quasischeme | Racket | Quasischeme `--racket` | Guile | Quasischeme `--guile` | Gauche | Chibi |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ack | 1.37 | 1.38 (1.01×) | 1.77 (1.29×) | 1.44 (1.05×) | 5.61 (4.09×) | 1.42 (1.04×) | 42.15 (30.75×) | 23.25 (16.96×) |
| array1 | 2.71 | 2.37 (0.87×) | 2.44 (0.90×) | 1.30 (0.48×) | 4.03 (1.48×) | 2.60 (0.96×) | 13.85 (5.10×) | 21.55 (7.94×) |
| browse | 0.65 | 1.36 (2.10×) | 1.09 (1.69×) | 1.44 (2.23×) | 2.27 (3.53×) | 1.40 (2.17×) | 10.87 (16.86×) | crashed |
| bv2string | 0.56 | 0.75 (1.34×) | 0.61 (1.08×) | 1.16 (2.06×) | 0.90 (1.61×) | 0.56 (0.99×) | 5.24 (9.33×) | 3.62 (6.45×) |
| cat | 1.56 | 1.41 (0.90×) | 5.22 (3.34×) | 2.35 (1.50×) | 8.97 (5.73×) | 9.92 (6.34×) | 7.22 (4.61×) | 25.31 (16.18×) |
| chudnovsky | 0.12 | 0.05 (0.41×) | 0.12 (0.94×) | 0.05 (0.41×) | 0.07 (0.54×) | 0.07 (0.57×) | 0.48 (3.90×) | 60.80 (495.02×) |
| compiler | 0.89 | 1.27 (1.43×) | 0.88 (0.99×) | 2.10 (2.36×) | 1.59 (1.79×) | 2.91 (3.27×) | 13.47 (15.12×) | 43.96 (49.36×) |
| conform | 1.14 | 1.73 (1.52×) | 1.81 (1.60×) | 4.61 (4.06×) | 3.61 (3.17×) | 4.23 (3.72×) | 22.90 (20.15×) | 59.70 (52.53×) |
| cpstak | 1.29 | 2.55 (1.97×) | 1.61 (1.24×) | 2.23 (1.72×) | 7.77 (6.00×) | 3.35 (2.59×) | 42.30 (32.68×) | 90.09 (69.59×) |
| ctak | 0.39 | 1.17 (3.00×) | 1.03 (2.64×) | 1.12 (2.89×) | 39.82 (102.33×) | 1.24 (3.20×) | 8.49 (21.82×) | 234.71 (603.19×) |
| deriv | 0.51 | 0.80 (1.57×) | 0.58 (1.15×) | 0.91 (1.79×) | 3.41 (6.73×) | 1.30 (2.56×) | 13.83 (27.30×) | 39.76 (78.46×) |
| destruc | 0.91 | 1.13 (1.24×) | 0.95 (1.05×) | 1.32 (1.45×) | 1.58 (1.74×) | 1.47 (1.62×) | 14.27 (15.72×) | 35.32 (38.90×) |
| diviter | 0.93 | 1.06 (1.15×) | 0.86 (0.93×) | 1.10 (1.18×) | 3.24 (3.49×) | 1.36 (1.47×) | 8.64 (9.33×) | 21.53 (23.25×) |
| divrec | 1.02 | 1.75 (1.70×) | 1.06 (1.04×) | 1.84 (1.80×) | 5.24 (5.11×) | 1.86 (1.81×) | 10.54 (10.29×) | 21.05 (20.54×) |
| dynamic | 1.56 | 1.62 (1.04×) | 4.42 (2.84×) | 2.61 (1.68×) | 3.75 (2.41×) | 5.48 (3.53×) | 9.62 (6.18×) | 97.16 (62.47×) |
| earley | 2.20 | 1.07 (0.48×) | 2.14 (0.97×) | 1.06 (0.48×) | 4.41 (2.00×) | 1.12 (0.51×) | 6.43 (2.92×) | crashed |
| equal | 0.45 | 0.49 (1.09×) | 0.99 (2.20×) | 0.70 (1.55×) | crashed | 0.48 (1.07×) | 6.12 (13.61×) | 17.63 (39.20×) |
| fft | 1.41 | 0.77 (0.54×) | 1.25 (0.89×) | 0.83 (0.59×) | 2.87 (2.04×) | 0.83 (0.59×) | 4.94 (3.50×) | 23.29 (16.52×) |
| fib | 1.75 | 2.11 (1.21×) | 1.78 (1.01×) | 2.22 (1.26×) | 4.72 (2.69×) | 2.07 (1.18×) | 25.10 (14.32×) | 27.82 (15.87×) |
| fibc | 0.26 | 0.74 (2.83×) | 0.73 (2.77×) | 0.75 (2.84×) | 25.49 (97.22×) | 1.37 (5.24×) | 8.00 (30.50×) | 49.01 (186.93×) |
| fibfp | 1.25 | 1.12 (0.89×) | 1.22 (0.97×) | 1.06 (0.85×) | 6.70 (5.34×) | 1.12 (0.89×) | 5.53 (4.41×) | 16.34 (13.02×) |
| gcbench | 0.46 | 0.45 (0.99×) | 0.42 (0.91×) | 0.85 (1.86×) | 1.08 (2.36×) | 0.52 (1.13×) | 11.41 (24.98×) | crashed |
| graphs | 1.19 | 1.22 (1.03×) | 1.28 (1.08×) | 2.14 (1.80×) | 6.54 (5.50×) | 2.13 (1.79×) | 49.79 (41.89×) | crashed |
| lattice | 1.72 | 3.02 (1.76×) | 1.68 (0.98×) | 3.27 (1.90×) | 6.22 (3.63×) | 3.53 (2.06×) | 35.43 (20.66×) | crashed |
| matrix | 0.60 | 1.34 (2.22×) | 0.67 (1.11×) | 2.03 (3.37×) | 3.08 (5.11×) | 1.61 (2.67×) | 18.94 (31.39×) | 85.53 (141.77×) |
| maze | 0.45 | 0.55 (1.23×) | 0.44 (0.97×) | 0.86 (1.91×) | 1.51 (3.36×) | 1.39 (3.08×) | 11.16 (24.85×) | 33.43 (74.41×) |
| mazefun | 1.14 | 1.29 (1.13×) | 1.07 (0.94×) | 1.25 (1.10×) | 3.42 (2.99×) | 1.86 (1.63×) | 21.96 (19.21×) | 43.22 (37.81×) |
| mbrot | 4.91 | 0.44 (0.09×) | 3.57 (0.73×) | 3.08 (0.63×) | 12.14 (2.47×) | 3.23 (0.66×) | 10.51 (2.14×) | 76.44 (15.57×) |
| mbrotZ | 2.50 | 3.41 (1.36×) | 2.22 (0.89×) | 3.44 (1.38×) | 10.35 (4.13×) | 3.65 (1.46×) | 15.27 (6.10×) | 164.98 (65.91×) |
| mperm | 5.82 | 2.69 (0.46×) | 5.61 (0.96×) | 2.21 (0.38×) | 6.15 (1.06×) | 2.22 (0.38×) | 16.70 (2.87×) | 74.09 (12.73×) |
| nboyer | 1.18 | 0.92 (0.78×) | 1.01 (0.85×) | 0.88 (0.74×) | 1.66 (1.41×) | 0.95 (0.80×) | 10.35 (8.76×) | 13.64 (11.55×) |
| nqueens | 3.50 | 4.20 (1.20×) | 3.00 (0.86×) | 4.26 (1.22×) | 5.80 (1.66×) | 4.32 (1.23×) | 39.62 (11.32×) | 633.75 (181.12×) |
| ntakl | 1.54 | 1.15 (0.75×) | 2.00 (1.30×) | 1.28 (0.83×) | 2.94 (1.91×) | 2.01 (1.30×) | 35.92 (23.29×) | 39.87 (25.85×) |
| nucleic | 1.02 | 1.19 (1.17×) | 0.93 (0.92×) | 1.26 (1.24×) | 2.92 (2.88×) | 1.99 (1.96×) | 8.71 (8.58×) | 31.63 (31.12×) |
| paraffins | 3.80 | 2.19 (0.58×) | 3.20 (0.84×) | 3.63 (0.95×) | 2.41 (0.63×) | 3.06 (0.80×) | 4.29 (1.13×) | crashed |
| parsing | 1.64 | 1.10 (0.67×) | 1.09 (0.67×) | 2.17 (1.32×) | 4.08 (2.49×) | 2.95 (1.80×) | 67.55 (41.22×) | crashed |
| peval | 1.04 | 1.11 (1.06×) | 1.13 (1.08×) | 1.56 (1.50×) | 3.59 (3.44×) | 2.19 (2.09×) | 21.25 (20.35×) | 70.53 (67.52×) |
| pi | 0.24 | 0.11 (0.45×) | 0.28 (1.19×) | 0.11 (0.45×) | 0.05 (0.20×) | 0.12 (0.50×) | 1.96 (8.23×) | crashed |
| pnpoly | 2.92 | 1.24 (0.42×) | 2.57 (0.88×) | 1.50 (0.51×) | 7.67 (2.62×) | 2.40 (0.82×) | 13.18 (4.51×) | 95.57 (32.71×) |
| primes | 0.52 | 0.54 (1.04×) | 0.43 (0.82×) | 0.55 (1.05×) | 1.68 (3.22×) | 0.61 (1.16×) | 6.90 (13.27×) | 7.68 (14.78×) |
| puzzle | 1.40 | 1.69 (1.21×) | 1.59 (1.14×) | 1.73 (1.24×) | 4.02 (2.87×) | 2.57 (1.84×) | 17.21 (12.32×) | 101.89 (72.94×) |
| quicksort | 2.33 | 3.35 (1.43×) | 2.12 (0.91×) | 4.26 (1.83×) | 4.44 (1.90×) | 3.39 (1.45×) | 21.93 (9.40×) | 157.72 (67.59×) |
| ray | 1.35 | 1.40 (1.04×) | 1.48 (1.10×) | 1.78 (1.32×) | 3.58 (2.66×) | 2.19 (1.63×) | 10.48 (7.79×) | 84.46 (62.77×) |
| read1 | 1.19 | 0.85 (0.72×) | 6.22 (5.22×) | 0.72 (0.61×) | 3.31 (2.78×) | 6.14 (5.15×) | 1.24 (1.04×) | 89.59 (75.20×) |
| sboyer | 0.50 | 0.48 (0.96×) | 0.41 (0.82×) | 0.65 (1.29×) | 1.64 (3.26×) | 0.58 (1.15×) | 9.54 (18.95×) | 13.17 (26.16×) |
| scheme | 1.38 | 4.16 (3.02×) | 1.19 (0.87×) | 3.06 (2.22×) | 5.07 (3.68×) | 3.14 (2.27×) | 16.02 (11.62×) | 45.68 (33.14×) |
| simplex | 1.29 | 1.01 (0.78×) | 1.07 (0.83×) | 1.03 (0.80×) | 3.94 (3.06×) | 2.48 (1.93×) | 19.13 (14.86×) | 72.78 (56.55×) |
| slatex | 5.48 | 7.71 (1.41×) | 5.96 (1.09×) | 7.65 (1.39×) | 10.56 (1.93×) | 22.26 (4.06×) | 11.74 (2.14×) | 53.22 (9.70×) |
| string | 0.74 | 0.58 (0.78×) | 0.96 (1.30×) | 0.50 (0.68×) | 0.10 (0.14×) | 0.58 (0.79×) | 0.46 (0.62×) | 2.91 (3.94×) |
| sum | 1.78 | 1.86 (1.05×) | 2.09 (1.17×) | 2.02 (1.14×) | 2.46 (1.38×) | 1.99 (1.12×) | 20.19 (11.35×) | 33.52 (18.84×) |
| sum1 | 0.82 | 0.40 (0.49×) | 2.55 (3.11×) | 2.96 (3.61×) | 2.67 (3.26×) | 4.81 (5.88×) | 0.64 (0.78×) | 31.87 (38.93×) |
| sumfp | 1.92 | 0.57 (0.30×) | 1.93 (1.01×) | 0.63 (0.33×) | 11.68 (6.10×) | 2.32 (1.21×) | 6.47 (3.38×) | 30.58 (15.97×) |
| tail | 1.71 | 0.34 (0.20×) | 1.68 (0.98×) | 1.05 (0.61×) | 4.00 (2.34×) | 0.98 (0.57×) | 2.42 (1.41×) | 3.39 (1.98×) |
| tak | 0.74 | 1.17 (1.58×) | 0.74 (1.00×) | 1.26 (1.70×) | 2.12 (2.87×) | 1.32 (1.78×) | 11.12 (15.03×) | 25.37 (34.29×) |
| takl | 1.60 | 1.62 (1.01×) | 1.83 (1.14×) | 1.73 (1.08×) | 2.83 (1.77×) | 2.84 (1.77×) | 42.16 (26.29×) | 202.89 (126.54×) |
| triangl | 1.27 | 0.86 (0.68×) | 1.17 (0.92×) | 1.05 (0.83×) | 3.37 (2.66×) | 3.05 (2.41×) | 12.23 (9.64×) | 35.96 (28.35×) |
| wc | 0.87 | 0.91 (1.04×) | 2.62 (3.01×) | 1.49 (1.71×) | 5.40 (6.21×) | 5.72 (6.58×) | 11.34 (13.03×) | 166.40 (191.22×) |
| **geometric mean** | **1.00×** | **0.96×** | **1.17×** | **1.21×** | **2.78×** | **1.59×** | **9.15×** | **35.68×** |
<!-- /bench -->

Reproduce with `bench/run.sh quasischeme quasischeme-guile
quasischeme-racket racket-base chez-akku guile gauche-local chibi`.

## History

Late October 2026, from 1.37× Chez's time (full continuations) to the
figures above: the optimizer's passes after Chez's (`cp0`, `cptypes`
with flonum versions of procedures, `cpletrec`; docs/optimizations.md);
a program's own definitions bound locally rather than as global
locations; `map` and `for-each` on one list open-coded; frame pointers
restored only after calls that need it; smaller thread stacks, so that
a collection has less stack to scrub.

### Early October 2026: what made the difference

From 3.0× Chez's time to 1.44× escape-only (an earlier run on the same
machine, then the first run), in order of effect:

- **Definitions as `letrec`** (src/psyntax.lisp, `definitions-as-letrec`).
  psyntax expands a body's definitions as `letrec*`: variables bound to
  `#f`, then assigned. Assigned and closed over, each was boxed by SBCL,
  and every call to a program's procedure was a `funcall` through the
  box. A variable assigned once to a lambda is now bound by a `letrec`,
  which the translator makes a `labels` function, called directly; one
  that aliases another such procedure or a primitive is replaced by it.
  Big programs, whose procedures would make one code object too big for
  SBCL, get top-level definitions instead (`hoist-definitions`).
- **Inline boolean tests.** core.lisp declared `truep` and `true?` inline
  with `proclaim`, which works only at load time, so every Scheme `if`
  whose test wasn't already a Lisp boolean was a call.
- **`(void)` as a constant**: psyntax's unspecified value, from every
  one-armed `if`, `when`, `unless` and `cond` without `else`, was a call.
- **Inline fixnum and flonum arithmetic** for two-argument `+`, `-` and
  `*` (src/numbers.lisp), like the comparisons'.
- **Primitives open-coded again**: the R6RS layer had replaced `memq`
  and `memv` with closure-calling versions, and R7RS's character
  comparisons with an n-ary wrapper around the built-in n-ary ones;
  `case` on symbols uses `memq`; `map` is no longer kept from being
  open-coded.
- **R7RS records** define procedures of the program's own instead of
  closures from the procedural record API.
- **`equal?`**: a typed first pass, and union-find for big or cyclic
  data.

Biggest gains: `lattice` 23.2 → 2.9 s, `parsing` 11.2 → 1.4 s, `takl`
11.1 → 2.5 s, `wc` 7.5 → 1.1 s, `sum` 8.9 → 2.0 s, `gcbench` 4.7 →
1.0 s, `conform` 9.0 → 2.5 s.

