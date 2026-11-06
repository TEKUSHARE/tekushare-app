import 'package:flutter/foundation.dart';
import 'package:tekushare/domain/entities/contact.dart';
import 'package:tekushare/domain/entities/safety_alert_result.dart';
import 'package:tekushare/domain/repositories/safety_alert_repository.dart';
import 'package:tekushare/infrastructure/sms_service.dart';

/// 不活動が続いたときに、通知先・連携相手へ安否通知を送る
///
/// - 連携相手へのプッシュ通知：iOS・Android の両方で送る
/// - 通知先への SMS：[isSmsSupported] のとき（Android）だけ送る。
///   iOS はアプリから SMS を自動送信できず、メッセージアプリを開くだけになるため使わない
class SendSafetyAlert {
  const SendSafetyAlert({
    required SafetyAlertRepository safetyAlertRepository,
    required SmsService smsService,
    required this.isSmsSupported,
  })  : _safetyAlertRepository = safetyAlertRepository,
        _smsService = smsService;

  final SafetyAlertRepository _safetyAlertRepository;
  final SmsService _smsService;

  /// この端末で SMS を自動送信できるか
  final bool isSmsSupported;

  Future<SafetyAlertResult> call({
    required List<Contact> contacts,
    required String senderName,
  }) async {
    // プッシュは結果待ちに時間がかかるため、SMS と同時に送る
    final results = await Future.wait([
      _sendSms(contacts, senderName),
      _sendPush(),
    ]);
    return SafetyAlertResult(
      isSmsSent: results[0] as bool,
      pushSentCount: results[1] as int,
    );
  }

  Future<bool> _sendSms(List<Contact> contacts, String senderName) async {
    if (!isSmsSupported || contacts.isEmpty) return false;
    try {
      await _smsService.sendInactivityAlert(
        contacts: contacts,
        senderName: senderName,
      );
      return true;
    } catch (e) {
      // プッシュ側で届いている可能性があるため、ここでは失敗として結果に反映するだけにする
      debugPrint('安否通知の SMS 送信に失敗しました: $e');
      return false;
    }
  }

  Future<int> _sendPush() async {
    try {
      return await _safetyAlertRepository.requestAlert();
    } catch (e) {
      debugPrint('安否通知のプッシュ送信に失敗しました: $e');
      return 0;
    }
  }
}
