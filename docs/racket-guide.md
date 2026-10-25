# Racket on Quasischeme: a user's guide

This guide is for people who write Racket. It shows how to run your
programs with `quasischeme --racket`, what the first run costs and why,
and what to set for speed. docs/racket.md covers how Racket mode is
built and where it stands. docs/racket-linklet-compiler.md covers the
compiler. docs/configuration.md lists every setting.

In short: Racket mode runs Racket 9.3's own expander and Racket's own
collections (`racket/base`, `racket`, `racket/match`, Typed Racket, ...).
It compiles their linklets, Racket's compiled form, to Lisp, and SBCL
compiles that to machine code. Racket's primitives (structs, ports,
hash tables, threads, futures, places, continuations and marks,
parameters, the printer, the FFI) are written natively in Lisp.

## What you need

- **Racket's source, pinned.** `sh utils/racket/setup.sh` makes a
  shallow clone of racket/racket at tag v9.3 into
  `build/external/racket/` (gitignored). With a C compiler it also
  builds rktio, Racket's OS layer, which the REPL's terminal uses.
  `sh utils/racket/setup.sh --typed` also fetches Typed Racket's
  packages. `QUASISCHEME_RACKET_SOURCE` names another source tree.
- **A `racket` of the same version, optional.** It is used only to
  extract Racket's layers (`utils/racket/extract.sh`). Without it, the
  expander is read from the copy in Racket BC's `startup.inc`.
- **`bin/quasischeme`,** built by `make -C contrib/cli`.

To run it as `racket`, make a link named exactly `racket`, in a
directory of its own so that it doesn't hide the real one:

```sh
mkdir -p ~/qs-bin && ln -s "$PWD/bin/quasischeme" ~/qs-bin/racket
```

Under any other name, give `--racket` first. Quasischeme's own options
go before it; everything after it is racket's command line.

## Running programs

The command line is racket's (`racket -h`), parsed as Racket CS's
`main.sps` parses it:

```sh
quasischeme --racket hello.rkt               # run a module, then its main submodule
quasischeme --racket -e '(displayln (+ 1 2))'
quasischeme --racket -l racket/base -e '(require racket/list) (last (list 1 2 3))'
quasischeme --racket -t lib.rkt -e '(f 10)'
quasischeme --racket -I typed/racket          # Typed Racket's REPL
quasischeme --racket                          # the REPL
```

`-e`, `-f`, `-t`, `-l`, `-r`, `-u`, `-m`, `-i`, `-n`, `-I`, `-X`, `-S`,
`-A` and the rest work as in racket. Combined switches (`-ifve file
expr`) work too. A few switches are accepted and do nothing (`-d`, `-b`,
`-j`, the logging levels), and `-k` and the cross-compiling switches
are errors (docs/racket.md, "The command line").

### Collections and packages

Modules come from the collections in Racket's source tree
(`build/external/racket/racket/collects` and its `pkgs`). To add your own
collections:

```sh
quasischeme --racket -S "$HOME/src/my-collects" -e '(require mycoll)'
```

