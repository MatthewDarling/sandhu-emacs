(setq ns-use-srgb-colorspace nil)

;; Remove the UI
(dolist (mode '(tool-bar-mode scroll-bar-mode))
  (when (fboundp mode) (funcall mode -1)))
(when (and (fboundp 'menu-bar-mode)
           (not (equal system-type 'darwin)))
  (menu-bar-mode -1))
(setq inhibit-startup-message t)
(set-fringe-mode '(1 . 1))
(setq use-dialog-box nil)

;; Make sure path is correct when launched as application
(setenv "PATH" (concat "/usr/local/bin:" (getenv "PATH")))
(push "/usr/local/bin" exec-path)

;; Don't save stuff into init.el
(setq custom-file (expand-file-name "emacs-custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))

;; Setup the package management
(require 'package)
(setq package-enable-at-startup nil)
(setq package-user-dir "~/.emacs.d/elpa/")
(add-to-list 'package-archives '("melpa-stable" . "http://stable.melpa.org/packages/") t)
(add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/") t)
;;; GNU ELPA has been down for several weeks in early 2019, remove it for now
;;; Also, this syntax is horrible, will be better in Emacs 27 apparently:
;;; https://stackoverflow.com/a/54602877/1137749
(setq package-archives (delq (assoc "gnu" package-archives) package-archives))
(setq package-archive-priorities '(("melpa-stable" . 30) ("gnu" . 20) ("melpa" . 10)))

(package-initialize)

;; Bootstrap 'use-package'
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)

;; Load the configuration
(let ((user-config-file (expand-file-name (concat user-login-name ".el") user-emacs-directory)))
  (dolist (dir (list "lisp" "config" user-login-name))
    (let ((config-dir (expand-file-name dir user-emacs-directory)))
      (when (file-exists-p config-dir)
        (add-to-list 'load-path config-dir)
        (mapc 'load (directory-files config-dir nil "^[^#].*el$")))))
  (when (file-exists-p user-config-file) (load user-config-file)))

;; Run the emacs server
(use-package server
  :if window-system
  :init (add-hook 'after-init-hook 'server-start t))
