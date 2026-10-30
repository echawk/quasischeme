;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 uri)
  (export ;; record types
          uri non-relative-uri? make-raw-uri
          relative-uri relative-uri? make-raw-relative-uri
          ;; polymorphic procedures
          uri? uri=? empty-uri rfc3986-absolute-uri?
          ;; conversion and serialisation
          uri->string
          get-uri get-non-relative-uri get-rfc3986-absolute-uri
          string->uri string->non-relative-uri string->rfc3986-absolute-uri
          ;; polymorphic accessors
          uri-scheme update-uri-scheme
          uri-user update-uri-user uri-username+password
          uri-host update-uri-host
          uri-port update-uri-port
          uri-path update-uri-path
          uri-query update-uri-query
          uri-fragment update-uri-fragment
          uri-authority update-uri-authority
          ;; character sets
          char-set:uri-unreserved
          char-set:gen-delims char-set:sub-delims char-set:reserved
          char-set:uri
          char-set:scheme
          char-set:uri-userinfo
          char-set:uri-reg-name
          char-set:uri-segment
          char-set:uri-query
          char-set:uri-fragment
          ;; paths
          uri-path-segment-ref uri-path-segment-update)
  (import (rnrs base (6))
          (only (rnrs control (6)) case-lambda)
          (only (rnrs io simple (6)) eof-object)
          (prefix (only (srfi :275 internal uri)
                        get-uri get-non-relative-uri get-rfc3986-absolute-uri)
                  ex:)
          (except (srfi :275 internal uri)
                  get-uri get-non-relative-uri get-rfc3986-absolute-uri)
          (srfi :275 internal utils))

  (define get-uri
    (case-lambda
     [(port) (ex:get-uri port (eof-object) 'get-uri)]
     [(port stop-on) (ex:get-uri port stop-on 'get-uri)]))

  (define get-non-relative-uri
    (case-lambda
     [(port) (ex:get-non-relative-uri port (eof-object) 'get-non-relative-uri)]
     [(port stop-on) (ex:get-non-relative-uri port stop-on 'get-non-relative-uri)]))

  (define get-rfc3986-absolute-uri
    (case-lambda
     [(port) (ex:get-rfc3986-absolute-uri port (eof-object) 'get-rfc3986-absolute-uri)]
     [(port stop-on) (ex:get-rfc3986-absolute-uri port stop-on 'get-rfc3986-absolute-uri)]))

  ;;;
  ); library
