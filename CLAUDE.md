# CLAUDE_base.md — メニューバー常駐アプリ作成の共通ガイド

snapperkun / whisperkun / keykun の知見をまとめた、macOS タスクトレイ（メニューバー常駐）
アプリを新規作成する際の共通方針。新規プロジェクトの `CLAUDE.md` はこれをベースに、
プロジェクト固有の事項を足して作る。

## 基本構成

- **Swift Package Manager** の 2 ターゲット構成。**純粋ロジックとプラットフォーム依存を分離**する。
  - `<Name>Core`（ライブラリ / テスト対象）: AppKit/Carbon/AX/CGEventTap に依存しないロジックとモデル。
    判定ロジックは時刻などを注入する純粋関数/状態機械にして **TDD（テスト先行）** で実装する。
  - `<Name>`（実行ファイル）: AppKit/SwiftUI/各種 OS 連携と UI。
- **メニューバー常駐**（Dock アイコンなし）。`Info.plist` に `LSUIElement = true`、
  `main.swift` で `NSApplication` を `.accessory` 起動（`MainActor.assumeIsolated`）。
- **多重起動防止**: 起動時に同じ bundle ID の他インスタンスがあれば、それを前面化して自分は `exit(0)`。
- `.app` 化は `Scripts/bundle.sh`（`swift build` → バンドル組み立て → 署名）。Xcode プロジェクトは持たない。
- リリースは GitHub Actions（`.github/workflows/release.yml`）。`Info.plist` の
  `CFBundleShortVersionString` を上げて `main` に push すると `v<version>` を自動作成する
  （同名リリースがあればスキップ）。

---

## 必須チェックリスト

### 1. Secrets は `setup-release-secrets.sh` で登録する
配布用の署名＋公証の Secrets（計6つ）は、上位ディレクトリの **`setup-release-secrets.sh`** で一括登録する。
```sh
~/git/github.com/m-tkg/setup-release-secrets.sh -r m-tkg/<repo>
```
- 署名: `SIGNING_IDENTITY` / `SIGNING_CERTIFICATE_PASSWORD` / `SIGNING_CERTIFICATE_P12_BASE64`
- 公証: `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID`
- 署名は Developer ID Application（Team ID `G72M73C546`）。**安定署名でアクセシビリティ権限(TCC)が
  アップデート越しに保持される**（ad-hoc は毎回変わり無効化される）。
- ワークフローは Secrets が無ければ ad-hoc 署名／公証スキップにフォールバックする。
- `setup-release-secrets.sh` は秘密鍵(.p12)を含むので**リポジトリにコミットしない**（上位ディレクトリは git 管理外）。

### 2. すべての UI を日英対応にする
GUI 文字列は **日本語・英語の 2 言語**に対応し、OS の優先言語に追従する（既定 `en`）。
- 文字列リテラルを `Text`/`Button`/`NSMenuItem`/`NSAlert`/ウィンドウタイトル/HUD 等に直接渡さない。
  `Resources/{en,ja}.lproj/Localizable.strings` の**両方**にキーと対訳を足し、
  コードは `L.string("キー")` / `L.format("キー", 値…)` で参照する（`Localization.swift` の `L`）。
- `Package.swift` に `defaultLocalization: "en"` と `resources: [.process("Resources")]`。
- **`Info.plist` に `CFBundleLocalizations`（en, ja）が必須**。無いと macOS がアプリ言語を
  開発リージョン(en)に固定し、ネスト文字列バンドルも en にフォールバックして日本語が一切出ない。
  ```xml
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
  ```
- `L` は SwiftPM 生成のリソースバンドル（`<Name>_<Name>.bundle`）を自前探索で解決し、
  見つからなければ `.main` にフォールバック（`Bundle.module` はクラッシュしうるので使わない）。
  `bundle.sh` がこのバンドルを `Contents/Resources/` にコピーする。

### 3. bundle ID は `com.mtkg.****` にする
本番の bundle ID は **`com.mtkg.<appname>`**（例: `com.mtkg.keykun` / `com.mtkg.snapperkun`）。
`Info.plist` の `CFBundleIdentifier`、各 `Logger(subsystem:)`、`UpdateService` 等で一貫させる。

