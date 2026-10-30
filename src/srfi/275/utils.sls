;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 utils)
  (export encode-string decode-string
          user-settable? host-settable? port-settable?
          path-settable?)
  (import (rnrs base (6))
          (only (rnrs arithmetic fixnums (6)) fixnum? fx<=?)
          (rename (prefix (srfi :275 internal utils) ex:)
                  (ex:utf8->string/raise utf8->string/raise)
                  (ex:encode-string encode-string)
                  (ex:decode-string decode-string)
                  (ex:split-userinfo username+password))
          (prefix (srfi :275 internal resource-identifier) ex:)
          (srfi :275 internal path))

  (define (user-settable? ident p)
    (cond [(ex:resource-identifier? ident)
           (ex:authority-settable? ident p ex:user-sets-authority?)]
          [(ex:relative-reference? ident)
           (ex:reference-authority-settable? ident p ex:reference-user-sets-authority?)]
          [else
           (assertion-violation 'user-settable? "not an URI or IRI" ident)]))

  (define (host-settable? ident p)
    (cond [(ex:resource-identifier? ident)
           (ex:authority-settable? ident p ex:host-sets-authority?)]
          [(ex:relative-reference? ident)
           (ex:reference-authority-settable? ident p ex:reference-host-sets-authority?)]
          [else
           (assertion-violation 'host-settable? "not an URI or IRI" ident)]))

  (define (port-settable? ident p)
    (cond [(ex:resource-identifier? ident)
           (ex:authority-settable? ident p ex:port-sets-authority?)]
          [(ex:relative-reference? ident)
           (ex:reference-authority-settable? ident p ex:reference-port-sets-authority?)]
          [else
           (assertion-violation 'port-settable? "not an URI or IRI" ident)]))

  (define (path-settable? ident path)
    (cond [(or (not (path? path)) path)
           (assertion-violation 'path-settable? "not a path object" path)]
          [(ex:resource-identifier? ident)
           (ex:path-settable? ident path)]
          [(ex:relative-reference? ident)
           (ex:reference-path-settable? ident path)]
          [else
           (assertion-violation 'path-settable? "not an URI or IRI" ident)]))

  ;;;
  ); library
