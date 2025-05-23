;; -*- lexical-binding: t; coding: utf-8; -*-
(require 'ert)

(defconst openssl-cipher-test-versions
  '(latest default pbkdf2 legacy-sha256 legacy-md5))

(defun openssl-cipher-test-mtime (file)
  (ceiling (float-time (nth 5 (file-attributes file)))))

(defmacro openssl-cipher-map-version (&rest form)
  (let ((ver (make-symbol "ver")))
    `(let ((,ver openssl-cipher-encryption-version))
       (unwind-protect
           (dolist (v openssl-cipher-test-versions)
             (princ (format "Changing cipher version to `%s'\n" v))
             (setq openssl-cipher-encryption-version v)
             (progn ,@form))
         (setq openssl-cipher-encryption-version ,ver)))))

(ert-deftest openssl-cipher-normal ()
  "Normal test (for ascii)"
  :tags '(openssl-cipher)
  (openssl-cipher-map-version
   ;; ascii as unibyte array
   (let ((E (let ((openssl-cipher-password (copy-sequence "pass")))
              (prog1
                  (openssl-cipher-encrypt-unibytes "abcd")
                ;; check password is cleared.
                (should (equal openssl-cipher-password (make-string 4 0)))))))
     ;; check invalid pass
     (should-error (let ((openssl-cipher-password (copy-sequence "not pass")))
                     (openssl-cipher-decrypt-string E)))
     (should (equal (let ((openssl-cipher-password (copy-sequence "pass")))
                      (openssl-cipher-decrypt-unibytes E))
                    "abcd")))
   ;; ascii as unibyte string
   (let ((E (let ((openssl-cipher-password (copy-sequence "pass")))
              (openssl-cipher-encrypt-string "abcd"))))
     (should (equal (let ((openssl-cipher-password (copy-sequence "pass")))
                      (openssl-cipher-decrypt-string E))
                    "abcd")))))

(ert-deftest openssl-cipher-normal-multibyte ()
  "Normal test (for multibyte string)"
  :tags '(openssl-cipher)
  ;; check binary string
  (openssl-cipher-map-version
   (let ((E (let ((openssl-cipher-password (copy-sequence "pass")))
              (openssl-cipher-encrypt-unibytes "\316\323"))))
     (should (equal (let ((openssl-cipher-password (copy-sequence "pass")))
                      (openssl-cipher-decrypt-unibytes E))
                    "\316\323")))
   (let ((E (let ((openssl-cipher-password (copy-sequence "pass")))
              (openssl-cipher-encrypt-string "test マルチバイト文字"))))
     (should (equal (let ((openssl-cipher-password (copy-sequence "pass")))
                      (openssl-cipher-decrypt-string E))
                    "test マルチバイト文字")))))

(ert-deftest openssl-cipher-with-algorithm ()
  "Encrypt/Decrypt some of algorithms.
Some of algorithms are not working fine although."
  :tags '(openssl-cipher)
  (dolist (a (openssl-cipher-supported-types))
    (let ((func (lambda (value key iv algo)
                  (princ (format "Checking algorithm `%s'" algo))
                  (let* ((E (openssl-cipher-encrypt value key iv algo))
                         (M (condition-case err
                                (openssl-cipher-decrypt E key iv algo)
                              (error err))))
                    (cond
                     ((consp M)
                      (princ (format " => NG %s" M)))
                     ((stringp M)
                      (if (equal value M)
                          (princ " => OK")
                        (princ " => NG"))))
                    (princ "\n")))))
      (funcall func "a" [255] [0] a)
      (funcall func "a" "a" "a" a)
      (funcall func "a" "00" "a" a))))

(ert-deftest openssl-cipher-validate-bytes ()
  "Check validation IV/KEY input"
  :tags '(openssl-cipher)
  (openssl-cipher-map-version
   (should (openssl-cipher-encrypt "a" nil))
   (should (openssl-cipher-encrypt "a" [1]))
   ;; invalid byte range of vector
   (should-error (openssl-cipher-encrypt "a" [-1]))
   ;; invalid byte range of vector
   (should-error (openssl-cipher-encrypt "a" [256]))
   ;; unibyte vector
   (should (openssl-cipher-encrypt "a" [0] [0]))
   ;; hex string
   (should (openssl-cipher-encrypt "a" "0"))
   ;; unibyte string (Not exclusive with hex string)
   (should (openssl-cipher-encrypt "a" "\000"))
   (should-error (openssl-cipher-encrypt "a" "あ"))))


(ert-deftest openssl-cipher-file ()
  ""
  :tags '(openssl-cipher)
  (openssl-cipher-map-version
   (let ((file (openssl-cipher--create-temp-binary "abcdefg")))
     (unwind-protect
         (progn
           (let ((mtime (openssl-cipher-test-mtime file))
                 (openssl-cipher-password (copy-sequence "a")))
             (openssl-cipher-encrypt-file file)
             (should (equal (openssl-cipher-test-mtime  file) mtime)))
           ;; wrong password
           (let ((openssl-cipher-password (copy-sequence "d")))
             (should-error (openssl-cipher-decrypt-file file)))
           (let ((openssl-cipher-password (copy-sequence "a")))
             (openssl-cipher-decrypt-file file))
           (should (equal (openssl-cipher--file-unibytes file) "abcdefg")))
       (delete-file file)))))

(ert-deftest openssl-cipher-file-with-save-file ()
  ""
  :tags '(openssl-cipher)
  (openssl-cipher-map-version
   (let* ((file (openssl-cipher--create-temp-binary "opqrstu"))
          (save-file (concat file ".save-file"))
          (restore-file (concat file ".restore-file")))
     (unwind-protect
         (progn
           (let ((mtime (openssl-cipher-test-mtime file))
                 (openssl-cipher-password (copy-sequence "a")))
             (openssl-cipher-encrypt-file file nil save-file)
             (should (equal (openssl-cipher-test-mtime save-file) mtime)))
           ;; wrong password
           (let ((openssl-cipher-password (copy-sequence "d")))
             (should-error (openssl-cipher-decrypt-file save-file nil restore-file)))
           (let ((openssl-cipher-password (copy-sequence "a")))
             (openssl-cipher-decrypt-file save-file nil restore-file))
           (should (equal (openssl-cipher--file-unibytes file)
                          (openssl-cipher--file-unibytes restore-file))))
       (openssl-cipher--purge-file file)
       (openssl-cipher--purge-file save-file)
       (openssl-cipher--purge-file restore-file)))))
