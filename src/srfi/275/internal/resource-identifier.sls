;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 internal resource-identifier)
  (export ;; resource-identifier record type
          resource-identifier resource-identifier? make-resource-identifier
          resource-identifier-raw-scheme set-resource-identifier-raw-scheme!
          resource-identifier-raw-user set-resource-identifier-raw-user!
          resource-identifier-raw-host set-resource-identifier-raw-host!
          resource-identifier-port set-resource-identifier-port!
          resource-identifier-path set-resource-identifier-path!
          resource-identifier-raw-query set-resource-identifier-raw-query!
          resource-identifier-raw-fragment set-resource-identifier-raw-fragment!
          ;; relative reference record type
          relative-reference relative-reference? make-relative-reference
          relative-reference-raw-user set-relative-reference-raw-user!
          relative-reference-raw-host set-relative-reference-raw-host!
          relative-reference-port set-relative-reference-port!
          relative-reference-path set-relative-reference-path!
          relative-reference-raw-query set-relative-reference-raw-query!
          relative-reference-raw-fragment set-relative-reference-raw-fragment!
          resource-identifier-raw-authority relative-reference-raw-authority
          resource-identifier-has-authority? relative-reference-has-authority?
          resource-identifier-equal? relative-reference-equal?
          ;;
          deconstruct-resource-identifier
          user-sets-authority? host-sets-authority? port-sets-authority?
          reference-user-sets-authority? reference-host-sets-authority? reference-port-sets-authority?
          authority-settable? reference-authority-settable? path-settable? reference-path-settable?
          ;;
          copy-resource-identifier
          copy-relative-reference
          copy-raw-component
          raw-component-equal?)
  (import (only (chezscheme) errorf assertion-violationf)
          (rnrs base (6))
          (only (rnrs arithmetic fixnums (6)) fixnum?)
          (rnrs control (6))
          (rnrs conditions (6))
          (rnrs exceptions (6))
          (rnrs records syntactic (6))
          (only (srfi :1 lists) list-copy)
          (only (srfi :160 u16) u16vector? u16vector= u16vector-copy)
          (srfi :262 match)
          (srfi :275 internal path)
          (srfi :275 internal utils))

  (define-record-type resource-identifier/par)

  (define-record-type resource-identifier
    (parent resource-identifier/par)
    (fields (mutable scheme    resource-identifier-raw-scheme    set-resource-identifier-raw-scheme!)
            (mutable user      resource-identifier-raw-user      set-resource-identifier-raw-user!)
            (mutable host      resource-identifier-raw-host      set-resource-identifier-raw-host!)
            (mutable port      resource-identifier-port          set-resource-identifier-port!)
            (mutable path      resource-identifier-path      set-resource-identifier-path!)
            (mutable query     resource-identifier-raw-query     set-resource-identifier-raw-query!)
            (mutable fragment  resource-identifier-raw-fragment  set-resource-identifier-raw-fragment!))
    (opaque #t))

  (define-record-type relative-reference
    (parent resource-identifier/par)
    (fields (mutable  user      relative-reference-raw-user      set-relative-reference-raw-user!)
            (mutable  host      relative-reference-raw-host      set-relative-reference-raw-host!)
            (mutable  port      relative-reference-port          set-relative-reference-port!)
            (mutable  path      relative-reference-path      set-relative-reference-path!)
            (mutable  query     relative-reference-raw-query     set-relative-reference-raw-query!)
            (mutable  fragment  relative-reference-raw-fragment  set-relative-reference-raw-fragment!))
    (opaque #t))

  (define (copy-raw-component seq)
    (and seq
         (u16vector-copy seq)))

  (define (raw-component-equal? A B)
    (if (and (u16vector? A) (u16vector? B))
        (u16vector= A B)
        (eq? A B)))

  (define (resource-identifier-raw-authority res)
    (values (resource-identifier-raw-user res)
            (resource-identifier-raw-host res)
            (resource-identifier-port res)))

  (define (resource-identifier-has-authority? res)
    (match-values (resource-identifier-raw-authority res)
      [(#f #f #f) #f]
      [(_ _ _)    #t]))

  (define (relative-reference-raw-authority res)
    (values (relative-reference-raw-user res)
            (relative-reference-raw-host res)
            (relative-reference-port res)))

  (define (relative-reference-has-authority? res)
    (match-values (relative-reference-raw-authority res)
      [(#f #f #f) #f]
      [(_ _ _)    #t]))

  (define (resource-identifier-equal? A B)
    #|
    No structural equivalence (like `equal?' for records):
    they are compared with `eqv?'. This is not generalisable but it's
    sufficient for testing. Need to work out a good way to get
    structural equvialence for records.

    FIXME: compare the rarely-used authority components in a reference!
    |#
    (cond [(and (resource-identifier? A) (resource-identifier? B))
           (and (raw-component-equal? (resource-identifier-raw-scheme A)
                                      (resource-identifier-raw-scheme B))
                (raw-component-equal? (resource-identifier-raw-user A)
                                      (resource-identifier-raw-user B))
                (raw-component-equal? (resource-identifier-raw-host A)
                                      (resource-identifier-raw-host B))
                (eq? (resource-identifier-port A)
                     (resource-identifier-port B))
                (path=? (resource-identifier-path A)
                        (resource-identifier-path B))
                (raw-component-equal? (resource-identifier-raw-query A)
                                      (resource-identifier-raw-query B))
                (raw-component-equal? (resource-identifier-raw-fragment A)
                                      (resource-identifier-raw-fragment B)))]
          [(not (resource-identifier? A))
           (assertion-violationf 'resource-identifier-equal?
                                 "~a was not a resource identifier"
                                 A)]
          [else
           (assertion-violationf 'resource-identifier-equal?
                                 "~a was not a resource identifier"
                                 B)]))

  (define (relative-reference-equal? A B)
    (cond [(and (relative-reference? A) (relative-reference? B))
           (and (raw-component-equal? (relative-reference-raw-user A)
                                      (relative-reference-raw-user B))
                (raw-component-equal? (relative-reference-raw-host A)
                                      (relative-reference-raw-host B))
                (eq? (relative-reference-port A)
                     (relative-reference-port B))
                (path=? (relative-reference-path A)
                             (relative-reference-path B))
                (raw-component-equal? (relative-reference-raw-query A)
                                      (relative-reference-raw-query B))
                (raw-component-equal? (relative-reference-raw-fragment A)
                                      (relative-reference-raw-fragment B)))]
          [(not (relative-reference? A))
           (assertion-violationf 'relative-reference-equal?
                                 "~a was not a relative reference"
                                 A)]
          [else
           (assertion-violationf 'relative-reference-equal?
                                 "~a was not a relative reference"
                                 B)]))

  (define (deconstruct-resource-identifier res)
    (if (resource-identifier? res)
        `([scheme . ,(resource-identifier-raw-scheme res)]
          [user . ,(resource-identifier-raw-user res)]
          [host . ,(resource-identifier-raw-host res)]
          [port . ,(resource-identifier-port res)]
          [path . ,(resource-identifier-path res)]
          [query . ,(resource-identifier-raw-query res)]
          [fragment . ,(resource-identifier-raw-fragment res)])
        `([user . ,(relative-reference-raw-user res)]
          [host . ,(relative-reference-raw-host res)]
          [port . ,(relative-reference-port res)]
          [path . ,(relative-reference-path res)]
          [query . ,(relative-reference-raw-query res)]
          [fragment . ,(relative-reference-raw-fragment res)])))

  (define (user-sets-authority? ident u)
    (let ([raw-host (resource-identifier-raw-host ident)]
          [port (resource-identifier-port ident)])
      (or u raw-host port)))

  (define (reference-user-sets-authority? ident u)
    (let ([raw-host (relative-reference-raw-host ident)]
          [port (relative-reference-port ident)])
      (or u raw-host port)))

  (define (host-sets-authority? ident h)
    (let ([raw-user (resource-identifier-raw-user ident)]
          [port (resource-identifier-port ident)])
      (or raw-user h port)))

  (define (reference-host-sets-authority? ident h)
    (let ([raw-user (relative-reference-raw-user ident)]
          [port (relative-reference-port ident)])
      (or raw-user h port)))

  (define (port-sets-authority? ident p)
    (let ([raw-user (resource-identifier-raw-user ident)]
          [raw-host (resource-identifier-raw-host ident)])
      (or raw-user raw-host p)))

  (define (reference-port-sets-authority? ident p)
    (let ([raw-user (relative-reference-raw-user ident)]
          [raw-host (relative-reference-raw-host ident)])
      (or raw-user raw-host p)))

  ;; predicate for checking hier-part
  (define (authority-settable? ident new auth-is-set?)
    (if (auth-is-set? ident new)
        (rfc3987-path-abempty? (resource-identifier-path ident))
        (or (rfc3987-path-absolute? (resource-identifier-path ident))
            (rfc3987-path-rootless? (resource-identifier-path ident))
            (empty-path? (resource-identifier-path ident)))))

  ;; predicate for checking relative-part
  (define (reference-authority-settable? ident new auth-is-set?)
    (if (auth-is-set? ident new)
        (rfc3987-path-abempty? (relative-reference-path ident))
        (or (rfc3987-path-absolute? (relative-reference-path ident))
            (rfc3987-path-noscheme? (relative-reference-path ident))
            (empty-path? (relative-reference-path ident)))))

  (define (path-settable? ident path)
    (if (resource-identifier-has-authority? ident)
        (rfc3987-path-abempty? path)
        (or (rfc3987-path-absolute? path)
            (rfc3987-path-rootless? path)
            (empty-path? path))))

  (define (reference-path-settable? ident path)
    (if (relative-reference-has-authority? ident)
        (rfc3987-path-abempty? path)
        (or (rfc3987-path-absolute? path)
            (rfc3987-path-noscheme? path)
            (empty-path? path))))

  (define (copy-resource-identifier mk res)
    (mk (copy-raw-component (resource-identifier-raw-scheme res))
        (copy-raw-component (resource-identifier-raw-user res))
        (copy-raw-component (resource-identifier-raw-host res))
        (resource-identifier-port res)
        (copy-path (resource-identifier-path res))
        (copy-raw-component (resource-identifier-raw-query res))
        (copy-raw-component (resource-identifier-raw-fragment res))))

  (define (copy-relative-reference mk res)
    (mk (copy-raw-component (relative-reference-raw-user res))
        (copy-raw-component (relative-reference-raw-host res))
        (relative-reference-port res)
        (copy-path (relative-reference-path res))
        (copy-raw-component (relative-reference-raw-query res))
        (copy-raw-component (relative-reference-raw-fragment res))))
  ;;;
  ); library
