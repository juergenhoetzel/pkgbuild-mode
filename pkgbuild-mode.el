;; Copyright (C) 2005-2010 Juergen Hoetzel

;;; License

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

;;; TODO
;; - menu
;; - namcap/devtools integration
;; - use auto-insert

;;; Usage

;; Put this in your .emacs file to enable autoloading of pkgbuild-mode
;; and auto-recognition of "PKGBUILD" files:
;;
;;  (autoload 'pkgbuild-mode "pkgbuild-mode.el" "PKGBUILD mode." t)
;;  (setq auto-mode-alist (append '(("/PKGBUILD$" . pkgbuild-mode))
;;                                auto-mode-alist))

;;; Changelog:
;; 0.11.8
;; added support for visiting the AUR site 
;;
;; 0.11.7 
;; really fix the point brought up with 0.11.2
;;
;; 0.11.6
;; new pacman 4.1 compliant VCS templates (git, bzr, svn, mercurial. Missing: cvs, darcs)
;;
;; 0.11.5
;; redefine some shortcuts 
;;
;; 0.11.4
;; pkgbuild-read-makepkg-command: more sane default
;; 
;; 0.11.3
;; throw away all code regarding source-taurball-creation, use makepkg --source for that instead
;;
;; 0.11.2
;; fix creation of tarfiles if the source-URL uses syntax to save the 
;; downloaded file under another name, useful e.g. to add a version number
;;
;; 0.11.1
;; more templates, some minor code cosmetics
;;
;; 0.10.1
;; Use more sane defaults in PKGBUILD skel
;;
;; 0.10
;; made the calculation of sums generic (use makepkg.conf setting)
;;
;; 0.9
;;    fixed `pkgbuild-tar' (empty directory name: thanks Stefan Husmann)
;;    new custom variable: pkgbuild-template 
;;    code cleanup
;;
;; 0.8 
;;    added `pkgbuild-shell-command' and
;;      `pkgbuild-shell-command-to-string' (required to always use
;;      "/bin/bash" when calling shell functions, which create new
;;      buffers)
;;
;; 0.7 make shell-file-name buffer-local set to "/bin/bash" (required
;; to parse PKGBUILDs)
;;
;; 0.6
;;    New interactive function pkgbuild-etags (C-c C-e) 
;;      create tags table for all PKGBUILDs in your source tree, so you
;;      can search PKGBUILDs by pkgname. Customize your tags-table-list 
;;      to include the TAGS file in your source tree. 
;;    changed default  makepkg-command (disabled ANSI colors in emacs TERM) 
;;    set default indentation to 2
;;
;; 0.5
;;    New interactive function pkgbuild-browse-url to visit project's website (C-c C-u).
;;      Customize your browse-url-browser-function
;;    emacs 22 (cvs snapshot) compatibility: ensure makepkg buffer is not read-only
;;
;; 0.4
;;    handle source parse errors when updating md5sums and opening PKGBUILDs
;;    only update md5sums if all sources are available
;;    code cleanup
;;    highlight sources not available when trying to update md5sums and opening PKGBUILDs 
;;    (this does not work when globbing returns multiple filenames)
;;
;; 0.3
;;   Update md5sums line when saving PKGBUILD 
;;     (Can be disabled via custom variable [pkgbuild-update-md5sums-on-save])
;;   New interactive function pkgbuild-tar to create Source Tarball (C-c C-a)
;;     (Usefull for AUR uploads)
;;   Insert warn-messages in md5sums line when source files are not present
;;   Several bug fixes

;;; Code

(require 'cl)
(require 'sh-script)
(require 'advice)

(defconst pkgbuild-mode-version "0.11.8" "Version of `pkgbuild-mode'.")

(defconst pkgbuild-mode-menu
  (purecopy '("PKGBUILD"
              ["Update sums" pkgbuild-update-sums-line t]
              ["Browse upstream url" pkgbuild-browse-upstream-url t]
              ["Browse AUR url" pkgbuild-browse-AUR-url t]
              ["Increase release tag"    pkgbuild-increase-release-tag t]
              "---"
              ("Build package"
               ["Build tarball"       pkgbuild-tar                t]
               ["Build binary package"    pkgbuild-makepkg             t])
              "---"
              ["Create TAGS file"         pkgbuild-etags       t]
              ["Create install file"      pkgbuild-install-file-initialize   t]
              "---"
              ["About pkgbuild-mode"         pkgbuild-about-pkgbuild-mode       t]
              )))

