;;; egh-faces.el --- Faces for egh -*- lexical-binding: t -*-

;; Copyright (C) 2026

;;; Commentary:

;; Face definitions for egh PR states and review status.

;;; Code:

(defgroup egh-faces nil
  "Faces for egh."
  :group 'egh)

(defface egh-face-state-open
  '((t :inherit success))
  "Face for open PRs."
  :group 'egh-faces)

(defface egh-face-state-closed
  '((t :inherit error))
  "Face for closed PRs."
  :group 'egh-faces)

(defface egh-face-state-merged
  '((t :inherit shadow))
  "Face for merged PRs."
  :group 'egh-faces)

(defface egh-face-draft
  '((t :inherit shadow))
  "Face for draft PRs."
  :group 'egh-faces)

(defface egh-face-review-approved
  '((t :inherit success))
  "Face for approved review status."
  :group 'egh-faces)

(defface egh-face-review-changes-requested
  '((t :inherit warning))
  "Face for changes-requested review status."
  :group 'egh-faces)

(provide 'egh-faces)
;;; egh-faces.el ends here