### 4. アップデート機能を入れる
GitHub Releases から最新版を取得して自己更新する。
- `Core`: `ReleaseInfo`（`/releases/latest` の Decodable）と `VersionComparator`（タグの数値比較・純粋・テスト）。
- `App`: `UpdateService`（公開 GitHub API を URLSession で取得・zip DL。キャッシュ無効の ephemeral セッション）、
  `SelfUpdater`（zip を `ditto` 展開 → bundle ID 検証 → 旧プロセス終了待ち→入替の切り離しスクリプト→再起動）。
- メニューに「アップデートを確認…」を置き、起動時にサイレントチェック。新版があればメニュー文言を
  「アップデート v… をインストール…」に変える。
- 自己更新の bundle ID 検証は**基底ID（`.local` を除去）で比較**し、ローカルビルドからも本番へ更新できるようにする。

### 5. 自動起動（ログイン項目）機能を入れる
- `LoginItemController` で `SMAppService.mainApp`（macOS 13+）を register/unregister。
- **状態はシステム側が source of truth**。`Settings`/JSON には保存しない。表示時に `refresh()` で同期する。
- `.requiresApproval`（システム設定でログイン項目が無効）時は案内文を出す。
- トグルは設定の Apply/Cancel とは独立に**即時反映**する。

### 6. 設定は「設定」メニュー/ダイアログに集約する
- メニューバーのメニューは入口だけ（設定… / 権限確認 / アップデート確認 / 終了 など）。
  設定項目そのものはメニューに展開せず、**設定ダイアログ**に集約する。
- 設定ダイアログは SwiftUI を `NSWindow` にホストし、**タブ**で機能ごとに分割（機能追加はタブを足す）。
  「一般」タブ（自動起動・バージョン等）は**左端**に置く。
- **設定ダイアログ表示中は Dock アイコンを出す**。`SettingsWindowController` が表示時に
  `NSApp.setActivationPolicy(.regular)`、クローズ時に `.accessory` へ戻す。
- 設定の永続化は `Core` の `Settings`（機能ごとにサブ構造体）＋ `SettingsStore`（JSON、読込失敗で既定にフォールバック）。
  Codable は `decodeIfPresent ?? 既定値` で欠損キーを補完し前方/後方互換にする。
- SwiftUI を import するファイルでは `Settings`/`Binding` が SwiftUI と名前衝突するため
  `<Name>Core.Settings` / `@SwiftUI.Binding` と明示する。

### 7. ローカルビルドは「ローカル」表示で本番と区別する
- `bundle.sh` に `LOCAL=1` モードを設ける: bundle ID を `com.mtkg.<app>.local`、表示名を `<App> (Local)` にする。
- アプリは bundle ID が `.local` で終わるかで `isLocalBuild` を判定し、**メニューバーアイコンに「ローカル」を併記**、
  メニューのバージョン項目にも「(ローカル)」を付ける。
- 本番と bundle ID が違うので **TCC 権限が別エントリになり衝突しない**（独立して許可できる）。

### 8. ローカルの公証に気をつける
- 公証(notarization)は **CI のリリースビルドのみ**。ローカルビルド（`LOCAL=1` / `bundle.sh` 手元実行）は
  **署名はされるが公証されない**。配布物と取り違えない。
- ローカルビルドは bundle ID が `.local` で**別アプリ扱い**のため、**アクセシビリティ権限を別途付与**する必要がある。
- ローカルは未公証なので Gatekeeper の quarantine が付くと起動を阻まれることがある。必要なら
  `xattr -dr com.apple.quarantine <App>.app`（自己更新の入替スクリプトでも実施している）。
- ローカルでも Developer ID 署名（`SIGN_IDENTITY` 既定）にしておくと、再ビルドで TCC 権限が保持され検証が楽。

### 9. メニューにバージョン情報を入れる
- メニューバーのメニュー**先頭に操作不可のバージョン項目**（例: `Keykun 1.1.1`）を置き、区切り線を続ける。
- 文言は `Bundle.main` の `CFBundleShortVersionString`（`UpdateService.currentVersion`）から生成し、ローカルは「(ローカル)」を付す。
- 設定ダイアログ「一般」タブにもバージョンを表示する。

---

## イベントタップ系（keykun のような CGEventTap を使う場合）

- **イベントタップは1つを共有**し、機能ごとにハンドラを登録する（別タップを作らない）。
- **コールバック内で重い処理や再入しうる post を同期実行しない**。重い処理は `tapDisabledByTimeout` を招き
  イベントを取りこぼして状態が固着する。副作用は `DispatchQueue.main.async` でコールバック復帰後に逃がす。
