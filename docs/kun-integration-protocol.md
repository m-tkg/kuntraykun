# Kuntraykun 連携プロトコル v1

kuntraykun が `com.mtkg.*` の自作メニューバーアプリ（kun シリーズ）を **1つのアイコンに集約**するための、
アプリ間連携プロトコル。各 kun アプリはこの仕様を実装すると kuntraykun に「まとめられる」ようになる。

macOS では他プロセスの `NSStatusItem` メニューを取得して自前描画できないため、
**メニューの所有は各 kun アプリのまま**にし、kuntraykun は「アイコンを隠せ」「この座標にメニューを出せ」を
通知で依頼するだけにする。これにより各 kun アプリの追加実装は最小（通知の観測とアイコン表示制御）で済み、
メニューの見た目・動作は完全にネイティブのまま保たれる。

## 役割
- **kuntraykun**（`com.mtkg.kuntraykun`）: 集約ハブ。まとめる対象集合を管理し、通知を送る。
- **管理対象アプリ**: kun シリーズ＝ bundle ID が `com.mtkg.` で始まり末尾が `kun`（例 `com.mtkg.clipkun`）。
  kuntraykun 自身および `.local` 派生は除く。同じ `com.mtkg.*` でも非 kun（例 `com.mtkg.gogai`）は対象外。
  各アプリは通知を観測してアイコン表示制御とメニュー表示を行う。

## 通信方式
`DistributedNotificationCenter.default()` を用いる。すべて `deliverImmediately: true` で送信し、
**userInfo の値は文字列のみ**（分散通知はプロパティリスト型のみ・非サンドボックス前提）。
kun シリーズはいずれも非サンドボックス（Developer ID 署名）なので userInfo 付き分散通知が届く。

---

## 通知一覧

### 1. `com.mtkg.kuntraykun.sync` — kuntraykun → 全アプリ（ブロードキャスト）
まとめる対象集合を知らせる。冪等。
- userInfo: `{ "managed": "<カンマ区切りの対象 bundleID 群>" }`（例 `"com.mtkg.clipkun,com.mtkg.keykun"`）
- 送信タイミング（kuntraykun 側）: 起動時 / 対象集合の変更時 / `appLaunched` 受信時。
- 受信時の各アプリの動作: 自分の bundleID（基底ID）が `managed` に含まれるかで「管理対象フラグ」を更新・**永続化**し、
  アイコン表示を再計算する（後述の表示規則）。

### 2. `com.mtkg.kuntraykun.showMenu` — kuntraykun → 対象1アプリ
指定座標に自分のメニューを出すよう依頼する。
- userInfo: `{ "target": "<bundleID>", "x": "<screenX>", "y": "<screenY>" }`
  - 座標は **Cocoa スクリーン座標（左下原点）**。メニューを表示する左上アンカー点（kuntraykun アイコンの左下）。
- 受信時の動作: `target` が自分の基底 bundleID と一致するときのみ、自分のステータスメニューを
  `menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: nil)` で表示する。一致しなければ無視。
- **メニュー構築は `menuNeedsUpdate` 内で同期的に行うこと**。`popUp` は `menuNeedsUpdate` を
  同期的に呼んだ直後に表示するため、構築を `Task` / `DispatchQueue.main.async` に逃がすと
  popUp 時点でメニューが空（起動後初回は何も表示されない）または1回遅れの内容になる
  （gitkun で実際に発生した不具合。間欠的な「メニューが出ない」として現れる）。
- **`popUp` の直前に `NSApp.activate(ignoringOtherApps: true)` を呼ぶこと**。
  LSUIElement（バックグラウンド）アプリは非アクティブのままだと popUp が表示に失敗することがある。

### 3. `com.mtkg.kun.appLaunched` — アプリ → kuntraykun
連携対応アプリが起動したことを知らせる（kuntraykun が最新 `sync` を送り返すため）。
- userInfo: `{ "bundleID": "<id>", "protocol": "1" }`
- 送信タイミング（アプリ側）: 起動完了時（`applicationDidFinishLaunching`）。
- 受信時（kuntraykun 側）: `sync` を再送して、起動直後のアプリに最新の対象集合を反映させる。

---

## v2: 実際のメニューバーアイコンの書き出し（任意・推奨）

