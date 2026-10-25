# Guile on Quasischeme: a user's guide

This guide is for people who already write GNU Guile. It shows how to
run your code with `quasischeme --guile`. It also shows how to reuse the
bytecode Guile has already compiled for you, and what to set to get the
most speed. docs/guile.md covers how Guile mode is built and where it
stands against Guile's own test suite. docs/guile-vm.md covers the
bytecode VM in depth. docs/configuration.md lists every setting.

In short: Guile mode runs Guile 3.0's own `boot-9.scm`, its own expander
and its own modules (`(ice-9 match)`, `(srfi srfi-1)`, GOOPS, the web
modules, ...). It runs them on a libguile written in Common Lisp, and
compiles them with SBCL to native machine code. Your programs, modules
and command lines are Guile's, and so are the errors you see.

## What you need

- **Guile 3.0, installed.** Quasischeme reads Guile's Scheme sources
  (`ice-9/boot-9.scm` and the rest) from the installation. It looks
  where `guile` says they are (`%package-data-dir`), then in the usual
  prefixes. Set `GUILE_SOURCE_DIR` to the directory that holds
  `ice-9/boot-9.scm` to choose another. Guile's sources are read, never
  copied or changed.
- **`bin/quasischeme`,** built by `make -C contrib/cli`. Guile is booted
  into it when it is built, so `--guile` starts in a fraction of a
  second.

To run it as `guile`, make a link named exactly `guile`, in a directory
of its own so that it doesn't hide the real one. The program looks at
the name it was run by.

```sh
mkdir -p ~/qs-bin && ln -s "$PWD/bin/quasischeme" ~/qs-bin/guile
~/qs-bin/guile -c '(display (version))'
```

Run under any other name, give `--guile` first. Quasischeme's own options
go before `--guile`; everything after it is Guile's command line.

## Running programs

Everything `guile --help` lists works the same way, because Guile's own
`(ice-9 command-line)` parses it.

```sh
quasischeme --guile hello.scm                 # a script
quasischeme --guile -c '(display (+ 1 2))'    # an expression
quasischeme --guile -L src -e main -s app.scm arg1 arg2
quasischeme --guile -l prelude.scm            # load, then the REPL
quasischeme --guile                           # the REPL
```

A script runs in `(guile-user)`, as with `guile`.
`(program-arguments)` and `(command-line)` are what Guile gives.
`(exit n)` exits with `n`, and an uncaught error exits with 1.

Modules are found on `%load-path`, as in Guile:

```sh
GUILE_LOAD_PATH=$HOME/src/mylib quasischeme --guile -c '(use-modules (mylib util))'
```

`GUILE_LOAD_PATH`, `GUILE_LOAD_COMPILED_PATH`, `-L`, `-C`, `-x` and
`%load-path` work as in Guile.

## The REPL

`quasischeme --guile` with no script starts Guile's own REPL,
`(system repl repl)`. It reads lines from Quasischeme's line editor, which
has history and completion. Guile's meta-commands work (`,help`, `,describe`,
`,time`, `,language elisp`, ...), and two more show what the native
compiler did:

```
scheme@(guile-user)> (define (sq x) (* x x))
scheme@(guile-user)> ,lisp sq       ; the Lisp it was translated to
scheme@(guile-user)> ,asm sq        ; the machine code SBCL made of it
```

`,language elisp` switches to Emacs Lisp, Guile's elisp front end
running unmodified.

## Speed: two ways to run Guile code

Quasischeme runs Guile code in one of two ways:

1. **Natively** (the default). Guile's expander makes Tree-IL from your
   source. Quasischeme translates the Tree-IL to Lisp, and SBCL compiles
   that to machine code. Modules compiled this way are cached as fasls
   under `~/.cache/quasischeme/guile/`, so the second run loads them
   with nothing to compile.
2. **From bytecode.** Guile's own compiler (`guild compile`,
   auto-compilation) makes `.go` files. Quasischeme loads those ELF
   images and runs their bytecode on its own implementation of Guile's
   VM. Each hot region is translated to Lisp and compiled by SBCL.

### Guile's bytecode, faster than Guile

