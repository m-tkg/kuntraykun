# kuntraykun

複数の kun シリーズ（Clipkun / gitkun / Keykun / Pointerkun / Snapperkun / whisperkun …）を
同時に起動するとメニューバーがアイコンだらけになります。**kuntraykun はそれらを1つのアイコンに集約**する
ランチャー兼ハブです。メニューバーのアイコンを1個に減らしつつ、各アプリのメニューへ素早くアクセスできます。

## 特長

- **1つのアイコンに集約**: 選択した kun アプリのメニューバーアイコンを隠し、kuntraykun のアイコンにまとめる
- **サブメニュー表示**: kuntraykun のメニューを開くと、各 kun アプリのメニューが**アプリ名のサブメニュー**として
  そのまま並ぶ（項目クリックで対象アプリのアクションを実行）
- **実行中のアプリだけ表示**: 選択済み かつ 起動中の kun アプリだけがメニューに並ぶ
- **表示順を変更可能**: 設定の「管理アプリ」タブで ▲▼ 並べ替え
- **アップデートの集約表示**: いずれかの管理対象アプリに更新があると、kuntraykun のアイコンにバッジ・
  該当アプリ行に赤丸を表示
- **Accessibility 権限は不要**（分散通知と共有ファイルで各アプリと協調）
- ログイン時の自動起動、GitHub Releases からの自己アップデートに対応

## 動作環境

- macOS 13 以降
- 集約対象は bundle ID が `com.mtkg.` で始まり末尾が `kun` のメニューバーアプリ（kun シリーズ）

## インストール

### リリース版を使う

1. [Releases](https://github.com/m-tkg/kuntraykun/releases/latest) から `Kuntraykun.zip` をダウンロード
2. 展開して `Kuntraykun.app` を `/Applications` に移動して起動
3. メニューバーのアイコンから設定を開き、「管理アプリ」タブで集約したい kun アプリを選ぶ

アップデートはメニューの「アップデートを確認…」から自己更新できます。

## 使い方

1. 集約したい kun アプリ（Clipkun など）を選択すると、それらのアプリは自分のアイコンを隠し kuntraykun に集約されます
2. kuntraykun のアイコンをクリックすると、選択済み かつ 実行中のアプリがサブメニューとして並びます
3. サブメニューから各アプリのメニュー項目を直接選べます（連携対応前のアプリは、クリックで元のメニューが直下に開きます）

各 kun アプリ側の連携は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit) が提供します。連携プロトコルの
仕様は [`docs/kun-integration-protocol.md`](docs/kun-integration-protocol.md) を参照してください。

## 開発

純粋ロジック（`KuntraykunCore`）は TDD、UI/OS 連携は実機で手動確認します。

```sh
swift test                              # 純粋ロジックのテスト
LOCAL=1 bash Scripts/bundle.sh debug    # ローカル検証用の .app（本番と別 bundle ID）
```

開発方針の詳細は [`CLAUDE.md`](CLAUDE.md)（共通方針は `../CLAUDE_base.md`）を参照。
