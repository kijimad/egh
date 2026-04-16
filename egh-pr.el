;;; egh-pr.el --- PR list mode for egh -*- lexical-binding: t -*-

;; Copyright (C) 2026

;;; Commentary:

;; Tabulated list mode for GitHub Pull Requests using gh CLI.

;;; Code:

(require 'egh-core)
(require 'egh-faces)
(require 'tablist)
(require 'transient)

(declare-function egh-pr-view "egh-pr-view")
(declare-function egh-pr-comment--start "egh-pr-view")

(defcustom egh-pr-columns
  '((:name "#"       :width 6  :field number      :sort nil :format nil)
    (:name "State"   :width 8  :field state       :sort nil :format nil)
    (:name "Title"   :width 50 :field title       :sort nil :format nil)
    (:name "Author"  :width 15 :field author      :sort nil :format egh-pr--format-author)
    (:name "Branch"  :width 25 :field headRefName :sort nil :format nil)
    (:name "Labels"  :width 15 :field labels      :sort nil :format egh-pr--format-labels)
    (:name "Updated" :width 12 :field updatedAt   :sort nil :format egh-pr--format-time))
  "Column definitions for PR list."
  :group 'egh
  :type 'sexp)

(defcustom egh-pr-default-sort-key '("#" . nil)
  "Default sort key for PR list."
  :group 'egh
  :type '(cons string boolean))

(defvar-local egh-pr--args nil
  "Current filter arguments for PR list.")

(defun egh-pr--json-fields ()
  "Return comma-separated JSON field names from `egh-pr-columns'."
  (s-join ","
          (-uniq
           (-map (lambda (col)
                   (let ((field (plist-get col :field)))
                     (symbol-name field)))
                 egh-pr-columns))))

(defun egh-pr-entries (&optional args)
  "Fetch PR list entries.  ARGS are extra gh arguments."
  (let* ((fields (egh-pr--json-fields))
         (cmd-args `("pr" "list" "--json" ,fields "--limit" "100"))
         (cmd-args (if args (append cmd-args args) cmd-args))
         (data (apply #'egh-gh-json cmd-args)))
    (-map (-partial #'egh-utils-parse-entry egh-pr-columns) data)))

(defun egh-pr--state-face (state)
  "Return face for PR STATE string."
  (pcase (downcase state)
    ("open" 'egh-face-state-open)
    ("closed" 'egh-face-state-closed)
    ("merged" 'egh-face-state-merged)
    (_ nil)))

(defun egh-pr-propertize-entry (entry)
  "Add faces to ENTRY state column."
  (let* ((state-idx (--find-index (eq (plist-get it :field) 'state) egh-pr-columns))
         (data (cadr entry)))
    (when state-idx
      (let* ((state (aref data state-idx))
             (face (egh-pr--state-face state)))
        (when face
          (aset data state-idx (propertize state 'font-lock-face face)))))
    entry))

(defun egh-pr-refresh ()
  "Refresh the PR list."
  (setq tabulated-list-entries
        (-map #'egh-pr-propertize-entry (egh-pr-entries egh-pr--args)))
  (tabulated-list-print t))

(defvar egh-pr-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'egh-pr-view-at-point)
    (define-key map "?" #'egh-pr-help)
    (define-key map "b" #'egh-pr-browse)
    (define-key map "c" #'egh-pr-comment)
    (define-key map "l" #'egh-pr-ls)
    (define-key map "m" #'egh-pr-merge)
    (define-key map "C" #'egh-pr-close)
    (define-key map "R" #'egh-pr-reopen)
    (define-key map "k" #'egh-pr-checkout)
    map)
  "Keymap for `egh-pr-mode'.")

(define-derived-mode egh-pr-mode tabulated-list-mode "PRs"
  "Major mode for listing GitHub Pull Requests."
  (setq tabulated-list-format (egh-utils-columns-list-format egh-pr-columns))
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key egh-pr-default-sort-key)
  (add-hook 'tabulated-list-revert-hook #'egh-pr-refresh nil t)
  (tabulated-list-init-header)
  (tablist-minor-mode))

;;;###autoload
(defun egh-pull-requests ()
  "List GitHub pull requests for the current repository."
  (interactive)
  (egh-utils-pop-to-buffer "*egh-pull-requests*")
  (egh-pr-mode)
  (tablist-revert))

;; Actions

(defun egh-pr-view-at-point ()
  "View PR at point in detail buffer."
  (interactive)
  (let ((number (tabulated-list-get-id)))
    (when number
      (require 'egh-pr-view)
      (egh-pr-view (string-to-number number)))))

(defun egh-pr-browse ()
  "Open selected PRs in browser."
  (interactive)
  (dolist (id (egh-utils-ensure-items))
    (egh-gh-command "pr" "view" "--web" id)))

(defun egh-pr-comment ()
  "Add comment to PR at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (error "No PR at point"))
    (require 'egh-pr-view)
    (egh-pr-comment--start id)))

(defun egh-pr-close ()
  "Close selected PRs."
  (interactive)
  (dolist (id (egh-utils-ensure-items))
    (egh-gh-command "pr" "close" id))
  (tablist-revert))

(defun egh-pr-reopen ()
  "Reopen selected PRs."
  (interactive)
  (dolist (id (egh-utils-ensure-items))
    (egh-gh-command "pr" "reopen" id))
  (tablist-revert))

(defun egh-pr-checkout ()
  "Checkout PR at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (error "No PR at point"))
    (egh-gh-command "pr" "checkout" id)
    (message "Checked out PR #%s" id)))

;; Transient menus

(transient-define-prefix egh-pr-merge ()
  "Merge a pull request."
  ["Arguments"
   ("-s" "Squash" "--squash")
   ("-r" "Rebase" "--rebase")
   ("-d" "Delete branch" "--delete-branch")
   ("-a" "Auto-merge" "--auto")]
  ["Actions"
   ("m" "Merge" egh-pr-merge--execute)])

(defun egh-pr-merge--execute (&optional args)
  "Execute merge with transient ARGS."
  (interactive (list (transient-args 'egh-pr-merge)))
  (let ((id (or (tabulated-list-get-id)
                (and (boundp 'egh-pr-view--number)
                     (number-to-string egh-pr-view--number)))))
    (unless id (error "No PR selected"))
    (apply #'egh-gh-command "pr" "merge" id args)
    (message "Merged PR #%s" id)
    (when (derived-mode-p 'egh-pr-mode)
      (tablist-revert))))

(transient-define-prefix egh-pr-ls ()
  "Filter pull request list."
  ["Filters"
   ("-s" "State" "--state "
    :reader (lambda (prompt &rest _)
              (completing-read prompt '("open" "closed" "merged" "all"))))
   ("-a" "Author" "--author ")
   ("-l" "Label" "--label ")
   ("-b" "Base branch" "--base ")
   ("-L" "Limit" "--limit ")]
  ["Actions"
   ("l" "List" egh-pr-ls--execute)])

(defun egh-pr-ls--execute (&optional args)
  "Execute PR list with filter ARGS."
  (interactive (list (transient-args 'egh-pr-ls)))
  (setq egh-pr--args args)
  (tablist-revert))

(transient-define-prefix egh-pr-help ()
  "Help for PR list."
  ["Pull Requests"
   ["View"
    ("RET" "View PR" egh-pr-view-at-point)
    ("b" "Browse in browser" egh-pr-browse)
    ("l" "Filter list" egh-pr-ls)]
   ["Actions"
    ("c" "Comment" egh-pr-comment)
    ("m" "Merge" egh-pr-merge)
    ("C" "Close" egh-pr-close)
    ("R" "Reopen" egh-pr-reopen)
    ("k" "Checkout" egh-pr-checkout)]])

(provide 'egh-pr)
;;; egh-pr.el ends here