The bytecode VM's default backend on arm64 is called `vop`. It
compiles the hot bytecode regions to machine code with
instruction-specific VOPs (SBCL's code templates). It runs Guile's own
`.go` files faster than Guile 3.0.11 does, with Guile's VM or with its
JIT. The table is `sh tests/guile-vm/bench.sh`, on an M4, 2026-10-25,
best of 3. It runs one `.go` file, compiled by the installed `guild`,
four ways:

| milliseconds | Quasischeme, `vop` | Quasischeme, `jit` | Guile 3.0.11, VM | Guile 3.0.11, JIT |
|---|---|---|---|---|
| fib 30 | **41** | 107 | 103 | 106 |
| loop 10^6 | **4.1** | 16.5 | 16.9 | 19.0 |
| tak 24 16 8 | **39** | 79 | 86 | 92 |
| vector sum 10^6 | **14** | 44 | 45 | 45 |
| cons 10^6 | **8.1** | 30 | 26 | 26 |

That is 2.2 to 4.6 times as fast as Guile's own JIT, on Guile's own
bytecode. The `jit` column is Quasischeme's portable backend, used where
`vop` isn't available (SBCL on other machines). It is about as fast as
Guile.

Compiling the source natively is faster still: about 1.5 to 5 times as
fast as `vop` on the r7rs-benchmarks (docs/guile.md, "Native code or
bytecode"). Use bytecode when you already have it and don't want to
compile anything. Use native code for the code you run most.

### Using the bytecode you already have

If you use Guile a lot, you already have plenty of compiled `.go` files.
Guile auto-compiles every module and script it loads, and keeps them in
`~/.cache/guile/ccache/3.0-LE-8-4.7/` (the name holds Guile's version
and its bytecode's). You may also have `.go` files installed with your
packages, on `GUILE_LOAD_COMPILED_PATH`. Quasischeme can load them as
they are, with nothing compiled, by setting `QUASISCHEME_GUILE_GO`:

| `QUASISCHEME_GUILE_GO` | loads from `.go` files, on the VM |
|---|---|
| unset (the default) | nothing: everything is compiled natively (and cached) |
| `user` | your modules and scripts that have a fresh `.go` file |
| `guile` | Guile's own modules, from the installed Guile's `.go` files |
| `all` (or `1`) | both |

The words combine with commas (`user,guile`). For your files, the
lookup is Guile's own:

1. `NAME.go` in each directory of `%load-compiled-path`
   (`GUILE_LOAD_COMPILED_PATH`, then `-C` directories);
2. then the file Guile's auto-compilation would have written:
   `%compile-fallback-path` (asked of the installed `guile` once:
   `$XDG_CACHE_HOME/guile/ccache/...`, or `~/.cache/guile/ccache/...`)
   followed by the source's full path and `.go`.

A `.go` file is used only if it is at least as new as its source, as
Guile does. A stale one is ignored, and the source is compiled natively
instead. A module with no `.go` file anywhere is compiled natively, as
always.

A worked example, with a module of your own:

```sh
mkdir -p src/demo
cat > src/demo/fib.scm <<'EOF'
(define-module (demo fib)
  #:use-module (srfi srfi-1)
  #:export (fib fib-sum))
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(define (fib-sum k) (fold + 0 (map fib (iota k))))
EOF
echo '(use-modules (demo fib)) (display (fib-sum 25)) (newline)' > main.scm

guile -L src main.scm                         # Guile auto-compiles into its ccache
QUASISCHEME_GUILE_GO=user quasischeme --guile -L src main.scm
# (demo fib) and main.scm load from Guile's ccache, on the VM
```

Or compile ahead of time with `guild` and point
`GUILE_LOAD_COMPILED_PATH` at the output, as you would for an installed
package:

```sh
guild compile -L src -o build/go/demo/fib.go src/demo/fib.scm
GUILE_LOAD_COMPILED_PATH=$PWD/build/go QUASISCHEME_GUILE_GO=user \
  quasischeme --guile -L src main.scm
```

You can also load one compiled file directly, from Scheme:

```scheme
(load-compiled "build/go/demo/fib.go")
```

What it costs: the first `.go` file a process loads asks the installed
`guile` for two tables (the VM's intrinsics, and the ccache's
location), about 0.3 to 0.4 s in all. A `case` on symbols in compiled
code asks it for each symbol's hash, once per symbol. Loading many of
Guile's own modules from `.go` files is slower than from Quasischeme's
native cache: 400-530 ms for 19 modules, against 57 ms. That is why
`guile` isn't the default. For your own modules, bytecode saves the
native compile on the first run. On later runs the native cache is
about as fast to load, and its code runs faster.

### Choosing the bytecode backend

`QUASISCHEME_GUILE_VM_BACKEND` chooses how bytecode runs:

| backend | what it does |
|---|---|
| `vop` | the default on SBCL/arm64: hot regions compiled with Quasischeme's VOPs (the table above) |
| `jit` | the default elsewhere: hot regions translated to portable Lisp and compiled |
| `aot` | every region of an image translated when it loads, and kept as a fasl in the cache |
| `interpret` | the bytecode interpreter alone, the reference |

`QUASISCHEME_GUILE_JIT_THRESHOLD` (default 20) is how many jumps to an
instruction make its region compiled. `0` compiles everything that runs.
`QUASISCHEME_GUILE_JIT=0` is the same as `interpret`.

### `compile` at run time

Guile's `compile` procedure, with `#:to 'value`, goes through Quasischeme's
native compiler by default. `QUASISCHEME_GUILE_COMPILER` changes that:

| value | `compile` to `value` |
|---|---|
| `native` (default) | Tree-IL straight to native code |
| `vm` | Guile's compiler, loaded from the installed `.go` files, makes bytecode for the VM |
| `vm-source` | Guile's compiler, compiled from its sources natively, makes bytecode |

## Speed tips for native code

- **Keep the cache on.** `QUASISCHEME_GUILE_CACHE=0` turns off the
  compiled-module cache, and every run then compiles every module
  again. Twelve large modules take 49 s to compile and 6 s to load
  from the cache. The cache lives under `~/.cache/quasischeme/guile/`
  (`QUASISCHEME_GUILE_CACHE_DIRECTORY` to move it), and is keyed by
  each file, its date and the Quasischeme build.
- **Put hot code in modules.** A module is compiled once into the
  cache. Top-level forms of a script loaded with `load` are compiled as
  they are read, every run.
- **Root primitives are open-coded.** `+`, `<`, `car`, `vector-ref` and
  the like compile in line when they are the `(guile)` module's,
  as Guile's `resolve-primitives` pass does. A module that defines its own `+`
  keeps it.
- **Calls through top-level variables** cost a little more than in
  `--r7rs`, because Guile allows any module variable to be redefined. A
  procedure that calls itself by name is compiled with a fast path that
  checks the variable is unchanged (docs/guile.md, "Speed").
- **Executables.** `quasischeme --compile app.scm -o app --guile` (the mode flag last) makes a
  stand-alone executable. Its modules are compiled into it, and it
  starts in about 0.05 s (docs/executables.md).

## Guile and Common Lisp

Guile code can call Lisp: `(use-modules ((cl common-lisp) #:prefix cl:))`
makes Lisp's functions procedures and its macros syntax. Lisp can load
Guile modules: `(qg:use-modules ((srfi srfi-1) :select (fold)))`.
docs/interop.md, section 6a, has the details. The REPL's `,lisp` shows
the Lisp any procedure became.

## Embedding: libguile

C programs that link against libguile (`scm_init_guile`, `scm_c_eval_string`,
...) can link against Quasischeme's libguile instead, which is
ABI-compatible with Guile 3.0.11. LilyPond typesets scores on it.
docs/libguile.md has the details.

## Differences you may meet

- Sockets are partly done. Guile's `(ice-9 threads)`, ports, `(system
  foreign)`, GOOPS and regular expressions are all there.
- On macOS, `regcomp` rejects an empty alternative, `(|x)`, which glibc
  accepts. Such a pattern becomes `(x)?`.
- Bytecode instructions that only libguile's own generated trampolines
  use (`capture-continuation`, `subr-call`, ...) have no handler. No
  `.go` file Guile installs uses them.
- docs/guile.md, "Differences from Guile that remain", has the rest.

## Settings at a glance

| variable | default | effect |
|---|---|---|
| `GUILE_LOAD_PATH`, `GUILE_LOAD_COMPILED_PATH` | | as in Guile |
| `GUILE_SOURCE_DIR` | found from `guile` | where Guile's Scheme sources are |
| `QUASISCHEME_GUILE_GO` | unset | which modules load from `.go` files (above) |
| `QUASISCHEME_GUILE_VM_BACKEND` | `vop` on arm64, else `jit` | how bytecode runs |
| `QUASISCHEME_GUILE_JIT_THRESHOLD` | 20 | jumps before a region is compiled |
| `QUASISCHEME_GUILE_JIT` | on | `0`: interpret bytecode |
| `QUASISCHEME_GUILE_COMPILER` | `native` | what `compile` to `value` uses |
| `QUASISCHEME_GUILE_CACHE` | on | `0`/`no`/`off`: no compiled-module cache |
| `QUASISCHEME_GUILE_CACHE_DIRECTORY` | `~/.cache/quasischeme/guile/` | the cache's directory |
| `QUASISCHEME_GUILE_TRACE_THROWS` | off | print Guile throws: `1`, `backtrace`, or `backtrace:key,key` |

The settings shared by all modes (optimization level, threads' stacks,
the fast layer) are in docs/configuration.md.
