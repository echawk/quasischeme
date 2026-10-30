;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 internal iri)
  (export ;; record types
          iri non-relative-iri? make-raw-iri
          relative-iri relative-iri? make-raw-relative-iri
          ;; polymorphic procedures
          iri? rfc3987-absolute-iri?
          iri=?
          iri->string
          empty-iri
          copy-iri
          (rename (deconstruct-resource-identifier deconstruct-iri))
          ;; polymorphic accessors
          iri-scheme set-iri-scheme! update-iri-scheme
          iri-user iri-username+password set-iri-user! update-iri-user
          iri-host set-iri-host! update-iri-host
          iri-port set-iri-port! update-iri-port
          iri-path set-iri-path! update-iri-path
          iri-query set-iri-query! update-iri-query
          iri-fragment set-iri-fragment! update-iri-fragment
          iri-authority set-iri-authority! update-iri-authority
          ;; parsing
          get-iri get-non-relative-iri get-rfc3987-absolute-iri
          string->iri string->non-relative-iri string->rfc3987-absolute-iri
          ;;
          string->iri-raw-user
          string->iri-raw-host
          iri-path-segment-ref iri-path-segment-set! iri-path-segment-update
          string->iri-raw-query
          string->iri-raw-fragment)
  (import (only (chezscheme) record-writer record-type-equal-procedure assertion-violationf errorf void)
          (rnrs base (6))
          (rnrs arithmetic fixnums (6))
          (rnrs bytevectors (6))
          (rnrs control (6))
          (rnrs conditions (6))
          (rnrs exceptions (6))
          (rnrs io ports (6))
          (only (rnrs io simple (6)) display)
          (only (rnrs lists (6)) memq)
          (rnrs records syntactic (6))
          (only (srfi :1 lists) drop)
          (srfi :14 char-sets)
          (srfi :48 intermediate-format-strings)
          (only (srfi :1 lists) drop)
          (only (srfi :152 strings) reverse-list->string string-null? string-any string-every)
          (srfi :160 u16)
          (srfi :262 match)
          (srfi :275 internal resource-identifier)
          (except (srfi :275 internal utils)
                  char-set:uri char-set:uri-pchar-unescaped
                  char-set:uri-userinfo char-set:uri-reg-name
                  char-set:uri-segment
                  char-set:uri-query char-set:uri-fragment)
          (rename (srfi :275 internal resource-identifier)
                  (resource-identifier-raw-scheme raw-scheme)
                  (resource-identifier-raw-user raw-user)
                  (resource-identifier-raw-host raw-host)
                  (resource-identifier-raw-query raw-query)
                  (resource-identifier-raw-fragment raw-fragment)
                  (resource-identifier-raw-authority raw-authority)
                  (resource-identifier-has-authority? has-authority?)
                  (set-resource-identifier-raw-scheme! set-raw-scheme!)
                  (set-resource-identifier-raw-user! set-raw-user!)
                  (set-resource-identifier-raw-host! set-raw-host!)
                  (set-resource-identifier-raw-query! set-raw-query!)
                  (set-resource-identifier-raw-fragment! set-raw-fragment!)
                   ;;
                  (relative-reference-raw-user reference-raw-user)
                  (relative-reference-raw-host reference-raw-host)
                  (relative-reference-raw-query reference-raw-query)
                  (relative-reference-raw-fragment reference-raw-fragment)
                  (relative-reference-raw-authority reference-raw-authority)
                  (relative-reference-has-authority? reference-has-authority?)
                  (set-relative-reference-raw-user! set-reference-raw-user!)
                  (set-relative-reference-raw-host! set-reference-raw-host!)
                  (set-relative-reference-raw-query! set-reference-raw-query!)
                  (set-relative-reference-raw-fragment! set-reference-raw-fragment!))
          (srfi :275 internal path))

  (define-record-type (iri make-raw-iri non-relative-iri?)
    (parent resource-identifier)
    (opaque #t)
    (sealed #t))

  (define-record-type (relative-iri make-raw-relative-iri relative-iri?)
    (parent relative-reference)
    (opaque #t)
    (sealed #t))

  (define (iri? ident)
    (or (non-relative-iri? ident) (relative-iri? ident)))

  (define (rfc3987-absolute-iri? ident)
    (and (non-relative-iri? ident)
         (not (resource-identifier-raw-fragment ident))))

  (define (%copy-iri who res)
    (cond [(non-relative-iri? res)
           (copy-resource-identifier make-raw-iri res)]
          [(relative-iri? res)
           (copy-relative-reference make-raw-relative-iri res)]
          [else
           (assertion-violationf who "~s is not an IRI or relative reference" res)]))

  (define (copy-iri res) (%copy-iri 'copy-iri res))

  (define (%iri=? A B)
    (cond [(and (non-relative-iri? A) (non-relative-iri? B))
           (resource-identifier-equal? A B)]
          [(and (relative-iri? A) (relative-iri? B))
           (relative-reference-equal? A B)]
          [(and (non-relative-iri? A) (relative-iri? B))
           #f]
          [(and (relative-iri? A) (non-relative-iri? B))
           #f]
          [(not (iri? A))
           (assertion-violationf 'iri=?
                                  "~s is not an IRI or relative reference"
                                  A)]
          [(not (iri? B))
           (assertion-violationf 'iri=?
                                  "~s is not an IRI or relative reference"
                                  B)]))

  (define iri=?
    (case-lambda
     [(iri1 iri2)
      (%iri=? iri1 iri2)]
     [(iri1 . iri*)
      (let loop ([curr iri1] [pool iri*])
        (match pool
          ['() #t]
          [(cons next rest)
           (and (%iri=? curr next)
                (loop next rest))]))]))

  (define iri-scheme
    (match-lambda
      [((? non-relative-iri? ident))
       (and (raw-scheme ident)
            (decode-raw-component->string (raw-scheme ident) 'iri-scheme #f))]
      [((? relative-iri? ident))
       (assertion-violationf 'iri-scheme "~s was an IRI relative reference" ident)]
      [(ident)
       (assertion-violationf 'iri-scheme "~s is not a non-relative IRI" ident)]))

  (define (%set-iri-scheme! who ident str)
    (cond [(non-relative-iri? ident)
           (set-raw-scheme! ident (string->raw-scheme str ident who))]
          [(relative-iri? ident)
           (assertion-violationf who "~s was an IRI relative reference" ident)]
          [else
           (assertion-violationf who "~s is not an IRI" ident)]))

  (define (set-iri-scheme! ident str)
    (%set-iri-scheme! 'set-iri-scheme ident str))

  (define (update-iri-scheme ident str)
    (let ([tgt (%copy-iri 'update-iri-scheme ident)])
      (%set-iri-scheme! 'update-iri-scheme  tgt str)
      tgt))

  (define iri-user
    (let ([decode-these
           (char-set-difference char-set:iri-userinfo
                                char-set:reserved)])
      (match-lambda
        [((? non-relative-iri? ident))
         (and (raw-user ident)
              (decode-raw-component->string (raw-user ident) 'iri-user #f))]
        [((? relative-iri? ident))
         (and (reference-raw-user ident)
              (decode-raw-component->string (reference-raw-user ident) 'iri-user #f))]
        [(ident)
         (assertion-violationf 'iri-user "~s is not an IRI or relative reference" ident)])))

  (define (iri-username+password ident)
    (cond
     [(non-relative-iri? ident)
      (split-raw-userinfo (raw-user ident) 'iri-username+password)]
     [(relative-iri? ident)
      (split-raw-userinfo (reference-raw-user ident) 'iri-username+password)]
     [else
      (assertion-violationf 'iri-username+password "~s is not an IRI or relative reference" ident)]))

  (define (%set-iri-user! who ident str)
    (cond
     [(and (non-relative-iri? ident)
           (authority-settable? ident str user-sets-authority?))
      (set-raw-user! ident (string->iri-raw-user str who))]
     [(and (relative-iri? ident)
           (reference-authority-settable? ident str reference-user-sets-authority?))
      (set-reference-raw-user! ident (string->iri-raw-user str who))]
     [(or (non-relative-iri? ident) (relative-iri? ident))
      (errorf who
              "cannot set user to ~s given path of IRI ~s"
              str ident)]

     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-user! ident str)
    (%set-iri-user! 'set-iri-user! ident str))

  (define (update-iri-user ident str)
    (let ([tgt (%copy-iri 'update-iri-user ident)])
      (%set-iri-user! 'update-iri-user tgt str)
      tgt))

  (define iri-host
    (let ([decode-these
           (char-set-difference char-set:iri-reg-name
                                char-set:reserved)])
      (match-lambda
        [((? non-relative-iri? ident))
         (and (raw-host ident)
              (decode-raw-component->string (raw-host ident) 'iri-host #f))]
        [((? relative-iri? ident))
         (and (reference-raw-host ident)
              (decode-raw-component->string (reference-raw-host ident) 'iri-host #f))]
        [(ident)
         (assertion-violationf 'iri-host "~s is not an IRI or relative reference" ident)])))

  (define (%set-iri-host! who ident str)
    (cond
     [(and (non-relative-iri? ident)
           (authority-settable? ident str host-sets-authority?))
      (set-raw-host! ident (string->iri-raw-host str who))]
     [(and (relative-iri? ident)
           (reference-authority-settable? ident str reference-host-sets-authority?))
      (set-reference-raw-host! ident (string->iri-raw-host str who))]
     [(or (non-relative-iri? ident) (relative-iri? ident))
      (errorf who
              "cannot set host to ~s given path of IRI ~s"
              str ident)]
     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-host! ident str)
    (%set-iri-host! 'set-iri-host ident str))

  (define (update-iri-host ident str)
    (let ([tgt (%copy-iri 'update-iri-host ident)])
      (%set-iri-host! 'update-iri-host tgt str)
      tgt))

  (define (iri-port ident)
    (cond [(non-relative-iri? ident)
           (resource-identifier-port ident)]
          [(relative-iri? ident)
           (relative-reference-port ident)]
          [else
           (assertion-violationf 'iri-host "~s is not an IRI or relative reference" ident)]))

  (define (valid-port? port)
    (or (not port)
        (and (fixnum? port) (fx>=? port 0))))

  (define (%set-iri-port! who ident port)
    (cond
     [(not (valid-port? port))
      (assertion-violationf who
                            "port to set ~s is not a non-negative fixnum or #f"
                            port)]
     [(and (non-relative-iri? ident)
           (authority-settable? ident port port-sets-authority?))
      (set-resource-identifier-port! ident port)]
     [(and (relative-iri? ident)
           (reference-authority-settable? ident port reference-port-sets-authority?))
      (set-relative-reference-port! ident port)]
     [(or (non-relative-iri? ident) (relative-iri? ident))
      (errorf who
              "cannot set port to ~s given path of IRI ~s"
              port ident)]
     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-port! ident port)
    (%set-iri-port! 'set-iri-port! ident port))

  (define (update-iri-port ident port)
    (let ([tgt (%copy-iri 'update-iri-port ident)])
      (%set-iri-port! 'set-iri-port tgt port)
      tgt))

  (define (iri-path ident)
    (cond [(non-relative-iri? ident)
           (resource-identifier-path ident)]
          [(relative-iri? ident)
           (relative-reference-path ident)]
          [else
           (assertion-violationf 'iri-path "~s is not an IRI or relative reference" ident)]))

  (define (%set-iri-path! who ident path)
    (cond [(not (path? path))
           (assertion-violationf who "~s is not a path object" path)]
          [(and (non-relative-iri? ident)
                (path-settable? ident path))
           (set-resource-identifier-path! ident (path->iri-path path))]
          [(and (relative-iri? ident)
                (reference-path-settable? ident path))
           (set-relative-reference-path! ident (path->iri-path path))]
          [(or (non-relative-iri? ident) (relative-iri? ident))
           (errorf who
                   "cannot set path to ~s given authority of IRI ~s"
                   path ident)]
          [else
           (assertion-violationf who "~s is not an IRI or relative reference" ident)]))

  (define (set-iri-path! ident x)
    (%set-iri-path! 'set-iri-path ident x))

  (define (update-iri-path ident x)
    (let ([tgt (%copy-iri 'update-iri-path ident)])
      (%set-iri-path! 'update-iri-path tgt x)
      tgt))

  (define iri-query
    (let ([decode-these
           (char-set-difference char-set:iri-query char-set:reserved)])
      (match-lambda
        [((? non-relative-iri? ident))
         (and (raw-query ident)
              (decode-raw-component->string (raw-query ident) 'iri-query #f))]
        [((? relative-iri? ident))
         (and (reference-raw-query ident)
              (decode-raw-component->string (reference-raw-query ident) 'iri-query #f))]
        [(ident)
         (assertion-violationf 'iri-query "~s is not an IRI or relative reference" ident)])))

  (define (%set-iri-query! who ident str)
    (cond
     [(non-relative-iri? ident)
      (let ([raw-query (string->iri-raw-query str who)])
        (set-raw-query! ident raw-query))]
     [(relative-iri? ident)
      (let ([raw-query (string->iri-raw-query str who)])
        (set-reference-raw-query! ident raw-query))]
     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-query! ident str)
    (%set-iri-query! 'set-iri-query! ident str))

  (define (update-iri-query ident str)
    (let ([tgt (%copy-iri 'update-iri-query ident)])
      (%set-iri-query! 'update-iri-query tgt str)
      tgt))

  (define iri-fragment
    (let ([decode-these
           (char-set-difference char-set:iri-fragment char-set:reserved)])
      (match-lambda
        [((? non-relative-iri? ident))
         (and (raw-fragment ident)
              (decode-raw-component->string (raw-fragment ident) 'iri-fragment #f))]
        [((? relative-iri? ident))
         (and (reference-raw-fragment ident)
              (decode-raw-component->string (reference-raw-fragment ident) 'iri-fragment #f))]
        [(ident)
         (assertion-violationf 'iri-fragment "~s is not an IRI or relative reference" ident)])))

  (define (%set-iri-fragment! who ident str)
    (cond
     [(non-relative-iri? ident)
      (let ([raw-fragment (string->iri-raw-fragment str who)])
        (set-raw-fragment! ident raw-fragment))]
     [(relative-iri? ident)
      (let ([raw-fragment (string->iri-raw-fragment str who)])
        (set-reference-raw-fragment! ident raw-fragment))]
     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-fragment! ident str)
    (%set-iri-fragment! 'set-iri-fragment! ident str))

  (define (update-iri-fragment ident str)
    (let ([tgt (%copy-iri 'update-iri-fragment ident)])
      (%set-iri-fragment! 'update-iri-fragment tgt str)
      tgt))

  (define (iri-authority->string user host port)
    (define (if-exists field prefix suffix)
      (if field
          (string-append prefix field suffix)
          ""))
    (define (port->string port)
      (and port (number->string port)))
    (string-append (if-exists user "" "@")
                   (if-exists host "" "")
                   (if-exists (port->string port) ":" "")))

  (define (iri-authority ident)
    (call-with-values
        (cond [(non-relative-iri? ident)
               (lambda () (resource-identifier-raw-authority ident))]
              [(relative-iri? ident)
               (lambda () (relative-reference-raw-authority ident))]
              [else
               (assertion-violationf 'iri-fragment "~s is not an IRI or relative reference" ident)])
      (lambda (user host port)
        (values (and user (decode-raw-component->string user 'iri-authority #f))
                (and host (decode-raw-component->string host 'iri-authority #f))
                port))))

  (define (%set-iri-authority! who ident user host port)
    (cond
     [(and (non-relative-iri? ident)
           (authority-settable? ident #f (lambda _ (or user host port))))
      (set-raw-user! ident (string->iri-raw-user user who))
      (set-raw-host! ident (string->iri-raw-host user who))
      (set-resource-identifier-port! ident port)]
     [(and (relative-iri? ident)
           (reference-authority-settable? ident #f (lambda _ (or user host port))))
      (set-reference-raw-user! ident (string->iri-raw-user user who))
      (set-reference-raw-host! ident (string->iri-raw-host user who))
      (set-relative-reference-port! ident port)]
     [(or (non-relative-iri? ident) (relative-iri? ident))
      (errorf who
              "cannot set authority to ~s, ~s and ~s given path of IRI ~s"
              user host port ident)]
     [else
      (assertion-violationf who
                            "~s is not an IRI or relative reference"
                            ident)]))

  (define (set-iri-authority! ident user host port)
    (%set-iri-authority! 'set-iri-authority! ident user host port))

  (define (update-iri-authority ident user host port)
    (let ([tgt (%copy-iri 'update-iri-authority ident)])
      (%set-iri-authority! 'update-iri-authority tgt user host port)
      tgt))

  (define (iri->string ident)
    (define (if-exists getter prefix suffix)
      (let ([sought (getter ident)])
        (if sought
            (string-append prefix sought suffix)
            "")))
    (cond [(non-relative-iri? ident)
           (string-append (if-exists iri-scheme "" ":")
                          (if-exists (compose iri-authority->string iri-authority) "//" "")
                          (path->string (iri-path ident))
                          (if-exists iri-query "?" "")
                          (if-exists iri-fragment "#" ""))]
          [(relative-iri? ident)
           (string-append (if-exists (compose iri-authority->string iri-authority) "//" "")
                          (path->string (iri-path ident))
                          (if-exists iri-query "?" "")
                          (if-exists iri-fragment "#" ""))]
          [else
           (assertion-violationf 'iri->string "~s is not an IRI or relative reference" ident)]))

  (define empty-iri
    (let ([emp (make-raw-relative-iri #f #f #f
                                      (empty-path)
                                      #f #f)])
      (lambda () emp)))

  #|
     Parsers
  |#
  (define (get-iri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-iri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty" #\: 0)]
            [(cset-elem char-set:alpha char)
             (get-iri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (with-eof port stop-on
               (make-raw-relative-iri #f #f #f (empty-path) #f #f))]
            [#\/
             (get-iri-authority port slots stop-on who)]
            [#\?
             (get-iri-query port slots stop-on who)]
            [#\#
             (get-iri-fragment port slots stop-on who)]
            [#\%
             (get-iri-path/noscheme port (consume-escapes port who) slots stop-on who)]
            [(cset-elem char-set:iri-segment char)
             (get-iri-path/noscheme port (char->reverse-u8-list char) slots stop-on who)]
            [char
             (errorf who "char ~s at position ~s is not valid within any segment" char 0)])
          (if (raw-scheme slots)
              slots
              (make-raw-relative-iri (raw-user slots)
                                     (raw-host slots)
                                     (resource-identifier-port slots)
                                     (resource-identifier-path slots)
                                     (raw-query slots)
                                     (raw-fragment slots))))
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define (get-non-relative-iri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-iri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty"
                     #\: 0)]
            [#\#
             (raise-fragment port who)]
            [(cset-elem char-set:alpha char)
             (get-non-relative-iri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (errorf who "EOF object ~s at position ~s indicated non-relative IRI was empty"
                     stop-on 0)]
            [char
             (errorf who "char ~s at position ~s is not valid within scheme" char 0)])
          slots)
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define (get-rfc3987-absolute-iri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-iri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty"
                     #\: 0)]
            [#\#
             (raise-fragment port who)]
            [(cset-elem char-set:alpha char)
             (get-rfc3987-absolute-iri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (errorf who "EOF object ~s at position ~s indicated RFC 3987 absolute IRI was empty"
                     stop-on 0)]
            [char
             (errorf who "char ~s at position ~s is not valid within scheme" char 0)])
          slots)
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define consume-iri-pchar
    (match-lambda
      [((cset-elem char-set:iri-unreserved char))
       (char->reverse-u8-list char)]
      [((cset-elem char-set:sub-delims char))
       `(,(char->integer char))]
      [(#\:) '(#x3A)]
      [(#\@) '(#x40)]
      [(char) char]))

  (define (get-iri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on (void))]
           [#\/ (get-iri-authority port slots stop-on who)]
           [#\? (get-iri-query port slots stop-on who)]
           [#\# (get-iri-fragment port slots stop-on who)]
           [char (get-iri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [#\/
         (let ([segment0 (reverse-list->u16vector acc)])
           (consume-iri-segments port '() `(,segment0) make-raw-relative-path slots stop-on who))]
        [#\%
         (let ([segment0/incomplete (append (consume-escapes port who) acc)])
           (get-iri-path/noscheme port segment0/incomplete slots stop-on who))]
        [#\?
         (let ([segment0 (reverse-list->u16vector acc)])
           (set-resource-identifier-path! slots (make-raw-relative-path `(,segment0)))
           (get-iri-query port slots stop-on who))]
        [#\#
         (let ([segment0 (reverse-list->u16vector acc)])
           (set-resource-identifier-path! slots (make-raw-relative-path `(,segment0)))
           (get-iri-fragment port slots stop-on who))]
        [(cset-elem char-set:iri-segment curr)
         (let ([segment0/incomplete (cons (char->integer curr) acc)])
           (get-iri-path/noscheme port segment0/incomplete slots stop-on who))]
        [(? (stop-here? stop-on))
         (let ([rpath (make-raw-relative-path
                       `(,(reverse-list->u16vector acc)))])
           (with-eof port stop-on
             (set-resource-identifier-path! slots rpath)))]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-non-relative-iri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on)) (with-eof port stop-on (void))]
           [#\/ (get-iri-authority port slots stop-on who)]
           [#\? (get-iri-query port slots stop-on who)]
           [#\# (get-iri-fragment port slots stop-on who)]
           [char (get-iri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [(? (stop-here? stop-on))
         (errorf who
                 "EOF object ~s at position ~s indicated premature end"
                 stop-on (last-port-position port))]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-rfc3987-absolute-iri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on)) (with-eof port stop-on (void))]
           [#\/ (get-rfc3987-absolute-iri-authority port slots stop-on who)]
           [#\? (get-rfc3987-absolute-iri-query port slots stop-on who)]
           [#\# (raise-fragment port who)]
           [char (get-rfc3987-absolute-iri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [(? (stop-here? stop-on))
         (errorf who
                 "EOF object ~s at position ~s indicated premature end"
                 stop-on (last-port-position port))]
        [#\#
         (raise-fragment port who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-iri-authority port slots stop-on who)
    (match (get-char port)
      [(? (stop-here? stop-on))
       (with-eof port stop-on
         (set-resource-identifier-path! slots (empty-absolute-path)))]
      [#\/; second slash
       (match (lookahead-char port)
         [#\: (next port (get-iri-port port slots stop-on who))]
         [#\@ (set-raw-user! slots (u16vector))
          (next port (get-iri-host port slots stop-on who))]
         [(? (stop-here? stop-on))
          (set-raw-host! slots (u16vector))]
         [#\[
          #| Final catch-all actually hands over to consume-host-rest,
             so we need to special-case: |#
          (get-iri-host port slots stop-on who)]
         [char
          (get-iri-user port (port-position port) '() slots stop-on who)])]
      [#\%
       (let ([lst (next port (consume-escapes port who))])
         (get-iri-path/absolute port lst slots stop-on who))]
      [(cset-elem char-set:iri-pchar-unescaped char)
       (get-iri-path/absolute port (char->reverse-u8-list char) slots stop-on who)]))

  (define (get-rfc3987-absolute-iri-authority port slots stop-on who)
    (match (get-char port)
      [(? (stop-here? stop-on))
       (with-eof port stop-on
         (set-resource-identifier-path! slots (empty-absolute-path)))]
      [#\/; second slash
       (match (lookahead-char port)
         [(? (stop-here? stop-on))
          (set-raw-host! slots (u16vector))]
         [#\: (next port (get-rfc3987-absolute-iri-port port slots stop-on who))]
         [#\@ (set-raw-user! slots (u16vector))
          (next port (get-rfc3987-absolute-iri-host port slots stop-on who))]
         [#\[  (get-rfc3987-absolute-iri-host port slots stop-on who)]
         [char (get-rfc3987-absolute-iri-user port (port-position port) '() slots stop-on who)])]
      [#\%
       (let ([lst (next port (consume-escapes port who))])
         (get-rfc3987-absolute-iri-path/absolute port lst slots stop-on who))]
      [(cset-elem char-set:iri-pchar-unescaped char)
       (get-rfc3987-absolute-iri-path/absolute port (char->reverse-u8-list char) slots stop-on who)]))

  (define (get-iri-user port start ini slots stop-on who)
    (let loop ([acc ini])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (set-port-position! port start)
         (get-iri-host port slots stop-on who)]
        [(or #\/ #\? #\#)
         (set-port-position! port start)
         (get-iri-host port slots stop-on who)]
        [(cset-elem char-set:iri-unreserved char)
         (loop (append (char->reverse-u8-list char) acc))]
        [#\:
         (loop (cons #x3A acc))]
        [#\%
         (loop (append (consume-escapes port who) acc))]
        [(cset-elem char-set:sub-delims char)
         (loop (cons (char->integer char) acc))]
        [#\@
         (set-raw-user! slots (reverse-list->u16vector acc))
         (get-iri-host port slots stop-on who)]
        [(cset-elem char-set:iri-reg-name char)
         (set-port-position! port start)
         (get-iri-host port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within user or host"
                 char (last-port-position port))])))

  (define (get-rfc3987-absolute-iri-user port start ini slots stop-on who)
    (let loop ([acc ini])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (set-port-position! port start)
         (get-rfc3987-absolute-iri-host port slots stop-on who)]
        [(or #\/ #\? #\#)
         (set-port-position! port start)
         (get-rfc3987-absolute-iri-host port slots stop-on who)]
        [(cset-elem char-set:iri-unreserved char)
         (loop (append (char->reverse-u8-list char) acc))]
        [#\:
         (loop (cons #x3A acc))]
        [#\%
         (loop (append (consume-escapes port who) acc))]
        [(cset-elem char-set:sub-delims char)
         (loop (cons (char->integer char) acc))]
        [#\@
         (set-raw-user! slots (reverse-list->u16vector acc))
         (get-rfc3987-absolute-iri-host port slots stop-on who)]
        [(cset-elem char-set:iri-reg-name char)
         (set-port-position! port start)
         (get-rfc3987-absolute-iri-host port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within user or host"
                 char (last-port-position port))])))

  (define (get-iri-host port slots stop-on who)
    (match (lookahead-char port)
      [(? (stop-here? stop-on))
       (finalise-host! slots '())]
      [#\[
       (let ([iplit (next port (consume-ip-literal port stop-on who))])
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on
              (set-raw-host! slots iplit))]
           [#\: (set-raw-host! slots iplit)
            (get-iri-port port slots stop-on who)]
           [#\? (set-raw-host! slots iplit)
            (get-iri-query port slots stop-on who)]
           [#\# (set-raw-host! slots iplit)
            (get-iri-fragment port slots stop-on who)]
           [#\/ (set-raw-host! slots iplit)
            (get-iri-path/abempty port slots stop-on who)]
           [char
            (errorf who
                    "char ~s at position ~s cannot be contained within host"
                    char (last-port-position port))]))]
      [(cset-elem char-set:digit)
       (let ([acc (consume-ipv4-address port '() stop-on who)])
         (match (lookahead-char port)
           [(? (stop-here? stop-on))
            (finalise-host! slots acc)]
           [char
            (get-iri-host/rest port acc slots stop-on who)]))]
      [_
       (get-iri-host/rest port '() slots stop-on who)]))

  (define (get-iri-host/rest port prev slots stop-on who)
    (let loop ([acc prev])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-host! slots acc))]
        [(cset-elem char-set:iri-reg-name char)
         (loop (append (char->reverse-u8-list char) acc))]
        [#\% (loop (append (consume-escapes port who) acc))]
        [#\: (finalise-host! slots acc)
         (get-iri-port port slots stop-on who)]
        [#\? (finalise-host! slots acc)
         (get-iri-query port slots stop-on who)]
        [#\# (finalise-host! slots acc)
         (get-iri-fragment port slots stop-on who)]
        [#\/ (finalise-host! slots acc)
         (get-iri-path/abempty port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within host"
                 char (last-port-position port))])))

  (define (get-rfc3987-absolute-iri-host port slots stop-on who)
    (match (lookahead-char port)
      [(? (stop-here? stop-on))
       (finalise-host! slots '())]
      [#\[
       (let ([iplit (next port (consume-ip-literal port stop-on who))])
         (match (get-char port)
           [(? (stop-here? stop-on)) (set-raw-host! slots iplit)]
           [#\: (set-raw-host! slots iplit)
            (get-rfc3987-absolute-iri-port port slots stop-on who)]
           [#\? (set-raw-host! slots iplit)
            (get-rfc3987-absolute-iri-query port slots stop-on who)]
           [#\#
            (raise-fragment port who)]
           [#\/ (set-raw-host! slots iplit)
            (get-rfc3987-absolute-iri-path/abempty port slots stop-on who)]
           [char
            (errorf who
                    "char ~s at position ~s cannot be contained within host"
                    char (last-port-position port))]))]
      [(cset-elem char-set:digit)
       (let ([acc (consume-ipv4-address port '() stop-on who)])
         (match (lookahead-char port)
           [(? (stop-here? stop-on))
            (finalise-host! slots acc)]
           [char
            (get-rfc3987-absolute-iri-host/rest port acc slots stop-on who)]))]
      [_
       (get-rfc3987-absolute-iri-host/rest port '() slots stop-on who)]))

  (define (get-rfc3987-absolute-iri-host/rest port prev slots stop-on who)
    (let loop ([acc prev])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-host! slots acc))]
        [(cset-elem char-set:iri-reg-name char)
         (loop (append (char->reverse-u8-list char) acc))]
        [#\% (loop (append (consume-escapes port who) acc))]
        [#\: (finalise-host! slots acc)
         (get-rfc3987-absolute-iri-port port slots stop-on who)]
        [#\? (finalise-host! slots acc)
         (get-rfc3987-absolute-iri-query port slots stop-on who)]
        [#\#
         (raise-fragment port who)]
        [#\/ (finalise-host! slots acc)
         (get-rfc3987-absolute-iri-path/abempty port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within host"
                 char (last-port-position port))])))

  (define (get-iri-port port slots stop-on who)
    (let loop ([acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-port! slots acc))]
        [(cset-elem char-set:numeric char)
         (loop (cons char acc))]
        [#\/ (finalise-port! slots acc)
         (get-iri-path/abempty port slots stop-on who)]
        [#\? (finalise-port! slots acc)
         (get-iri-query port slots stop-on who)]
        [#\# (finalise-port! slots acc)
         (get-iri-fragment port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within (numeric) port"
                 char (last-port-position port))])))

  (define (get-rfc3987-absolute-iri-port port slots stop-on who)
    (let loop ([acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-port! slots acc))]
        [(cset-elem char-set:numeric char)
         (loop (cons char acc))]
        [#\/ (finalise-port! slots acc)
         (get-rfc3987-absolute-iri-path/abempty port slots stop-on who)]
        [#\? (finalise-port! slots acc)
         (get-rfc3987-absolute-iri-query port slots stop-on who)]
        [#\# (raise-fragment port who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within (numeric) port"
                 char (last-port-position port))])))

  (define (get-iri-path/noscheme port rseg-lead slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment)))]
        [#\/ (let ([segment0 (reverse-list->u16vector rsegment)])
               (consume-iri-segments port '() `(,segment0) make-raw-relative-path slots stop-on who))]
        [#\? (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment))
         (get-iri-query port slots stop-on who)]
        [#\# (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment))
         (get-iri-fragment port slots stop-on who)]
        [#\@ (loop (cons #x40 rsegment) acc)]
        [(cset-elem char-set:iri-unreserved char)
         (loop (append (char->reverse-u8-list char) rsegment)
               acc)]
        [#\%
         (loop (append (consume-escapes port who) rsegment)
               acc)]
        [(cset-elem char-set:sub-delims char)
         (loop (cons (char->integer char) rsegment) acc)]
        [#\:
         (errorf who
                 "colon (~s) at position ~s is not valid in the first path segment"
                 #\: (last-port-position port))]
        [char
         (errorf who
                 "char ~s at position ~s is not valid within a path segment"
                 char (last-port-position port))])))

  (define (get-iri-path/rootless port ini slots stop-on who)
    (match (consume-iri-pchar ini)
      [(list enc ...)
       (consume-iri-segments port enc '() make-raw-relative-path slots stop-on who)]
      [#\%
       (consume-iri-segments port (consume-escapes port who) '() make-raw-relative-path slots stop-on who)]
      [_
       (errorf who
               "initial char ~s at position ~s cannot lead a path-rootless path"
               ini (last-port-position port))]))

  (define (get-rfc3987-absolute-iri-path/rootless port ini slots stop-on who)
    (match (consume-iri-pchar ini)
      [(list enc ...)
       (consume-absolute-iri-segments port enc '() make-raw-relative-path slots stop-on who)]
      [#\%
       (let ([enc (consume-escapes port who)])
         (consume-absolute-iri-segments port enc '() make-raw-relative-path slots stop-on who))]
      [_
       (errorf who
               "initial char ~s at position ~s cannot lead a path-rootless path"
               ini (last-port-position port))]))

  (define (get-iri-path/abempty port slots stop-on who)
    (consume-iri-segments port '() '() make-raw-absolute-path slots stop-on who))

  (define (get-iri-path/absolute port ini slots stop-on who)
    (consume-iri-segments port ini '() make-raw-absolute-path slots stop-on who))

  (define (get-rfc3987-absolute-iri-path/abempty port slots stop-on who)
    (consume-absolute-iri-segments port '() '() make-raw-absolute-path slots stop-on who))

  (define (get-rfc3987-absolute-iri-path/absolute port ini slots stop-on who)
    (consume-absolute-iri-segments port ini '() make-raw-absolute-path slots stop-on who))

  (define (consume-iri-segments port rseg-lead complete mkpath slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc complete])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment)))
            (match (consume-iri-pchar curr)
              [(list enc ...) (loop (append enc rsegment) acc)]
              [#\% (loop (append (consume-escapes port who) rsegment) acc)]
              [#\/ (loop '() (cons (reverse-list->u16vector rsegment) acc))]
              [#\? (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
               (get-iri-query port slots stop-on who)]
              [#\# (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
               (get-iri-fragment port slots stop-on who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within segment"
                       char (last-port-position port))])))))

  (define (consume-absolute-iri-segments port rseg-lead complete mkpath slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc complete])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment)))
            (match (consume-iri-pchar curr)
              [(list enc ...) (loop (append enc rsegment) acc)]
              [#\% (loop (append (consume-escapes port who) rsegment) acc)]
              [#\/ (loop '() (cons (reverse-list->u16vector rsegment) acc))]
              [#\? (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
               (get-rfc3987-absolute-iri-query port slots stop-on who)]
              [#\# (raise-fragment port who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within segment"
                       char (last-port-position port))])))))

  (define (get-iri-query port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-query! slots (reverse-list->u16vector acc)))
            (match (consume-iri-pchar curr)
              [(list enc ...)
               (loop (append enc acc))]
              [(cset-elem char-set:iri-private char)
               (loop (append (char->reverse-u8-list char) acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [#\#
               (set-raw-query! slots (reverse-list->u16vector acc))
               (get-iri-fragment port slots stop-on who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within IRI query"
                       char (last-port-position port))])))))

  (define (get-rfc3987-absolute-iri-query port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-query! slots (reverse-list->u16vector acc)))
            (match (consume-iri-pchar curr)
              [(list enc ...)
               (loop (append enc acc))]
              [(cset-elem char-set:iri-private char)
               (loop (append (char->reverse-u8-list char) acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [#\# (raise-fragment port who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within IRI query"
                       char (last-port-position port))])))))

  (define (get-iri-fragment port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-fragment! slots (reverse-list->u16vector acc)))
            (match (consume-iri-pchar curr)
              [(list enc ...) (loop (append enc acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within IRI fragment"
                       char (last-port-position port))])))))

  #|
  Generic utilities for finalising specific components
  |#

  (define (finalise-host! slots rlist)
    (unless (and (null? rlist)
                 (raw-user slots))
      (set-raw-host! slots
                     (reverse-list->u16vector rlist))))

  (define (finalise-port! slots rlist)
    (if (and (null? rlist)
             (not (or (raw-user slots)
                      (raw-host slots))))
        (set-raw-host! slots (u16vector))
        (let ([port (string->number
                     (reverse-list->string rlist))])
          (set-resource-identifier-port! slots port))))

  (define (finalise-path mkpath rlist last-rseg)
    (let ([last-segment
           (reverse-list->u16vector last-rseg)])
      (mkpath
       (reverse (cons last-segment rlist)))))

  #|
     Dedicated string conversion procedures
  |#
  (define string->iri
    (match-lambda
      [((? string? str))
       (get-iri (open-string-input-port str) (eof-object) 'string->iri)]
      [(nonstr)
       (assertion-violationf 'string->iri "~s is not a string" nonstr)]))

  (define string->non-relative-iri
    (match-lambda
      [((? string? str))
       (get-non-relative-iri (open-string-input-port str) (eof-object) 'string->non-relative-iri)]
      [(nonstr)
       (assertion-violationf 'string->non-relative-iri "~s is not a string" nonstr)]))

  (define string->rfc3987-absolute-iri
    (match-lambda
      [((? string? str))
       (get-rfc3987-absolute-iri (open-string-input-port str) (eof-object) 'string->rfc3987-absolute-iri)]
      [(nonstr)
       (assertion-violationf 'string->rfc3987-absolute-iri "~s is not a string" nonstr)]))

  (define string->iri-raw-user
    (match-lambda
      [(#f _) #f]
      [((? string? str) who)
       (let ([port (open-string-input-port str)])
         (let loop ([acc '()])
           (match (get-char port)
             [(? eof-object?)
              (reverse-list->u16vector acc)]
             [(cset-elem char-set:iri-userinfo char)
              (loop (append (char->reverse-u8-list char) acc))]
             [#\%
              (loop (append (consume-escapes port who) acc))]
             [char
              (loop (append (reverse-escape-utf8-octets char) acc))])))]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  (define string->iri-raw-host
    (match-lambda
      [(#f _) #f]
      [("" _)
       (u16vector)]
      [((? string? str) who)
       (define (on-rest port)
         (let loop ([acc '()])
           (match (get-char port)
             [(? eof-object?)
              (reverse-list->u16vector acc)]
             [(cset-elem char-set:iri-reg-name char)
              (loop (append (char->reverse-u8-list char) acc))]
             [#\%
              (loop (append (consume-escapes port who) acc))]
             [char
              (loop (append (reverse-escape-utf8-octets char) acc))])))
       (match (string-ref str 0)
         [#\[
          (let* ([port (open-string-input-port str)]
                 [iplit (next port (consume-ip-literal port (eof-object) who))])
            (match (get-char port)
              [(? eof-object?) iplit]
              [char (errorf who
                            "char ~s at position ~s followed IP literal"
                            char port)]))]
         [(cset-elem char-set:numeric)
           (let* ([port (open-string-input-port str)]
                  [acc (next port (consume-ipv4-address port '() (eof-object) who))])
             (match (get-char port)
               [(? eof-object?)
                (reverse-list->u16vector acc)]
               [char
                (on-rest port)]))]
         [_
          (on-rest (open-string-input-port str))])]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  #|
     IRI-specific path manipulation, so we avoid escaping characters valid in IRIs.
  |#
  (define char-set:^iri-segment (char-set-complement char-set:iri-segment))

  (define (iri-path-segment-ref ident k)
    (cond [(non-relative-iri? ident)
           (path-ref (resource-identifier-path ident) k)]
          [(relative-iri? ident)
           (path-ref (relative-reference-path ident) k)]
          [else
           (assertion-violationf 'iri-path-ref
                                 "~s is not an IRI or relative reference" ident)]))

  (define (%set-iri-path-segment! ident k x who)
    (cond
     [(not (string? x))
      (assertion-violationf who
                            "~s is not a string"
                            x)]
     [(and (non-relative-iri? ident)
           (has-authority? ident))
      (list-set! (path-raw-segments (resource-identifier-path ident))
                 k
                 (string->raw-segment x char-set:^iri-segment who ident k))]
     [(non-relative-iri? ident)
      (if (and (fxzero? k) (string-null? x))
          (errorf who
                  "cannot set initial segment to empty in absence of authority in IRI ~s"
                  ident)
          (list-set! (path-raw-segments (resource-identifier-path ident))
                     k
                     (string->raw-segment x char-set:^iri-segment who ident k)))]
     [(and (relative-iri? ident)
           (reference-has-authority? ident))
      (list-set! (path-raw-segments (relative-reference-path ident))
                 k
                 (string->raw-segment x char-set:^iri-segment who ident k))]
     [(relative-iri? ident)
      (cond [(and (fxzero? k) (string-null? x))
             (errorf who
                     "cannot set initial segment to empty in absence of authority in IRI relative reference ~s"
                     ident)]
            [(and (fxzero? k) (string-any (lambda (c) (char=? c #\:)) x))
             (errorf who
                     "cannot set initial segment to contain a colon in absence of authority in IRI relative reference ~s"
                     ident)]
            [else
             (list-set! (path-raw-segments (relative-reference-path ident))
                        k
                        (string->raw-segment x char-set:^iri-segment who ident k))])]
     [else
      (assertion-violationf who "~s is not an IRI or relative reference"
                            ident)]))

  (define (iri-path-segment-set! ident k x)
    (%set-iri-path-segment! ident k x 'iri-path-segment-set!))

  (define (iri-path-segment-update ident k x)
    (let ([tgt (%copy-iri 'iri-path-segmen-update ident)])
      (%set-iri-path-segment! tgt k x 'iri-path-segment-update)
      tgt))

  (define (get-reencoded path)
    (map (lambda (segment)
           (encode-string segment char-set:^iri-segment))
         (path-segments path)))

  (define (path->iri-path path)
    (cond [(empty-path? path)
           (empty-path)]
          [(absolute-path? path)
           (list->absolute-path (get-reencoded path) #f)]
          [(rfc3987-path-noscheme? path)
           (list->relative-path (get-reencoded path) #t)]
          [(and (relative-path? path)
                (u16vector-empty? (car (path-raw-segments path))))
           (errorf 'path->iri-path
                   "relative path ~s had empty initial segment"
                   path)]
          [(relative-path? path)
           (list->relative-path (get-reencoded path) #f)]
          [else
           (assertion-violationf 'path->iri-path
                                 "~s is not a path object"
                                 path)]))

  (define string->iri-raw-query
    (match-lambda
      [(#f _) #f]
      [((? string? str) who)
       (let ([port (open-string-input-port str)])
         (let loop ([acc '()])
           (let ([curr (get-char port)])
             (if (eof-object? curr)
                 (reverse-list->u16vector acc)
                 (match (consume-iri-pchar curr)
                   [(list enc ...)
                    (loop (append enc acc))]
                   [(cset-elem char-set:iri-private char)
                    (loop (append (char->reverse-u8-list char) acc))]
                   [#\/ (loop (cons #x2F acc))]
                   [#\? (loop (cons #x3F acc))]
                   [#\% (loop (append (consume-escapes port who) acc))]
                   [char (loop (append (reverse-escape-utf8-octets char) acc))])))))]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  #|
     URI query and fragment share the exact same structure whereas IRI
     queries additionally admit characters in the iprivate range.
     So we need to duplicate the above procedure minus the second
     char-set:iri-private range check:
  |#
  (define string->iri-raw-fragment
    (match-lambda
      [(#f _) #f]
      [((? string? str) who)
       (let ([port (open-string-input-port str)])
         (let loop ([acc '()])
           (let ([curr (get-char port)])
             (if (eof-object? curr)
                 (reverse-list->u16vector acc)
                 (match (consume-iri-pchar curr)
                   [(list enc ...) (loop (append enc acc))]
                   [#\/ (loop (cons #x2F acc))]
                   [#\? (loop (cons #x3F acc))]
                   [#\% (loop (append (consume-escapes port who) acc))]
                   [char (loop (append (reverse-escape-utf8-octets char) acc))])))))]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  #|
     Chez Scheme
  |#
  (record-writer (record-type-descriptor iri)
    (lambda (rec port _)
      (display (format "<~a>" (iri->string rec)) port)))

  #| Indicate in the REPL an IRI reference with double angle brackets:
     Maybe there's a convention for this? |#
  (record-writer (record-type-descriptor relative-iri)
    (lambda (rec port _)
      (display (format "<~a>" (iri->string rec)) port)))

  (record-type-equal-procedure (record-type-descriptor iri)
    (lambda (A B _) (resource-identifier-equal? A B)))

  (record-type-equal-procedure (record-type-descriptor relative-iri)
    (lambda (A B _) (relative-reference-equal? A B)))

   ;;;
  ); library
