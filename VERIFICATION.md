# 検証記録 — 2026-09-13

ブランチ: `feature/develop`

## 実行環境

- Windows / Godot `4.7.2.stable.official.ed1daf0bf`
- Compatibility / OpenGL 3.3.0 / NVIDIA GeForce RTX 2070 SUPER
- 日本語表示: システムフォントYu Gothic / Meiryo
- テンプレート取得元: [Godot公式4.7.2リリース](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)

## 実施結果

| 検証 | 結果 |
| --- | --- |
| Godotのインポートとスクリプト読み込み | 成功 |
| `tools/test.ps1` | **42チェック、失敗0、終了コード0** |
| 通常戦A/B→C→ボスの自動攻略 | 両分岐を含む20シード中20勝 |
| Windows/OpenGLでの実画面生成 | 成功。タイトル・拠点・マップ・戦闘・エディタ・テスト設定 |
| 戦闘／エディタの生成画像確認 | 日本語表示、手札10枚の横スクロール、フォーム表示を確認 |
| `tools/export.ps1` | 成功、Windows x64のexeとpckを生成 |
| Windows実行ファイルの `-- --smoke` | **7チェック成功、終了コード0** |

42チェックではカードの解決中領域と山札末尾への移動、自身をドローしないこと、初期手札・次ターンドロー・手札保持・上限、AP/MP不足と無効対象時の無変更、8ダメージの式一致、毒・ブロック・死亡順序、不正数式・重複ID・参照切れ・到達不能・循環の拒否、シード再現、報酬・初クリアの重複防止、装備個体保存、不正セーブの保護を確認しました。

同じ実シーンを使用し、カード威力12の保存→再読込→14ダメージ、同条件リスタート、編集ID復帰、無効ドラフトによる保存阻止、未保存キャンセル、通常セーブ不変、停止中の通常戦闘復帰、敗北／確認付き撤退での拠点帰還も検証しました。編集テストは `.godot/tests/editor_data/` の専用コピーを使用し、元のサンプルデータを変更しません。

エクスポート版7チェックは、`user://editor_workspace/data` への保存、再読込、変更値の復元、新規セーブ、通常戦報酬、セーブ／ロード、エディタ往復です。通常の `saves/profile.json` は使わず `user://smoke/profile.json` を使用しました。

初回のサンドボックス内実行ではGodotの標準ログ・キャッシュへのアクセスエラーがありました。標準領域へのアクセスが可能な実行で最終検証を再実施し、上記結果を得ています。

## 検証の範囲

画面の遷移・操作はGodot内からの自動呼び出しによるものです。実際の描画結果を画像で確認しましたが、マウスで全シナリオを手操作する通しプレイや長時間の操作感・難易度評価は未実施です。異なるWindows環境、全リサイズ条件、レア装備を含む長期バランスも未確認です。

初回プロトタイプとして動作経路を実装しています。正式配布品質やspec.mdの全手動確認項目まで完了した、という扱いにはしていません。

## 確認に使う生成物

- `build/CardSlayer.exe` と `build/CardSlayer.pck`（同じディレクトリに置く）
- `.godot/tests/title.png`, `hub.png`, `map.png`, `battle.png`, `editor.png`, `test-settings.png`
- `%APPDATA%\Godot\app_userdata\CardSlayer\smoke\report.json`

buildと.godotはGit管理対象外です。再生成方法はREADME.mdに記載しています。
