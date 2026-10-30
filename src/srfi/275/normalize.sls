;; SPDX-FileCopyrightText: 2026 D. Guthrie <dguthrie@posteo.net>
;;;
;;; SPDX-License-Identifier: MIT
#!r6rs
(library (srfi :275 normalize)
  (export ;; normalization, reference resolution and comparison
          normalize-iri-case
          normalize-iri-escape
          normalize-iri-path
          normalize-iri
          normalize-uri-case
          normalize-uri-escape
          normalize-uri-path
          normalize-uri
          ;; relative reference resolution
          resolve-iri
          resolve-uri
          relativize-iri
          relativize-uri
          ;; conversion and equivalence
          uri->iri
          iri->uri)
  (import (srfi :275 internal normalize)))
