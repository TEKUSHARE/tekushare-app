# CLAUDE.md

このリポジトリで作業するAIエージェント（Claude Code）向けのルール集約ファイル。個別ドキュメントに散らばる決定事項ではなく、**作業の進め方そのものに関するルール**をここにまとめる。本リポジトリの[コード規約](docs/コード規約.md)・[環境とブランチ運用](docs/環境とブランチ運用.md)は姉妹プロジェクト（kumayokeru-app、burari-date）が踏襲する**原本**であるため、ここでの変更は他リポジトリの規約にも影響しうることを意識する。

## このリポジトリについて

てくしぇあ（TekuShare）― 散歩中に「ここいいな」を1タップで記録できるFlutterアプリ。ルートも自動記録し、地図で振り返れる。

## ドキュメントの優先順位

| ドキュメント | 内容 |
|---|---|
| [全体設計書](docs/全体設計書.md) | 機能・画面・状態管理・ファイル構造 |
| [コード規約](docs/コード規約.md) | Flutter/Dartのプロジェクト固有ルール（迷ったら参照する原本。**必読**） |
| [デザイントークン](docs/デザイントークン.md) | カラー・スペーシング・サイズ等のUI定数 |
| [環境とブランチ運用](docs/環境とブランチ運用.md) | Flavor（dev/stg/prod）・GitHub Flow + タグリリースの原本 |
| [環境構築手順](docs/環境構築手順.md) | 新規セットアップ手順 |
| [テスト方針](docs/テスト方針.md) / [テスト一覧](docs/テスト一覧.md) | テスト方針と既存テストの一覧 |
| [Androidリリースチェックリスト](docs/android_release_checklist.md) | リリース前確認事項 |
| [iOSリリースチェックリスト](docs/ios_release_checklist.md) | App Store への提出手順・掲載情報・審査メモ |

コードを書く前に必ず[コード規約](docs/コード規約.md)を確認する。

## ブランチ・PRの運用: GitHub Flow + タグリリース

環境ごとの長命ブランチ（dev/stg/prodブランチ）は作らない。環境の切り替えはFlavor（`lib/main_dev.dart`/`main_stg.dart`/`main_prod.dart`）で行う（[環境とブランチ運用](docs/環境とブランチ運用.md)参照）。

```text
main                    ← これ1本
  ├─ feature/NNN-xxx    ← 機能開発。Issue番号を先頭に付ける（短命）
  └─ fix/xxx             ← バグ修正（短命）
```

- 作業は`main`から分岐し、PR経由で`main`へマージする。`main`へ直接pushしない。
- ブランチ名にはIssue番号を含める慣習がある（例：`feature/105-password-reset`）。
- PRと同じタイミングで対応するテストを作成する（[テスト方針](docs/テスト方針.md)）。

## コミット・PRメッセージ

- 日本語で、変更の意図（なぜ）が分かるように書く。
- コミットメッセージ・PR説明の末尾に付ける attribution（Co-Authored-By等）は、呼び出し元（Claude Codeのシステム設定）の指示に従う。本ファイルでは固定しない。

## セットアップ・実行

```bash
flutter pub get
flutter run --flavor dev -t lib/main_dev.dart

flutter test
```

詳細は[環境構築手順](docs/環境構築手順.md)を参照。

## 作業時の注意

- `lib/objectbox-model.json`・`lib/objectbox.g.dart`はObjectBoxのコード生成物。スキーマ変更時のみ意図的に更新し、無関係な変更で上書きしない。
- `pubspec.lock`はコマンド実行結果で変わることがあるため、意図しない差分が出ていないか確認してからコミットする。
- Firebase関連の秘密鍵・APIキーをリポジトリに含めない。
