;;; ob-clojure.el --- Babel Functions for Clojure    -*- lexical-binding: t; -*-
;;;;;;;COPIED FROM Org Mode repo: http://orgmode.org/ ;;;;;;;
;;;;;;;because the released Org Mode doesn't include this for some reason ;;;;;;;

;; Copyright (C) 2009-2016 Free Software Foundation, Inc.

;; Author: Joel Boehland, Eric Schulte, Oleh Krehel
;;
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Support for evaluating clojure code

;; Requirements:

;; - clojure (at least 1.2.0)
;; - clojure-mode
;; - either cider or SLIME

;; For Cider, see https://github.com/clojure-emacs/cider

;; For SLIME, the best way to install these components is by following
;; the directions as set out by Phil Hagelberg (Technomancy) on the
;; web page: http://technomancy.us/126

;;; Code:
(require 'cl-lib)
(require 'ob)

(declare-function cider-current-connection "ext:cider-client" (&optional type))
(declare-function cider-current-session "ext:cider-client" ())
(declare-function nrepl-dict-get "ext:nrepl-client" (dict key))
(declare-function nrepl-sync-request:eval "ext:nrepl-client"
                  (input connection session &optional ns))
(declare-function org-trim "org" (s &optional keep-lead))
(declare-function slime-eval "ext:slime" (sexp &optional package))

(defvar org-babel-tangle-lang-exts)
(add-to-list 'org-babel-tangle-lang-exts '("clojure" . "clj"))

(defvar org-babel-default-header-args:clojure '())
(defvar org-babel-header-args:clojure '((package . :any)))

(defcustom org-babel-clojure-backend
  (cond ((featurep 'cider) 'cider)
        (t 'slime))
  "Backend used to evaluate Clojure code blocks."
  :group 'org-babel
  :type '(choice
          (const :tag "cider" cider)
          (const :tag "SLIME" slime)))

(defun org-babel-expand-body:clojure (body params)
  "Expand BODY according to PARAMS, return the expanded body."
  (let* ((vars (org-babel--get-vars params))
         (result-params (cdr (assq :result-params params)))
         (print-level nil) (print-length nil)
         (body (org-trim
                (if (null vars) (org-trim body)
                  (concat "(let ["
                          (mapconcat
                           (lambda (var)
                             (format "%S (quote %S)" (car var) (cdr var)))
                           vars "\n      ")
                          "]\n" body ")")))))
    (if (or (member "code" result-params)
            (member "pp" result-params))
        (format "(clojure.pprint/pprint (do %s))" body)
      body)))

;; (defun org-babel-execute:clojure (body params)
;;   "Execute a block of Clojure code with Babel."
;;   (let ((expanded (org-babel-expand-body:clojure body params))
;;         result)
;;     (cl-case org-babel-clojure-backend
;;       (cider
;;        (require 'cider)
;;        (let ((result-params (cdr (assq :result-params params))))
;;          (setq result
;;                (nrepl-dict-get
;;                 (nrepl-sync-request:eval
;;                  expanded (cider-current-connection) (cider-current-session))
;;                 (if (or (member "output" result-params)
;;                         (member "pp" result-params))
;;                     "out"
;;                   "value")))))
;;       (slime
;;        (require 'slime)
;;        (with-temp-buffer
;;          (insert expanded)
;;          (setq result
;;                (slime-eval
;;                 `(swank:eval-and-grab-output
;;                   ,(buffer-substring-no-properties (point-min) (point-max)))
;;                 (cdr (assq :package params)))))))
;;     (org-babel-result-cond (cdr (assq :result-params params))
;;       result
;;       (condition-case nil (org-babel-script-escape result)
;;         (error result)))))

;;;code below from
;;;http://fgiasson.com/blog/index.php/2016/04/05/using-clojure-in-org-mode-and-implementing-asynchronous-processing/
(defvar org-babel-clojure-nrepl-timeout nil)

(defun org-babel-execute:clojure (body params)
  "Execute a block of Clojure code with Babel."
  (lexical-let* ((expanded (org-babel-expand-body:clojure body params))
                 ;; name of the buffer that will receive the asyn output
                 (sbuffer "*Clojure Sub Buffer*")
                 ;; determine if the :async option is specified for this block
                 (async (if (assoc :async params) t nil))
                 ;; generate the full response from the REPL
                 (response (cons 'dict nil))
                 ;; keep track of the status of the output in async mode
                 status
                 ;; result to return to Babel
                 result)
    (case org-babel-clojure-backend
      (cider
       (require 'cider)
       (let ((result-params (cdr (assoc :result-params params))))
         ;; Check if the user want to run code asynchronously
         (when async
           ;; Create a new window with the async output buffer
           (switch-to-buffer-other-window sbuffer)

           ;; Run the Clojure code asynchronously in nREPL
           (nrepl-request:eval
            expanded
            (lambda (resp)
              (when (member "out" resp)
                ;; Print the output of the nREPL in the asyn output buffer
                (princ (nrepl-dict-get resp "out") (get-buffer sbuffer)))
              (nrepl--merge response resp)
              ;; Update the status of the nREPL output session
              (setq status (nrepl-dict-get response "status")))
            (cider-current-connection)
            (cider-current-session))

           ;; Wait until the nREPL code finished to be processed
           (while (not (member "done" status))
             (nrepl-dict-put response "status" (remove "need-input" status))
             (accept-process-output nil 0.01)
             (redisplay))

           ;; Delete the async buffer & window when the processing is finalized
           (let ((wins (get-buffer-window-list sbuffer nil t)))
             (dolist (win wins)
               (delete-window win))
             (kill-buffer sbuffer))

           ;; Put the output or the value in the result section of the code block
           (setq result (nrepl-dict-get response
                                        (if (or (member "output" result-params)
                                                (member "pp" result-params))
                                            "out"
                                          "value"))))
         ;; Check if user want to run code synchronously
         (when (not async)
           (setq result
                 (nrepl-dict-get
                  (let ((nrepl-sync-request-timeout
                         org-babel-clojure-nrepl-timeout))
                    (nrepl-sync-request:eval
                     expanded (cider-current-connection) (cider-current-session)))
                  (if (or (member "output" result-params)
                          (member "pp" result-params))
                      "out"
                    "value"))))))
      (slime
       (require 'slime)
       (with-temp-buffer
         (insert expanded)
         (setq result
               (slime-eval
                `(swank:eval-and-grab-output
                  ,(buffer-substring-no-properties (point-min) (point-max)))
                (cdr (assoc :package params)))))))
    (org-babel-result-cond (cdr (assoc :result-params params))
      result
      (condition-case nil (org-babel-script-escape result)
        (error result)))))

(provide 'ob-clojure)

;;; ob-clojure.el ends here
