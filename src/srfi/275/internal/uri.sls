;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 internal uri)
  (export ;; record types
          uri non-relative-uri? make-raw-uri
          relative-uri relative-uri? make-raw-relative-uri
          ;; polymorphic procedures
          uri? rfc3986-absolute-uri?
          uri=?
          uri->string
          empty-uri
          copy-uri
          (rename (deconstruct-resource-identifier deconstruct-uri))
          ;; polymorphic accessors
          uri-scheme set-uri-scheme! update-uri-scheme
          uri-user uri-username+password set-uri-user! update-uri-user
          uri-host set-uri-host! update-uri-host
          uri-port set-uri-port! update-uri-port
          uri-path set-uri-path! update-uri-path
          uri-query set-uri-query! update-uri-query
          uri-fragment set-uri-fragment! update-uri-fragment
          uri-authority set-uri-authority! update-uri-authority
          ;; parsing
          get-uri get-non-relative-uri get-rfc3986-absolute-uri
          string->uri string->non-relative-uri string->rfc3986-absolute-uri
          ;;
          string->uri-raw-user
          string->uri-raw-host
          uri-path-segment-ref uri-path-segment-set! uri-path-segment-update
          string->uri-raw-query
          string->uri-raw-fragment)
  (import (only (chezscheme) record-writer record-type-equal-procedure assertion-violationf errorf void)
          (rnrs base (6))
          (rnrs arithmetic fixnums (6))
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
                  char-set:iri-illegal-controls char-set:ucschar
                  char-set:iri-unreserved char-set:iri-private
                  char-set:iri char-set:iri-pchar-unescaped
                  char-set:iri-userinfo char-set:iri-reg-name
                  char-set:iri-segment
                  char-set:iri-query char-set:iri-fragment)
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

  (define-record-type (uri make-raw-uri non-relative-uri?)
    (parent resource-identifier)
    (opaque #t)
    (sealed #t))

  (define-record-type (relative-uri make-raw-relative-uri relative-uri?)
    (parent relative-reference)
    (opaque #t)
    (sealed #t))

  (define (uri? ident)
    (or (non-relative-uri? ident) (relative-uri? ident)))

  (define (rfc3986-absolute-uri? ident)
    (and (non-relative-uri? ident)
         (not (raw-fragment ident))))

  (define (%copy-uri who res)
    (cond [(non-relative-uri? res)
           (copy-resource-identifier make-raw-uri res)]
          [(relative-uri? res)
           (copy-relative-reference make-raw-relative-uri res)]
          [else
           (assertion-violationf who "~s is not an URI or relative reference" res)]))

  (define (copy-uri res) (%copy-uri 'copy-uri res))

  (define (%uri=? A B)
    (cond [(and (non-relative-uri? A) (non-relative-uri? B))
           (resource-identifier-equal? A B)]
          [(and (relative-uri? A) (relative-uri? B))
           (relative-reference-equal? A B)]
          [(and (non-relative-uri? A) (relative-uri? B))
           #f]
          [(and (relative-uri? A) (non-relative-uri? B))
           #f]
          [(not (uri? A))
           (assertion-violationf 'uri=?
                                  "~s is not an URI or relative reference"
                                  A)]
          [(not (uri? B))
           (assertion-violationf 'uri=?
                                  "~s is not an URI or relative reference"
                                  B)]))

  (define uri=?
    (case-lambda
     [(uri1 uri2)
      (%uri=? uri1 uri2)]
     [(uri1 . uri*)
      (let loop ([curr uri1] [pool uri*])
        (match pool
          ['() #t]
          [(cons next rest)
           (and (%uri=? curr next)
                (loop next rest))]))]))

  (define uri-scheme
    (match-lambda
      [((? non-relative-uri? ident))
       (and (raw-scheme ident)
            (decode-raw-component->string (raw-scheme ident) 'uri-scheme #f))]
      [((? relative-uri? ident))
       (assertion-violationf 'uri-scheme "~s was an URI relative reference" ident)]
      [(ident)
       (assertion-violationf 'uri-scheme "~s is not a non-relative URI" ident)]))

  (define (%set-uri-scheme! who ident str)
    (cond [(non-relative-uri? ident)
           (set-raw-scheme! ident (string->raw-scheme str ident who))]
          [(relative-uri? ident)
           (assertion-violationf who "~s was an URI relative reference" ident)]
          [else
           (assertion-violationf who "~s is not an URI" ident)]))

  (define (set-uri-scheme! ident str)
    (%set-uri-scheme! 'set-uri-scheme ident str))

  (define (update-uri-scheme ident str)
    (let ([tgt (%copy-uri 'update-uri-scheme ident)])
      (%set-uri-scheme! 'update-uri-scheme  tgt str)
      tgt))

  (define uri-user
    (let ([decode-these
           (char-set-difference char-set:uri-userinfo
                                char-set:reserved)])
      (match-lambda
        [((? non-relative-uri? ident))
         (and (raw-user ident)
              (decode-raw-component->string (raw-user ident) 'uri-user #f))]
        [((? relative-uri? ident))
         (and (reference-raw-user ident)
              (decode-raw-component->string (reference-raw-user ident) 'uri-user #f))]
        [(ident)
         (assertion-violationf 'uri-user "~s is not an URI or relative reference" ident)])))

  (define (uri-username+password ident)
    (cond
     [(non-relative-uri? ident)
      (split-raw-userinfo (raw-user ident) 'uri-username+password)]
     [(relative-uri? ident)
      (split-raw-userinfo (reference-raw-user ident) 'uri-username+password)]
     [else
      (assertion-violationf 'uri-username+password "~s is not an URI or relative reference" ident)]))

  (define (%set-uri-user! who ident str)
    (cond
     [(and (non-relative-uri? ident)
           (authority-settable? ident str user-sets-authority?))
      (set-raw-user! ident (string->uri-raw-user str who))]
     [(and (relative-uri? ident)
           (reference-authority-settable? ident str reference-user-sets-authority?))
      (set-reference-raw-user! ident (string->uri-raw-user str who))]
     [(or (non-relative-uri? ident) (relative-uri? ident))
      (errorf who
              "cannot set user to ~s given path of URI ~s"
              str ident)]

     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-user! ident str)
    (%set-uri-user! 'set-uri-user! ident str))

  (define (update-uri-user ident str)
    (let ([tgt (%copy-uri 'update-uri-user ident)])
      (%set-uri-user! 'update-uri-user tgt str)
      tgt))

  (define uri-host
    (let ([decode-these
           (char-set-difference char-set:uri-reg-name
                                char-set:reserved)])
      (match-lambda
        [((? non-relative-uri? ident))
         (and (raw-host ident)
              (decode-raw-component->string (raw-host ident) 'uri-host #f))]
        [((? relative-uri? ident))
         (and (reference-raw-host ident)
              (decode-raw-component->string (reference-raw-host ident) 'uri-host #f))]
        [(ident)
         (assertion-violationf 'uri-host "~s is not an URI or relative reference" ident)])))

  (define (%set-uri-host! who ident str)
    (cond
     [(and (non-relative-uri? ident)
           (authority-settable? ident str host-sets-authority?))
      (set-raw-host! ident (string->uri-raw-host str who))]
     [(and (relative-uri? ident)
           (reference-authority-settable? ident str reference-host-sets-authority?))
      (set-reference-raw-host! ident (string->uri-raw-host str who))]
     [(or (non-relative-uri? ident) (relative-uri? ident))
      (errorf who
              "cannot set host to ~s given path of URI ~s"
              str ident)]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-host! ident str)
    (%set-uri-host! 'set-uri-host ident str))

  (define (update-uri-host ident str)
    (let ([tgt (%copy-uri 'update-uri-host ident)])
      (%set-uri-host! 'update-uri-host tgt str)
      tgt))

  (define (uri-port ident)
    (cond [(non-relative-uri? ident)
           (resource-identifier-port ident)]
          [(relative-uri? ident)
           (relative-reference-port ident)]
          [else
           (assertion-violationf 'uri-host "~s is not an URI or relative reference" ident)]))

  (define (valid-port? port)
    (or (not port)
        (and (fixnum? port) (fx>=? port 0))))

  (define (%set-uri-port! who ident port)
    (cond
     [(not (valid-port? port))
      (assertion-violationf who
                            "port to set ~s is not a non-negative fixnum or #f"
                            port)]
     [(and (non-relative-uri? ident)
           (authority-settable? ident port port-sets-authority?))
      (set-resource-identifier-port! ident port)]
     [(and (relative-uri? ident)
           (reference-authority-settable? ident port reference-port-sets-authority?))
      (set-relative-reference-port! ident port)]
     [(or (non-relative-uri? ident) (relative-uri? ident))
      (errorf who
              "cannot set port to ~s given path of URI ~s"
              port ident)]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-port! ident port)
    (%set-uri-port! 'set-uri-port! ident port))

  (define (update-uri-port ident port)
    (let ([tgt (%copy-uri 'update-uri-port ident)])
      (%set-uri-port! 'set-uri-port tgt port)
      tgt))

  (define (uri-path ident)
    (cond [(non-relative-uri? ident)
           (resource-identifier-path ident)]
          [(relative-uri? ident)
           (relative-reference-path ident)]
          [else
           (assertion-violationf 'uri-path "~s is not an URI or relative reference" ident)]))

  (define (%set-uri-path! who ident path)
    (cond [(not (path? path))
           (assertion-violationf who "~s is not a path object" path)]
          [(and (non-relative-uri? ident)
                (path-settable? ident path))
           (set-resource-identifier-path! ident (path->uri-path path))]
          [(and (relative-uri? ident)
                (reference-path-settable? ident path))
           (set-relative-reference-path! ident (path->uri-path path))]
          [(or (non-relative-uri? ident) (relative-uri? ident))
           (errorf who
                   "cannot set path to ~s given authority of URI ~s"
                   path ident)]
          [else
           (assertion-violationf who "~s is not an URI or relative reference" ident)]))

  (define (set-uri-path! ident x)
    (%set-uri-path! 'set-uri-path ident x))

  (define (update-uri-path ident x)
    (let ([tgt (%copy-uri 'update-uri-path ident)])
      (%set-uri-path! 'update-uri-path tgt x)
      tgt))

  (define uri-query
    (let ([decode-these
           (char-set-difference char-set:uri-query char-set:reserved)])
      (match-lambda
        [((? non-relative-uri? ident))
         (and (raw-query ident)
              (decode-raw-component->string (raw-query ident) 'uri-query #f))]
        [((? relative-uri? ident))
         (and (reference-raw-query ident)
              (decode-raw-component->string (reference-raw-query ident) 'uri-query #f))]
        [(ident)
         (assertion-violationf 'uri-query "~s is not an URI or relative reference" ident)])))

  (define (%set-uri-query! who ident str)
    (cond
     [(non-relative-uri? ident)
      (let ([raw-query (string->uri-raw-query str who)])
        (set-raw-query! ident raw-query))]
     [(relative-uri? ident)
      (let ([raw-query (string->uri-raw-query str who)])
        (set-reference-raw-query! ident raw-query))]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-query! ident str)
    (%set-uri-query! 'set-uri-query! ident str))

  (define (update-uri-query ident str)
    (let ([tgt (%copy-uri 'update-uri-query ident)])
      (%set-uri-query! 'update-uri-query tgt str)
      tgt))

  (define uri-fragment
    (let ([decode-these
           (char-set-difference char-set:uri-fragment char-set:reserved)])
      (match-lambda
        [((? non-relative-uri? ident))
         (and (raw-fragment ident)
              (decode-raw-component->string (raw-fragment ident) 'uri-fragment #f))]
        [((? relative-uri? ident))
         (and (reference-raw-fragment ident)
              (decode-raw-component->string (reference-raw-fragment ident) 'uri-fragment #f))]
        [(ident)
         (assertion-violationf 'uri-fragment "~s is not an URI or relative reference" ident)])))

  (define (%set-uri-fragment! who ident str)
    (cond
     [(non-relative-uri? ident)
      (let ([raw-fragment (string->uri-raw-fragment str who)])
        (set-raw-fragment! ident raw-fragment))]
     [(relative-uri? ident)
      (let ([raw-fragment (string->uri-raw-fragment str who)])
        (set-reference-raw-fragment! ident raw-fragment))]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-fragment! ident str)
    (%set-uri-fragment! 'set-uri-fragment! ident str))

  (define (update-uri-fragment ident str)
    (let ([tgt (%copy-uri 'update-uri-fragment ident)])
      (%set-uri-fragment! 'update-uri-fragment tgt str)
      tgt))

  (define (uri-authority->string user host port)
    (define (if-exists field prefix suffix)
      (if field
          (string-append prefix field suffix)
          ""))
    (define (port->string port)
      (and port (number->string port)))
    (string-append (if-exists user "" "@")
                   (if-exists host "" "")
                   (if-exists (port->string port) ":" "")))

  (define (uri-authority ident)
    (call-with-values
        (cond [(non-relative-uri? ident)
               (lambda () (resource-identifier-raw-authority ident))]
              [(relative-uri? ident)
               (lambda () (relative-reference-raw-authority ident))]
              [else
               (assertion-violationf 'uri-fragment "~s is not an URI or relative reference" ident)])
      (lambda (user host port)
        (values (and user (decode-raw-component->string user 'uri-authority #f))
                (and host (decode-raw-component->string host 'uri-authority #f))
                port))))

  (define (%set-uri-authority! who ident user host port)
    (cond
     [(and (non-relative-uri? ident)
           (authority-settable? ident #f (lambda _ (or user host port))))
      (set-raw-user! ident (string->uri-raw-user user who))
      (set-raw-host! ident (string->uri-raw-host user who))
      (set-resource-identifier-port! ident port)]
     [(and (relative-uri? ident)
           (reference-authority-settable? ident #f (lambda _ (or user host port))))
      (set-reference-raw-user! ident (string->uri-raw-user user who))
      (set-reference-raw-host! ident (string->uri-raw-host user who))
      (set-relative-reference-port! ident port)]
     [(or (non-relative-uri? ident) (relative-uri? ident))
      (errorf who
              "cannot set authority to ~s, ~s and ~s given path of URI ~s"
              user host port ident)]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (set-uri-authority! ident user host port)
    (%set-uri-authority! 'set-uri-authority! ident user host port))

  (define (update-uri-authority ident user host port)
    (let ([tgt (%copy-uri 'update-uri-authority ident)])
      (%set-uri-authority! 'update-uri-authority tgt user host port)
      tgt))

  (define (uri->string ident)
    (define (if-exists getter prefix suffix)
      (let ([sought (getter ident)])
        (if sought
            (string-append prefix sought suffix)
            "")))
    (cond [(non-relative-uri? ident)
           (string-append (if-exists uri-scheme "" ":")
                          (if-exists (compose uri-authority->string uri-authority) "//" "")
                          (path->string (uri-path ident))
                          (if-exists uri-query "?" "")
                          (if-exists uri-fragment "#" ""))]
          [(relative-uri? ident)
           (string-append (if-exists (compose uri-authority->string uri-authority) "//" "")
                          (path->string (uri-path ident))
                          (if-exists uri-query "?" "")
                          (if-exists uri-fragment "#" ""))]
          [else
           (assertion-violationf 'uri->string "~s is not an URI or relative reference" ident)]))

  (define empty-uri
    (let ([emp (make-raw-relative-uri #f #f #f
                                      (empty-path)
                                      #f #f)])
      (lambda () emp)))

  #|
     Parsers
  |#
  (define (get-uri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-uri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty" #\: 0)]
            [(cset-elem char-set:alpha char)
             (get-uri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (with-eof port stop-on
               (make-raw-relative-uri #f #f #f (empty-path) #f #f))]
            [#\/
             (get-uri-authority port slots stop-on who)]
            [#\?
             (get-uri-query port slots stop-on who)]
            [#\#
             (get-uri-fragment port slots stop-on who)]
            [#\%
             (get-uri-path/noscheme port (consume-escapes port who) slots stop-on who)]
            [(cset-elem char-set:uri-segment char)
             (get-uri-path/noscheme port `(,(char->integer char)) slots stop-on who)]
            [char
             (errorf who "char ~s at position ~s is not valid within any segment" char 0)])
          (if (raw-scheme slots)
              slots
              (make-raw-relative-uri (raw-user slots)
                                     (raw-host slots)
                                     (resource-identifier-port slots)
                                     (resource-identifier-path slots)
                                     (raw-query slots)
                                     (raw-fragment slots))))
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define (get-non-relative-uri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-uri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty"
                     #\: 0)]
            [#\#
             (raise-fragment port who)]
            [(cset-elem char-set:alpha char)
             (get-non-relative-uri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (errorf who
                     "EOF object ~s at position ~s indicated premature end"
                     stop-on (last-port-position port))]
            [char
             (errorf who "char ~s at position ~s is not valid within scheme" char 0)])
          slots)
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define (get-rfc3986-absolute-uri port stop-on who)
    (if (textual-port? port)
        (let ([slots (make-raw-uri #f #f #f #f (empty-path) #f #f)])
          (match (get-char port)
            [#\:
             (errorf who "char ~s indicated that scheme at position ~s was empty"
                     #\: 0)]
            [#\#
             (raise-fragment port who)]
            [(cset-elem char-set:alpha char)
             (get-rfc3986-absolute-uri-scheme port char slots stop-on who)]
            [(? (stop-here? stop-on))
             (errorf who
                     "EOF object ~s at position ~s indicated premature end"
                     stop-on (last-port-position port))]
            [char
             (errorf who "char ~s at position ~s is not valid within scheme" char 0)])
          slots)
        (assertion-violationf who
                              "~s is not a textual input port"
                              port)))

  (define consume-uri-pchar
    (match-lambda
      [((cset-elem char-set:uri-unreserved char)) (char->integer char)]
      [((cset-elem char-set:sub-delims char)) (char->integer char)]
      [(#\:) #x3A]
      [(#\@) #x40]
      [(char) char]))

  (define (get-uri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [(? (stop-here? stop-on) curr)
         (let ([rpath (make-raw-relative-path
                       `(,(reverse-list->u16vector acc)))])
           (with-eof port stop-on
             (set-resource-identifier-path! slots rpath)))]
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on (void))]
           [#\/ (get-uri-authority port slots stop-on who)]
           [#\? (get-uri-query port slots stop-on who)]
           [#\# (get-uri-fragment port slots stop-on who)]
           [char (get-uri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [#\/
         (let ([segment0 (reverse-list->u16vector acc)])
           (consume-uri-segments port '() `(,segment0) make-raw-relative-path slots stop-on who))]
        [#\%
         (let ([segment0/incomplete (append (consume-escapes port who) acc)])
           (get-uri-path/noscheme port segment0/incomplete slots stop-on who))]
        [#\?
         (let ([segment0 (reverse-list->u16vector acc)])
           (set-resource-identifier-path! slots (make-raw-relative-path `(,segment0)))
           (get-uri-query port slots stop-on who))]
        [#\#
         (let ([segment0 (reverse-list->u16vector acc)])
           (set-resource-identifier-path! slots (make-raw-relative-path `(,segment0)))
           (get-uri-fragment port slots stop-on who))]
        [(cset-elem char-set:uri-segment curr)
         (let ([segment0/incomplete (cons (char->integer curr) acc)])
           (get-uri-path/noscheme port segment0/incomplete slots stop-on who))]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-non-relative-uri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on (void))]
           [#\/ (get-uri-authority port slots stop-on who)]
           [#\? (get-uri-query port slots stop-on who)]
           [#\# (get-uri-fragment port slots stop-on who)]
           [char (get-uri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [(? (stop-here? stop-on))
         (errorf who
                 "EOF object ~s at position ~s indicated premature end to scheme"
                 stop-on (last-port-position port))]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-rfc3986-absolute-uri-scheme port ini slots stop-on who)
    (let loop ([acc `(,(char->integer ini))])
      (match (get-char port)
        [#\:
         (set-raw-scheme! slots (reverse-list->u16vector acc))
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on (void))]
           [#\/ (get-rfc3986-absolute-uri-authority port slots stop-on who)]
           [#\? (get-rfc3986-absolute-uri-query port slots stop-on who)]
           [#\# (raise-fragment port who)]
           [char (get-rfc3986-absolute-uri-path/rootless port char slots stop-on who)])]
        [(cset-elem char-set:scheme curr)
         (loop (cons (char->integer curr) acc))]
        [(and (or #\/ #\? (? (stop-here? stop-on))) curr)
         (errorf who
                 "EOF object ~s at position ~s indicated premature end to scheme"
                 stop-on (last-port-position port))]
        [#\#
         (raise-fragment port who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within scheme"
                 char (last-port-position port))])))

  (define (get-uri-authority port slots stop-on who)
    (match (get-char port)
      [(? (stop-here? stop-on))
       (with-eof port stop-on
         (set-resource-identifier-path! slots (empty-absolute-path)))]
      [#\/; second slash
       (match (lookahead-char port)
         [(? (stop-here? stop-on))
          (set-raw-host! slots (u16vector))]
         [#\: (next port (get-uri-port port slots stop-on who))]
         [#\@ (set-raw-user! slots (u16vector))
              (next port (get-uri-host port slots stop-on who))]
         [#\[ #| Final catch-all actually hands over to consume-host-rest,
                 so we need to special-case: |#
          (get-uri-host port slots stop-on who)]
         [char
          (get-uri-user port (port-position port) '() slots stop-on who)])]
      [#\%
       (let ([lst (next port (consume-escapes port who))])
         (get-uri-path/absolute port lst slots stop-on who))]
      [(cset-elem char-set:uri-pchar-unescaped char)
       (get-uri-path/absolute port `(,(char->integer char)) slots stop-on who)]))

  (define (get-rfc3986-absolute-uri-authority port slots stop-on who)
    (match (get-char port)
      [(? (stop-here? stop-on))
       (with-eof port stop-on
        (set-resource-identifier-path! slots (empty-absolute-path)))]
      [#\/; second slash
       (match (lookahead-char port)
         [(? (stop-here? stop-on))
          (set-raw-host! slots (u16vector))]
         [#\: (next port (get-rfc3986-absolute-uri-port port slots stop-on who))]
         [#\@ (set-raw-user! slots (u16vector))
              (next port (get-rfc3986-absolute-uri-host port slots stop-on who))]
         [#\[  (get-rfc3986-absolute-uri-host port slots stop-on who)]
         [char (get-rfc3986-absolute-uri-user port (port-position port) '() slots stop-on who)])]
      [#\%
       (let ([lst (next port (consume-escapes port who))])
         (get-rfc3986-absolute-uri-path/absolute port lst slots stop-on who))]
      [(cset-elem char-set:uri-pchar-unescaped char)
       (get-rfc3986-absolute-uri-path/absolute port `(,(char->integer char)) slots stop-on who)]))

  (define (get-uri-user port start ini slots stop-on who)
    (let loop ([acc ini])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (set-port-position! port start)
         (get-uri-host port slots stop-on who)]
        [(or #\/ #\? #\#)
         (set-port-position! port start)
         (get-uri-host port slots stop-on who)]
        [(cset-elem char-set:uri-unreserved char)
         (loop (cons (char->integer char) acc))]
        [#\:
         (loop (cons #x3A acc))]
        [#\%
         (loop (append (consume-escapes port who) acc))]
        [(cset-elem char-set:sub-delims char)
         (loop (cons (char->integer char) acc))]
        [#\@
         (set-raw-user! slots (reverse-list->u16vector acc))
         (get-uri-host port slots stop-on who)]
        [(cset-elem char-set:uri-reg-name ini)
         (set-port-position! port start)
         (get-uri-host port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within user or host"
                 char (last-port-position port))])))

  (define (get-rfc3986-absolute-uri-user port start ini slots stop-on who)
    (let loop ([acc ini])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (set-port-position! port start)
         (get-rfc3986-absolute-uri-host port slots stop-on who)]
        [#\#
         (raise-fragment port who)]
        [(or #\/ #\?)
         (set-port-position! port start)
         (get-rfc3986-absolute-uri-host port slots stop-on who)]
        [(cset-elem char-set:uri-unreserved char)
         (loop (cons (char->integer char) acc))]
        [#\:
         (loop (cons #x3A acc))]
        [#\%
         (loop (append (consume-escapes port who) acc))]
        [(cset-elem char-set:sub-delims char)
         (loop (cons (char->integer char) acc))]
        [#\@
         (set-raw-user! slots (reverse-list->u16vector acc))
         (get-rfc3986-absolute-uri-host port slots stop-on who)]
        [(cset-elem char-set:uri-reg-name ini)
         (set-port-position! port start)
         (get-rfc3986-absolute-uri-host port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within user or host"
                 char (last-port-position port))])))

  (define (get-uri-host port slots stop-on who)
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
                (get-uri-port port slots stop-on who)]
           [#\? (set-raw-host! slots iplit)
                (get-uri-query port slots stop-on who)]
           [#\# (set-raw-host! slots iplit)
                (get-uri-fragment port slots stop-on who)]
           [#\/ (set-raw-host! slots iplit)
                (get-uri-path/abempty port slots stop-on who)]
           [char
            (errorf who
                    "char ~s at position ~s cannot be contained within host"
                    char (last-port-position port))]))]
      [(cset-elem char-set:numeric)
       (let ([acc (consume-ipv4-address port '() stop-on who)])
         (match (lookahead-char port)
           [(? (stop-here? stop-on))
            (finalise-host! slots acc)]
           [char
            (get-uri-host/rest port acc slots stop-on who)]))]
      [_
       (get-uri-host/rest port '() slots stop-on who)]))

  (define (get-rfc3986-absolute-uri-host port slots stop-on who)
    (match (lookahead-char port)
      [(? (stop-here? stop-on))
       (finalise-host! slots '())]
      [#\[
       (let ([iplit (next port (consume-ip-literal port stop-on who))])
         (match (get-char port)
           [(? (stop-here? stop-on))
            (with-eof port stop-on
              (set-raw-host! slots iplit))]
           [#\# (raise-fragment port who)]
           [#\: (set-raw-host! slots iplit)
                (get-rfc3986-absolute-uri-port port slots stop-on who)]
           [#\? (set-raw-host! slots iplit)
                (get-rfc3986-absolute-uri-query port slots stop-on who)]
           [#\/ (set-raw-host! slots iplit)
                (get-rfc3986-absolute-uri-path/abempty port slots stop-on who)]
           [char
            (errorf who
                    "char ~s at position ~s cannot be contained within host"
                    char (last-port-position port))]))]
      [(cset-elem char-set:numeric)
       (let ([acc (consume-ipv4-address port '() stop-on who)])
         (match (lookahead-char port)
           [(? (stop-here? stop-on))
            (finalise-host! slots acc)]
           [char
            (get-rfc3986-absolute-uri-host/rest port acc slots stop-on who)]))]
      [_
       (get-rfc3986-absolute-uri-host/rest port '() slots stop-on who)]))

  (define (get-uri-host/rest port prev slots stop-on who)
    (let loop ([acc prev])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-host! slots acc))]
        [(cset-elem char-set:uri-reg-name char)
         (loop (cons (char->integer char) acc))]
        [#\% (loop (append (consume-escapes port who)
                           acc))]
        [#\: (finalise-host! slots acc)
             (get-uri-port port slots stop-on who)]
        [#\? (finalise-host! slots acc)
             (get-uri-query port slots stop-on who)]
        [#\# (finalise-host! slots acc)
             (get-uri-fragment port slots stop-on who)]
        [#\/ (finalise-host! slots acc)
             (get-uri-path/abempty port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within host"
                 char (last-port-position port))])))

  (define (get-rfc3986-absolute-uri-host/rest port prev slots stop-on who)
    (let loop ([acc prev])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-host! slots acc))]
        [(cset-elem char-set:uri-reg-name char)
         (loop (cons (char->integer char) acc))]
        [#\% (loop (append (consume-escapes port who)
                           acc))]
        [#\: (finalise-host! slots acc)
             (get-rfc3986-absolute-uri-port port slots stop-on who)]
        [#\? (finalise-host! slots acc)
             (get-rfc3986-absolute-uri-query port slots stop-on who)]
        [#\/ (finalise-host! slots acc)
             (get-rfc3986-absolute-uri-path/abempty port slots stop-on who)]
        [#\# (raise-fragment port who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within host"
                 char (last-port-position port))])))

  (define (get-uri-port port slots stop-on who)
    (let loop ([acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-port! slots acc))]
        [(cset-elem char-set:numeric char)
         (loop (cons char acc))]
        [#\/ (finalise-port! slots acc)
             (get-uri-path/abempty port slots stop-on who)]
        [#\? (finalise-port! slots acc)
             (get-uri-query port slots stop-on who)]
        [#\# (finalise-port! slots acc)
             (get-uri-fragment port slots stop-on who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within (numeric) port"
                 char (last-port-position port))])))

  (define (get-rfc3986-absolute-uri-port port slots stop-on who)
    (let loop ([acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (finalise-port! slots acc))]
        [(cset-elem char-set:numeric char)
         (loop (cons char acc))]
        [#\/ (finalise-port! slots acc)
             (get-rfc3986-absolute-uri-path/abempty port slots stop-on who)]
        [#\? (finalise-port! slots acc)
             (get-rfc3986-absolute-uri-query port slots stop-on who)]
        [#\# (raise-fragment port who)]
        [char
         (errorf who
                 "char ~s at position ~s cannot be contained within (numeric) port"
                 char (last-port-position port))])))

  (define (get-uri-path/noscheme port rseg-lead slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc '()])
      (match (get-char port)
        [(? (stop-here? stop-on))
         (with-eof port stop-on
           (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment)))]
        [#\/ (let ([segment0 (reverse-list->u16vector rsegment)])
               (consume-uri-segments port '() `(,segment0) make-raw-relative-path slots stop-on who))]
        [#\? (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment))
             (get-uri-query port slots stop-on who)]
        [#\# (set-resource-identifier-path! slots (finalise-path make-raw-relative-path acc rsegment))
             (get-uri-fragment port slots stop-on who)]
        [#\@ (loop (cons #x40 rsegment) acc)]
        [(cset-elem char-set:uri-unreserved char)
         (loop (cons (char->integer char) rsegment) acc)]
        [#\%
         (loop (append (consume-escapes port who)
                       rsegment)
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

  (define (get-uri-path/rootless port ini slots stop-on who)
    (match (consume-uri-pchar ini)
      [(? fixnum? enc0)
       (consume-uri-segments port `(,enc0) '() make-raw-relative-path slots stop-on who)]
      [#\%
       (let ([enc0 (consume-escapes port who)])
         (consume-uri-segments port `(,enc0) '() make-raw-relative-path slots stop-on who))]
      [_
       (errorf who
               "initial char ~s at position ~s cannot lead a path-rootless path"
               ini (last-port-position port))]))

  (define (get-rfc3986-absolute-uri-path/rootless port ini slots stop-on who)
    (match (consume-uri-pchar ini)
      [(? fixnum? enc0)
       (consume-absolute-uri-segments port `(,enc0) '() make-raw-relative-path slots stop-on who)]
      [#\%
       (let ([enc0 (consume-escapes port who)])
         (consume-absolute-uri-segments port `(,enc0) '() make-raw-relative-path slots stop-on who))]
      [_
       (errorf who
               "initial char ~s at position ~s cannot lead a path-rootless path"
               ini (last-port-position port))]))

  (define (get-uri-path/abempty port slots stop-on who)
    (consume-uri-segments port '() '() make-raw-absolute-path slots stop-on who))

  (define (get-rfc3986-absolute-uri-path/abempty port slots stop-on who)
    (consume-absolute-uri-segments port '() '() make-raw-absolute-path slots stop-on who))

  (define (get-uri-path/absolute port ini slots stop-on who)
    (consume-uri-segments port ini '() make-raw-absolute-path slots stop-on who))

  (define (get-rfc3986-absolute-uri-path/absolute port ini slots stop-on who)
    (consume-absolute-uri-segments port ini '() make-raw-absolute-path slots stop-on who))

  (define (consume-uri-segments port rseg-lead complete mkpath slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc complete])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment)))
            (match (consume-uri-pchar curr)
              [(? fixnum? enc) (loop (cons enc rsegment) acc)]
              [#\% (loop (append (consume-escapes port who) rsegment) acc)]
              [#\/ (loop '() (cons (reverse-list->u16vector rsegment) acc))]
              [#\? (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
                   (get-uri-query port slots stop-on who)]
              [#\# (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
                   (get-uri-fragment port slots stop-on who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within segment"
                       char (last-port-position port))])))))

  (define (consume-absolute-uri-segments port rseg-lead complete mkpath slots stop-on who)
    (let loop ([rsegment rseg-lead] [acc complete])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment)))
            (match (consume-uri-pchar curr)
              [(? fixnum? enc) (loop (cons enc rsegment) acc)]
              [#\% (loop (append (consume-escapes port who) rsegment) acc)]
              [#\/ (loop '() (cons (reverse-list->u16vector rsegment) acc))]
              [#\? (set-resource-identifier-path! slots (finalise-path mkpath acc rsegment))
                   (get-rfc3986-absolute-uri-query port slots stop-on who)]
              [#\# (raise-fragment port who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within segment"
                       char (last-port-position port))])))))

  (define (get-uri-query port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-query! slots (reverse-list->u16vector acc)))
            (match (consume-uri-pchar curr)
              [(? fixnum? enc) (loop (cons enc acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [#\#
               (set-raw-query! slots (reverse-list->u16vector acc))
               (get-uri-fragment port slots stop-on who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within URI query"
                       char (last-port-position port))])))))

  (define (get-rfc3986-absolute-uri-query port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-query! slots (reverse-list->u16vector acc)))
            (match (consume-uri-pchar curr)
              [(? fixnum? enc) (loop (cons enc acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [#\# (raise-fragment port who)]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within URI query"
                       char (last-port-position port))])))))

  (define (get-uri-fragment port slots stop-on who)
    (let loop ([acc '()])
      (let ([curr (get-char port)])
        (if ((stop-here? stop-on) curr)
            (with-eof port stop-on
              (set-raw-fragment! slots (reverse-list->u16vector acc)))
            (match (consume-uri-pchar curr)
              [(? fixnum? enc) (loop (cons enc acc))]
              [#\% (loop (append (consume-escapes port who) acc))]
              [#\/ (loop (cons #x2F acc))]
              [#\? (loop (cons #x3F acc))]
              [char
               (errorf who
                       "char ~s at position ~s cannot be contained within URI fragment"
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
  (define string->uri
    (match-lambda
      [((? string? str))
       (get-uri (open-string-input-port str) (eof-object) 'string->uri)]
      [(nonstr)
       (assertion-violationf 'string->uri "~s is not a string" nonstr)]))

  (define string->non-relative-uri
    (match-lambda
      [((? string? str))
       (get-non-relative-uri (open-string-input-port str) (eof-object) 'string->non-relative-uri)]
      [(nonstr)
       (assertion-violationf 'string->non-relative-uri "~s is not a string" nonstr)]))

  (define string->rfc3986-absolute-uri
    (match-lambda
      [((? string? str))
       (get-rfc3986-absolute-uri (open-string-input-port str) (eof-object) 'string->rfc3986-absolute-uri)]
      [(nonstr)
       (assertion-violationf 'string->rfc3986-absolute-uri "~s is not a string" nonstr)]))

  (define string->uri-raw-user
    (match-lambda
      [(#f _) #f]
      [((? string? str) who)
       (let ([port (open-string-input-port str)])
         (let loop ([acc '()])
           (match (get-char port)
             [(? eof-object?)
              (reverse-list->u16vector acc)]
             [(cset-elem char-set:uri-userinfo char)
              (loop (cons (char->integer char) acc))]
             [#\%
              (loop (append (consume-escapes port who) acc))]
             [char
              (loop (append (reverse-escape-utf8-octets char) acc))])))]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  (define string->uri-raw-host
    (match-lambda
      [(#f _) #f]
      [("" who) (u16vector)]
      [((? string? str) who)
       (define (on-rest port)
         (let loop ([acc '()])
           (match (get-char port)
             [(? eof-object?)
              (reverse-list->u16vector acc)]
             [(cset-elem char-set:uri-reg-name char)
              (loop (cons (char->integer char) acc))]
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
     URI-specific path manipulation, so we avoid escaping characters valid in URIs.
  |#
  (define char-set:^uri-segment (char-set-complement char-set:uri-segment))

  (define (uri-path-segment-ref ident k)
    (cond [(non-relative-uri? ident)
           (path-ref (resource-identifier-path ident) k)]
          [(relative-uri? ident)
           (path-ref (relative-reference-path ident) k)]
          [else
           (assertion-violationf 'uri-path-ref
                                 "~s is not an URI or relative reference" ident)]))

  (define (%set-uri-path-segment! ident k x who)
    (cond
     [(not (string? x))
      (assertion-violationf who
                            "~s is not a string"
                            x)]
     [(and (non-relative-uri? ident)
           (has-authority? ident))
      (list-set! (path-raw-segments (resource-identifier-path ident))
                 k
                 (string->raw-segment x char-set:^uri-segment who ident k))]
     [(non-relative-uri? ident)
      (if (and (fxzero? k) (string-null? x))
          (errorf who
                  "cannot set initial segment to empty in absence of authority in URI ~s"
                  ident)
          (list-set! (path-raw-segments (resource-identifier-path ident))
                     k
                     (string->raw-segment x char-set:^uri-segment who ident k)))]
     [(and (relative-uri? ident)
           (reference-has-authority? ident))
      (list-set! (path-raw-segments (relative-reference-path ident))
                 k
                 (string->raw-segment x char-set:^uri-segment who ident k))]
     [(relative-uri? ident)
      (cond [(and (fxzero? k) (string-null? x))
             (errorf who
                     "cannot set initial segment to empty in absence of authority in URI relative reference ~s"
                     ident)]
            [(and (fxzero? k) (string-any (lambda (c) (char=? c #\:)) x))
             (errorf who
                     "cannot set initial segment to contain a colon in absence of authority in URI relative reference ~s"
                     ident)]
            [else
             (list-set! (path-raw-segments (relative-reference-path ident))
                        k
                        (string->raw-segment x char-set:^uri-segment who ident k))])]
     [else
      (assertion-violationf who
                            "~s is not an URI or relative reference"
                            ident)]))

  (define (uri-path-segment-set! ident k x)
    (%set-uri-path-segment! ident k x 'uri-path-segment-set!))

  (define (uri-path-segment-update ident k x)
    (let ([tgt (%copy-uri 'uri-path-segment-update ident)])
      (%set-uri-path-segment! tgt k x 'uri-path-segment-update)
      tgt))

  (define (get-reencoded path)
    (map (lambda (segment)
           (encode-string segment char-set:^uri-segment))
         (path-segments path)))

  (define (path->uri-path path)
    (cond [(empty-path? path)
           (empty-path)]
          [(absolute-path? path)
           (list->absolute-path (get-reencoded path) #f)]
          [(rfc3987-path-noscheme? path)
           (list->relative-path (get-reencoded path) #t)]
          [(and (relative-path? path)
                (u16vector-empty? (car (path-raw-segments path))))
           (errorf 'path->uri-path
                   "relative path ~s had empty initial segment"
                   path)]
          [(relative-path? path)
           (list->relative-path (get-reencoded path) #f)]
          [else
           (assertion-violationf 'path->uri-path
                                 "~s is not a path object"
                                 path)]))

  (define string->uri-raw-query
    (match-lambda
      [(#f _) #f]
      [((? string? str) who)
       (let ([port (open-string-input-port str)])
         (let loop ([acc '()])
           (let ([curr (get-char port)])
             (if (eof-object? curr)
                 (reverse-list->u16vector acc)
                 (match (consume-uri-pchar curr)
                   [(? fixnum? enc) (loop (cons enc acc))]
                   [#\/ (loop (cons #x2F acc))]
                   [#\? (loop (cons #x3F acc))]
                   [#\% (loop (append (consume-escapes port who) acc))]
                   [char (loop (append (reverse-escape-utf8-octets char) acc))])))))]
      [(nonstr who)
       (assertion-violationf who "~s is not a string" nonstr)]))

  (define string->uri-raw-fragment string->uri-raw-query)

  #|
     Chez Scheme
  |#
  (record-writer (record-type-descriptor uri)
    (lambda (rec port _)
      (display (format "<~a>" (uri->string rec)) port)))

  #| Indicate in the REPL an URI reference with double angle brackets:
     Maybe there's a convention for this? |#
  (record-writer (record-type-descriptor relative-uri)
    (lambda (rec port _)
      (display (format "<~a>" (uri->string rec)) port)))

  (record-type-equal-procedure (record-type-descriptor uri)
    (lambda (A B _) (resource-identifier-equal? A B)))

  (record-type-equal-procedure (record-type-descriptor relative-uri)
    (lambda (A B _) (relative-reference-equal? A B)))

  ;;;
  ); library