kuntraykun の一覧に各アプリの**実際のメニューバーアイコン（色・状態込み）**を表示するための仕組み。
他プロセスの `NSStatusItem` の画像を直接読む公開 API が無いため、**各アプリが現在のアイコンを共有ファイルに書き出す**。

- **共有場所**: `~/Library/Application Support/Kuntraykun/MenuBarIcons/`（`IntegrationProtocol.sharedIconDirRelativePath`）。
  - `<基底bundleID>.png`: 現在のステータスアイコンを描画した PNG（18pt@2x=36px 目安、アスペクト保持）。
  - `<基底bundleID>.template`: 空ファイル。**存在すればテンプレート画像**（単色・明暗追従）として扱う。色付き画像のときは作らない/削除する。
- **アプリ側の書き出しタイミング**: 自分の `statusItem.button?.image` を設定するすべての箇所（起動時＋状態変化時）。
  `image.isTemplate` を見てマーカーを書く/消す。`KuntraykunIconExport.export(_:)`（各アプリ同梱の小ヘルパー）を呼ぶだけ。
- **kuntraykun 側の読み込み**: 一覧アイコンを「共有PNG → バンドル内 `MenuBarIcon.png` → アプリアイコン」の優先順で解決
  （`KunAppIcon.image`）。メニューは開くたびに再構築するので、開いた時点の最新アイコン（gitkun の状態色など）が反映される。
- 書き出しは任意。未対応アプリはバンドル内 `MenuBarIcon.png`（または Finder アイコン）にフォールバックする。

---

## v4: メニュースナップショットの共有（サブメニュー表示・任意・推奨）

kuntraykun のプルダウンを**閉じずに**、各アプリのメニューを**アプリ名のサブメニュー**として表示し、
項目クリックで対象アプリのアクションを実行するための仕組み。
他プロセスの `NSMenu` は読めないため、**各アプリがメニュー構造を JSON で共有ファイルに書き出し**、
kuntraykun がそれをサブメニューとして再構築、クリックを `invokeMenuItem` で依頼し返す。

対応は任意。未対応アプリ（スナップショット未受信）は従来どおり「クリック → `showMenu` → 相手が popUp」に
フォールバックする（v1 の動作は変わらない）。

### 共有ファイル
- **場所**: `~/Library/Application Support/Kuntraykun/Menus/<基底bundleID>.json`
  （`IntegrationProtocol.sharedMenuDirRelativePath = "Kuntraykun/Menus"`）。
- **書き込みは原子的に**（`Data.write(options: .atomic)` = temp へ書いて rename）行い、
  **書き込み完了後に `menuSnapshot` 通知**を送ること。読み手が中途半端な内容を見ないため。

### JSON スキーマ（MenuSnapshot）
```json
{
  "formatVersion": 1,
  "generation": "<書き出しごとに変える世代トークン（UUID など）>",
  "items": [
    { "id": "0", "title": "Clipkun 1.4.2", "enabled": false, "state": "off",
      "separator": false, "children": [] }
  ]
}
```
- `id`: 項目 ID。既定は**メニュー内の実インデックスのパス**（トップレベル 3番目 = `"2"`、
  そのサブメニュー 2番目 = `"2.1"`）。アプリが安定 ID を明示してもよい。
- `state`: `"off"` / `"on"` / `"mixed"`（チェック状態）。
- `separator: true` の項目は区切り線（他フィールドは無視される）。
- サブメニューは `children` のネストで表す。
- **前方互換**: 未知キーは無視、欠損キーは既定値（`enabled=true` / `state="off"` /
  `separator=false` / `children=[]`）で補完される。
- **上限**（kuntraykun 側がデコード時に切り詰め）: ネスト深さ 3、項目数はツリー全体で 500。
- **スコープ外（v4 では転送されない）**: 項目の画像・attributedTitle・keyEquivalent・カスタムビュー・
  alternate 項目。カスタムビュー項目はタイトルのみ・disabled で書き出すか省略する。

### 通知

#### 4. `com.mtkg.kuntraykun.requestMenu` — kuntraykun → アプリ
スナップショットの書き出しを依頼する。
- userInfo: `{ "targets": "<カンマ区切りの基底 bundleID 群>" }`
- 送信タイミング（kuntraykun 側）: 起動時 / 対象集合の変更時 / メニューを開くたび（次回オープンに反映）。
- 受信時の動作: `targets` に自分の基底 bundleID が含まれるときのみ、スナップショットを書き出して
  `menuSnapshot` を送る。

