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
  '((:name "#"       :width 6  :field number            :sort nil :format nil)
    (:name "State"   :width 8  :field state             :sort nil :format nil)
    (:name "CI"      :width 3  :field statusCheckRollup :sort nil :format egh-pr--format-checks)
    (:name "Title"   :width 50 :field title             :sort nil :format nil)
    (:name "Author"  :width 15 :field author            :sort nil :format egh-pr--format-author)
    (:name "Branch"  :width 25 :field headRefName       :sort nil :format nil)
    (:name "Labels"  :width 15 :field labels            :sort nil :format egh-pr--format-labels)
    (:name "Updated" :width 12 :field updatedAt         :sort nil :format egh-pr--format-time))
  "Column definitions for PR list."
  :group 'egh
  :type 'sexp)

(defcustom egh-pr-default-sort-key '("#" . nil)
  "Default sort key for PR list."
  :group 'egh
  :type '(cons string boolean))

(defvar-local egh-pr--args nil
  "Current filter arguments for PR list.")

(defvar-local egh-pr--repo nil
  "Repository name (owner/repo) for this PR list buffer.")

(defconst egh-pr--extra-fields '("isDraft")
  "Extra JSON fields to fetch beyond column definitions.")

(defun egh-pr--json-fields ()
  "Return comma-separated JSON field names from `egh-pr-columns'."
  (s-join ","
          (-uniq
           (append (-map (lambda (col)
                           (let ((field (plist-get col :field)))
                             (symbol-name field)))
                         egh-pr-columns)
                   egh-pr--extra-fields))))

(defun egh-pr-entries (&optional args)
  "Fetch PR list entries.  ARGS are extra gh arguments."
  (let* ((fields (egh-pr--json-fields))
         (cmd-args `("pr" "list" "--json" ,fields "--limit" "100"))
         (cmd-args (if egh-pr--repo
                       (append cmd-args (list "--repo" egh-pr--repo))
                     cmd-args))
         (valid-args (when args
                       (--filter (string-match-p "\\`--[^ ]+ .+" it) args)))
         (cmd-args (if valid-args
                       (append cmd-args (flatten-list (-map #'split-string valid-args)))
                     cmd-args))
         (data (apply #'egh-gh-json cmd-args)))
    (dolist (item data)
      (when (eq (alist-get 'isDraft item) t)
        (setf (alist-get 'state item) "DRAFT")))
    (-map (-partial #'egh-utils-parse-entry egh-pr-columns) data)))

(defun egh-pr--state-face (state)
  "Return face for PR STATE string."
  (pcase (downcase state)
    ("open" 'egh-face-state-open)
    ("closed" 'egh-face-state-closed)
    ("merged" 'egh-face-state-merged)
    ("draft" 'egh-face-draft)
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
    (define-key map "b" #'egh-pr-switch)
    (define-key map "o" #'egh-pr-browse)
    (define-key map "c" #'egh-pr-comment)
    (define-key map "l" #'egh-pr-ls)
    (define-key map "m" #'egh-pr-merge)
    (define-key map "C" #'egh-pr-close)
    (define-key map "R" #'egh-pr-reopen)
    (define-key map "k" #'egh-pr-checkout)
    (define-key map "O" #'egh-pr-ready)
    (define-key map "D" #'egh-pr-draft)
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
  (let ((repo (egh-repo-name)))
    (egh-utils-pop-to-buffer (format "*egh-pull-requests: %s*" repo))
    (egh-pr-mode)
    (setq-local egh-pr--repo repo)
    (tablist-revert)))

;; Actions

(defun egh-pr-view-at-point ()
  "View PR at point in detail buffer."
  (interactive)
  (let ((number (tabulated-list-get-id)))
    (when number
      (require 'egh-pr-view)
      (egh-pr-view (string-to-number number) egh-pr--repo))))

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
  "Checkout PR at point via gh pr checkout."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (error "No PR at point"))
    (egh-gh-command "pr" "checkout" id)
    (message "Checked out PR #%s" id)))

(defun egh-pr-ready ()
  "Mark PR at point as ready for review."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (error "No PR at point"))
    (egh-gh-command "pr" "ready" id
                    (when egh-pr--repo (list "--repo" egh-pr--repo)))
    (message "PR #%s marked as ready" id)
    (tablist-revert)))

(defun egh-pr-draft ()
  "Convert PR at point to draft."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless id (error "No PR at point"))
    (egh-gh-command "pr" "ready" id "--undo"
                    (when egh-pr--repo (list "--repo" egh-pr--repo)))
    (message "PR #%s converted to draft" id)
    (tablist-revert)))

(defun egh-pr--branch-at-point ()
  "Return the branch name of the PR at point."
  (let ((entry (tabulated-list-get-entry)))
    (unless entry (error "No PR at point"))
    (let ((branch-idx (--find-index (eq (plist-get it :field) 'headRefName) egh-pr-columns)))
      (when branch-idx (aref entry branch-idx)))))

(defun egh-pr-switch ()
  "Switch to the local branch of the PR at point."
  (interactive)
  (let ((branch (egh-pr--branch-at-point)))
    (unless branch (error "No branch found"))
    (let ((default-directory (or (vc-root-dir) default-directory)))
      (vc-git-command nil 0 nil "switch" branch)
      (message "Switched to branch %s" branch))))

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
  (let* ((id (or (tabulated-list-get-id)
                 (and (boundp 'egh-pr-view--number)
                      (number-to-string egh-pr-view--number))))
         (repo (or (and (boundp 'egh-pr--repo) egh-pr--repo)
                   (and (boundp 'egh-pr-view--repo) egh-pr-view--repo))))
    (unless id (error "No PR selected"))
    (apply #'egh-gh-command "pr" "merge" id
           (append args (when repo (list "--repo" repo))))
    (message "Merged PR #%s" id)
    (cond
     ((derived-mode-p 'egh-pr-mode)
      (tablist-revert))
     ((derived-mode-p 'egh-pr-view-mode)
      (revert-buffer)
      (egh-pr-view--refresh-list repo)))))

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
    ("o" "Open in browser" egh-pr-browse)
    ("l" "Filter list" egh-pr-ls)]
   ["Actions"
    ("b" "Switch branch" egh-pr-switch)
    ("k" "Checkout (remote)" egh-pr-checkout)
    ("c" "Comment" egh-pr-comment)
    ("m" "Merge" egh-pr-merge)
    ("C" "Close" egh-pr-close)
    ("R" "Reopen" egh-pr-reopen)
    ("O" "Ready for review" egh-pr-ready)
    ("D" "Convert to draft" egh-pr-draft)]])

(provide 'egh-pr)
;;; egh-pr.el ends here
