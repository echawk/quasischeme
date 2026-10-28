; -*- Mode: Lisp; Syntax: Common-Lisp; Package: QUASISCHEME-R6RS -*-

;;;; Host procedures behind Chez Scheme's ftypes (src/chez/ftype.scm,
;;;; src/chez/ftype-helpers.sls): integers and floats read and written at
;;;; an address, or in a bytevector, in either byte order, and the atomic
;;;; operations of the ftype lock procedures.
;;;;
;;;; Memory is a BASE and an OFFSET: an integer address, or an octet vector
;;;; (what a pointer to a Scheme object points into).  The locks are atomic
;;;; with respect to each other (one mutex), as sb-ext:compare-and-swap
;;;; doesn't take an address.

(in-package "QUASISCHEME-R6RS")

(defvar *ftype-lock* (bt:make-lock "ftypes")
  "What makes the lock procedures' reads and writes of memory atomic.")

(defun ftype-read-uint (base offset n big)
  "The N-byte unsigned integer at BASE + OFFSET, the most significant byte
first if BIG."
  (let ((v 0))
    (if (integerp base)
	(let ((sap (qsffi::address-pointer (+ base offset))))
	  (dotimes (i n)
	    (setq v (logior (ash v 8) (cffi:mem-ref sap :uint8 (if big i (- n 1 i)))))))
	(dotimes (i n)
	  (setq v (logior (ash v 8) (aref base (+ offset (if big i (- n 1 i))))))))
    v))

(defun ftype-write-uint (base offset n big value)
  "Store the unsigned integer VALUE, of N bytes, at BASE + OFFSET."
  (if (integerp base)
      (let ((sap (qsffi::address-pointer (+ base offset))))
	(dotimes (i n)
	  (setf (cffi:mem-ref sap :uint8 (if big i (- n 1 i)))
		(ldb (byte 8 (* 8 (- n 1 i))) value))))
      (dotimes (i n)
	(setf (aref base (+ offset (if big i (- n 1 i))))
	      (ldb (byte 8 (* 8 (- n 1 i))) value)))))

(defun ftype-float-from-bits (bits n)
  "The flonum whose N-byte IEEE representation is the integer BITS."
  (float-features:with-float-traps-masked (:invalid :overflow :divide-by-zero :inexact)
    (if (= n 4)
	(coerce #+sbcl (sb-kernel:make-single-float (if (logbitp 31 bits) (- bits (ash 1 32)) bits))
		#-sbcl (float-features:bits-single-float bits)
		'double-float)
	#+sbcl (sb-kernel:make-double-float
		(let ((hi (ldb (byte 32 32) bits))) (if (logbitp 31 hi) (- hi (ash 1 32)) hi))
		(ldb (byte 32 0) bits))
	#-sbcl (float-features:bits-double-float bits))))

(defun ftype-float-to-bits (x n)
  "The integer that is the N-byte IEEE representation of the real X."
  (float-features:with-float-traps-masked (:invalid :overflow :divide-by-zero :inexact)
    (if (= n 4)
	(ldb (byte 32 0) (#+sbcl sb-kernel:single-float-bits #-sbcl float-features:single-float-bits
			  (coerce x 'single-float)))
	(let ((d (coerce x 'double-float)))
	  #+sbcl (logior (ash (ldb (byte 32 0) (sb-kernel:double-float-high-bits d)) 32)
			 (sb-kernel:double-float-low-bits d))
	  #-sbcl (ldb (byte 64 0) (float-features:double-float-bits d))))))

(defprim "chez:ftype-read-uint" (base offset n big)
  (ftype-read-uint base offset n (qs:truep big)))

(defprim "chez:ftype-write-uint!" (base offset n big value)
  (ftype-write-uint base offset n (qs:truep big) value)
  qs:unspecific)

(defprim "chez:ftype-read-float" (base offset n big)
  (ftype-float-from-bits (ftype-read-uint base offset n (qs:truep big)) n))

(defprim "chez:ftype-write-float!" (base offset n big value)
  (ftype-write-uint base offset n (qs:truep big) (ftype-float-to-bits value n))
  qs:unspecific)

;;; The lock procedures work on integers in the machine's byte order

(defprim "chez:ftype-atomic-add!" (base offset n delta)
  "Add DELTA to the N-byte integer at BASE + OFFSET: its new value."
  (bt:with-lock-held (*ftype-lock*)
    (let ((new (ldb (byte (* 8 n) 0) (+ (ftype-read-uint base offset n nil) delta))))
      (ftype-write-uint base offset n nil new)
      new)))

(defprim "chez:ftype-cas!" (base offset n old new)
  "If the N-byte integer at BASE + OFFSET is OLD, make it NEW: whether it was."
  (bool (bt:with-lock-held (*ftype-lock*)
	  (when (= (ftype-read-uint base offset n nil) old)
	    (ftype-write-uint base offset n nil new)
	    t))))

(defprim "chez:ftype-spin-lock!" (base offset n)
  (loop until (bt:with-lock-held (*ftype-lock*)
		(when (zerop (ftype-read-uint base offset n nil))
		  (ftype-write-uint base offset n nil 1)
		  t))
	do (bt:thread-yield))
  qs:unspecific)

;;; The address of a bytevector's data: where it is now, as the collector
;;; may move it

(defprim "chez:ftype-object-address" (object)
  (unless (typep object '(simple-array (unsigned-byte 8) (*)))
    (qs:scheme-error "ftype-pointer-address: a pointer into ~S has no address" object))
  (qsffi:vector-address object))
