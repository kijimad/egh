;;; egh-pr-view.el --- PR detail view for egh -*- lexical-binding: t -*-

;; Copyright (C) 2026

;;; Commentary:

;; Individual PR detail buffer for viewing and editing.

;;; Code:

(require 'egh-core)
(require 'egh-faces)

(declare-function egh-pr-merge "egh-pr")

(defun egh-pr-view--buffer-name (repo number)
  "Return buffer name for REPO and PR NUMBER."
  (format "*egh-pr: %s #%s*" repo number))

(defun egh-pr-view--refresh-buffer (repo number)
  "Refresh the PR view buffer for REPO and NUMBER if it exists."
  (let ((buf (get-buffer (egh-pr-view--buffer-name repo number))))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (revert-buffer)))))

(defun egh-pr-view--refresh-list (repo)
  "Refresh all PR list buffers for REPO if they exist."
  (dolist (suffix '("open" "all" "mine"))
    (let ((buf (get-buffer (format "*egh-pull-requests-%s: %s*" suffix repo))))
      (when (and buf (buffer-live-p buf))
        (with-current-buffer buf
          (tablist-revert))))))

(defvar-local egh-pr-view--number nil
  "PR number for this buffer.")

(defvar-local egh-pr-view--repo nil
  "Repository name for this buffer.")

(defvar-local egh-pr-view--data nil
  "PR data alist for this buffer.")

(defconst egh-pr-view--fields
  "number,title,body,author,state,createdAt,updatedAt,comments,reviews,reviewDecision,labels,headRefName,baseRefName,url,additions,deletions,changedFiles,isDraft,statusCheckRollup,commits"
  "JSON fields for PR view.")

(defun egh-pr-view--fetch (number &optional repo)
  "Fetch PR data for NUMBER, optionally in REPO."
  (let ((args (list "pr" "view" (number-to-string number)
                    "--json" egh-pr-view--fields)))
    (when repo (setq args (append args (list "--repo" repo))))
    (apply #'egh-gh-json args)))

(defun egh-pr-view--state-string (data)
  "Return propertized state string from DATA."
  (let* ((state (alist-get 'state data))
         (draft (eq (alist-get 'isDraft data) t))
         (display (if draft "DRAFT" (upcase state)))
         (face (if draft 'egh-face-draft
                 (pcase (downcase state)
                   ("open" 'egh-face-state-open)
                   ("closed" 'egh-face-state-closed)
                   ("merged" 'egh-face-state-merged)
                   (_ nil)))))
    (if face (propertize display 'font-lock-face face) display)))

(defun egh-pr-view--review-string (decision)
  "Return propertized review DECISION string."
  (let ((face (pcase decision
                ("APPROVED" 'egh-face-review-approved)
                ("CHANGES_REQUESTED" 'egh-face-review-changes-requested)
                (_ nil)))
        (display (or decision "PENDING")))
    (if face (propertize display 'font-lock-face face) display)))

(defun egh-pr-view--format-time (time-str)
  "Format TIME-STR for display."
  (if (and time-str (stringp time-str) (not (string-empty-p time-str)))
      (format-time-string "%Y-%m-%d %H:%M" (date-to-time time-str))
    ""))

(defun egh-pr-view--insert-header (data)
  "Insert PR header from DATA."
  (let ((number (alist-get 'number data))
        (title (alist-get 'title data))
        (author (egh-pr--format-author (alist-get 'author data)))
        (state-str (egh-pr-view--state-string data))
        (head (alist-get 'headRefName data))
        (base (alist-get 'baseRefName data))
        (labels (alist-get 'labels data))
        (review (alist-get 'reviewDecision data))
        (additions (alist-get 'additions data))
        (deletions (alist-get 'deletions data))
        (files (alist-get 'changedFiles data))
        (created (alist-get 'createdAt data))
        (updated (alist-get 'updatedAt data))
        (url (alist-get 'url data)))
    (insert (propertize (format "#%s" number) 'font-lock-face 'bold)
            " [" state-str "] "
            (propertize title 'font-lock-face 'bold)
            "\n")
    (insert (format "Author: %-16s Branch: %s -> %s\n" author head base))
    (when labels
      (insert (format "Labels: %s    " (egh-pr--format-labels labels))))
    (insert (format "Review: %s\n" (egh-pr-view--review-string review)))
    (insert (propertize (format "+%s" (or additions 0)) 'font-lock-face 'success)
            " "
            (propertize (format "-%s" (or deletions 0)) 'font-lock-face 'error)
            (format "  %s files changed\n" (or files 0)))
    (insert (format "Created: %s  Updated: %s\n"
                    (egh-pr-view--format-time created)
                    (egh-pr-view--format-time updated)))
    (insert (format "URL: %s\n" (or url "")))))

(defun egh-pr-view--insert-body (data)
  "Insert PR body from DATA."
  (let ((body (alist-get 'body data)))
    (insert "\n" (propertize "--- Body ---" 'font-lock-face 'bold) "\n")
    (if (and body (not (string-empty-p body)))
        (insert body "\n")
      (insert "(no description)\n"))))

(defun egh-pr-view--insert-comments (data)
  "Insert PR comments from DATA."
  (let ((comments (alist-get 'comments data)))
    (insert "\n" (propertize (format "--- Comments (%d) ---" (length comments))
                             'font-lock-face 'bold)
            "\n")
    (if (null comments)
        (insert "(no comments)\n")
      (dolist (comment comments)
        (let ((author (egh-pr--format-author (alist-get 'author comment)))
              (created (egh-pr-view--format-time (alist-get 'createdAt comment)))
              (body (alist-get 'body comment)))
          (insert "\n" (propertize (format "@%s" author) 'font-lock-face 'bold)
                  (format " (%s):\n" created))
          (insert (or body "") "\n"))))))

(defun egh-pr-view--insert-reviews (data)
  "Insert PR reviews from DATA."
  (let ((reviews (alist-get 'reviews data)))
    (when reviews
      (insert "\n" (propertize "--- Reviews ---" 'font-lock-face 'bold) "\n")
      (dolist (review reviews)
        (let ((author (egh-pr--format-author (alist-get 'author review)))
              (state (alist-get 'state review))
              (submitted (egh-pr-view--format-time (alist-get 'submittedAt review))))
          (insert (format "@%s: %s (%s)\n" author
                          (egh-pr-view--review-string state) submitted)))))))

(defun egh-pr-view--check-icon (state)
  "Return icon string for check STATE."
  (let ((s (downcase (or state ""))))
    (pcase s
      ((or "success" "neutral" "skipped")
       (propertize "✓" 'font-lock-face 'egh-face-checks-pass))
      ((or "failure" "error" "cancelled" "timed_out"
           "startup_failure" "stale" "action_required")
       (propertize "✗" 'font-lock-face 'egh-face-checks-fail))
      (_
       (propertize "●" 'font-lock-face 'egh-face-checks-pending)))))

(defun egh-pr-view--latest-commit (data)
  "Return the latest commit alist from DATA, or nil."
  (let ((commits (alist-get 'commits data)))
    (when (and commits (listp commits))
      (car (last commits)))))

(defun egh-pr-view--insert-checks (data)
  "Insert CI checks section from DATA."
  (let* ((checks (alist-get 'statusCheckRollup data))
         (summary (egh-pr--checks-summary (or checks '())))
         (pass (nth 0 summary))
         (total (nth 3 summary))
         (commit (egh-pr-view--latest-commit data)))
    (insert "\n" (propertize (format "--- Checks (%d/%d passed) ---" pass total)
                             'font-lock-face 'bold)
            "\n")
    (when commit
      (let ((oid (or (alist-get 'oid commit) ""))
            (headline (or (alist-get 'messageHeadline commit) "")))
        (insert (format "Latest: %s %s\n"
                        (propertize (substring oid 0 (min 7 (length oid)))
                                    'font-lock-face 'shadow)
                        headline))))
    (if (null checks)
        (insert "(no checks)\n")
      (dolist (check checks)
        (let ((name (or (alist-get 'name check) ""))
              (state (or (alist-get 'state check) ""))
              (workflow (or (alist-get 'workflow check) nil)))
          (insert (egh-pr-view--check-icon state) "  "
                  (propertize name 'font-lock-face 'bold))
          (when (and workflow (listp workflow))
            (let ((wf-name (alist-get 'name workflow)))
              (when wf-name
                (insert "  " wf-name))))
          (insert (format "  (%s)\n" (downcase state))))))))

(defun egh-pr-view--render (data)
  "Render PR DATA into current buffer."
  (egh-pr-view--insert-header data)
  (egh-pr-view--insert-checks data)
  (egh-pr-view--insert-body data)
  (egh-pr-view--insert-comments data)
  (egh-pr-view--insert-reviews data))

(defun egh-pr-view--revert (_ignore-auto _noconfirm)
  "Revert PR view buffer."
  (let* ((number egh-pr-view--number)
         (repo egh-pr-view--repo)
         (data (egh-pr-view--fetch number repo))
         (inhibit-read-only t))
    (erase-buffer)
    (egh-pr-view--render data)
    (setq egh-pr-view--data data)
    (goto-char (point-min))))

(defvar egh-pr-view-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "c" #'egh-pr-view-comment)
    (define-key map "e" #'egh-pr-view-edit)
    (define-key map "o" #'egh-pr-view-browse)
    (define-key map "m" #'egh-pr-view-merge)
    (define-key map "C" #'egh-pr-view-close)
    (define-key map "R" #'egh-pr-view-reopen)
    (define-key map "k" #'egh-pr-view-checkout)
    (define-key map "O" #'egh-pr-view-ready)
    (define-key map "D" #'egh-pr-view-draft)
    (define-key map "g" #'revert-buffer)
    map)
  "Keymap for `egh-pr-view-mode'.")

(define-derived-mode egh-pr-view-mode special-mode "PR View"
  "Major mode for viewing a GitHub Pull Request."
  (setq-local revert-buffer-function #'egh-pr-view--revert))

;;;###autoload
(defun egh-pr-view (number &optional repo)
  "View PR NUMBER in a detail buffer.
REPO is \"owner/repo\"; defaults to the current repository."
  (interactive "nPR number: ")
  (let* ((repo (or repo (egh-repo-name)))
         (buf (get-buffer-create (egh-pr-view--buffer-name repo number)))
         (data (egh-pr-view--fetch number repo)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (egh-pr-view--render data))
      (egh-pr-view-mode)
      (setq-local egh-pr-view--number number)
      (setq-local egh-pr-view--repo repo)
      (setq-local egh-pr-view--data data)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;; View buffer actions

(defun egh-pr-view--repo-args ()
  "Return --repo args if `egh-pr-view--repo' is set."
  (when egh-pr-view--repo (list "--repo" egh-pr-view--repo)))

(defun egh-pr-view-browse ()
  "Open current PR in browser."
  (interactive)
  (egh-gh-command "pr" "view" "--web" (number-to-string egh-pr-view--number)
                  (egh-pr-view--repo-args)))

(defun egh-pr-view-close ()
  "Close current PR."
  (interactive)
  (egh-gh-command "pr" "close" (number-to-string egh-pr-view--number)
                  (egh-pr-view--repo-args))
  (revert-buffer)
  (egh-pr-view--refresh-list egh-pr-view--repo))

(defun egh-pr-view-reopen ()
  "Reopen current PR."
  (interactive)
  (egh-gh-command "pr" "reopen" (number-to-string egh-pr-view--number)
                  (egh-pr-view--repo-args))
  (revert-buffer)
  (egh-pr-view--refresh-list egh-pr-view--repo))

(defun egh-pr-view-checkout ()
  "Checkout current PR."
  (interactive)
  (egh-gh-command "pr" "checkout" (number-to-string egh-pr-view--number)
                  (egh-pr-view--repo-args))
  (message "Checked out PR #%s" egh-pr-view--number))

(defun egh-pr-view-ready ()
  "Mark current PR as ready for review."
  (interactive)
  (egh-gh-command "pr" "ready" (number-to-string egh-pr-view--number)
                  (egh-pr-view--repo-args))
  (message "PR #%s marked as ready" egh-pr-view--number)
  (revert-buffer)
  (egh-pr-view--refresh-list egh-pr-view--repo))

(defun egh-pr-view-draft ()
  "Convert current PR to draft."
  (interactive)
  (egh-gh-command "pr" "ready" (number-to-string egh-pr-view--number) "--undo"
                  (egh-pr-view--repo-args))
  (message "PR #%s converted to draft" egh-pr-view--number)
  (revert-buffer)
  (egh-pr-view--refresh-list egh-pr-view--repo))

(defun egh-pr-view-merge ()
  "Merge current PR."
  (interactive)
  (egh-pr-merge))

(defun egh-pr-view-comment ()
  "Add comment to current PR."
  (interactive)
  (egh-pr-comment--start (number-to-string egh-pr-view--number) egh-pr-view--repo))

(defun egh-pr-view-edit ()
  "Edit current PR title or body."
  (interactive)
  (egh-pr-edit--start egh-pr-view--number egh-pr-view--data egh-pr-view--repo))

;; Comment compose buffer

(defvar-local egh-pr-comment--pr-number nil
  "PR number for comment buffer.")

(defvar-local egh-pr-comment--repo nil
  "Repository name for comment buffer.")

(defvar egh-pr-comment-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map text-mode-map)
    (define-key map (kbd "C-c C-c") #'egh-pr-comment--submit)
    (define-key map (kbd "C-c C-k") #'egh-pr-comment--cancel)
    map)
  "Keymap for comment compose.")

(define-derived-mode egh-pr-comment-mode text-mode "PR Comment"
  "Mode for composing a PR comment.
\\[egh-pr-comment--submit] to submit, \\[egh-pr-comment--cancel] to cancel.")

(defun egh-pr-comment--start (pr-number &optional repo)
  "Open comment buffer for PR-NUMBER in REPO."
  (let ((buf (get-buffer-create (format "*egh-comment-pr-%s*" pr-number))))
    (pop-to-buffer buf)
    (egh-pr-comment-mode)
    (setq-local egh-pr-comment--pr-number pr-number)
    (setq-local egh-pr-comment--repo repo)
    (erase-buffer)
    (message "Write comment. C-c C-c to submit, C-c C-k to cancel.")))

(defun egh-pr-comment--submit ()
  "Submit the comment."
  (interactive)
  (let ((body (s-trim (buffer-string)))
        (pr-number egh-pr-comment--pr-number)
        (repo egh-pr-comment--repo))
    (when (string-empty-p body)
      (error "Comment body is empty"))
    (egh-gh-command "pr" "comment" pr-number "--body" body
                    (when repo (list "--repo" repo)))
    (message "Comment added to PR #%s" pr-number)
    (kill-buffer)
    (egh-pr-view--refresh-buffer repo pr-number)))

(defun egh-pr-comment--cancel ()
  "Cancel composing comment."
  (interactive)
  (kill-buffer)
  (message "Comment cancelled."))

;; Edit PR

(defconst egh-pr-edit--separator
  "-- PR body (do not edit this line) --"
  "Separator between title and body in edit buffer.")

(defvar-local egh-pr-edit--pr-number nil
  "PR number for edit buffer.")

(defvar-local egh-pr-edit--repo nil
  "Repository name for edit buffer.")

(defvar egh-pr-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map text-mode-map)
    (define-key map (kbd "C-c C-c") #'egh-pr-edit--submit)
    (define-key map (kbd "C-c C-k") #'egh-pr-edit--cancel)
    map)
  "Keymap for PR edit.")

(define-derived-mode egh-pr-edit-mode text-mode "PR Edit"
  "Mode for editing a PR title and body.
First line is the title, followed by a separator line, then the body.
\\[egh-pr-edit--submit] to submit, \\[egh-pr-edit--cancel] to cancel.")

(defun egh-pr-edit--start (number data &optional repo)
  "Open edit buffer for PR NUMBER with current DATA in REPO."
  (let ((buf (get-buffer-create (format "*egh-edit-pr-%s*" number)))
        (title (or (alist-get 'title data) ""))
        (body (or (alist-get 'body data) "")))
    (pop-to-buffer buf)
    (egh-pr-edit-mode)
    (setq-local egh-pr-edit--pr-number number)
    (setq-local egh-pr-edit--repo repo)
    (erase-buffer)
    (insert title "\n" egh-pr-edit--separator "\n" body)
    (goto-char (point-min))
    (message "Edit title (1st line) and body (below separator). C-c C-c to submit, C-c C-k to cancel.")))

(defun egh-pr-edit--parse ()
  "Parse edit buffer into (TITLE . BODY)."
  (save-excursion
    (goto-char (point-min))
    (if (search-forward egh-pr-edit--separator nil t)
        (let ((title (s-trim (buffer-substring-no-properties (point-min) (line-beginning-position))))
              (body (buffer-substring-no-properties (1+ (line-end-position)) (point-max))))
          (cons title body))
      (cons (s-trim (buffer-string)) ""))))

(defun egh-pr-edit--submit ()
  "Submit title and body edits."
  (interactive)
  (let* ((parsed (egh-pr-edit--parse))
         (title (car parsed))
         (body (cdr parsed))
         (number egh-pr-edit--pr-number)
         (repo egh-pr-edit--repo))
    (when (string-empty-p title)
      (error "Title cannot be empty"))
    (egh-gh-command "pr" "edit" (number-to-string number)
                    "--title" title "--body" body
                    (when repo (list "--repo" repo)))
    (message "Updated PR #%s" number)
    (kill-buffer)
    (egh-pr-view--refresh-buffer repo (number-to-string number))))

(defun egh-pr-edit--cancel ()
  "Cancel editing."
  (interactive)
  (kill-buffer)
  (message "Edit cancelled."))

(provide 'egh-pr-view)
;;; egh-pr-view.el ends here
