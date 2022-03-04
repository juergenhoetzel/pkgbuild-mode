;;; pkgbuild-mode-test.el --- Tests for pkgbuild-mode

;;; pkgbuild-mode-test.el ends here

(require 'ert)

(ert-deftest updates-sums-line ()
  "Should update sums line when source is available."
  (find-file "test/fixtures/PKGBUILD")

  (pkgbuild-update-sums-line)
  (should (buffer-modified-p))

  (goto-char (point-min))
  (should  (search-forward-regexp "^sha256sums=\('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'\)" nil t)))