`-S DIR` adds DIR to the collection search path, as in racket.
`PLTCOLLECTS` replaces the default list entirely (unlike racket, a
trailing `:` doesn't keep it), so name the source tree's
`racket/collects` in it too if you use it. Typed Racket and its dependencies come from
`sh utils/racket/packages.sh`, and `packages.sh PACKAGE...` fetches
other packages the same way, from their repositories or the package
catalog. The packages installed into a real Racket (`raco pkg install`)
are not used: Racket mode's add-on directory is
`$XDG_DATA_HOME/racket/` (`-A` to change it).

## The REPL

`quasischeme --racket` with no file starts Racket's own REPL, the one
`racket` gives. It prints the banner, loads `racket/init` and
`racket/interactive`, and runs Racket's `read-eval-print-loop`. At a
terminal, Quasischeme's line editor supplies the lines, with history,
and completion from the namespace's names. Errors print as racket
prints them and return to the prompt.

## The first run, and the caches

Racket mode compiles each linklet with SBCL the first time it meets it,
and keeps the machine code. Three things make later runs fast:

1. **`.zo` files**, written for each module file the first time it is
   compiled, under the Racket cache (Racket's `current-compiled-file-roots`),
   never next to your sources or into Racket's tree. A `.zo` carries its
   linklets' cache keys.
2. **The linklet cache:** each compiled linklet as an SBCL fasl, under
   `~/.cache/quasischeme/racket/` (beside the library cache;
   `QUASISCHEME_LIBRARY_CACHE_DIRECTORY` moves both).
3. **A saved image:** the first run saves an executable with the
   expander instantiated and `racket/base` and `racket` declared and
   instantiated (190 MB, in the Racket cache, kept only for the current
   build of `bin/quasischeme`). Each run after that execs it.
   `QUASISCHEME_RACKET_PRELOAD` names the modules it holds (default
   `racket/base racket`); add the ones your programs use.

What that means in time (M4, 2026-10-25, warm cache):

| | Quasischeme | `racket` 9.3 CS |
|---|---|---|
| `#lang racket/base` hello | 0.20 s | 0.13 s |
| `#lang racket` hello (2026-10-21, instructions) | 1.1G | 1.8G |

The first run is slow. A cold `#lang racket/base` takes about a minute,
and a first `#lang racket` about 280 s, most of it SBCL compiling the
7,400 linklets the expander runs. One run fills the caches for every
later one. To fill them ahead of time, run each entry point once
(`quasischeme --racket -e '(require (file "app.rkt"))'` compiles without
running `main`). `raco` itself isn't available: its `make` command is in a
package the source tree doesn't hold.

`QUASISCHEME_RACKET_INTERPRET=1` interprets the linklets the expander
compiles in `'(quick)` mode, as Racket CS does, instead of compiling
them. It is slower for now (docs/racket.md, "Future work").

## Speed

Run time, against upstream Racket 9.3 CS on the same programs (the
r7rs-benchmarks' Racket versions), by instructions retired
(docs/optimizations.md):

| benchmark | Quasischeme / racket |
|---|---|
| fib | 1.22 |
| tak | 1.13 |
| nqueens | 1.23 |
| destruc | 1.28 |
| peval | 1.55 |
| gcbench | 1.68 |
| parsing | 1.80 |
| lattice | 2.16 |
| ray, simplex (2026-10-21) | 0.97, 0.86 |

Racket mode keeps full first-class continuations, as Racket does. A call
of an unknown procedure is a point where one may be captured, and it
costs a frame. What makes it fast:

- **Known structs.** A struct type defined in the shape `struct`
  expands to (no guard) gets a constructor, predicate, accessors and
  mutators the compiler knows, which can't capture a continuation. A
  plain instance is one SBCL object.
- **Safe imports.** Each compiled linklet records which of its exports
  can't capture. A linklet compiled against it calls them without a
  frame. Racket's collections give about 1,170 such exports.
- **Inlining.** A small top-level procedure, never assigned, is inlined
  where it is called, as Racket CS's schemify does.
- **Hash tables.** `hash-ref`, `hash-set!` and the like are not capture
  sites.
- **The optimizer and the fast layer** that every mode has (cp0,
  cptypes, the VOPs, deep recursion without the return-address stack;
  docs/optimizations.md).

To make your own code faster:

- Define data with `struct` and no guard, so the compiler knows its
  procedures.
- Prefer `define`d procedures to procedures stored in mutable
  variables: a procedure that is never `set!` can be inlined and called
  directly.
- Keep long-running work in a module, which is compiled once into the
  cache, not in `-e` expressions, which are compiled every run.

## Threads, futures and places

Racket threads are SBCL threads that hold a baton in turn, preempted
every 10 ms, so they behave as Racket's green threads do. Futures run on
lparallel's workers and block at a future-unsafe operation until
touched, as in Racket CS. Places are SBCL threads, each with its own
scheduler, parameters and namespace. A parallel thread pool
(`make-parallel-thread-pool`, `thread #:pool`) runs threads on cores at
once. Each thread's control stack is `QUASISCHEME_THREAD_STACK_SIZE`
megabytes (32 by default; at most 64 in Racket mode).

## Racket and Common Lisp

Racket code can call Lisp: `(require (prefix-in cl: cl/common-lisp))`.
Lisp can require Racket modules: `(qr:require (only-in racket/string
string-join))`. docs/interop.md, section 6b, has the details.

## Executables

`quasischeme --compile app.rkt -o app --racket` (the mode flag last)
makes a stand-alone executable with the expander instantiated and the
program's modules declared. It starts in about 0.15 s for `#lang racket`
(docs/executables.md).

## Settings at a glance

| variable | default | effect |
|---|---|---|
| `PLTCOLLECTS` | the source tree's `racket/collects` | the collection directories, replacing the default |
| `QUASISCHEME_RACKET_SOURCE` | `build/external/racket/` | Racket's source tree |
| `QUASISCHEME_RACKET_STRATEGY` | `linklet` | `linklet`; `cs` and `hybrid` are not working yet |
| `QUASISCHEME_RACKET_CORE` | on | `0`/`no`/`off`: no saved image |
| `QUASISCHEME_RACKET_PRELOAD` | `racket/base racket` | modules held in the saved image |
| `QUASISCHEME_RACKET_ZO` | on | `0`/`no`/`off`: write no `.zo` files |
| `QUASISCHEME_RACKET_SAFE_IMPORTS` | on | `0`: no cross-linklet capture analysis |
| `QUASISCHEME_RACKET_INTERPRET` | off | `1`: interpret the expander's quick linklets |
| `QUASISCHEME_RACKET_REGEXP` | Racket's regexp layer | `native`: the older cl-ppcre regexps |
| `PLT_ERROR_PRINT_CONTEXT_LENGTH` | 16 | `error-print-context-length` |
| `QUASISCHEME_RACKET_STATS` | off | print linklet lowering and compile times at exit |
| `QUASISCHEME_RACKET_BACKTRACE` | off | print the Lisp backtrace of internal errors |

The settings shared by all modes are in docs/configuration.md.
