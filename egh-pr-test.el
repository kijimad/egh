;;; egh-pr-test.el --- Tests for egh-pr -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'egh-pr)

;;; egh-pr--state-face

(ert-deftest egh-pr--state-face/open ()
  (should (eq 'egh-face-state-open (egh-pr--state-face "OPEN"))))

(ert-deftest egh-pr--state-face/closed ()
  (should (eq 'egh-face-state-closed (egh-pr--state-face "CLOSED"))))

(ert-deftest egh-pr--state-face/merged ()
  (should (eq 'egh-face-state-merged (egh-pr--state-face "MERGED"))))

(ert-deftest egh-pr--state-face/draft ()
  (should (eq 'egh-face-draft (egh-pr--state-face "DRAFT"))))

(ert-deftest egh-pr--state-face/unknown ()
  (should (eq nil (egh-pr--state-face "UNKNOWN"))))

(ert-deftest egh-pr--state-face/case-insensitive ()
  (should (eq 'egh-face-state-open (egh-pr--state-face "open")))
  (should (eq 'egh-face-state-open (egh-pr--state-face "Open"))))

;;; egh-pr-propertize-entry

(ert-deftest egh-pr-propertize-entry/applies-face ()
  "Propertize adds face to state column."
  (let* ((entry (list "1" (vector "1" "OPEN" "-" "Title" "author" "branch" "" "2026-01-01")))
         (result (egh-pr-propertize-entry entry))
         (state-val (aref (cadr result) 1)))
    (should (equal "OPEN" (substring-no-properties state-val)))
    (should (eq 'egh-face-state-open (get-text-property 0 'font-lock-face state-val)))))

(ert-deftest egh-pr-propertize-entry/closed-face ()
  "Propertize applies closed face."
  (let* ((entry (list "2" (vector "2" "CLOSED" "-" "Title" "a" "b" "" "d")))
         (result (egh-pr-propertize-entry entry))
         (state-val (aref (cadr result) 1)))
    (should (eq 'egh-face-state-closed (get-text-property 0 'font-lock-face state-val)))))

(ert-deftest egh-pr-propertize-entry/no-face-for-unknown ()
  "Propertize does not add face for unknown state."
  (let* ((entry (list "3" (vector "3" "WEIRD" "-" "Title" "a" "b" "" "d")))
         (result (egh-pr-propertize-entry entry))
         (state-val (aref (cadr result) 1)))
    (should (equal "WEIRD" state-val))
    (should-not (get-text-property 0 'font-lock-face state-val))))

;;; egh-pr--json-fields

(ert-deftest egh-pr--json-fields/contains-all-fields ()
  "json-fields includes all column field names."
  (let ((fields (egh-pr--json-fields)))
    (should (string-match-p "number" fields))
    (should (string-match-p "state" fields))
    (should (string-match-p "title" fields))
    (should (string-match-p "author" fields))
    (should (string-match-p "headRefName" fields))
    (should (string-match-p "statusCheckRollup" fields))
    (should (string-match-p "isDraft" fields))
    (should (string-match-p "labels" fields))
    (should (string-match-p "updatedAt" fields))))

(ert-deftest egh-pr--json-fields/comma-separated ()
  "json-fields returns comma-separated string."
  (let ((fields (egh-pr--json-fields)))
    (should (string-match-p "," fields))
    (should-not (string-match-p " " fields))))

;;; egh-pr-entries (with mocked gh)

(ert-deftest egh-pr-entries/parses-gh-output ()
  "egh-pr-entries returns parsed entries from gh output."
  (cl-letf (((symbol-function 'egh-gh-json)
             (lambda (&rest _args)
               '(((number . 10) (state . "OPEN") (title . "Test PR")
                  (author . ((login . "user"))) (headRefName . "feat")
                  (labels . nil) (updatedAt . "2026-04-01T00:00:00Z")
                  (statusCheckRollup . nil))))))
    (let ((egh-pr--repo nil)
          (entries (egh-pr-entries)))
      (should (= 1 (length entries)))
      (should (equal "10" (caar entries))))))

(ert-deftest egh-pr-entries/draft-replaces-state ()
  "Draft PRs have state replaced with DRAFT."
  (cl-letf (((symbol-function 'egh-gh-json)
             (lambda (&rest _args)
               (list (list '(number . 10) '(state . "OPEN") '(isDraft . t)
                           '(title . "WIP") '(author . ((login . "u")))
                           '(headRefName . "f") '(labels . nil)
                           '(updatedAt . "") '(statusCheckRollup . nil))))))
    (let* ((egh-pr--repo nil)
           (entries (egh-pr-entries))
           (state-idx (--find-index (eq (plist-get it :field) 'state) egh-pr-columns))
           (state (aref (cadr (car entries)) state-idx)))
      (should (equal "DRAFT" state)))))

(ert-deftest egh-pr-entries/non-draft-keeps-state ()
  "Non-draft PRs keep original state."
  (cl-letf (((symbol-function 'egh-gh-json)
             (lambda (&rest _args)
               (list (list '(number . 10) '(state . "OPEN") '(isDraft . :false)
                           '(title . "Ready") '(author . ((login . "u")))
                           '(headRefName . "f") '(labels . nil)
                           '(updatedAt . "") '(statusCheckRollup . nil))))))
    (let* ((egh-pr--repo nil)
           (entries (egh-pr-entries))
           (state-idx (--find-index (eq (plist-get it :field) 'state) egh-pr-columns))
           (state (aref (cadr (car entries)) state-idx)))
      (should (equal "OPEN" state)))))

(ert-deftest egh-pr-entries/passes-repo-arg ()
  "egh-pr-entries includes --repo when egh-pr--repo is set."
  (let ((called-args nil)
        (egh-pr--repo "owner/repo"))
    (cl-letf (((symbol-function 'egh-gh-json)
               (lambda (&rest args)
                 (setq called-args args)
                 nil)))
      (egh-pr-entries)
      (should (member "--repo" called-args))
      (should (member "owner/repo" called-args)))))

(ert-deftest egh-pr-entries/passes-extra-args ()
  "egh-pr-entries appends extra filter args."
  (let ((called-args nil)
        (egh-pr--repo nil))
    (cl-letf (((symbol-function 'egh-gh-json)
               (lambda (&rest args)
                 (setq called-args args)
                 nil)))
      (egh-pr-entries '("--state closed"))
      (should (member "--state" called-args))
      (should (member "closed" called-args)))))

;;; egh-pr-mode

(ert-deftest egh-pr-mode/sets-format ()
  "egh-pr-mode sets tabulated-list-format."
  (with-temp-buffer
    (egh-pr-mode)
    (should (vectorp tabulated-list-format))
    (should (= (length egh-pr-columns) (length tabulated-list-format)))))

(ert-deftest egh-pr-mode/keymap ()
  "egh-pr-mode-map has expected bindings."
  (should (eq 'egh-pr-view-at-point (lookup-key egh-pr-mode-map (kbd "RET"))))
  (should (eq 'egh-pr-help (lookup-key egh-pr-mode-map "?")))
  (should (eq 'egh-pr-switch (lookup-key egh-pr-mode-map "b")))
  (should (eq 'egh-pr-browse (lookup-key egh-pr-mode-map "o")))
  (should (eq 'egh-pr-close (lookup-key egh-pr-mode-map "C")))
  (should (eq 'egh-pr-reopen (lookup-key egh-pr-mode-map "R")))
  (should (eq 'egh-pr-checkout (lookup-key egh-pr-mode-map "k")))
  (should (eq 'egh-pr-ready (lookup-key egh-pr-mode-map "O")))
  (should (eq 'egh-pr-draft (lookup-key egh-pr-mode-map "D"))))

;;; egh-pr--branch-at-point

(ert-deftest egh-pr--branch-at-point/returns-branch ()
  "Returns branch name from entry."
  (cl-letf (((symbol-function 'tabulated-list-get-entry)
             (lambda () (vector "1" "OPEN" "-" "Title" "author" "feat-branch" "" "2026-01-01"))))
    (should (equal "feat-branch" (egh-pr--branch-at-point)))))

(ert-deftest egh-pr--branch-at-point/error-when-no-entry ()
  "Error when no entry at point."
  (cl-letf (((symbol-function 'tabulated-list-get-entry) (lambda () nil)))
    (should-error (egh-pr--branch-at-point))))

(provide 'egh-pr-test)
;;; egh-pr-test.el ends here
