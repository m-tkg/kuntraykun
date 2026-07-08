# CLAUDE.md — kuntraykun

このリポジトリで作業する際のガイド。

**メニューバー常駐アプリ（kun シリーズ）共通の方針は上位ディレクトリの [`../CLAUDE_base.md`](../CLAUDE_base.md) を参照**
（Swift Package 構成・日英ローカライズ・アップデート・kunkit 連携・リリース手順・ブランチ運用など）。
共通方針を変えるときは `CLAUDE_base.md`（[kun-template](https://github.com/m-tkg/kun-template) が canonical）を編集する。
本ファイルには kuntraykun 固有の事項のみを記す。

---

# kuntraykun 固有の事項

## 目的
`com.mtkg.*` の自作メニューバーアプリ（kun シリーズ: Clipkun / gitkun / Keykun / Pointerkun / Snapperkun /
whisperkun …）を全部起動するとメニューバーのアイコンが増えすぎる。kuntraykun は**それらを1つのアイコンに集約**する
ランチャー兼ハブ。bundle ID は `com.mtkg.kuntraykun`。

## 基本動作
- 設定の「管理アプリ」タブで `/Applications` から検出した kun アプリを選ぶ（`KunAppScanner` ＋ `KunAppMatcher`）。
- メニューバーアイコンをクリックすると、**選択済み かつ 実行中**の kun アプリだけがプルダウンに並ぶ
  （`KunAppMatcher.displayed`。未起動のアプリは出さない）。
- **表示順はユーザーが変更できる**。設定「管理アプリ」タブのリストを ▲▼ ボタンで並べ替えると、その順序が
  `ManagedAppsSettings.orderedBundleIDs`（基底 bundle ID 配列）に保存され、`KunAppMatcher.ordered` が
  その順でプルダウンを並べる（未登録のアプリは末尾に表示名昇順）。
- 項目をクリックすると、その kun アプリへ「kuntraykun アイコン直下にメニューを出せ」と依頼し、対象アプリが
  自分のネイティブメニューを `popUp` する。

## 連携プロトコル（重要）
- macOS では他プロセスの `NSStatusItem` メニューを取得して自前描画できない。そこで**各 kun アプリ側に連携の口**を
  実装してもらい、`DistributedNotificationCenter`（分散通知）で協調する。
- 仕様は **`docs/kun-integration-protocol.md`**。
- **実装は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit) と分担する**:
  - `KunIntegrationProtocol`（kunkit）: 通知名・userInfo キー・共有パス・基底 bundleID・`MenuSnapshot` モデル。
    kuntraykun 本体と各 kun アプリの両方が参照し、定数の二重管理をしない。
  - `KunIntegrationBridge`（kunkit）: 各 kun アプリ側の実装本体（Bridge / IconExport / MenuExport）。
    kuntraykun 本体は使わない。
  - kuntraykun 側（本リポジトリ）: 送受信は `Sources/Kuntraykun/IntegrationHub.swift`、
    スナップショットのキャッシュは `MenuSnapshotStore.swift`、サブメニュー構築は `KunSubmenuBuilder.swift`。
- **kunkit 由来の共通実装**: 自己更新（`SelfUpdater`）・ログイン項目（`LoginItemController`）・多重起動防止（`KunAppLaunch`、`main.swift`）・設定永続化（`KunSettingsStore`）・外部プロセス実行（`ProcessRunner`）・更新チェック（`GitHubReleaseFetcher` / `ReleaseInfo` / `VersionComparator` / `KunUpdateSchedule` / `ReleaseDownloader`）は kunkit（`KunAppKit` / `KunSupport` / `KunUpdateKit`）が提供する。アプリ側に複製は持たず、アプリ名・文言・repo は注入する。
- **kunkit の更新運用**: プロトコルの変更・修正は kunkit 側（TDD）で行って semver タグを発行し、
  本リポジトリは `swift package update kunkit` で追従する（`Package.resolved` を追跡しているので
  resolved の変更もコミットする。`from: "1.0.0"` 指定のため 1.x は自動追従、破壊的変更はメジャー）。
- 通知: `com.mtkg.kuntraykun.sync`（対象集合のブロードキャスト）/ `com.mtkg.kuntraykun.showMenu`（メニュー表示依頼）/
  `com.mtkg.kun.appLaunched`（アプリ→ハブの起動通知）。userInfo の値は文字列のみ。
- v4（サブメニュー表示）: 各アプリがメニュー構造の JSON を `Kuntraykun/Menus/<基底ID>.json` へ書き出し
  （`com.mtkg.kuntraykun.requestMenu` / `com.mtkg.kun.menuSnapshot`）、kuntraykun がサブメニューとして再構築、
  項目クリックを `com.mtkg.kuntraykun.invokeMenuItem`（世代トークン一致時のみ実行）で依頼し返す。
  未対応アプリは従来のクリック → showMenu popUp にフォールバック。
- 管理対象アプリ側の表示規則: `アイコンを隠す = (管理対象フラグ ON) かつ (kuntraykun 起動中)`。
  kuntraykun 未起動ならフォールバックでアイコンを出す（操作不能を防ぐ）。
- **Accessibility 権限は使わない**（AX 案は不採用）。

## 段階導入の状況
- kuntraykun 本体は実装済み。次は1つの kun アプリ（例 Clipkun）にプロトコルを実装して end-to-end 検証し、
  問題なければ残りへ展開する。最終的には本テンプレート（`CLAUDE_base.md`）にも「Kuntraykun 連携」章を足す。

## ローカル検証
`LOCAL=1 AD_HOC=1 bash Scripts/bundle.sh debug` で `Kuntraykun (Local).app` を生成（署名証明書が無い環境向け）。
本番署名がある環境では `LOCAL=1 bash Scripts/bundle.sh debug`。
