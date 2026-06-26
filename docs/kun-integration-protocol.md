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

### 3. `com.mtkg.kun.appLaunched` — アプリ → kuntraykun
連携対応アプリが起動したことを知らせる（kuntraykun が最新 `sync` を送り返すため）。
- userInfo: `{ "bundleID": "<id>", "protocol": "1" }`
- 送信タイミング（アプリ側）: 起動完了時（`applicationDidFinishLaunching`）。
- 受信時（kuntraykun 側）: `sync` を再送して、起動直後のアプリに最新の対象集合を反映させる。

---

## 管理対象アプリ側の必須挙動

### アイコン表示規則
```
自分のステータスアイコンを隠す = (管理対象フラグ ON) かつ (kuntraykun が起動中)
```
- 「kuntraykun が起動していなければ隠さない」フォールバックにより、kuntraykun が落ちていても
  ユーザーが各アプリを操作不能にならない。
- kuntraykun が起動中かは、起動時に `NSRunningApplication.runningApplications(withBundleIdentifier: "com.mtkg.kuntraykun")` で判定し、
  以後は `NSWorkspace.shared.notificationCenter` の `didLaunchApplicationNotification` / `didTerminateApplicationNotification` を
  観測して、kuntraykun の起動・終了のたびにアイコン表示を再計算する。

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

---

## 実装スケッチ（kun アプリ側 / Swift）

通知名・キーは kuntraykun の `KuntraykunCore/IntegrationProtocol.swift` と一致させること。

```swift
import AppKit

enum KunIntegration {
    static let kuntraykunBundleID = "com.mtkg.kuntraykun"
    static let syncName     = Notification.Name("com.mtkg.kuntraykun.sync")
    static let showMenuName = Notification.Name("com.mtkg.kuntraykun.showMenu")
    static let appLaunched  = Notification.Name("com.mtkg.kun.appLaunched")
}

@MainActor
final class KuntraykunBridge {
    private let statusItem: NSStatusItem      // 自分のメニューバー項目
    private let menu: NSMenu                   // 自分のステータスメニュー
    private let myBundleID: String             // 基底 bundleID（.local を除去したもの）
    private var isManaged = false              // 永続化した管理対象フラグ

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(onSync(_:)),
                        name: KunIntegration.syncName, object: nil)
        dnc.addObserver(self, selector: #selector(onShowMenu(_:)),
                        name: KunIntegration.showMenuName, object: nil)

        // kuntraykun の起動/終了を監視してアイコン表示を再計算
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(refreshIconVisibility),
                         name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(refreshIconVisibility),
                         name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        refreshIconVisibility()

        // 起動を通知（kuntraykun が最新 sync を返してくれる）
        dnc.postNotificationName(KunIntegration.appLaunched, object: nil,
            userInfo: ["bundleID": myBundleID, "protocol": "1"], deliverImmediately: true)
    }

    @objc private func onSync(_ note: Notification) {
        let managed = (note.userInfo?["managed"] as? String ?? "")
            .split(separator: ",").map(String.init)
        isManaged = managed.contains(myBundleID)
        persistManagedFlag(isManaged)        // 各アプリの設定に保存
        refreshIconVisibility()
    }

    @objc private func onShowMenu(_ note: Notification) {
        guard note.userInfo?["target"] as? String == myBundleID,
              let xs = note.userInfo?["x"] as? String, let x = Double(xs),
              let ys = note.userInfo?["y"] as? String, let y = Double(ys) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: nil)
    }

    @objc private func refreshIconVisibility() {
        let hubRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: KunIntegration.kuntraykunBundleID).isEmpty
        statusItem.isVisible = !(isManaged && hubRunning)
    }
}
```

> 基底 bundleID: ローカル検証ビルド（`com.mtkg.<app>.local`）でも一致させたい場合は、
> 比較前に末尾 `.local` を除去した基底 ID で突き合わせる。

---

## 段階導入
1. まず1つの kun アプリ（例 Clipkun）に本プロトコルを実装し、kuntraykun と end-to-end 検証する。
2. 問題なければ残りの kun アプリへ展開する。
3. 共通テンプレート（`CLAUDE_base.md`）にも「Kuntraykun 連携」章を追加し、新規 kun アプリが標準対応できるようにする。