- **タップ無効化時はハンドラ状態をリセット**して取りこぼし後の固着を防ぐ。
- **合成キーイベントは `.cghidEventTap`（HID 相当）に post**する（`.cgSessionEventTap` だと IME 等に届かない）。
- 入力モード切替は **英数/かなキー送出**が確実（`TISSelectInputSource` は「選択中の再選択が no-op」で
  複数モード IME では切り替わらない）。

## ブランチ運用（必須）

- **`main` ブランチへ直接コミット/push しない**。変更は必ず **Pull Request 経由**で行う。
- 作業ブランチは**必ずその時点の最新の `main` から切る**。ブランチ作成前に
  `git fetch origin && git switch main && git pull --ff-only`（または `git fetch && git switch -c <branch> origin/main`）
  で main を最新化してから分岐する。
- PR は `gh pr create` で作成し、マージはレビュー後に行う。
- **PR 作成後に追加の修正を行うときは、まずその PR が既にマージされていないか確認する**
  （`gh pr view <番号> --json state,mergedAt`）。マージ済みの場合、その PR の作業ブランチへ
  push しても main には反映されない（孤立コミットになる）。マージ済みなら**最新 `main` から
  新しいブランチを切り直し**、必要な修正と（リリースが要るなら）バージョン更新を入れて別 PR を出す。
- リリース用 Actions は `push: branches: [main]` で発火するため、main への push が
  そのままリリースに直結する。事故防止のためにも main 直 push は避け、PR マージ経由にする。

## 開発の進め方

- 純粋ロジック（`Core`）は **TDD**（テスト先行）。UI/OS 連携は手動確認（実機で権限付与が必要）。
- 新機能の追加手順: ①判定ロジックを `Core` に純粋実装＋テスト → ②`Settings` にサブ構造体を足す →
  ③設定 UI にタブを足す → ④GUI 文字列を en/ja 両方に対訳追加。
- リリースは `Info.plist` の `CFBundleShortVersionString` を上げて `main` に push（署名＋公証は CI が実施）。

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
- **表示順はユーザーが変更できる**。設定「管理アプリ」タブのリストをドラッグで並べ替えると、その順序が
  `ManagedAppsSettings.orderedBundleIDs`（基底 bundle ID 配列）に保存され、`KunAppMatcher.ordered` が
  その順でプルダウンを並べる（未登録のアプリは末尾に表示名昇順）。
- 項目をクリックすると、その kun アプリへ「kuntraykun アイコン直下にメニューを出せ」と依頼し、対象アプリが
  自分のネイティブメニューを `popUp` する。

## 連携プロトコル（重要）
- macOS では他プロセスの `NSStatusItem` メニューを取得して自前描画できない。そこで**各 kun アプリ側に連携の口**を
  実装してもらい、`DistributedNotificationCenter`（分散通知）で協調する。
- 仕様は **`docs/kun-integration-protocol.md`**。定数は `KuntraykunCore/IntegrationProtocol.swift`、
  kuntraykun 側の送受信は `Sources/Kuntraykun/IntegrationHub.swift`。
- 通知: `com.mtkg.kuntraykun.sync`（対象集合のブロードキャスト）/ `com.mtkg.kuntraykun.showMenu`（メニュー表示依頼）/
  `com.mtkg.kun.appLaunched`（アプリ→ハブの起動通知）。userInfo の値は文字列のみ。
- 管理対象アプリ側の表示規則: `アイコンを隠す = (管理対象フラグ ON) かつ (kuntraykun 起動中)`。
  kuntraykun 未起動ならフォールバックでアイコンを出す（操作不能を防ぐ）。
- **Accessibility 権限は使わない**（AX 案は不採用）。

## 段階導入の状況
- kuntraykun 本体は実装済み。次は1つの kun アプリ（例 Clipkun）にプロトコルを実装して end-to-end 検証し、
  問題なければ残りへ展開する。最終的には本テンプレート（`CLAUDE_base.md`）にも「Kuntraykun 連携」章を足す。

## ローカル検証
`LOCAL=1 AD_HOC=1 bash Scripts/bundle.sh debug` で `Kuntraykun (Local).app` を生成（署名証明書が無い環境向け）。
本番署名がある環境では `LOCAL=1 bash Scripts/bundle.sh debug`。
