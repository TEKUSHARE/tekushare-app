/// 安否通知（不活動時の通知）を送った結果
class SafetyAlertResult {
  const SafetyAlertResult({
    required this.isSmsSent,
    required this.pushSentCount,
  });

  /// 通知先へ SMS を送信できたか（Android のみ）
  final bool isSmsSent;

  /// プッシュ通知を届けられた連携相手の人数
  final int pushSentCount;

  /// 誰か一人にでも知らせることができたか
  bool get isDelivered => isSmsSent || pushSentCount > 0;
}
