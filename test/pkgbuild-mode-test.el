;;; pkgbuild-mode-test.el --- Tests for pkgbuild-mode

;;; pkgbuild-mode-test.el ends here

(require 'ert)

(ert-deftest updates-sums-line ()
  "Should update sums line when source is available."
  (find-file "test/fixtures/PKGBUILD")

  (pkgbuild-update-sums-line)
  (should (buffer-modified-p))

  (goto-char (point-min))
  (should  (search-forward-regexp "^md5sums=\('d41d8cd98f00b204e9800998ecf8427e'\)" nil t)))
