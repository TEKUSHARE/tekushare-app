import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/domain/entities/contact.dart';
import 'package:tekushare/domain/repositories/safety_alert_repository.dart';
import 'package:tekushare/domain/usecases/walk/send_safety_alert.dart';
import 'package:tekushare/infrastructure/sms_service.dart';

class _FakeSafetyAlertRepository implements SafetyAlertRepository {
  _FakeSafetyAlertRepository({this.sentCount = 0, this.error});

  final int sentCount;
  final Object? error;
  int callCount = 0;

  @override
  Future<int> requestAlert() async {
    callCount++;
    if (error != null) throw error!;
    return sentCount;
  }
}

class _FakeSmsService implements SmsService {
  _FakeSmsService({this.error});

  final Object? error;
  int callCount = 0;

  @override
  Future<void> sendInactivityAlert({
    required List<Contact> contacts,
    required String senderName,
  }) async {
    callCount++;
    if (error != null) throw error!;
  }
}

const _contacts = [Contact(id: 'c1', name: '家族', phone: '09000000000')];

void main() {
  group('SendSafetyAlert', () {
    test('iOS（SMS 非対応）では SMS を送らず、プッシュだけを送る', () async {
      final repo = _FakeSafetyAlertRepository(sentCount: 2);
      final sms = _FakeSmsService();
      final usecase = SendSafetyAlert(
        safetyAlertRepository: repo,
        smsService: sms,
        isSmsSupported: false,
      );

      final result = await usecase(contacts: _contacts, senderName: 'A');

      expect(sms.callCount, 0);
      expect(repo.callCount, 1);
      expect(result.isSmsSent, isFalse);
      expect(result.pushSentCount, 2);
      expect(result.isDelivered, isTrue);
    });

    test('Android では SMS とプッシュの両方を送る', () async {
      final repo = _FakeSafetyAlertRepository(sentCount: 1);
      final sms = _FakeSmsService();
      final usecase = SendSafetyAlert(
        safetyAlertRepository: repo,
        smsService: sms,
        isSmsSupported: true,
      );

      final result = await usecase(contacts: _contacts, senderName: 'A');

      expect(sms.callCount, 1);
      expect(repo.callCount, 1);
      expect(result.isSmsSent, isTrue);
      expect(result.pushSentCount, 1);
    });

    test('Android でも通知先が未登録なら SMS は送らない', () async {
      final sms = _FakeSmsService();
      final usecase = SendSafetyAlert(
        safetyAlertRepository: _FakeSafetyAlertRepository(),
        smsService: sms,
        isSmsSupported: true,
      );

      final result = await usecase(contacts: const [], senderName: 'A');

      expect(sms.callCount, 0);
      expect(result.isSmsSent, isFalse);
    });

    test('プッシュが失敗しても SMS が届いていれば届いた扱いにする', () async {
      final usecase = SendSafetyAlert(
        safetyAlertRepository:
            _FakeSafetyAlertRepository(error: Exception('timeout')),
        smsService: _FakeSmsService(),
        isSmsSupported: true,
      );

      final result = await usecase(contacts: _contacts, senderName: 'A');

      expect(result.pushSentCount, 0);
      expect(result.isDelivered, isTrue);
    });

    test('SMS もプッシュも届かなければ届いていない扱いにする', () async {
      final usecase = SendSafetyAlert(
        safetyAlertRepository:
            _FakeSafetyAlertRepository(error: Exception('offline')),
        smsService: _FakeSmsService(error: Exception('no sms')),
        isSmsSupported: true,
      );

      final result = await usecase(contacts: _contacts, senderName: 'A');

      expect(result.isSmsSent, isFalse);
      expect(result.pushSentCount, 0);
      expect(result.isDelivered, isFalse);
    });

    test('連携相手がいない（送信 0 人）iOS では届いていない扱いにする', () async {
      final usecase = SendSafetyAlert(
        safetyAlertRepository: _FakeSafetyAlertRepository(sentCount: 0),
        smsService: _FakeSmsService(),
        isSmsSupported: false,
      );

      final result = await usecase(contacts: _contacts, senderName: 'A');

      expect(result.isDelivered, isFalse);
    });
  });
}
