import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/infrastructure/fcm_token_registrar.dart';

void main() {
  group('FcmTokenRegistrar', () {
    late List<String?> tokens;
    late List<Object?> saveErrors;
    late List<(String, String)> saved;

    FcmTokenRegistrar make({
      List<Duration> retryDelays = const [
        Duration(milliseconds: 20),
        Duration(milliseconds: 40),
      ],
    }) {
      return FcmTokenRegistrar(
        getToken: () async {
          final token = tokens.isEmpty ? 'token' : tokens.removeAt(0);
          if (token == 'throw') throw Exception('apns-token-not-set');
          return token;
        },
        saveToken: (uid, token) async {
          final error = saveErrors.isEmpty ? null : saveErrors.removeAt(0);
          if (error != null) throw error;
          saved.add((uid, token));
        },
        retryDelays: retryDelays,
      );
    }

    setUp(() {
      tokens = [];
      saveErrors = [];
      saved = [];
    });

    test('保存に成功したら登録済みになり、同じユーザーでは保存し直さない', () async {
      final registrar = make();

      await registrar.register('alice');
      await registrar.register('alice');

      expect(saved, [('alice', 'token')]);
      expect(registrar.isRegisteredFor('alice'), isTrue);
    });

    test('保存に失敗したら登録済みにせず、同じログイン中でも再度保存できる', () async {
      saveErrors = [Exception('offline')];
      final registrar = make(retryDelays: const []);

      await registrar.register('alice');
      expect(registrar.isRegisteredFor('alice'), isFalse);

      await registrar.register('alice');
      expect(saved, [('alice', 'token')]);
      expect(registrar.isRegisteredFor('alice'), isTrue);
    });

    Future<void> wait(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('トークン取得に失敗したら間隔を空けて自動で再試行する', () async {
      tokens = ['throw', 'throw', 'token'];
      final registrar = make();

      await registrar.register('alice');
      expect(saved, isEmpty);

      await wait(30);
      expect(saved, isEmpty);

      await wait(150);
      expect(saved, [('alice', 'token')]);
      expect(registrar.isRegisteredFor('alice'), isTrue);
    });

    test('トークンが null のときも失敗として再試行する', () async {
      tokens = [null, 'token'];
      final registrar = make();

      await registrar.register('alice');
      expect(registrar.isRegisteredFor('alice'), isFalse);

      await wait(100);
      expect(saved, [('alice', 'token')]);
    });

    test('再試行を使い切っても retryNow で改めて保存できる', () async {
      tokens = ['throw', 'throw', 'throw', 'token'];
      final registrar = make();

      await registrar.register('alice');
      await wait(200);
      expect(saved, isEmpty);

      await registrar.retryNow('alice');
      expect(saved, [('alice', 'token')]);
    });

    test('保存の途中でサインアウトされたら登録済みにせず、再ログインで保存し直す', () async {
      final saving = Completer<void>();
      final registrar = FcmTokenRegistrar(
        getToken: () async => 'token',
        saveToken: (uid, token) async {
          if (!saving.isCompleted) await saving.future;
          saved.add((uid, token));
        },
      );

      final first = registrar.register('alice');
      await Future<void>.delayed(Duration.zero);
      registrar.reset(); // 保存の完了前にサインアウト
      saving.complete();
      await first;

      expect(registrar.isRegisteredFor('alice'), isFalse);

      await registrar.register('alice'); // 同じユーザーで再ログイン
      expect(registrar.isRegisteredFor('alice'), isTrue);
      expect(saved.length, 2); // 再ログインでも保存し直している
    });

    test('サインアウト（reset）で再試行を止める', () async {
      tokens = ['throw', 'token'];
      final registrar = make();

      await registrar.register('alice');
      registrar.reset();
      await wait(100);

      expect(saved, isEmpty);
    });

    test('トークン更新（markStale）後は同じユーザーでも保存し直す', () async {
      final registrar = make();

      await registrar.register('alice');
      registrar.markStale();
      await registrar.register('alice');

      expect(saved.length, 2);
    });
  });
}
