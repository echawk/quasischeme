;;; SRFI 267 tests: the sample implementation's test.scm (Peter McGoron;
;;; MIT licence), but for its two cond-expands for CHICKEN before the
;;; import (a program starts with its imports), and with (scheme write),
;;; for its write, imported.  It exits 1 at the first
;;; failure.
; SPDX-FileCopyrightText: 2026 Peter McGoron
;
; SPDX-License-Identifier: MIT
; This assumes that the reader has already been modified to accept raw strings.


(import (scheme base) (scheme write) (srfi 267) (scheme process-context))

(define (write* form)
  (write form) (newline))
(define (fail form)
  (write form) (newline) (exit 1))

(define (test name expected raw to-read the-delimiter bad-delimiter)
  ;; Did the reader read the string correctly?
  (if (string=? expected raw)
      (write* `(,name passed))
      (fail `(,name failed (string=? ,expected ,raw))))
  ;; Does `read-raw-string` work?
  (let* ((port (open-input-string to-read))
         (as-read (read-raw-string port)))
    (if (string=? expected as-read)
        (write* `(,name read-raw-string passed))
        (fail `(,name read-raw-string failed (string=? ,expected ,as-read)))))
  ;; Does `write-raw-string` with the same delimiter the reader read work?
  (let* ((port (open-output-string))
         (ignored (write-raw-string expected the-delimiter port))
         (as-written (get-output-string port)))
    (if (string=? as-written to-read)
        (write* `(,name write-raw-string passed))
        (fail `(,name write-raw-string failed (string=? ,to-read ,as-written)))))
  ;; Does `write-raw-string` fail for a known bad delimiter?
  (when bad-delimiter
    (if (can-delimit? expected bad-delimiter)
        (fail `(,name can-delimit? failed ,expected ,bad-delimiter))
        (write* `(,name can-delimit? passed)))
    (newline)
    (guard (x ((raw-string-write-error? x)
               (write* `(,name write-raw-string bad passed)))
               (else (fail `(,name write-raw-string bad failed))))
        (write-raw-string expected bad-delimiter)
        (fail `(,name write-raw-string bad failed))))
  ;; Does `generate-delimiter` work properly?
  (let* ((delim (generate-delimiter expected))
         (output-port (open-output-string))
         (_ (write-raw-string expected delim output-port))
         (input-port (open-input-string (get-output-string output-port))))
    (if (equal? expected (read-raw-string input-port))
        (write* `(,name generate-delimiter passed))
        (fail `(,name generate-delimiter failed ,delim ,expected))))
)

(test "empty"
      ""
      #""""
      #"-"#"""""-"
      ""
      #f)
(test "single character"
      "a"
      #""a""
      #"-"#""a"""-"
      ""
      #f)
(test "no escapes"
      "\\"
      #""\""
      #"-"#""\"""-"
      ""
      #f)
(test "Inserting double quote using custom delimiters"
      "\""
      #"-"""-"
      #"--"#"-"""-""--"
      "-"
      "")
(test "Inserting double quote using space"
      " \" "
      #"" " ""
      #"-"#"" " """-"
      ""
      #f)
(test "Inserting backslash and double quote using custom delimiters"
      "\\\""
      #"-"\""-"
      #"--"#"-"\""-""--"
      "-"
      "")
(test "Quoted string using custom delimiters"
      "#\"()\""
      #"-"#"()""-"
      #"--"#"-"#"()""-""--"
      "-"
      "")
(test "Embedded raw string"
      "#\"\"a\"\""
      #"-"#""a"""-"
      #"--"#"-"#""a"""-""--"
      "-"
      "")
(test "ends with double quote"
      "ends with \\\""
      #"-"ends with \""-"
      #"--"#"-"ends with \""-""--"
      "-"
      "")
(test "multiline string"
      "multiline\nstring"
      #""multiline
string""
      #"-"#""multiline
string"""-"
      ""
      #f)
(test "no whitespace stripping"
      "\n    no whitespace stripping"
      #""
    no whitespace stripping""
      #"-"#""
    no whitespace stripping"""-"
    ""
    #f)

(test "SRFI 264 example"
      "\\(?(\\d{3})\\D{0,3}(\\d{3})\\D{0,3}(\\d{4})"
      #""\(?(\d{3})\D{0,3}(\d{3})\D{0,3}(\d{4})""
      #"-"#""\(?(\d{3})\D{0,3}(\d{3})\D{0,3}(\d{4})"""-"
      ""
      #f
)

(test "wisp example"
      "\ndefine: hello-name name\n  string-append \"Hello,\" name \"!\"\n"
      #"wisp-EOS"
define: hello-name name
  string-append "Hello," name "!"
"wisp-EOS"
      #"-"#"wisp-EOS"
define: hello-name name
  string-append "Hello," name "!"
"wisp-EOS""-"
      "wisp-EOS"
      #f
)

(test "parse-url example"
      "Given a URL as a string, returns a Parsed-URL record with the\ncomponents of that URL.\n\n(parse-url \"https://example.org/~smith/?record\")\n=> #<Parsed-URL protocol: \"https\" domain: \"example.org\"\n                path: \"/~smith/\" query: \"?record\">"
      #""Given a URL as a string, returns a Parsed-URL record with the
components of that URL.

(parse-url "https://example.org/~smith/?record")
=> #<Parsed-URL protocol: "https" domain: "example.org"
                path: "/~smith/" query: "?record">""
      #"-"#""Given a URL as a string, returns a Parsed-URL record with the
components of that URL.

(parse-url "https://example.org/~smith/?record")
=> #<Parsed-URL protocol: "https" domain: "example.org"
                path: "/~smith/" query: "?record">"""-"
       ""
       #f
)

;;;; Test that read fails on EOF
(guard (x ((raw-string-read-error? x)
           (write* `("read fails on EOF in delimiter" success)))
          (else (fail `("read fails on EOF in delimiter" failed))))
  (read-raw-string (open-input-string #"-"#"ab"-")))

(guard (x ((raw-string-read-error? x)
           (write* `("read fails on EOF in string" success)))
          (else (fail `("read fails on EOF in string" failed))))
  (read-raw-string (open-input-string #"-"#"ab"abcd"-")))

(guard (x ((raw-string-read-error? x)
           (write* `("read after prefix fails on EOF in delimiter" success)))
          (else (fail `("read after prefix fails on EOF in delimiter" failed))))
  (read-raw-string-after-prefix (open-input-string "ab")))

(guard (x ((raw-string-read-error? x)
           (write* `("read after prefix fails on EOF in string" success)))
          (else (fail `("read after prefix fails on EOF in string" failed))))
  (read-raw-string (open-input-string #"-"ab"abcd"-")))

(if (can-delimit? "x" "\"")
    (fail `("can delimit fails with double quote in delimiter"
            failed))
    (write* `("can delimit fails with double quote in delimiter"
              success)))
