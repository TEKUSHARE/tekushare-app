# iOS リリース手順チェックリスト

初回リリース（1.0.0 / ビルド16、2026-11-10 審査提出）で実際に行った手順をまとめる。アップデート時は「4. ビルドとアップロード」以降を繰り返す。

## 固定値

| 項目 | 値 |
|---|---|
| Team ID | `4N5F9L6BC2` |
| Bundle ID | prod `com.tekushare.app` / dev `com.tekushare.app.dev` / stg `com.tekushare.app.stg` |
| App Store ID | `6831876057`（`https://apps.apple.com/jp/app/id6831876057`） |
| SKU | `tekushare-ios` |
| APNs 認証キー | Key ID `45LHMBNQW6`（Sandbox & Production）。Firebase の「てくしぇあ iOS」に開発用・本番用ともアップロード済み |
| Firebase プロジェクト | `tekushare`（**dev / stg / prod とも同じプロジェクト**。dev 版で触ったデータも本番に入る） |

> `.p8`（APNs 認証キー）・審査用アカウントのパスワードは**リポジトリに入れない**。

## 1. 初回だけ行う設定（完了済み）

- Apple Developer Program に登録し、Team ID を `ios/Runner.xcodeproj` の `DEVELOPMENT_TEAM` と `public/.well-known/apple-app-site-association` に反映（#192）
- App Store Connect でアプリを作成し、App Store ID を Web のストアリンクに反映（#194）
- APNs 認証キーを作成し、Firebase Console → プロジェクトの設定 → Cloud Messaging → Apple アプリの構成にアップロード
- Hosting のデプロイ（AASA・プライバシーポリシー・サポートページ）

```bash
firebase deploy --only hosting --project tekushare
```

> リポジトリに `.firebaserc` が無いため、`--project tekushare` を付ける。

## 2. App Store Connect の掲載情報

### バージョンのページ

| 項目 | 値・注意 |
|---|---|
| プロモーション用テキスト | 170文字以内。審査なしでいつでも変更できる |
| 概要 | 4000文字以内。iOS 版は安否通知が**プッシュ通知のみ**（SMS は Android のみ）なので、SMS に触れない |
| キーワード | 100文字以内・カンマ区切り・スペースなし。アプリ名・他社アプリ名は入れない |
| サポート URL | `https://tekushare.web.app/support.html` |
| マーケティング URL | 空欄でよい |
| バージョン | `pubspec.yaml` の `version` の前半と同じにする（例：`1.0.0`。`1.0` にしない） |
| 著作権 | `2026 てくしぇあ` |
| ルーティングアプリカバレッジファイル・App Clip・iMessage | 不要 |
| ヘッダ（5244×2950 など） | 任意 |

### スクリーンショット

- 「Dynamic Island搭載iPhone（中型ディスプレイ）」に **1206×2622px**（または 1179×2556px）を最大10枚。iPad・iPhone Duo は不要（iPhone 専用のため）
- Google Play 用（1080×1920）はサイズが合わず、Android のナビゲーションバー（◀●■）や SMS の通知先が写っているので**使えない**（ガイドライン 2.3.10）
- 初回は iPhone 18 Pro シミュレーターで撮影し、Play 版と同じ見出し・配色で合成した（`~/Downloads/てくしぇあ写真/AppStore_iPhone_1206x2622/`）
- 撮影時の注意
  - dev 版も本番の Firebase につながるので、撮影用のデータはリポジトリ層をダミーに差し替えて表示する（結合テストの仕組みで画面を順に開き、`xcrun simctl io <UDID> screenshot` で撮る）
  - 位置情報は `locationServiceProvider` をダミーに差し替えると OS の許可ダイアログが出ない
  - 答えないまま残った許可ダイアログは、シミュレーターを再起動すると消える
  - ステータスバーは `xcrun simctl status_bar <UDID> override` で電池・電波を整える（時刻はアプリの時計と揃える）
  - 散歩ルートは端末内にのみ保存され共有されないので、「ルートをシェア」のような見出しにしない

### App Review に関する情報

- **サインイン情報**：本番版でメール認証まで済ませた審査用アカウント
- **連携相手のアカウント**も用意し、審査用アカウントと連携しておく（安否通知・共有の確認用）。メモに記載する
- **連絡先情報**：審査員からの連絡用（公開されない）
- **メモ**（英語）：以下を基本にする。アカウントのメール・パスワードは App Store Connect にだけ書く

