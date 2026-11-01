#!/usr/bin/env python3
"""Differential testing of Quasischeme's compiler options.

    python3 tests/fuzz/difftest.py [--count N] [--seed S] [--configs a,b,...]
                                   [--keep DIR] [--timeout SECS] [--guile]

Generates random, terminating R7RS programs (typed, so that they never
signal an error) and runs each under several configurations of
bin/quasischeme -- optimizer levels, continuation modes, the optional
passes and code layers, Guile mode -- and, with --guile, under GNU Guile
as an oracle.  Every configuration must print the same thing.  A program
whose outputs differ is shrunk (whole top-level forms, then the printed
expressions, removed while the difference stays) and kept in --keep
(default tests/fuzz/failures/), with each configuration's output.

The programs lean on what has broken before: groups of closures that
refer to each other, made in loops while the collector runs (arm64's
CLOSURE-INIT without a card mark), escapes and re-entries through
call/cc, set! of captured variables, letrec, named let, vectors,
strings and exact arithmetic past the fixnums.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
QS = os.path.join(ROOT, "bin", "quasischeme")

# name -> (extra arguments, extra environment)
CONFIGS = {
    "default": ([], {}),
    "escape": (["--continuations=escape"], {}),
    "O0": ([], {"QUASISCHEME_OPTIMIZE": "0"}),
    "O1": ([], {"QUASISCHEME_OPTIMIZE": "1"}),
    "no-fast": ([], {"QUASISCHEME_FAST": "0"}),
    "no-flonum-versions": ([], {"QUASISCHEME_FLONUM_VERSIONS": "0"}),
    "no-cpdx": ([], {"QUASISCHEME_CPDX": "0"}),
    "no-cpletrec": ([], {"QUASISCHEME_CPLETREC": "0"}),
    "no-stack-sites": ([], {"QUASISCHEME_STACK_SITES": "0"}),
    "site-closures": ([], {"QUASISCHEME_SITE_CLOSURES": "1"}),
    "parametric": ([], {"QUASISCHEME_PARAMETRIC": "1"}),
    "interpret": ([], {"QUASISCHEME_EVALUATOR": "interpret"}),
    "guile-mode": (["--guile"], {"QUASISCHEME_GUILE_CACHE": "0"}),
    # collections every 256 KB: what goes wrong across one (a store
    # without its card mark) shows
    "gc-stress": ([], {"QUASISCHEME_NURSERY": "256"}),
    "guile-gc-stress": (["--guile"], {"QUASISCHEME_GUILE_CACHE": "0", "QUASISCHEME_NURSERY": "256"}),
}


class Gen:
    """Random expressions of a type, over the variables in scope."""

    def __init__(self, rng):
        self.rng = rng
        self.n = 0

    def fresh(self, prefix="v"):
        self.n += 1
        return "%s%d" % (prefix, self.n)

    def pick(self, *xs):
        return self.rng.choice(xs)

    def chance(self, p):
        return self.rng.random() < p

    def vars_of(self, env, ty):
        return [v for v, t in env.items() if t == ty]

    # --- integers ---------------------------------------------------------
    def int_(self, env, d):
        vs = self.vars_of(env, "int")
        if d <= 0 or self.chance(0.25):
            if vs and self.chance(0.7):
                return self.rng.choice(vs)
            return str(self.rng.choice([0, 1, 2, 3, 7, -5, 100, 4611686018427387903,
                                         -4611686018427387904, 12345678901234567890]))
        k = self.rng.randrange(17)
        a = lambda: self.int_(env, d - 1)
        if k == 0: return "(+ %s %s)" % (a(), a())
        if k == 1: return "(- %s %s)" % (a(), a())
        if k == 2: return "(* %s %s)" % (a(), a())
        if k == 3: return "(%s %s (+ 1 (abs %s)))" % (self.pick("quotient", "remainder", "modulo"), a(), a())
        if k == 4: return "(if %s %s %s)" % (self.bool_(env, d - 1), a(), a())
        if k == 5: return "(length %s)" % self.list_(env, d - 1)
        if k == 6: return "(vector-length %s)" % self.vec(env, d - 1)
        if k == 7: return "(string-length %s)" % self.str_(env, d - 1)
        if k == 8:
            v = self.fresh()
            return "(let ((%s %s)) %s)" % (v, a(), self.int_(dict(env, **{v: "int"}), d - 1))
        if k == 9: return self.loop(env, d)
        if k == 10: return "(%s %s %s)" % (self.pick("max", "min"), a(), a())
        if k == 11: return self.callcc(env, d)
        if k == 12: return self.apply_fn(env, d)
        if k == 13: return "(fold-ints %s)" % self.list_(env, d - 1)
        if k == 14:
            vs2 = self.vars_of(env, "int")
            if vs2:
                v = self.rng.choice(vs2)
                return "(begin (set! %s %s) %s)" % (v, a(), v)
            return a()
        if k == 15: return "(vector-ref %s 0)" % self.nonempty_vec(env, d - 1)
        return self.closure_group(env, d)

    def nonempty_vec(self, env, d):
        return "(make-vector (+ 1 (modulo %s 5)) %s)" % (self.int_(env, d - 1), self.int_(env, d - 1))

    def loop(self, env, d):
        i, acc = self.fresh("i"), self.fresh("acc")
        n = self.rng.choice([3, 10, 200, 3000])
        lp = self.fresh("lp")
        body_env = dict(env, **{i: "int", acc: "int"})
        step = "(+ %s (remainder %s 1000003))" % (acc, self.int_(body_env, d - 2))
        return "(let %s ((%s 0) (%s %s)) (if (= %s %d) %s (%s (+ %s 1) %s)))" % (
            lp, i, acc, self.int_(env, d - 1), i, n, acc, lp, i, step)

    def callcc(self, env, d):
        k = self.fresh("k")
        inner = dict(env)
        body = self.int_(inner, d - 1)
        if self.chance(0.5):
            # escape from inside a computation
            return "(call/cc (lambda (%s) (+ %s (%s %s))))" % (k, self.int_(env, d - 1), k, body)
        return "(call/cc (lambda (%s) %s))" % (k, body)

    def apply_fn(self, env, d):
        x = self.fresh("x")
        body = self.int_(dict(env, **{x: "int"}), d - 1)
        if self.chance(0.5):
            return "((lambda (%s) %s) %s)" % (x, body, self.int_(env, d - 1))
        return "(apply (lambda (%s . rest) (+ %s (length rest))) (list %s %s))" % (
            x, body, self.int_(env, d - 1), self.int_(env, d - 1))

    def closure_group(self, env, d):
        """Mutually referring closures over several variables, made in a
        loop that allocates, then walked: a GC between the closures'
        allocations once lost the younger ones."""
        names = [self.fresh("f") for _ in range(self.rng.choice([2, 4, 6]))]
        caps = [self.fresh("c") for _ in range(self.rng.choice([1, 3, 6]))]
        defs = []
        for j, f in enumerate(names):
            nxt = names[(j + 1) % len(names)]
            defs.append("(%s (lambda (n) (if (<= n 0) (+ %s) (%s (- n 1)))))" % (
                f, " ".join(caps), nxt))
        i = self.fresh("i")
        return ("(let loop ((%s 0) (keep '())) (if (= %s 50) (apply + (map (lambda (g) (g 7)) keep)) "
                "(let (%s) (letrec (%s) (loop (+ %s 1) (cons %s (if (> (length keep) 20) (cdr keep) keep)))))))") % (
            i, i, " ".join("(%s %s)" % (c, self.int_(env, d - 2)) for c in caps),
            " ".join(defs), i, names[0])

    # --- other types ------------------------------------------------------
    def bool_(self, env, d):
        a = lambda: self.int_(env, d - 1)
        k = self.rng.randrange(7)
        if d <= 0 or k == 0: return self.pick("#t", "#f")
        if k == 1: return "(%s %s %s)" % (self.pick("<", "=", ">", "<=", ">="), a(), a())
        if k == 2: return "(not %s)" % self.bool_(env, d - 1)
        if k == 3: return "(and %s %s)" % (self.bool_(env, d - 1), self.bool_(env, d - 1))
        if k == 4: return "(or %s %s)" % (self.bool_(env, d - 1), self.bool_(env, d - 1))
        if k == 5: return "(even? %s)" % a()
        return "(equal? %s %s)" % (self.list_(env, d - 1), self.list_(env, d - 1))

    def list_(self, env, d):
        k = self.rng.randrange(6)
        if d <= 0 or k == 0:
            return "(list %s)" % " ".join(self.int_(env, 0) for _ in range(self.rng.randrange(4)))
        if k == 1: return "(cons %s %s)" % (self.int_(env, d - 1), self.list_(env, d - 1))
        if k == 2: return "(map (lambda (x) (+ x %s)) %s)" % (self.int_(env, d - 1), self.list_(env, d - 1))
        if k == 3: return "(reverse %s)" % self.list_(env, d - 1)
        if k == 4: return "(vector->list %s)" % self.vec(env, d - 1)
        return "(iota-list (modulo %s 50))" % self.int_(env, d - 1)

    def vec(self, env, d):
        k = self.rng.randrange(4)
        if d <= 0 or k == 0: return "(vector %s)" % " ".join(self.int_(env, 0) for _ in range(self.rng.randrange(4)))
        if k == 1: return "(list->vector %s)" % self.list_(env, d - 1)
        if k == 2:
            v = self.fresh("vec")
            return "(let ((%s %s)) (vector-set! %s 0 %s) %s)" % (v, self.nonempty_vec(env, d - 1), v, self.int_(env, d - 1), v)
        return self.nonempty_vec(env, d)

    def str_(self, env, d):
        k = self.rng.randrange(4)
        if d <= 0 or k == 0: return '"%s"' % self.pick("", "a", "hello", "λx")
        if k == 1: return "(string-append %s %s)" % (self.str_(env, d - 1), self.str_(env, d - 1))
        if k == 2: return "(number->string %s)" % self.int_(env, d - 1)
        return "(list->string (map (lambda (c) c) (string->list %s)))" % self.str_(env, d - 1)

    def any_(self, env, d):
        return self.rng.choice([self.int_, self.bool_, self.list_, self.vec, self.str_])(env, d)

    # --- a program ----------------------------------------------------------
    def program(self, nforms=12, depth=5, reentry=True):
        forms = []
        env = {}
        for _ in range(3):
            g = self.fresh("g")
            forms.append("(define %s %s)" % (g, self.int_(env, 2)))
            env[g] = "int"
        for _ in range(nforms):
            forms.append("(write %s) (newline)" % self.any_(env, depth))
        # a re-entered continuation: full continuations' business (not
        # escape-only ones', which refuse it)
        if reentry:
            forms.append("(let ((k #f) (n 0)) (let ((v (call/cc (lambda (c) (set! k c) 1)))) (set! n (+ n v))) "
                         "(if (< n 5) (k 1)) (write n) (newline))")
        return forms


PRELUDE = """(import (scheme base) (scheme write))
(define (iota-list n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))
(define (fold-ints l) (let loop ((l l) (acc 0)) (if (null? l) acc (loop (cdr l) (+ acc (car l))))))
"""


def run(config, path, timeout):
    if config == "guile":
        cmd, env = ["guile", "--r7rs", "--no-auto-compile", path], dict(os.environ)
    else:
        args, extra = CONFIGS[config]
        cmd = [QS] + args + [path]
        env = dict(os.environ, **extra)
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                           timeout=timeout, env=env)
        out = p.stdout
        if p.returncode != 0:
            out += "\n[exit %d] %s" % (p.returncode, p.stderr.strip().splitlines()[-1:] if p.stderr else "")
        return out
    except subprocess.TimeoutExpired:
        return "[timeout]"


def outputs(forms, configs, timeout, tmpdir):
    path = os.path.join(tmpdir, "p.scm")
    with open(path, "w") as f:
        f.write(PRELUDE + "\n".join(forms) + "\n")
    return {c: run(c, path, timeout) for c in configs}


def differs(outs):
    return len(set(outs.values())) > 1


def shrink(forms, configs, timeout, tmpdir):
    """Remove forms one at a time while the outputs still differ."""
    changed = True
    while changed:
        changed = False
        for i in range(len(forms)):
            trial = forms[:i] + forms[i + 1:]
            if trial and differs(outputs(trial, configs, timeout, tmpdir)):
                forms = trial
                changed = True
                break
    return forms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--configs", default="default,O0,no-fast,interpret,guile-mode,gc-stress")
    ap.add_argument("--guile", action="store_true", help="also GNU Guile, as an oracle")
    ap.add_argument("--keep", default=os.path.join(ROOT, "tests", "fuzz", "failures"))
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--forms", type=int, default=12)
    ap.add_argument("--depth", type=int, default=5)
    a = ap.parse_args()
    configs = a.configs.split(",") + (["guile"] if a.guile else [])
    seed = a.seed if a.seed is not None else random.randrange(1 << 30)
    failures = 0
    with tempfile.TemporaryDirectory() as tmpdir:
        for n in range(a.count):
            s = seed + n
            forms = Gen(random.Random(s)).program(a.forms, a.depth, reentry="escape" not in configs)
            outs = outputs(forms, configs, a.timeout, tmpdir)
            if not differs(outs):
                print("seed %d: ok (%d configurations agree)" % (s, len(configs)), flush=True)
                continue
            failures += 1
            small = shrink(forms, configs, a.timeout, tmpdir)
            outs = outputs(small, configs, a.timeout, tmpdir)
            os.makedirs(a.keep, exist_ok=True)
            base = os.path.join(a.keep, "seed-%d" % s)
            with open(base + ".scm", "w") as f:
                f.write(PRELUDE + "\n".join(small) + "\n")
            with open(base + ".out", "w") as f:
                for c, o in outs.items():
                    f.write(";;; %s\n%s\n" % (c, o))
            print("seed %d: DIFFERENT -> %s.scm" % (s, base), flush=True)
            groups = {}
            for c, o in outs.items():
                groups.setdefault(o, []).append(c)
            for o, cs in groups.items():
                print("   %s: %s" % (",".join(cs), o.strip()[:200].replace("\n", " | ")), flush=True)
    print("%d of %d programs differed (seeds %d..%d)" % (failures, a.count, seed, seed + a.count - 1))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
