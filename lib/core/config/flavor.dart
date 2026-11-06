/// アプリの実行環境（Flavor）
enum Flavor {
  /// 開発環境
  dev,

  /// テスト・ステージング環境
  stg,

  /// 本番（リリース）環境
  prod,
}

/// 実行中の環境に応じた設定値を提供する
///
/// エントリーポイント（main_dev / main_stg / main_prod）で
/// [AppConfig.flavor] を設定してから [runApp] を呼び出すこと
abstract class AppConfig {
  static Flavor _flavor = Flavor.dev;

  /// 現在の実行環境
  static Flavor get flavor => _flavor;

  /// エントリーポイントから一度だけ呼び出す
  static void setFlavor(Flavor flavor) {
    _flavor = flavor;
  }

  /// 画面に表示するアプリ名
  static String get appName {
    switch (_flavor) {
      case Flavor.dev:
        return 'TekuShare Dev';
      case Flavor.stg:
        return 'TekuShare Stg';
      case Flavor.prod:
        return 'TekuShare';
    }
  }

  /// Android パッケージ名
  static String get packageName {
    switch (_flavor) {
      case Flavor.dev:
        return 'com.tekushare.app.dev';
      case Flavor.stg:
        return 'com.tekushare.app.stg';
      case Flavor.prod:
        return 'com.tekushare.app';
    }
  }

  /// iOS Bundle ID
  static String get iosBundleId {
    switch (_flavor) {
      case Flavor.dev:
        return 'com.tekushare.app.dev';
      case Flavor.stg:
        return 'com.tekushare.app.stg';
      case Flavor.prod:
        return 'com.tekushare.app';
    }
  }

  /// dev環境かどうか
  static bool get isDev => _flavor == Flavor.dev;

  /// stg環境かどうか
  static bool get isStg => _flavor == Flavor.stg;

  /// prod環境かどうか
  static bool get isProd => _flavor == Flavor.prod;

  // TODO: Phase2でFirebaseの環境別プロジェクトIDなどを追加
  // static String get firebaseProjectId => switch (_flavor) { ... };
}
