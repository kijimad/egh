# egh - GitHub CLI interface for Emacs

`gh` CLI をデータソースに、Emacs 上で GitHub Pull Request の一覧・閲覧・編集を行うパッケージ。
一覧 UI は `docker.el` の `docker-containers` と同様に `tabulated-list-mode` + `tablist` を使用。

## 必要なもの

- Emacs 28.1+
- [gh CLI](https://cli.github.com/) (認証済み)
- Emacs パッケージ: `dash`, `s`, `tablist`, `transient`

## インストール

### load-path に追加する方法

```elisp
(add-to-list 'load-path "/path/to/egh")
(require 'egh)
```

`require 'egh` が `egh-core`, `egh-pr` を内部で読み込むので、個別に require する必要はない。

### Cask を使う場合

```sh
cd /path/to/egh
cask install
```

```elisp
(add-to-list 'load-path "/path/to/egh")
(require 'egh)
```

### use-package の場合

```elisp
(use-package egh
  :load-path "/path/to/egh"
  :commands (egh egh-pull-requests))
```

## 使い方

### PR 一覧

```
M-x egh-pull-requests
```

| キー    | 動作               |
|---------|--------------------|
| `RET`   | PR 詳細を開く      |
| `l`     | フィルタ (transient) |
| `m`     | マージ             |
| `C`     | クローズ           |
| `R`     | リオープン         |
| `k`     | チェックアウト     |
| `b`     | ブラウザで開く     |
| `c`     | コメント追加       |
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
| `b`     | ブラウザで開く     |
| `q`     | 閉じる             |

### コメント・本文編集バッファ

| キー        | 動作   |
|-------------|--------|
| `C-c C-c`   | 送信   |
| `C-c C-k`   | キャンセル |

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
