# iOS Flavor セットアップ（完了済み）

> 2026-07-10 に対応完了。Build Configuration / Scheme は Xcode の GUI ではなく、
> `xcodeproj` Ruby gem を使ったスクリプトで作成した（手順は本ファイル末尾に記録）。
> 新しく Mac 環境を用意する人は、このファイルの「動作しない場合」だけ読めば十分。

## 何が設定されているか

- Build Configuration: `Debug` / `Release` / `Profile` に加えて、flavor 分の 9 つ
  （`Debug-dev` / `Release-dev` / `Profile-dev` / `*-stg` / `*-prod`）を
  プロジェクトレベル・`Runner` ターゲット・`RunnerTests` ターゲットそれぞれに追加済み。
- Scheme: `dev` / `stg` / `prod`（Shared）を追加済み。`flutter run --flavor <dev|stg|prod>` が
  そのままこのスキーム名を探しにいく。
- xcconfig: `ios/Flutter/<Debug|Release|Profile>-<dev|stg|prod>.xcconfig` を新規作成し、
  それぞれ次を include している。
  ```
  #include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.<config>-<flavor>.xcconfig"
  #include "<Debug|Release>.xcconfig"   ← Profile は Release.xcconfig を使う（既存の Profile 構成に合わせた）
  #include "<Dev|Stg|Prod>.xcconfig"     ← BUNDLE_ID_SUFFIX / BUNDLE_DISPLAY_NAME
  ```
- `Runner` ターゲットの `PRODUCT_BUNDLE_IDENTIFIER` は flavor 用 Configuration でのみ
  `com.tekushare.app$(BUNDLE_ID_SUFFIX)` に上書き済み（Debug/Release/Profile 標準側は無変更）。
- `ios/Podfile` の `project 'Runner', {...}` に `Debug-dev` 等 9 configuration すべてを
  `:debug` / `:release` にマッピング済み（CocoaPods が per-flavor の xcconfig を生成するために必須）。
- `ios/Podfile` の `platform :ios` を `13.0` → `15.0` に変更済み
  （`cloud_firestore` / `firebase_auth` / `firebase_core` の Swift Package が iOS 15.0 以上を要求するため）。
- `ios/Runner/Info.plist` に `NSLocationWhenInUseUsageDescription` を追加済み
  （geolocator が権限リクエストする際に必須。無いとリクエスト時に即クラッシュする）。

確認:

```bash
cd ios
xcodebuild -list -project Runner.xcodeproj   # Schemes に dev/stg/prod があるか
xcodebuild -showBuildSettings -workspace Runner.xcworkspace -scheme dev -configuration Debug-dev \
  | grep -i "PRODUCT_BUNDLE_IDENTIFIER\|BUNDLE_DISPLAY_NAME"
# => com.tekushare.app.dev / てくしぇあ Dev になっていればOK
```

```bash
flutter run --flavor dev  -t lib/main_dev.dart
flutter run --flavor stg  -t lib/main_stg.dart
flutter run --flavor prod -t lib/main_prod.dart --release
```

VS Code なら `F5` → `dev (debug)` / `stg (debug)` / `prod (debug)` を選択するだけでOK
（`.vscode/launch.json` に定義済み）。

---

## 動作しない場合（トラブルシューティング）

新しい Mac で `flutter run --flavor dev` を初めて実行すると、以下の順で詰まることが多い。
上から順番に確認する。

### 1. `CocoaPods not installed or not in valid state`

macOS 標準の Ruby（`/usr/bin/ruby`、2.6系）は古く、`sudo gem install cocoapods` は
`ffi` が Ruby 3.0+ を要求するため失敗する。**Homebrew 経由でインストールすること**。

```bash
# Homebrew が無ければ先に入れる
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install cocoapods
pod setup
```

### 2. `Error: The Xcode project does not define custom schemes. You cannot use the --flavor option.`

`dev`/`stg`/`prod` スキームが見つかっていない。まず `xcode-select` が
Command Line Tools ではなく本体の Xcode.app を指しているか確認する。

```bash
xcode-select -p
# /Library/Developer/CommandLineTools になっていたら↓で切り替え
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license   # 初回は同意が必要
```

それでも出る場合はスキーム自体が壊れていないか `xcodebuild -list -project ios/Runner.xcodeproj` で確認。

### 3. `No supported devices found with name or id matching '...'`

シミュレーターが起動していない。Xcode.app に切り替わっていないと `xcrun simctl` が
Command Line Tools 側を見て失敗することがあるので、上記 1. を先に直す。

### 4. `requires minimum platform version 15.0 ... but this target supports 13.0`

`ios/Podfile` の `platform :ios` が `15.0` になっているか確認。なっていても直らない場合は
`project.pbxproj` 内の `IPHONEOS_DEPLOYMENT_TARGET` が 13.0 のまま残っていないか grep する。

```bash
grep -n "IPHONEOS_DEPLOYMENT_TARGET" ios/Runner.xcodeproj/project.pbxproj
```

### 5. 位置情報を取得した瞬間にアプリが落ちる

`ios/Runner/Info.plist` に `NSLocationWhenInUseUsageDescription` があるか確認
（無いと `Geolocator.requestPermission()` 呼び出し時に OS がアプリを強制終了する）。

### 6. VS Code の Problems パネルが無関係なエラーで真っ赤

`build/ios/SourcePackages/...` 配下（Firebase パッケージ同梱の example/test コード）を
Dart アナライザが拾っている。`analysis_options.yaml` の `exclude` に `build/**` が
入っているか確認し、入っていれば Dart Analysis Server を再起動する。

### 7. テストコードが `MockXxx` を解決できない

`.mocks.dart` が未生成。`build_runner` を実行する。

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## Build Configuration / Scheme を作り直したい場合

Xcode の GUI で 9 個の Configuration と 3 個の Scheme を手作業で作るのはミスが起きやすいため、
`xcodeproj` gem を使って再現できるようにしてある（当時使ったスクリプトの要点）。

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')

flavors = %w[dev stg prod]
bases   = %w[Debug Release Profile]

# プロジェクトレベル / Runner ターゲット / RunnerTests ターゲットそれぞれの
# XCConfigurationList に対して、既存の Debug/Release/Profile を複製し
# 新しい名前（例: "Debug-dev"）を付ける。Runner ターゲット分だけ
# base_configuration_reference を対応する ios/Flutter/<name>.xcconfig に差し替え、
# PRODUCT_BUNDLE_IDENTIFIER を 'com.tekushare.app$(BUNDLE_ID_SUFFIX)' に上書きする。
```

Scheme は既存の `Runner.xcscheme` を複製し、`buildConfiguration="Debug"` 等の属性を
`buildConfiguration="Debug-dev"` のように置換するだけで作れる（XML なのでテキスト置換で十分）。

複製後は `cd ios && pod install` を必ず実行すること（flavor 分の
`Pods-Runner.<config>.xcconfig` が生成され、各 xcconfig から include されるため）。
