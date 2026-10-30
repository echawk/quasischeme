;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 iri)
  (export ;; record types
          iri non-relative-iri? make-raw-iri
          relative-iri relative-iri? make-raw-relative-iri
          ;; polymorphic procedures
          iri? iri=? empty-iri rfc3987-absolute-iri?
          ;; conversion and serialisation
          iri->string
          get-iri get-non-relative-iri get-rfc3987-absolute-iri
          string->iri string->non-relative-iri string->rfc3987-absolute-iri
          ;; polymorphic accessors
          iri-scheme update-iri-scheme
          iri-user update-iri-user iri-username+password
          iri-host update-iri-host
          iri-port update-iri-port
          iri-path update-iri-path
          iri-query update-iri-query
          iri-fragment update-iri-fragment
          iri-authority update-iri-authority
          ;; character sets
          char-set:iri-unreserved char-set:iri-private char-set:ucschar
          char-set:gen-delims char-set:sub-delims char-set:reserved
          char-set:iri
          char-set:scheme
          char-set:iri-userinfo
          char-set:iri-reg-name
          char-set:iri-segment
          char-set:iri-query
          char-set:iri-fragment
          ;; paths
          iri-path-segment-ref iri-path-segment-update)
  (import (rnrs base (6))
          (only (rnrs control (6)) case-lambda)
          (only (rnrs io simple (6)) eof-object)
          (prefix (only (srfi :275 internal iri)
                        get-iri get-non-relative-iri get-rfc3987-absolute-iri)
                  ex:)
          (except (srfi :275 internal iri)
                  get-iri get-non-relative-iri get-rfc3987-absolute-iri)
          (srfi :275 internal utils))

  (define get-iri
    (case-lambda
     [(port) (ex:get-iri port (eof-object) 'get-iri)]
     [(port stop-on) (ex:get-iri port stop-on 'get-iri)]))

  (define get-non-relative-iri
    (case-lambda
     [(port) (ex:get-non-relative-iri port (eof-object) 'get-non-relative-iri)]
     [(port stop-on) (ex:get-non-relative-iri port stop-on 'get-non-relative-iri)]))

  (define get-rfc3987-absolute-iri
    (case-lambda
     [(port) (ex:get-rfc3987-absolute-iri port (eof-object) 'get-rfc3987-absolute-iri)]
     [(port stop-on) (ex:get-rfc3987-absolute-iri port stop-on 'get-rfc3987-absolute-iri)]))

  ;;;
  ); library
