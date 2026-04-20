# egh - GitHub CLI interface for Emacs

`gh` CLI をデータソースに、Emacs 上で GitHub Pull Request の一覧・閲覧・編集を行うパッケージ。
一覧 UI は `docker.el` の `docker-containers` と同様に `tabulated-list-mode` + `tablist` を使用。

## 必要なもの

- Emacs 28.1+
- [gh CLI](https://cli.github.com/) (認証済み)
- Emacs パッケージ: `dash`, `s`, `tablist`, `transient`

## インストール

### straight.el + use-package

```elisp
(use-package egh
  :straight (:host github :repo "kijimad/egh")
  :commands (egh egh-pull-requests-open egh-pull-requests-all egh-pull-requests-mine))
```

## 使い方

### PR 一覧

```
M-x egh-pull-requests-open   ;; open のみ
M-x egh-pull-requests-all    ;; 全ステータス
M-x egh-pull-requests-mine   ;; 自分のPRのみ
M-x egh                      ;; transient メニューから選択
```

| キー    | 動作               |
|---------|--------------------|
| `RET`   | PR 詳細を開く      |
| `l`     | フィルタ (transient) |
| `m`     | マージ             |
| `C`     | クローズ           |
| `R`     | リオープン         |
| `k`     | チェックアウト     |
| `b`     | ブランチ切り替え   |
| `o`     | ブラウザで開く     |
| `c`     | コメント追加       |
| `O`     | Ready に変更       |
| `D`     | Draft に変更       |
| `?`     | ヘルプ             |

`tablist` のマーク機能で複数 PR を選択して一括操作も可能。

### PR 詳細

| キー    | 動作               |
|---------|--------------------|
| `g`     | リロード           |
| `e`     | タイトル/本文 編集 |
| `c`     | コメント追加       |
| `m`     | マージ             |
| `C`     | クローズ           |
| `R`     | リオープン         |
| `k`     | チェックアウト     |
| `o`     | ブラウザで開く     |
| `O`     | Ready に変更       |
| `D`     | Draft に変更       |
| `q`     | 閉じる             |

### コメント・本文編集バッファ

| キー        | 動作   |
|-------------|--------|
| `C-c C-c`   | 送信   |
| `C-c C-k`   | キャンセル |

## テスト

```sh
emacs --batch -L . \
  -l egh-core-test -l egh-pr-test -l egh-pr-view-test \
  -f ert-run-tests-batch-and-exit
```

## ファイル構成

```
egh.el           -- エントリポイント (M-x egh)
egh-core.el      -- gh CLI 実行、JSON パース、共通ユーティリティ
egh-faces.el     -- フェイス定義 (PR 状態の色分け)
egh-pr.el        -- PR 一覧 (tabulated-list-mode)
egh-pr-view.el   -- PR 詳細表示・編集・コメント
```

`egh.el` が `egh-core` と `egh-pr` を require し、`egh-pr` が `egh-core` と `egh-faces` を require する。
`egh-pr-view` は `egh-pr` から `RET` で開いたときに遅延ロードされる。

```
egh.el → egh-pr.el → egh-core.el
              ↓            ↓
         egh-pr-view.el  egh-faces.el
```


(mapc (lambda (f) (load-file f))
      (seq-remove (lambda (f) (string-match-p "-test\\.el\\'" f))
                  (directory-files "." t "\\.el\\'")))
