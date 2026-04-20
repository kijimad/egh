;;; egh-pr-view-test.el --- Tests for egh-pr-view -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'egh-pr-view)

;;; Buffer name

(ert-deftest egh-pr-view--buffer-name/format ()
  "Buffer name includes repo and number."
  (should (equal "*egh-pr: owner/repo #42*"
                 (egh-pr-view--buffer-name "owner/repo" 42))))

(ert-deftest egh-pr-view--buffer-name/string-number ()
  "Buffer name works with string number."
  (should (equal "*egh-pr: foo/bar #7*"
                 (egh-pr-view--buffer-name "foo/bar" "7"))))

;;; egh-pr-view--state-string

(ert-deftest egh-pr-view--state-string/open ()
  "Open non-draft PR shows OPEN."
  (let* ((data '((state . "OPEN") (isDraft . :false)))
         (result (egh-pr-view--state-string data)))
    (should (equal "OPEN" (substring-no-properties result)))
    (should (eq 'egh-face-state-open (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--state-string/closed ()
  "Closed PR shows CLOSED."
  (let* ((data '((state . "CLOSED") (isDraft . :false)))
         (result (egh-pr-view--state-string data)))
    (should (equal "CLOSED" (substring-no-properties result)))
    (should (eq 'egh-face-state-closed (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--state-string/merged ()
  "Merged PR shows MERGED."
  (let* ((data '((state . "MERGED") (isDraft . :false)))
         (result (egh-pr-view--state-string data)))
    (should (equal "MERGED" (substring-no-properties result)))
    (should (eq 'egh-face-state-merged (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--state-string/draft ()
  "Draft PR shows DRAFT regardless of state."
  (let* ((data '((state . "OPEN") (isDraft . t)))
         (result (egh-pr-view--state-string data)))
    (should (equal "DRAFT" (substring-no-properties result)))
    (should (eq 'egh-face-draft (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--state-string/not-draft-false ()
  "isDraft :false is not treated as draft."
  (let* ((data '((state . "OPEN") (isDraft . :false)))
         (result (egh-pr-view--state-string data)))
    (should (equal "OPEN" (substring-no-properties result)))))

;;; egh-pr-view--review-string

(ert-deftest egh-pr-view--review-string/approved ()
  (let ((result (egh-pr-view--review-string "APPROVED")))
    (should (equal "APPROVED" (substring-no-properties result)))
    (should (eq 'egh-face-review-approved (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--review-string/changes-requested ()
  (let ((result (egh-pr-view--review-string "CHANGES_REQUESTED")))
    (should (equal "CHANGES_REQUESTED" (substring-no-properties result)))
    (should (eq 'egh-face-review-changes-requested (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--review-string/nil-pending ()
  "Nil decision shows PENDING without face."
  (let ((result (egh-pr-view--review-string nil)))
    (should (equal "PENDING" result))
    (should-not (get-text-property 0 'font-lock-face result))))

;;; egh-pr-view--format-time

(ert-deftest egh-pr-view--format-time/valid ()
  (let ((result (egh-pr-view--format-time "2026-04-10T15:30:00Z")))
    (should (string-match-p "2026-04" result))
    (should (string-match-p ":" result))))

(ert-deftest egh-pr-view--format-time/nil ()
  (should (equal "" (egh-pr-view--format-time nil))))

(ert-deftest egh-pr-view--format-time/empty ()
  (should (equal "" (egh-pr-view--format-time ""))))

;;; egh-pr-view--render

(ert-deftest egh-pr-view--render/contains-title ()
  "Rendered buffer contains PR title."
  (let ((data '((number . 42) (title . "Fix the bug")
                (state . "OPEN") (isDraft . :false)
                (author . ((login . "alice")))
                (headRefName . "fix") (baseRefName . "main")
                (labels . nil) (reviewDecision . nil)
                (additions . 10) (deletions . 3) (changedFiles . 2)
                (createdAt . "2026-04-01T00:00:00Z")
                (updatedAt . "2026-04-10T00:00:00Z")
                (url . "https://github.com/o/r/pull/42")
                (body . "Description here")
                (comments . nil) (reviews . nil)
                (statusCheckRollup . nil) (commits . nil))))
    (with-temp-buffer
      (egh-pr-view--render data)
      (let ((content (buffer-string)))
        (should (string-match-p "#42" content))
        (should (string-match-p "Fix the bug" content))
        (should (string-match-p "alice" content))
        (should (string-match-p "fix -> main" content))
        (should (string-match-p "Description here" content))))))

(ert-deftest egh-pr-view--render/no-body ()
  "Rendered buffer shows placeholder for empty body."
  (let ((data '((number . 1) (title . "T") (state . "OPEN") (isDraft . :false)
                (author . ((login . "x"))) (headRefName . "a") (baseRefName . "b")
                (labels . nil) (reviewDecision . nil)
                (additions . 0) (deletions . 0) (changedFiles . 0)
                (createdAt . "") (updatedAt . "") (url . "")
                (body . "") (comments . nil) (reviews . nil)
                (statusCheckRollup . nil) (commits . nil))))
    (with-temp-buffer
      (egh-pr-view--render data)
      (should (string-match-p "(no description)" (buffer-string))))))

(ert-deftest egh-pr-view--render/comments ()
  "Rendered buffer shows comments."
  (let ((data '((number . 1) (title . "T") (state . "OPEN") (isDraft . :false)
                (author . ((login . "x"))) (headRefName . "a") (baseRefName . "b")
                (labels . nil) (reviewDecision . nil)
                (additions . 0) (deletions . 0) (changedFiles . 0)
                (createdAt . "") (updatedAt . "") (url . "")
                (body . "body")
                (comments . (((author . ((login . "reviewer")))
                              (createdAt . "2026-04-05T12:00:00Z")
                              (body . "LGTM"))))
                (reviews . nil)
                (statusCheckRollup . nil) (commits . nil))))
    (with-temp-buffer
      (egh-pr-view--render data)
      (let ((content (buffer-string)))
        (should (string-match-p "@reviewer" content))
        (should (string-match-p "LGTM" content))
        (should (string-match-p "Comments (1)" content))))))

(ert-deftest egh-pr-view--render/reviews ()
  "Rendered buffer shows reviews."
  (let ((data '((number . 1) (title . "T") (state . "OPEN") (isDraft . :false)
                (author . ((login . "x"))) (headRefName . "a") (baseRefName . "b")
                (labels . nil) (reviewDecision . "APPROVED")
                (additions . 0) (deletions . 0) (changedFiles . 0)
                (createdAt . "") (updatedAt . "") (url . "")
                (body . "body") (comments . nil)
                (reviews . (((author . ((login . "rev")))
                             (state . "APPROVED")
                             (submittedAt . "2026-04-06T10:00:00Z"))))
                (statusCheckRollup . nil) (commits . nil))))
    (with-temp-buffer
      (egh-pr-view--render data)
      (let ((content (buffer-string)))
        (should (string-match-p "@rev" content))
        (should (string-match-p "Reviews" content))))))

;;; egh-pr-view--fetch

(ert-deftest egh-pr-view--fetch/passes-repo ()
  "Fetch includes --repo when provided."
  (let ((called-args nil))
    (cl-letf (((symbol-function 'egh-gh-json)
               (lambda (&rest args)
                 (setq called-args args)
                 '((number . 1)))))
      (egh-pr-view--fetch 42 "owner/repo")
      (should (member "--repo" called-args))
      (should (member "owner/repo" called-args)))))

(ert-deftest egh-pr-view--fetch/no-repo ()
  "Fetch omits --repo when nil."
  (let ((called-args nil))
    (cl-letf (((symbol-function 'egh-gh-json)
               (lambda (&rest args)
                 (setq called-args args)
                 '((number . 1)))))
      (egh-pr-view--fetch 42)
      (should-not (member "--repo" called-args)))))

;;; egh-pr-edit--parse

(ert-deftest egh-pr-edit--parse/title-and-body ()
  "Parse extracts title and body from edit buffer."
  (with-temp-buffer
    (insert "My PR Title\n" egh-pr-edit--separator "\nThis is the body\nWith multiple lines")
    (let ((result (egh-pr-edit--parse)))
      (should (equal "My PR Title" (car result)))
      (should (string-match-p "This is the body" (cdr result)))
      (should (string-match-p "With multiple lines" (cdr result))))))

(ert-deftest egh-pr-edit--parse/empty-body ()
  "Parse handles empty body."
  (with-temp-buffer
    (insert "Title Only\n" egh-pr-edit--separator "\n")
    (let ((result (egh-pr-edit--parse)))
      (should (equal "Title Only" (car result)))
      (should (equal "" (cdr result))))))

(ert-deftest egh-pr-edit--parse/no-separator ()
  "Parse without separator treats all as title."
  (with-temp-buffer
    (insert "Just a title")
    (let ((result (egh-pr-edit--parse)))
      (should (equal "Just a title" (car result)))
      (should (equal "" (cdr result))))))

(ert-deftest egh-pr-edit--parse/trims-title ()
  "Parse trims whitespace from title."
  (with-temp-buffer
    (insert "  Spaced Title  \n" egh-pr-edit--separator "\nbody")
    (let ((result (egh-pr-edit--parse)))
      (should (equal "Spaced Title" (car result))))))

;;; egh-pr-comment--start

(ert-deftest egh-pr-comment--start/sets-locals ()
  "Comment buffer sets local variables."
  (save-window-excursion
    (egh-pr-comment--start "42" "owner/repo")
    (should (equal "42" egh-pr-comment--pr-number))
    (should (equal "owner/repo" egh-pr-comment--repo))
    (should (derived-mode-p 'egh-pr-comment-mode))
    (kill-buffer)))

;;; egh-pr-edit--start

(ert-deftest egh-pr-edit--start/populates-buffer ()
  "Edit buffer is populated with title and body."
  (save-window-excursion
    (egh-pr-edit--start 42 '((title . "My Title") (body . "My Body")) "owner/repo")
    (should (equal 42 egh-pr-edit--pr-number))
    (should (equal "owner/repo" egh-pr-edit--repo))
    (let ((content (buffer-string)))
      (should (string-match-p "My Title" content))
      (should (string-match-p egh-pr-edit--separator content))
      (should (string-match-p "My Body" content)))
    (kill-buffer)))

;;; egh-pr-view-mode

(ert-deftest egh-pr-view-mode/keymap ()
  "PR view mode has expected keybindings."
  (should (eq 'egh-pr-view-comment (lookup-key egh-pr-view-mode-map "c")))
  (should (eq 'egh-pr-view-edit (lookup-key egh-pr-view-mode-map "e")))
  (should (eq 'egh-pr-view-browse (lookup-key egh-pr-view-mode-map "o")))
  (should (eq 'egh-pr-view-close (lookup-key egh-pr-view-mode-map "C")))
  (should (eq 'egh-pr-view-reopen (lookup-key egh-pr-view-mode-map "R")))
  (should (eq 'egh-pr-view-checkout (lookup-key egh-pr-view-mode-map "k")))
  (should (eq 'egh-pr-view-ready (lookup-key egh-pr-view-mode-map "O")))
  (should (eq 'egh-pr-view-draft (lookup-key egh-pr-view-mode-map "D")))
  (should (eq 'revert-buffer (lookup-key egh-pr-view-mode-map "g"))))

;;; egh-pr-view--refresh-buffer

(ert-deftest egh-pr-view--refresh-buffer/no-error-when-missing ()
  "Does not error when buffer doesn't exist."
  (egh-pr-view--refresh-buffer "nonexistent/repo" "999"))

;;; egh-pr-view--refresh-list

(ert-deftest egh-pr-view--refresh-list/no-error-when-missing ()
  "Does not error when list buffer doesn't exist."
  (egh-pr-view--refresh-list "nonexistent/repo"))

;;; egh-pr-view--repo-args

(ert-deftest egh-pr-view--repo-args/with-repo ()
  "Returns --repo args when repo is set."
  (let ((egh-pr-view--repo "foo/bar"))
    (should (equal '("--repo" "foo/bar") (egh-pr-view--repo-args)))))

(ert-deftest egh-pr-view--repo-args/without-repo ()
  "Returns nil when repo is not set."
  (let ((egh-pr-view--repo nil))
    (should (null (egh-pr-view--repo-args)))))

;;; egh-pr-view--check-icon

(ert-deftest egh-pr-view--check-icon/success ()
  "Success shows check mark."
  (let ((result (egh-pr-view--check-icon "SUCCESS")))
    (should (equal "✓" (substring-no-properties result)))
    (should (eq 'egh-face-checks-pass (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--check-icon/failure ()
  "Failure shows X."
  (let ((result (egh-pr-view--check-icon "FAILURE")))
    (should (equal "✗" (substring-no-properties result)))
    (should (eq 'egh-face-checks-fail (get-text-property 0 'font-lock-face result)))))

(ert-deftest egh-pr-view--check-icon/pending ()
  "Pending shows dot."
  (let ((result (egh-pr-view--check-icon "PENDING")))
    (should (equal "●" (substring-no-properties result)))
    (should (eq 'egh-face-checks-pending (get-text-property 0 'font-lock-face result)))))

;;; egh-pr-view--insert-checks

(ert-deftest egh-pr-view--insert-checks/no-checks ()
  "Shows no checks message when rollup is nil."
  (let ((data '((statusCheckRollup . nil) (commits . nil))))
    (with-temp-buffer
      (egh-pr-view--insert-checks data)
      (let ((content (buffer-string)))
        (should (string-match-p "Checks (0/0 passed)" content))
        (should (string-match-p "(no checks)" content))))))

(ert-deftest egh-pr-view--insert-checks/with-checks ()
  "Shows checks with icons."
  (let ((data '((statusCheckRollup . (((name . "build") (state . "SUCCESS")
                                        (workflow . ((name . "CI"))))
                                       ((name . "lint") (state . "FAILURE")
                                        (workflow . ((name . "CI")))))))))
    (with-temp-buffer
      (egh-pr-view--insert-checks data)
      (let ((content (buffer-string)))
        (should (string-match-p "Checks (1/2 passed)" content))
        (should (string-match-p "build" content))
        (should (string-match-p "lint" content))
        (should (string-match-p "CI" content))))))

(ert-deftest egh-pr-view--insert-checks/all-pass ()
  "All passed checks."
  (let ((data '((statusCheckRollup . (((name . "test") (state . "SUCCESS")))))))
    (with-temp-buffer
      (egh-pr-view--insert-checks data)
      (should (string-match-p "Checks (1/1 passed)" (buffer-string))))))

;;; egh-pr-view--latest-commit

(ert-deftest egh-pr-view--latest-commit/returns-last ()
  "Returns the last commit from commits list."
  (let* ((data '((commits . (((oid . "aaa") (messageHeadline . "first"))
                              ((oid . "bbb") (messageHeadline . "second"))))))
         (result (egh-pr-view--latest-commit data)))
    (should (equal "bbb" (alist-get 'oid result)))
    (should (equal "second" (alist-get 'messageHeadline result)))))

(ert-deftest egh-pr-view--latest-commit/nil-commits ()
  "Returns nil when commits is nil."
  (should (null (egh-pr-view--latest-commit '((commits . nil))))))

(ert-deftest egh-pr-view--insert-checks/shows-commit ()
  "Shows latest commit info in checks section."
  (let ((data '((statusCheckRollup . (((name . "build") (state . "SUCCESS"))))
                (commits . (((oid . "abc1234567890") (messageHeadline . "fix bug")))))))
    (with-temp-buffer
      (egh-pr-view--insert-checks data)
      (let ((content (buffer-string)))
        (should (string-match-p "abc1234" content))
        (should (string-match-p "fix bug" content))))))

(provide 'egh-pr-view-test)
;;; egh-pr-view-test.el ends here