```
Thank you for reviewing TekuShare.

[Demo account]
The account above is already linked with a partner account.
Partner account: <partner email> / <partner password>
You can sign in with the partner account on a second device to see shared spots and to receive the safety check push notification.

[Background location]
TekuShare uses location in the background only while a walk is in progress (after tapping the start button on the Home tab). It is used for:
1. Recording the walking route. The route is stored only on the device.
2. Safety check: if the user does not move for a set time (15 minutes by default, set in Settings > 安否確認), the app asks "元気です" (I'm OK). If there is no response, a push notification is sent to the linked partner.
Location updates stop when the walk ends.

[How to test]
1. Home tab > tap "散歩をはじめる" to start a walk.
2. Tap "行きたい！" to save the current location as a spot (photos can be attached).
3. Tap "散歩を終了する" to end the walk. The route can be viewed in the "散歩ルート" tab.
4. Settings > シェア shows the linked partner and sharing options.

[Account deletion]
Settings > アカウントを消去 deletes the account and all related data.

[Sign in]
The app uses email/password sign-in only (no third-party or social login).
```

- **リリース方法**：「このバージョンを手動でリリースする」（公開前に `appUpdates/prod_ios` を用意するため）
- 審査中は審査用・連携相手のアカウントを削除・パスワード変更しない

### アプリ情報

| 項目 | 値 |
|---|---|
| カテゴリ | プライマリ：ヘルスケア／フィットネス |
| コンテンツ配信権 | **はい**（地図に OpenStreetMap のタイルを使用。ODbL・出典表示済み） |
| 年齢制限 | 機能（ペアレンタルコントロール・年齢確認・ウェブアクセス・ユーザ生成コンテンツ・ソーシャルメディア・メッセージ・広告）はすべて「いいえ」。内容に関する質問はすべて「なし」→ 4+ |
| 規制対象の医療用デバイス | いいえ（ヘルスケア／フィットネスを選ぶと申告が必要） |
| 暗号化 | `Info.plist` の `ITSAppUsesNonExemptEncryption=false` で申告済み。書類の提出は不要 |

### アプリのプライバシー

- プライバシーポリシー URL：`https://tekushare.web.app/privacy.html`
- 収集するデータ（`ios/Runner/PrivacyInfo.xcprivacy` と揃える）

| 分類 | 項目 |
|---|---|
| 連絡先情報 | 名前、メールアドレス、電話番号 |
| 位置情報 | 正確な位置情報 |
| ユーザコンテンツ | 写真またはビデオ、その他のユーザコンテンツ（スポットのタイトル・メモ） |
| ID | ユーザ ID、デバイス ID（FCM トークン） |

- 各項目の回答はすべて同じ：用途「アプリの機能」のみ／ユーザに関連付け「はい」／トラッキング「いいえ」
- 使用状況データ・診断は**収集しない**（Analytics・Crashlytics は未導入）。導入したら申告を追加する
- 最後に右上の「**公開**」を押す（押さないと審査に出せない）

### 価格および配信状況

- 価格：0円（無料）、配信地域：日本

## 3. 提出前の確認

- `pubspec.yaml` の `version` を上げる（ビルド番号は App Store Connect にアップロード済みの番号より大きくする）
- 本番版の動作を TestFlight で実機確認する：ログイン、散歩の記録（画面オフ含む）、写真、プッシュ通知、Universal Links、アカウント消去

## 4. ビルドとアップロード

```bash
flutter build ipa --flavor prod -t lib/main_prod.dart
```

- 出力：`build/ios/archive/Runner.xcarchive`、`build/ios/ipa/てくしぇあ.ipa`（App Store 配布用の証明書で署名済み）
- 「Upload Symbols Failed」（FirebaseFirestoreInternal・grpc などの dSYM がない）の警告は無視してよい

アップロードは次のどちらか。

1. **Xcode の Organizer**：`open build/ios/archive/Runner.xcarchive` → アーカイブの行を選択 → Distribute App → App Store Connect → Upload
   - Xcode 27.2 では Distribute App が押せないことがあった。アーカイブの行を選択し、Validate App を実行したあとは押せる状態になった。押せない場合は Transporter を使う
2. **Transporter**（Mac App Store の Apple 純正アプリ）：`build/ios/ipa/てくしぇあ.ipa` をドラッグして「配信」

アップロード後 10〜30分で TestFlight タブのビルドが「提出準備完了」になる。

## 5. 審査への提出

1. 配信タブ → バージョンのページ → 「ビルド」の「＋」でビルドを選び、保存
2. 「審査用に追加」→「審査へ提出」。足りない項目があると一覧で表示される
3. 「審査待ち」→「審査中」→ 結果（目安 24〜48時間）。審査員からの質問は App Review のメッセージに届く

## 6. 承認後

1. Firestore に `appUpdates/prod_ios` を作成する（形式は [アップデート案内](app_update_prompt.md)。`storeUrl` は `https://apps.apple.com/jp/app/id6831876057`）
2. 「このバージョンをリリース」で公開する
3. App Store からインストールしてログイン・散歩の記録を確認する

## 関連 Issue

- #178 Team ID・App Store ID を AASA と Web に反映
- #179 iOS ストア申請準備（Apple Developer / App Store Connect / TestFlight）
- #193 iOS で位置の精度が低いと GPS が取得できない問題
