;;; egh-core-test.el --- Tests for egh-core -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'egh-core)

;;; Formatters

(ert-deftest egh-pr--format-author/alist ()
  "Format author from alist with login."
  (should (equal "octocat"
                 (egh-pr--format-author '((login . "octocat") (name . "Octo Cat"))))))

(ert-deftest egh-pr--format-author/alist-no-login ()
  "Format author from alist without login returns empty."
  (should (equal "" (egh-pr--format-author '((name . "Octo Cat"))))))

(ert-deftest egh-pr--format-author/string ()
  "Format author from plain string."
  (should (equal "octocat" (egh-pr--format-author "octocat"))))

(ert-deftest egh-pr--format-author/nil ()
  "Format author from nil."
  (should (equal "" (egh-pr--format-author nil))))

(ert-deftest egh-pr--format-time/valid ()
  "Format valid ISO time string to date."
  (let ((result (egh-pr--format-time "2026-04-10T12:00:00Z")))
    (should (equal "2026-04-10" result))))

(ert-deftest egh-pr--format-time/nil ()
  "Format nil time returns empty."
  (should (equal "" (egh-pr--format-time nil))))

(ert-deftest egh-pr--format-time/empty ()
  "Format empty string returns empty."
  (should (equal "" (egh-pr--format-time ""))))

(ert-deftest egh-pr--format-labels/multiple ()
  "Format multiple labels."
  (let ((labels '(((name . "bug")) ((name . "ui")))))
    (should (equal "bug,ui" (egh-pr--format-labels labels)))))

(ert-deftest egh-pr--format-labels/empty ()
  "Format empty labels list."
  (should (equal "" (egh-pr--format-labels nil))))

(ert-deftest egh-pr--format-labels/single ()
  "Format single label."
  (should (equal "enhancement"
                 (egh-pr--format-labels '(((name . "enhancement")))))))

;;; columns-list-format

(ert-deftest egh-utils-columns-list-format/basic ()
  "Convert column spec to tabulated-list-format vector."
  (let* ((spec '((:name "A" :width 10 :sort nil)
                 (:name "B" :width 20 :sort nil)))
         (result (egh-utils-columns-list-format spec)))
    (should (vectorp result))
    (should (= 2 (length result)))
    (should (equal '("A" 10 t) (aref result 0)))
    (should (equal '("B" 20 t) (aref result 1)))))

(ert-deftest egh-utils-columns-list-format/with-sort ()
  "Column with custom sort function."
  (let* ((spec '((:name "X" :width 5 :sort string<)))
         (result (egh-utils-columns-list-format spec)))
    (should (eq 'string< (nth 2 (aref result 0))))))

;;; parse-entry

(ert-deftest egh-utils-parse-entry/basic ()
  "Parse a JSON alist into tabulated-list entry."
  (let* ((spec '((:name "#" :width 6 :field number :format nil)
                 (:name "Title" :width 30 :field title :format nil)))
         (alist '((number . 42) (title . "Fix bug")))
         (result (egh-utils-parse-entry spec alist)))
    (should (equal "42" (car result)))
    (should (equal "42" (aref (cadr result) 0)))
    (should (equal "Fix bug" (aref (cadr result) 1)))))

(ert-deftest egh-utils-parse-entry/with-format-fn ()
  "Parse entry applies format function."
  (let* ((spec `((:name "Author" :width 15 :field author :format ,#'egh-pr--format-author)))
         (alist '((number . 1) (author . ((login . "bob")))))
         (result (egh-utils-parse-entry spec alist)))
    (should (equal "bob" (aref (cadr result) 0)))))

(ert-deftest egh-utils-parse-entry/nil-field ()
  "Parse entry with nil field value returns empty string."
  (let* ((spec '((:name "X" :width 10 :field missing :format nil)))
         (alist '((number . 1)))
         (result (egh-utils-parse-entry spec alist)))
    (should (equal "" (aref (cadr result) 0)))))

;;; egh-gh-command

(ert-deftest egh-gh-command/flattens-args ()
  "egh-gh-command flattens nested lists in args."
  (let* ((called-args nil)
         (egh-gh-executable "echo"))
    (cl-letf (((symbol-function 'call-process)
               (lambda (program _infile _dest _display &rest args)
                 (setq called-args args)
                 0)))
      (egh-gh-command "pr" "view" (list "--repo" "foo/bar"))
      (should (equal '("pr" "view" "--repo" "foo/bar") called-args)))))

(ert-deftest egh-gh-command/error-on-nonzero ()
  "egh-gh-command signals error on non-zero exit."
  (cl-letf (((symbol-function 'call-process)
             (lambda (_program _infile _dest _display &rest _args) 1)))
    (should-error (egh-gh-command "pr" "list"))))

;;; egh-gh-json

(ert-deftest egh-gh-json/parses-output ()
  "egh-gh-json parses JSON from gh output."
  (cl-letf (((symbol-function 'egh-gh-command)
             (lambda (&rest _args) "[{\"number\":1,\"title\":\"test\"}]")))
    (let ((result (egh-gh-json "pr" "list")))
      (should (listp result))
      (should (= 1 (alist-get 'number (car result))))
      (should (equal "test" (alist-get 'title (car result)))))))

;;; egh-utils-ensure-items

(ert-deftest egh-utils-ensure-items/error-when-none ()
  "Error when no items selected."
  (cl-letf (((symbol-function 'tablist-get-marked-items) (lambda () nil))
            ((symbol-function 'tabulated-list-get-id) (lambda () nil)))
    (should-error (egh-utils-ensure-items))))

(ert-deftest egh-utils-ensure-items/returns-current-id ()
  "Returns current item ID when nothing marked."
  (cl-letf (((symbol-function 'tabulated-list-get-id) (lambda () "42"))
            ((symbol-function 'egh-utils-get-marked-items-ids) (lambda () nil)))
    (should (equal '("42") (egh-utils-ensure-items)))))

(ert-deftest egh-utils-ensure-items/returns-marked ()
  "Returns marked item IDs."
  (cl-letf (((symbol-function 'tablist-get-marked-items)
             (lambda () '(("1" . nil) ("2" . nil)))))
    (should (equal '("1" "2") (egh-utils-ensure-items)))))

;;; egh-pr--checks-summary

(ert-deftest egh-pr--checks-summary/all-pass ()
  "All checks passed."
  (let ((rollup '(((state . "SUCCESS")) ((state . "NEUTRAL")) ((state . "SKIPPED")))))
    (should (equal '(3 0 0 3) (egh-pr--checks-summary rollup)))))

(ert-deftest egh-pr--checks-summary/mixed ()
  "Mixed check states."
  (let ((rollup '(((state . "SUCCESS")) ((state . "FAILURE")) ((state . "PENDING")))))
    (should (equal '(1 1 1 3) (egh-pr--checks-summary rollup)))))

(ert-deftest egh-pr--checks-summary/empty ()
  "Empty rollup."
  (should (equal '(0 0 0 0) (egh-pr--checks-summary nil))))

(ert-deftest egh-pr--checks-summary/failure-states ()
  "Various failure states counted correctly."
  (let ((rollup '(((state . "FAILURE")) ((state . "ERROR"))
                  ((state . "CANCELLED")) ((state . "TIMED_OUT")))))
    (should (equal '(0 4 0 4) (egh-pr--checks-summary rollup)))))

;;; egh-pr--checks-icon

(ert-deftest egh-pr--checks-icon/pass ()
  "All pass shows check mark."
  (let* ((rollup '(((state . "SUCCESS"))))
         (result (egh-pr--checks-icon rollup)))
    (should (equal "✓" (substring-no-properties result)))
    (should (eq 'egh-face-checks-pass (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr--checks-icon/fail ()
  "Failure shows X."
  (let* ((rollup '(((state . "FAILURE"))))
         (result (egh-pr--checks-icon rollup)))
    (should (equal "✗" (substring-no-properties result)))
    (should (eq 'egh-face-checks-fail (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr--checks-icon/pending ()
  "Pending shows dot."
  (let* ((rollup '(((state . "PENDING"))))
         (result (egh-pr--checks-icon rollup)))
    (should (equal "●" (substring-no-properties result)))
    (should (eq 'egh-face-checks-pending (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr--checks-icon/nil ()
  "Nil rollup shows dash."
  (should (equal "-" (egh-pr--checks-icon nil))))

(ert-deftest egh-pr--checks-icon/fail-takes-priority ()
  "Fail icon even when some pass."
  (let* ((rollup '(((state . "SUCCESS")) ((state . "FAILURE"))))
         (result (egh-pr--checks-icon rollup)))
    (should (equal "✗" (substring-no-properties result)))))

(provide 'egh-core-test)
;;; egh-core-test.el ends here
