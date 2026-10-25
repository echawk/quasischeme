# Configuring Quasischeme

Everything Quasischeme reads from its environment, by mode. Settings are
read when a program starts, not when `bin/quasischeme` is built, unless
noted. Command-line options are in `bin/quasischeme --help`. Mode-specific
guides: docs/guile-guide.md, docs/racket-guide.md, docs/chez.md.

Where files go, by default:

| what | where |
|---|---|
| compiled R6RS/R7RS/Chez libraries | `~/.cache/quasischeme/libraries/` (`$XDG_CACHE_HOME` if set) |
| Guile's compiled modules | `~/.cache/quasischeme/guile/` |
| Racket's compiled linklets, `.zo` files, saved image | `~/.cache/quasischeme/racket/` |
| the REPL's history | `~/.local/state/quasischeme/` (`$XDG_STATE_HOME`) |

Each cache is keyed by the build of Quasischeme that wrote it, so a
rebuild from changed sources starts afresh. Old generations are pruned.

## Every mode

| variable | values | default | effect |
|---|---|---|---|
| `QUASISCHEME_LIBRARY_PATH` | directories, `:`-separated | | searched for libraries before `-L` directories |
| `QUASISCHEME_LIBRARY_CACHE` | `0`, `no`, `off` | on | turn off the compiled-library cache |
| `QUASISCHEME_LIBRARY_CACHE_DIRECTORY` | a directory | see above | where compiled libraries (and, beside them, Racket's cache) go |
| `QUASISCHEME_THREAD_STACK_SIZE` | megabytes | 32 | control stack of each thread a program makes (the main thread's is 256 MB) |
| `QUASISCHEME_EVALUATOR` | `compile`, `auto`, `interpret` | `compile` | how top-level forms run: compiled by SBCL, interpreted when they make no closure, or always interpreted (docs/optimizations.md, "Interpreting instead of compiling") |
| `TERM` | `dumb` | | `dumb`: no line editing at the REPL |
| `COLUMNS` | a number | the terminal's | the REPL's width when the terminal won't say |

## Speed

| variable | values | default | effect |
|---|---|---|---|
| `QUASISCHEME_OPTIMIZE` | `0`, `1`, `2` | `2` | the optimizer: `0` off, `1` cp0 only, `2` cp0 and cptypes. A level other than 2 is part of the library cache's key |
| `QUASISCHEME_CPLETREC` | `0` | on | turn off cpletrec |
| `QUASISCHEME_CPDX` | `0`, `closures`, `rest` | both | which closures and rest lists may go on the stack |
| `QUASISCHEME_FAST` | `0` | on | turn off the SBCL fast layer (src/sbcl-vops.lisp: stack vectors in line, deep self-recursion; SBCL 2.6.9 on arm64 only) |
| `QUASISCHEME_SELF_CALLS` | `0` | on | turn off deep self-recursion without the return-address stack (docs/optimizations.md) |
| `QUASISCHEME_SITE_CLOSURES` | `1` | off | a capture site's body as a closure, as before October 2026 |
| `QUASISCHEME_CLOSED_WORLD` | `0` | on | in `--compile` executables, don't bind a script's never-assigned procedures as one `letrec` |

`--continuations=escape`, a command-line option, compiles with
escape-only continuations: a little faster where unknown procedures are
called in loops, but a continuation can't be re-entered after its
`call/cc` returns.

## Guile (`--guile`)

| variable | values | default | effect |
|---|---|---|---|
| `GUILE_LOAD_PATH`, `GUILE_LOAD_COMPILED_PATH` | directories | | as in Guile |
| `GUILE_SOURCE_DIR` | a directory holding `ice-9/boot-9.scm` | found from `guile` | Guile's Scheme sources |
| `QUASISCHEME_GUILE_GO` | `user`, `guile`, `all` (`1`), comma-separated | unset | which modules load from `.go` bytecode, on the VM, rather than compiling their source natively: your own (from `GUILE_LOAD_COMPILED_PATH` and Guile's ccache), Guile's, or both |
| `QUASISCHEME_GUILE_VM_BACKEND` | `vop`, `jit`, `aot`, `interpret` | `vop` on SBCL/arm64, else `jit` | how bytecode runs |
| `QUASISCHEME_GUILE_JIT` | `0` | on | `0`: interpret bytecode |
| `QUASISCHEME_GUILE_JIT_THRESHOLD` | a number | 20 | jumps to an instruction before its region is compiled; `0` compiles all |
| `QUASISCHEME_GUILE_COMPILER` | `native`, `vm`, `vm-source` | `native` | what Guile's `compile` to `value` uses |
| `QUASISCHEME_GUILE_CACHE` | `0`, `no`, `off` | on | turn off the compiled-module cache |
| `QUASISCHEME_GUILE_CACHE_DIRECTORY` | a directory | see above | the compiled-module cache |
| `QUASISCHEME_GUILE_TRACE_THROWS` | `1`, `backtrace`, `backtrace:KEY,...` | off | print Guile throws as they happen |

Embedded libguile (docs/libguile.md): `QUASISCHEME_LIBGUILE`,
`QUASISCHEME_GUILE_CORE`, `QUASISCHEME_LIBSBCL`, `QUASISCHEME_HEAP`
(default 8GB), `GUILE_EXTENSIONS_PATH`, and for debugging
`QUASISCHEME_LIBGUILE_TRACE`, `QUASISCHEME_LIBGUILE_TRACE_AFTER` and
`QUASISCHEME_LIBGUILE_PROFILE`.

## Racket (`--racket`)

| variable | values | default | effect |
|---|---|---|---|
| `PLTCOLLECTS` | directories | the source tree's `racket/collects` | the collection directories, replacing the default |
| `QUASISCHEME_RACKET_SOURCE` | a directory | `build/external/racket/` | Racket's source tree |
| `QUASISCHEME_RACKET_STRATEGY` | `linklet`, `cs`, `hybrid` | `linklet` | only `linklet` runs today |
| `QUASISCHEME_RACKET_CORE` | `0`, `no`, `off` | on | don't save or use the image with the expander instantiated |
| `QUASISCHEME_RACKET_PRELOAD` | module names, space-separated | `racket/base racket` | modules held in that image |
| `QUASISCHEME_RACKET_ZO` | `0`, `no`, `off` | on | write no `.zo` files |
| `QUASISCHEME_RACKET_SAFE_IMPORTS` | `0` | on | no cross-linklet analysis of which imports can't capture |
| `QUASISCHEME_RACKET_INTERPRET` | `1` | off | interpret the expander's quick linklets, as Racket CS does |
| `QUASISCHEME_RACKET_REGEXP` | `native` | Racket's regexp layer | the older cl-ppcre regexps |
| `QUASISCHEME_RKTIO_DIRECTORY` | a directory | `build/external/rktio/` | where librktio is |
| `PLT_ERROR_PRINT_CONTEXT_LENGTH` | a number | 16 | `error-print-context-length` |
| `TMPDIR`, `LC_ALL`, `LC_MESSAGES`, `LANG` | | | `(find-system-path 'temp-dir)`, `system-language+country` |

## Chez (`--chez`)

Chez mode has no settings of its own beyond the library cache's. Its
`(getenv NAME)` reads the environment. docs/chez.md has its options.

## Debugging and measuring

| variable | effect |
|---|---|
| `QUASISCHEME_OPTIMIZE_TRACE=1` | print each core form before and after the optimizer |
| `QUASISCHEME_OPTIMIZE_STATS=1` | print the optimizer's statistics at exit |
| `QUASISCHEME_RACKET_STATS=1` | print linklet lowering and compile times at exit |
| `QUASISCHEME_RACKET_BACKTRACE=1` | print Lisp backtraces of internal errors in Racket mode |
| `QUASISCHEME_RACKET_TRACE_STRUCT=NAME` | a backtrace when the struct type NAME is made |
| `QUASISCHEME_SYMBOL_SWEEP=N` | symbols interned between sweeps of unused ones (default 100000) |

At the REPL, `,lisp EXPR` shows the Lisp an expression or procedure
compiles to, `,asm EXPR` its machine code, and `,time EXPR` its cost.
To profile, load SBCL's profiler from a small ASDF system with
`-l SYSTEM` (docs/racket.md and docs/optimizations.md show how it was
done).