#### 5. `com.mtkg.kun.menuSnapshot` — アプリ → kuntraykun
共有ファイルへスナップショットを書き出したことを知らせる。
- userInfo: `{ "bundleID": "<基底ID>", "generation": "<世代>", "protocol": "1" }`
- 送信タイミング（アプリ側）: `requestMenu` 受信時 / **メニュー内容が変わったとき**
  （文言・enabled・チェック状態の変化。例: アップデート項目の文言変更）/ 起動時 / `invokeMenuItem` の実行後。
- 受信時（kuntraykun 側）: 共有ファイルを読みキャッシュを更新。**このセッション中に本通知を受け取ったアプリ
  だけをサブメニュー対応とみなす**（旧バージョンへ戻したアプリの stale ファイルを誤用しないため、
  起動時のファイル先読みはしない）。

#### 6. `com.mtkg.kuntraykun.invokeMenuItem` — kuntraykun → 対象1アプリ
サブメニューでクリックされた項目の実行を依頼する。
- userInfo: `{ "target": "<基底ID>", "itemID": "<項目ID>", "generation": "<世代>" }`
- 受信時の動作: `target` が自分の基底 bundleID と一致し、**`generation` が現行スナップショットの世代と
  一致するときのみ**、`itemID` の項目を解決して実行する（インデックスパスならサブメニューを辿って
  `NSMenu.performActionForItem(at:)`）。世代不一致（依頼が古い）なら**実行せず**最新スナップショットを
  書き出し直して `menuSnapshot` を再送する。実行後もメニュー内容が変わりうるため再書き出しする
  （アクションの副作用が済むよう次のランループに逃がすとよい）。

### アプリ側の実装注意
- シリアライズ前に `menu.update()` を呼び、`enabled` を確定させてから読む（autoenablesItems のメニューでは
  update 前の値が不定）。
- **メニュー表示中のエクスポートは保留が必要**。`menu.update()` は delegate の `menuNeedsUpdate` を
  同期的に呼ぶため、自分のメニューを表示（トラッキング）中に requestMenu 等でエクスポートが走ると、
  **開いているメニューが再構築されて表示が壊れる**。kunkit の `KuntraykunBridge` が `trackingMenu` の
  トラッキング通知（`NSMenu.didBegin/didEndTracking`）を観測して自動で保留・close 後に書き出すので、
  書き出しは必ず `bridge.exportMenuSnapshot()` 経由で行う（`KuntraykunMenuExport.export` を直接呼ばない）。
- **非表示項目（`isHidden`）は書き出しから省くが、ID の採番は実インデックスのまま**にする。
  invoke 時にそのままインデックスで辿れる（採番を詰めると実メニューとズレて誤実行する）。
- ウィンドウを開くアクションは従来どおりアプリ側で activate 処理を行う（showMenu 節の注意と同じ）。
- 実装: kunkit の `KuntraykunMenuExport.swift`（書き出し・項目実行）と `KuntraykunBridge.swift`
  （requestMenu / invokeMenuItem の観測）。

### kuntraykun 側の挙動（参考）
- `MenuSnapshotStore` が通知受信時に共有ファイルを読み in-memory キャッシュする。
- メニュー構築（`menuNeedsUpdate`）はキャッシュから同期的にサブメニューを付与し、同時に `requestMenu` を
  送って次回オープンへ反映する（表示中メニューの live 差し替えはしない）。
- サブメニュー項目のクリックで `invokeMenuItem` を送る（kuntraykun のメニューは通常どおり閉じる）。

---

## 管理対象アプリ側の必須挙動

### アイコン表示規則
```
自分のステータスアイコンを隠す = (管理対象フラグ ON) かつ (kuntraykun が起動中)
```
- 「kuntraykun が起動していなければ隠さない」フォールバックにより、kuntraykun が落ちていても
  ユーザーが各アプリを操作不能にならない。
- kuntraykun が起動中かは **`NSWorkspace.shared.runningApplications`**（各 `bundleIdentifier` を基底IDで突合）で判定する。
  `NSRunningApplication.runningApplications(withBundleIdentifier:)` は**実行中でも空を返すことがあり**（実機確認済み）、
  「kuntraykun 終了」と誤判定してアイコンが時間経過で再表示される不具合になるため使わない。
