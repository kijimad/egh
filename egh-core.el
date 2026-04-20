;;; egh-core.el --- Core utilities for egh -*- lexical-binding: t -*-

;; Copyright (C) 2026

;;; Commentary:

;; gh CLI execution and utility functions for egh.

;;; Code:

(require 'json)
(require 'dash)
(require 's)
(require 'tablist)

(defgroup egh nil
  "GitHub CLI interface for Emacs."
  :group 'tools)

(defcustom egh-gh-executable "gh"
  "Path to the gh CLI executable."
  :group 'egh
  :type 'string)

(defun egh-gh-command (&rest args)
  "Run gh with ARGS synchronously, return stdout as string.
Signal an error on non-zero exit."
  (let ((args (flatten-list args)))
    (with-temp-buffer
      (let ((exit-code (apply #'call-process egh-gh-executable nil t nil args)))
        (unless (zerop exit-code)
          (error "gh %s failed (exit %d): %s"
                 (s-join " " args) exit-code (buffer-string)))
        (buffer-string)))))

(defun egh-gh-json (&rest args)
  "Run gh with ARGS and parse JSON output."
  (let ((output (apply #'egh-gh-command args)))
    (json-parse-string output :object-type 'alist :array-type 'list)))

(defun egh-utils-columns-list-format (columns-spec)
  "Convert COLUMNS-SPEC to `tabulated-list-format'."
  (apply #'vector
         (--map-indexed
          (let* ((name (plist-get it :name))
                 (width (plist-get it :width))
                 (sort-fn (plist-get it :sort)))
            (list name width (or sort-fn t)))
          columns-spec)))

(defun egh-utils-parse-entry (columns-spec alist)
  "Convert ALIST to a tabulated-list entry using COLUMNS-SPEC.
Returns (ID [col-values...])."
  (let* ((id (number-to-string (alist-get 'number alist)))
         (cols (--map
                (let* ((field (plist-get it :field))
                       (raw (alist-get field alist))
                       (fmt (plist-get it :format)))
                  (if fmt
                      (funcall fmt raw)
                    (if raw (format "%s" raw) "")))
                columns-spec)))
    (list id (apply #'vector cols))))

(defun egh-utils-get-marked-items-ids ()
  "Return list of IDs (PR numbers) of marked items."
  (-map #'car (tablist-get-marked-items)))

(defun egh-utils-ensure-items ()
  "Get marked item IDs or current item, error if none."
  (let ((ids (egh-utils-get-marked-items-ids)))
    (if ids ids
      (let ((id (tabulated-list-get-id)))
        (if id (list id)
          (error "No items selected"))))))

(defun egh-repo-name ()
  "Return the current GitHub repository as \"owner/repo\"."
  (s-trim (egh-gh-command "repo" "view" "--json" "nameWithOwner" "--jq" ".nameWithOwner")))

(defun egh-utils-pop-to-buffer (name)
  "Pop to buffer NAME, creating if needed."
  (pop-to-buffer (get-buffer-create name)))

;; Common formatters (shared between egh-pr and egh-pr-view)

(defun egh-pr--format-author (author)
  "Format AUTHOR alist to login string."
  (if (listp author)
      (or (alist-get 'login author) "")
    (format "%s" (or author ""))))

(defun egh-pr--format-time (time-str)
  "Format TIME-STR to short date."
  (if (and time-str (stringp time-str) (not (string-empty-p time-str)))
      (format-time-string "%Y-%m-%d" (date-to-time time-str))
    ""))

(defun egh-pr--checks-summary (rollup)
  "Summarize statusCheckRollup ROLLUP into (PASS FAIL PENDING TOTAL)."
  (let ((pass 0) (fail 0) (pending 0))
    (dolist (check rollup)
      (let ((state (downcase (or (alist-get 'state check) ""))))
        (pcase state
          ((or "success" "neutral" "skipped") (cl-incf pass))
          ((or "failure" "error" "cancelled" "timed_out"
               "startup_failure" "stale" "action_required") (cl-incf fail))
          (_ (cl-incf pending)))))
    (list pass fail pending (+ pass fail pending))))

(defun egh-pr--checks-icon (rollup)
  "Return a propertized CI status icon for statusCheckRollup ROLLUP."
  (if (null rollup) "-"
    (let* ((summary (egh-pr--checks-summary rollup))
           (fail (nth 1 summary))
           (pending (nth 2 summary)))
      (cond
       ((> fail 0) (propertize "✗" 'font-lock-face 'egh-face-checks-fail))
       ((> pending 0) (propertize "●" 'font-lock-face 'egh-face-checks-pending))
       (t (propertize "✓" 'font-lock-face 'egh-face-checks-pass))))))

(defun egh-pr--format-checks (rollup)
  "Format statusCheckRollup ROLLUP for PR list column."
  (egh-pr--checks-icon rollup))

(defun egh-pr--format-labels (labels)
  "Format LABELS list to comma-separated string."
  (if (and labels (listp labels))
      (s-join "," (--map (or (alist-get 'name it) "") labels))
    ""))

(provide 'egh-core)
;;; egh-core.el ends here
