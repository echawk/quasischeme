;;; From Daphne Preston-Kendal's extensible-match, which provides (srfi :262
;;; match), the pattern matcher of withdrawn SRFI 262 that SRFI 275 uses:
;;; https://codeberg.org/dpk/extensible-match, commit
;;; 2a5834639666790bac14a89b05389eaea66c4d55, dedicated to the public domain
;;; (CC0 1.0, COPYING).  QUASISCHEME: its libraries' names (extensible-match
;;; ...) are renamed (srfi :262 extensible-match ...).
(library (srfi :262 extensible-match seq-pattern)
  (export seq-pattern-expand/nfa
          seq/unordered-pattern-expand)
  (import (rnrs (6))
          (srfi :262 extensible-match ast)
          (srfi :262 extensible-match seq-pattern nfa)
          ;; We will probably only ever have one strategy for
          ;; unordered patterns
          (srfi :262 extensible-match seq-pattern unordered)))