- **kuntraykun の起動・終了の検知は `NSWorkspace.runningApplications` の KVO で行う**こと。
  kuntraykun は LSUIElement（メニューバー常駐）のため、`NSWorkspace.didLaunchApplicationNotification` /
  `didTerminateApplicationNotification` は**配信されない**（実機確認済み）。これらに頼ると
  「kuntraykun を終了してもアイコンが復活しない」不具合になる。KVO は LSUIElement の起動/終了でも発火し、
  kuntraykun のクラッシュ時も復活する。

### 永続化
- 「管理対象フラグ」を各アプリ自身の設定（`SettingsStore` 等）に保存する。
- 起動時にフラグを読み、上記表示規則で初期のアイコン表示を決める（kuntraykun 起動前でも整合する）。

### 起動時
- `com.mtkg.kun.appLaunched` を送信する。
- `sync` / `showMenu` の観測を登録する。

### メニュー
- メニュー本体（`NSMenu`）と各項目のアクションは**各アプリのプロセスのまま**。挙動は完全にネイティブ。
- アイコンを隠している間も `NSStatusItem` 自体は破棄せず保持し（`isVisible = false`）、`showMenu` で `popUp` する
  メニューを使い回すのが簡単。
- メニューを動的に再構築する場合、`menuNeedsUpdate` 内で**同期的に**構築すること（`showMenu` 節の注意を参照）。

---

## 実装方法（kun アプリ側）— 共有ライブラリ kunkit を使う

本プロトコルのアプリ側実装（v1〜v4 の全機能）は共有ライブラリ
**[kunkit](https://github.com/m-tkg/kunkit)** にある。**新規・既存アプリとも自前実装やファイルコピーはせず、
SPM 依存で取り込む**（本章より上の各節はプロトコルの中身の説明で、挙動理解・デバッグ時に読む）。

```swift
// Package.swift
.package(url: "https://github.com/m-tkg/kunkit.git", from: "1.0.0"),
// executableTarget の dependencies に
.product(name: "KunIntegrationBridge", package: "kunkit"),
```

```swift
import KunIntegrationBridge

// AppDelegate の起動処理（statusItem / menu は自分のステータスバー実装のもの）
let bridge = KuntraykunBridge(statusItem: statusItem, menu: menu) // 標準配線
bridge.start()  // 観測開始・appLaunched 送信・初回メニュー書き出しまで行う
kuntraykunBridge = bridge

// アップデート有無が変わったら（v3）
kuntraykunBridge?.reportUpdate(hasUpdate)
// メニュー文言・チェック状態が変わったら（v4。表示中は自動保留）
kuntraykunBridge?.exportMenuSnapshot()
// アイコンを設定する箇所すべてで（v2）
KuntraykunIconExport.export(statusItem.button?.image)
```

- 標準配線 `init(statusItem:menu:)` は「隠す（`isVisible`）／popUp（activate 込み）／メニュー書き出し／
  項目実行／表示中の書き出し保留」まで既定実装する。特殊な配線が必要なアプリは
  クロージャ版 `init(setHidden:popUpMenu:exportMenu:performMenuItem:trackingMenu:)` を使う。
- 通知名・キー・`MenuSnapshot` モデルの定義は kunkit の `KunIntegrationProtocol` ターゲットにあり、
  kuntraykun 本体（ハブ側）も同じ定義を参照する（定数の二重管理はしない）。
- 基底 bundleID（末尾 `.local` の除去）も kunkit が処理する。
- 配線の実例: clipkun（`StatusBarController.makeKuntraykunBridge()` と `onMenuContentChanged`）。

---

## 段階導入（経緯）
1. まず1つの kun アプリ（Clipkun）に本プロトコルを実装し、kuntraykun と end-to-end 検証した。
2. 残りの kun アプリ（gitkun / keykun / pointerkun / snapperkun / whisperkun）へ展開した。
3. 各アプリに複製していた実装を共有ライブラリ kunkit へ集約した（現行の形）。
   共通テンプレート（`CLAUDE_base.md`）の「Kuntraykun 連携」章も kunkit ベースの記述になっている。