;; Local variables

(defgroup pkgbuild nil
  "pkgbuild mode (Arch Linux Packages)."
  :prefix "pkgbuild-"
  :group 'languages)

(defcustom pkgbuild-generic-template
"# Maintainer: %s <%s>
pkgname=%s  
pkgver=VERSION
pkgrel=1
pkgdesc=\"\"
url=\"\"
arch=('i686' 'x86_64')
license=('GPL')
depends=()
makedepends=()
conflicts=()
replaces=()
backup=()
install=
source=($pkgname-$pkgver.tar.gz)
md5sums=()
build() {
  cd $srcdir/$pkgname-$pkgver
  ./configure --prefix=/usr
  make 
  make DESTDIR=$pkgdir install
}"
  "Template for new generic PKGBUILDs"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-install-file-template
"infodir=usr/share/info
filelist=(foo.info bar)

post_install() {
  [ -x usr/bin/install-info ] || return 0
  for file in ${filelist[@]}; do
    install-info $infodir/$file.gz $infodir/dir 2> /dev/null
  done
}

post_upgrade() {
  post_install $1
}

pre_remove() {
  [ -x usr/bin/install-info ] || return 0
  for file in ${filelist[@]}; do
    install-info --delete $infodir/$file.gz $infodir/dir 2> /dev/null
  done
}"
  "Template for new install files"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-bzr-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('bzr')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=(\"BZRURL\")
noextract=()
md5sums=('SKIP')

pkgver() {
  cd $srcdir/$_bzrmod
  bzr revno
}

build() {
  cd $srcdir/$_bzrmod
  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_bzrmod\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from bzr sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-git-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('git')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=(\"GITURL\")
noextract=()
md5sums=('SKIP')
_gitname=\"MODENAME\"

pkgver() {
 cd $srcdir/$_gitname
 git describe --always | sed 's|-|.|g'
}
build() {
  cd \"$srcdir/$_gitname\"
  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_gitname\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from git sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-svn-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('subversion')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=(\"SVNURL\")
noextract=()
md5sums=('SKIP')
_svnmod=\"MODENAME\"

pkgver() {
  cd $SRCDEST/$_svnmod
  svnversion
}

build() {
  cd \"$srcdir/$_svnmod\"
  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_svnmod\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from svn sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-hg-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('mercurial')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=(\"HGURL\")
noextract=()
md5sums=()
_hgrepo=\"MODENAME\"

pkgver() {
  cd \"$srcdir\"/local_repo
  hg identify -ni | awk 'BEGIN{OFS=\".\";} {print $2,$1}'
}

build() {
  cd \"$srcdir/$_hgrepo\"

  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_hgrepo\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from mercurial sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-cvs-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('cvs')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=()
noextract=()
md5sums=()

_cvsroot=\"CVSROOT\"
_cvsmod=\"MODNAME\"

build() {
  cd \"$srcdir\"
  msg \"Connecting to $_cvsmod.sourceforge.net CVS server...\"
  if [ -d $_cvsmod/CVS ]; then
    cd $_cvsmod
    cvs -z3 update -d
  else
    cvs -z3 -d $_cvsroot co -D $pkgver -f $_cvsmod
    cd $_cvsmod
  fi

  msg \"CVS checkout done or server timeout\"
  msg \"Starting make...\"

  [ -d \"$srcdir/$_cvsmod-build\" ] &&rm -rf \"$srcdir/$_cvsmod-build\"
  cp -r \"$srcdir/$_cvsmod\" \"$srcdir/$_cvsmod-build\"
  cd \"$srcdir/$_cvsmod-build\"


  #
  # BUILD HERE
  #

  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_cvsmod-build\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from cvs sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-darcs-template
"# Maintainer: %s <%s>
pkgname=%s
pkgver=1
pkgrel=1
pkgdesc=\"\"
arch=('i686' 'x86_64')
url=\"\"
license=('GPL')
groups=()
depends=()
makedepends=('darcs')
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
source=()
noextract=()
md5sums=()

_darcstrunk=\"DARCSURL\"
_darcsmod=\"MODNAME\"

build() {
  cd \"$srcdir\"

  msg \"Checking for previous build\"

  if [[ -d $_darcsmod/_darcs ]]
  then
    msg \"Retrieving missing patches\"
    cd $_darcsmod
    darcs pull -a $_darcstrunk/$_darcsmod
  else
    msg \"Retrieving complete sources\"
    darcs get --partial --set-scripts-executable $_darcstrunk/$_darcsmod
    cd $_darcsmod
  fi

  [ -d \"$srcdir/$_darcsmod-build\" ] && rm -rf \"$srcdir/$_darcsmod-build\"
  cp -r \"$srcdir/$_darcsmod\" \"$srcdir/$_darcsmod-build\"
  cd \"$srcdir/$_darcsmod-build\"

  msg \"Starting build\"

  #
  # BUILD
  #

  ./autogen.sh
  ./configure --prefix=/usr
  make
}

package() {
  cd \"$srcdir/$_darcsmod-build\"
  make DESTDIR=\"$pkgdir/\" install
}"
  "Template for new PKGBUILDs to build from darcs sources"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-etags-command "find %s -name PKGBUILD|xargs etags -o %s --language=none --regex='/pkgname=\\([^ \t]+\\)/\\1/'"
  "pkgbuild-etags needs to call the find and the etags program. %s is
the placeholder for the toplevel directory and tagsfile"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-initialize t
  "Automatically add default headings to new pkgbuild files."
  :type 'boolean
  :group 'pkgbuild)

(defcustom pkgbuild-update-sums-on-save t
  "*Non-nil means buffer-safe will call a hook to update the sums line."
  :type 'boolean
  :group 'pkgbuild)

(defcustom pkgbuild-read-makepkg-command nil
  "*Non-nil means \\[pkgbuild-makepkg] reads the makepkg command to use.
Otherwise, \\[pkgbuild-makepkg] just uses the value of `pkgbuild-makepkg-command'."
  :type 'boolean
  :group 'pkgbuild)

(defcustom pkgbuild-read-tar-command t
  "*Non-nil means \\[pkgbuild-tar] reads the tar command to use."
  :type 'boolean
  :group 'pkgbuild)

(defcustom pkgbuild-makepkg-command "makepkg -m -f "
  "Command to create an ArchLinux package."
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-user-full-name user-full-name
  "*Full name of the user.
This is used in the Maintainer tag. It defaults to the
value of `user-full-name'."
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-user-mail-address user-mail-address
  "*Email address of the user.
This is used in the Maintainer tag. It defaults to the
value of `user-mail-address'."
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-source-directory-locations ".:src:/var/cache/pacman/src"
  "search path for PKGBUILD source files"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-sums-command "makepkg -g 2>/dev/null"
  "shell command to generate *sums lines"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-taurball-command "makepkg --source -f 2>/dev/null"
  "shell command to generate *sums lines"
  :type 'string
  :group 'pkgbuild)

(defcustom pkgbuild-ask-about-save t
  "*Non-nil means \\[pkgbuild-makepkg] asks which buffers to save before starting packaging.
Otherwise, it saves all modified buffers without asking."
  :type 'boolean
  :group 'pkgbuild)

;; (defcustom pkgbuild-read-namcap-command t
;;   "*Non-nil means \\[pkgbuild-run-namcap] reads the namcap command to use.
;; Otherwise, \\[pkgbuild-run-namcap] just uses the value of `pkgbuild-run-namcap-command'."
;;   :type 'boolean
;;   :group 'pkgbuild)

(defconst pkgbuild-bash-error-line-re
  "PKGBUILD:[ \t]+line[ \t]\\([0-9]+\\):[ \t]"
  "Regular expression that describes errors.")

(defvar pkgbuild-mode-map nil    ; Create a mode-specific keymap.
  "Keymap for pkgbuild mode.")

;;(defvar pkgbuild-read-namcap-command t)

(defface pkgbuild-error-face '((t (:underline "red")))
  "Face for PKGBUILD errors."
  :group 'pkgbuild)

(defvar pkgbuild-makepkg-history nil)

(defvar pkgbuild-hashtype "md5")

(defvar pkgbuild-in-hook-recursion nil) ;avoid recursion

(defvar pkgbuild-emacs                  ;helper variable for xemacs compatibility
  (cond
   ((string-match "XEmacs" emacs-version)
    'xemacs)
   (t
    'emacs))
  "The type of Emacs we are currently running.")


(unless pkgbuild-mode-map               ; Do not change the keymap if it is already set up.
  (setq pkgbuild-mode-map (make-sparse-keymap))
  (define-key pkgbuild-mode-map "\C-c\C-r" 'pkgbuild-increase-release-tag)
  (define-key pkgbuild-mode-map "\C-c\C-c" 'pkgbuild-makepkg)
  (define-key pkgbuild-mode-map "\C-c\C-t" 'pkgbuild-tar)
  (define-key pkgbuild-mode-map "\C-c\C-b" 'pkgbuild-browse-upstream-url)
  (define-key pkgbuild-mode-map "\C-c\C-a" 'pkgbuild-browse-AUR-url)
  (define-key pkgbuild-mode-map "\C-c\C-m" 'pkgbuild-update-sums-line)
  (define-key pkgbuild-mode-map "\C-c\C-e" 'pkgbuild-etags)
  (define-key pkgbuild-mode-map "\C-c\C-i" 'pkgbuild-install-file-initialize)
  )

(defun pkgbuild-trim-right (str)        ;Helper function
  "Trim whitespace from end of the string"
  (if (string-match "[ \f\t\n\r\v]+$" str -1) 
      (pkgbuild-trim-right (substring str 0 -1))
    str))

(defun pkgbuild-source-points()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (search-forward-regexp "^\\s-*source=(\\([^()]*\\))" (point-max) t)
        (let ((l (list (match-beginning 1) (match-end 1)))
              (end (match-end 1)))
          (goto-char (match-beginning 1))
          (while (search-forward-regexp "\\(\\\\[ \f\t\n\r\v]\\|[ \f\t\n\r\v]\\)+" end t)
                  (setcdr (last l 2) (cons (match-beginning 0) (cdr (last l 2))))
                  (setcdr (last l 2) (cons (match-end 1) (cdr (last l 2)))))
          l)
      nil)))

(defun pkgbuild-source-locations() 
  "find source regions"
  (delete-if (lambda (region) (= (car region) (cdr region))) (loop for item on (pkgbuild-source-points) by 'cddr collect (cons (car item) (cadr item)))))

(defun pkgbuild-shell-command-to-string(COMMAND)
  "same as `shell-command-to-string' always uses '/bin/bash'"
  (let ((shell-file-name "/bin/bash"))
    (shell-command-to-string COMMAND)))

(defun pkgbuild-shell-command (COMMAND &optional OUTPUT-BUFFER ERROR-BUFFER)
  "same as `shell-command' always uses '/bin/bash'"
  (let ((shell-file-name "/bin/bash"))
    (shell-command COMMAND OUTPUT-BUFFER ERROR-BUFFER)))
  
(defun pkgbuild-source-check ()
  "highlight sources not available. Return true if all sources are available. This does not work if globbing returns multiple files"
  (interactive)
  (save-excursion 
    (goto-char (point-min))
    (pkgbuild-delete-all-overlays)
    (if (search-forward-regexp "^\\s-*source=(\\([^()]*\\))" (point-max) t)
        (let ((all-available t)
              (sources (split-string (pkgbuild-shell-command-to-string 
				      "source PKGBUILD && for source in ${source[@]};do echo $source|sed 's+::+@+'|cut -d @ -f1 |sed 's|^.*://.*/||g';done")))
              (source-locations (pkgbuild-source-locations)))
          (if (= (length sources) (length source-locations)) 
              (progn
                (loop for source in sources
                      for source-location in source-locations
                      do (when (not (pkgbuild-find-file source (split-string pkgbuild-source-directory-locations ":")))
                           (progn 
                             (setq all-available nil)
                             (pkgbuild-make-overlay (car source-location) (cdr source-location)))))
                all-available)
            (progn
              (message "cannot verfify sources: don't use globbing %d/%d" (length sources) (length source-locations))
              nil)))
      (progn 
        (message "no source line found")
        nil))))
      
(defun pkgbuild-delete-all-overlays ()
  "Delete all the overlays used by pkgbuild-mode."
  (interactive)                         ;test
  (let ((l (overlays-in (point-min) (point-max))))
    (while (consp l)
      (progn
        (if (pkgbuild-overlay-p (car l))
            (delete-overlay (car l)))
        (setq l (cdr l))))))

(defun pkgbuild-overlay-p (o)
  "A predicate that return true iff O is an overlay used by pkgbuild-mode."
  (and (overlayp o) (overlay-get o 'pkgbuild-overlay)))

(defun pkgbuild-make-overlay (beg end)
  "Allocate an overlay to highlight. BEG and END specify the range in the buffer."
  (let ((pkgbuild-overlay (make-overlay beg end nil t nil)))
    (overlay-put pkgbuild-overlay 'face 'pkgbuild-error-face)
    (overlay-put pkgbuild-overlay 'pkgbuild-overlay t)
    pkgbuild-overlay))

(defun pkgbuild-find-file (file locations)
  "Find file in multible locations"
  (remove-if-not 'file-readable-p (mapcar (lambda (dir) (expand-file-name file dir)) locations)))

(defun pkgbuild-sums-line ()
  "calculate *sums=() line in PKGBUILDs"
  (pkgbuild-shell-command-to-string pkgbuild-sums-command))

(defun pkgbuild-update-sums-line ()
  "Update the sums line in a PKGBUILD."
  (interactive)
  (if (not (file-readable-p "PKGBUILD")) (error "Missing PKGBUILD")
    (if (not (pkgbuild-syntax-check)) (error "Syntax Error")
      (if (pkgbuild-source-check)       ;all sources available
          (save-excursion 
            (goto-char (point-min))
	    (while (re-search-forward "^[[:alnum:]]+sums=([^()]*)[ \f\t\r\v]*\n?" (point-max) t) ;sum line exists
	      (delete-region (match-beginning 0) (match-end 0)))
	    (goto-char (point-min))
	    (if (re-search-forward "^source=([^()]*)" (point-max) t)
                (insert "\n")
              (error "Missing source line"))
            (insert (pkgbuild-trim-right (pkgbuild-sums-line))))))))

(defun pkgbuild-about-pkgbuild-mode (&optional arg)
  "About `pkgbuild-mode'."
  (interactive "p")
  (message
   (concat "pkgbuild-mode version "
           pkgbuild-mode-version
           " by Juergen Hoetzel, <juergen@hoetzel.info>"
	   " and Stefan Husmann, <stefan-husmann@t-online.de>")))

(defun pkgbuild-update-sums-line-hook ()
  "Update sum lines if the file was modified"
  (if (and pkgbuild-update-sums-on-save (not pkgbuild-in-hook-recursion))
      (progn
        (setq pkgbuild-in-hook-recursion t)
        (save-buffer)                   ;always save BUFFER 2 times so we get the correct sums in this hook
        (setq pkgbuild-in-hook-recursion nil)
        (pkgbuild-update-sums-line))))

(defun pkgbuild-install-file-initialize ()
  "create an default install file"
  (interactive)
  (insert (format pkgbuild-install-file-template)))

(defun pkgbuild-initialize ()
  "Create a default pkgbuild if one does not exist or is empty."
  (interactive)
  (cond ((string-match "-bzr" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-bzr-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	((string-match "-git" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-git-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	((string-match "-svn" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-svn-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	((string-match "-hg" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-hg-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	((string-match "-cvs" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-cvs-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	((string-match "-darcs" (pkgbuild-get-directory buffer-file-name))
	 (insert (format pkgbuild-darcs-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))
	(t 
	 (insert (format pkgbuild-generic-template
			 pkgbuild-user-full-name 
			 pkgbuild-user-mail-address 
			 (or (pkgbuild-get-directory (buffer-file-name)) "NAME"))))))

(defun pkgbuild-process-check (buffer)
  "Check if BUFFER has a running process.
If so, give the user the choice of aborting the process or the current
command."
  (let ((process (get-buffer-process (get-buffer buffer))))
    (if (and process (eq (process-status process) 'run))
        (if (yes-or-no-p (concat "Process `" (process-name process)
                                 "' running.  Kill it? "))
            (delete-process process)
          (error "Cannot run two simultaneous processes ...")))))

(defun pkgbuild-get-directory (buffer-file-name)
    (car (last (split-string (file-name-directory (buffer-file-name)) "/" t))))

(defun pkgbuild-makepkg (command)
  "Build this package."
  (interactive
   (if pkgbuild-read-makepkg-command
       (list (read-from-minibuffer "makepkg command: " 
                                   (eval pkgbuild-makepkg-command)
                                   nil nil '(pkgbuild-makepkg-history . 1)))
     (list (eval pkgbuild-makepkg-command))))
  (save-some-buffers (not pkgbuild-ask-about-save) nil)
  (if (file-readable-p "PKGBUILD")
      (let ((pkgbuild-buffer-name (concat "*"  command " " (pkgbuild-get-directory buffer-file-name)  "*")))
        (pkgbuild-process-check pkgbuild-buffer-name)
        (if (get-buffer pkgbuild-buffer-name)
            (kill-buffer pkgbuild-buffer-name))
        (create-file-buffer pkgbuild-buffer-name)
        (display-buffer pkgbuild-buffer-name)
        (with-current-buffer (get-buffer pkgbuild-buffer-name)
          (if (fboundp 'compilation-mode) (compilation-mode pkgbuild-buffer-name))
          (if buffer-read-only (toggle-read-only)) 
          (goto-char (point-max)))
        (let ((process
               (start-process-shell-command "makepkg" pkgbuild-buffer-name
                                            command)))
          (set-process-filter process 'pkgbuild-command-filter)))
    (error "No PKGBUILD in current directory")))

(defun pkgbuild-command-filter (process string)
  "Filter to process normal output."
  (with-current-buffer (process-buffer process)
    (save-excursion
      (goto-char (process-mark process))
      (insert-before-markers string)
      (set-marker (process-mark process) (point)))))

(defun pkgbuild-increase-release-tag ()
  "Increase the release tag by 1."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (search-forward-regexp "^pkgrel=[ \t]*\\([0-9]+\\)[ \t]*$" nil t)
        (let ((release (1+ (string-to-number (match-string 1)))))
          (setq release (int-to-string release))
          (replace-match (concat "pkgrel=" release))
          (message (concat "Release tag changed to " release ".")))
      (message "No Release tag found..."))))

(defun pkgbuild-syntax-check ()
  "evaluate PKGBUILD and search stderr for errors"
  (interactive)
  (let  (
         (stderr-buffer (concat "*PKGBUILD(" (pkgbuild-get-directory (buffer-file-name)) ") stderr*"))
        (stdout-buffer (concat "*PKGBUILD(" (pkgbuild-get-directory (buffer-file-name)) ") stdout*")))
    (if (get-buffer stderr-buffer) (kill-buffer stderr-buffer))
    (if (get-buffer stdout-buffer) (kill-buffer stdout-buffer))
    (if (not (equal 
              (flet ((message (arg &optional args) nil)) ;Hack disable empty output
                (pkgbuild-shell-command "source PKGBUILD" stdout-buffer stderr-buffer))
              0))
        (multiple-value-bind (err-p line) (pkgbuild-postprocess-stderr stderr-buffer)
          (if err-p
              (goto-line line))
          nil)
      t)))

(defun pkgbuild-postprocess-stderr (buf)        ;multiple values return
  "Find errors in BUF.If an error occurred return multiple values (t line), otherwise return multiple values (nil line).  BUF must exist."
  (let (line err-p)
    (with-current-buffer buf (goto-char (point-min))
      (if (re-search-forward pkgbuild-bash-error-line-re nil t)
          (progn
            (setq line (string-to-number (match-string 1)))
            ; (pkgbuild-highlight-line line) TODO
            (setq err-p t)))
      (values err-p line))))
  
(defun pkgbuild-tar ()
   "Build a tarball containing all required files to build the package."
(interactive)
       (pkgbuild-shell-command-to-string pkgbuild-taurball-command))

(defun pkgbuild-browse-upstream-url ()
  "Visit upstream URL (if defined in PKGBUILD)"
  (interactive)
  (let ((url (pkgbuild-shell-command-to-string (concat (buffer-string) "\nsource /dev/stdin >/dev/null 2>&1 && echo -n $url" ))))
    (if (string= url "")
        (message "No URL defined in PKGBUILD") 
      (browse-url url))))

(defun pkgbuild-browse-AUR-url ()
  "Visit AUR URL"
  (interactive)
  (let ((url (pkgbuild-shell-command-to-string (concat (buffer-string) "echo https://aur.archlinux.org/packages/$\(source PKGBUILD && echo $pkgname|sed 's+ +/+g'\)"))))
    (if (string= url "")
        (message "No URL defined in PKGBUILD") 
      (browse-url url))))

;;;###autoload
(define-derived-mode pkgbuild-mode shell-script-mode "PKGBUILD"
  "Major mode for editing PKGBUILD files. This is much like shell-script-mode mode.
 Turning on pkgbuild mode calls the value of the variable `pkgbuild-mode-hook'
with no args, if that value is non-nil."
  (require 'easymenu)
  (easy-menu-define pkgbuild-call-menu pkgbuild-mode-map
                    "Post menu for `pkgbuild-mode'." pkgbuild-mode-menu)
  (set (make-local-variable 'sh-basic-offset) 2) ;This is what judd uses
  (sh-set-shell "/bin/bash")
  (easy-menu-add pkgbuild-mode-menu)
  ;; This does not work because makepkg requires safed file
  (add-hook 'local-write-file-hooks 'pkgbuild-update-sums-line-hook nil t)
  (if (= (buffer-size) 0)              
      (pkgbuild-initialize)
    (and (pkgbuild-syntax-check) (pkgbuild-source-check))))

(defadvice sh-must-be-shell-mode (around no-check-if-in-pkgbuild-mode activate)
  "Do not check for shell-mode if major mode is \\[pkgbuild-makepkg]"
  (if (not (eq major-mode 'pkgbuild-mode)) ;workaround for older shell-script-mode versions
      ad-do-it))                                

(defun pkgbuild-etags (toplevel-directory)
  "Create TAGS file by running `etags' recursively on the directory tree `pkgbuild-toplevel-directory'.
  The TAGS file is also immediately visited with `visit-tags-table'."
  (interactive "DToplevel directory: ")
  (let* ((etags-file (expand-file-name "TAGS" toplevel-directory)) 
	 (cmd (format pkgbuild-etags-command toplevel-directory etags-file)))
    (require 'etags)
    (message "Running etags to create TAGS file: %s" cmd)
    (pkgbuild-shell-command cmd)
    (visit-tags-table etags-file)))

(provide 'pkgbuild-mode)

;;; pkgbuild-mode.el ends here
