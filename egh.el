;;; egh.el --- GitHub CLI interface for Emacs -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: violet
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (dash "2.19.1") (s "1.13.0") (tablist "1.1") (transient "0.4.3"))
;; Keywords: tools, github
;; URL: https://github.com/kijimad/egh

;;; Commentary:

;; egh provides an Emacs interface to GitHub Pull Requests using the gh CLI.
;; Use `egh-pull-requests-open' to list PRs for the current repository.

;;; Code:

(require 'egh-core)
(require 'egh-pr)
(require 'transient)

;;;###autoload (autoload 'egh "egh" nil t)
(transient-define-prefix egh ()
  "GitHub CLI operations."
  ["Pull Requests"
   ("p" "Open PRs" egh-pull-requests-open)
   ("P" "All PRs" egh-pull-requests-all)
   ("m" "My PRs" egh-pull-requests-mine)])

(provide 'egh)
;;; egh.el ends here
