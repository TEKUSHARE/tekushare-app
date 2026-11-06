/// 連携相手への安否通知（プッシュ通知）を扱うリポジトリ
///
/// 送信そのものはサーバー（Cloud Functions）が行う。iOS ではアプリから SMS を
/// 自動送信できないため、端末の OS に関係なく届く手段として使う。
abstract interface class SafetyAlertRepository {
  /// 安否通知の送信を依頼し、プッシュ通知を届けられた連携相手の人数を返す。
  /// 一定時間内にサーバーから結果が返らない場合は例外を投げる。
  Future<int> requestAlert();
}
