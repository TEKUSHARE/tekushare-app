import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/data/repositories/firestore_safety_alert_repository_impl.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  FirestoreSafetyAlertRepositoryImpl repoFor(
    String? uid, {
    Duration resultTimeout = const Duration(seconds: 5),
  }) {
    final auth = MockFirebaseAuth(
      signedIn: uid != null,
      mockUser: MockUser(uid: uid ?? ''),
    );
    return FirestoreSafetyAlertRepositoryImpl(
      firestore,
      auth,
      resultTimeout: resultTimeout,
    );
  }

  /// Cloud Functions（onSafetyAlertRequested）の代わりに、
  /// 依頼が書き込まれたら結果を書き戻す
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> fakeFunction(
    String uid, {
    required int sentCount,
  }) {
    final ref = firestore.collection('safetyAlerts').doc(uid);
    return ref.snapshots().listen((snap) {
      final data = snap.data();
      final requestedAt = data?['requestedAt'];
      if (requestedAt == null) return;
      if (data?['result']?['requestedAt'] == requestedAt) return;
      ref.set({
        'result': {
          'requestedAt': requestedAt,
          'sentCount': sentCount,
          'failedCount': 0,
        },
      }, SetOptions(merge: true));
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('requestAlert', () {
    test('safetyAlerts/{uid} に依頼時刻を書き込み、サーバーの送信人数を返す', () async {
      final sub = fakeFunction('alice', sentCount: 2);
      addTearDown(sub.cancel);

      final sentCount = await repoFor('alice').requestAlert();

      expect(sentCount, 2);
      final doc = await firestore.collection('safetyAlerts').doc('alice').get();
      expect(doc.data()!['requestedAt'], isA<Timestamp>());
    });

    test('前回の依頼の結果は今回の結果として扱わない', () async {
      await firestore.collection('safetyAlerts').doc('alice').set({
        'requestedAt': Timestamp.fromMillisecondsSinceEpoch(0),
        'result': {
          'requestedAt': Timestamp.fromMillisecondsSinceEpoch(0),
          'sentCount': 5,
        },
      });
      final sub = fakeFunction('alice', sentCount: 1);
      addTearDown(sub.cancel);

      expect(await repoFor('alice').requestAlert(), 1);
    });

    test('サーバーから結果が返らなければタイムアウトで例外を投げる', () async {
      final repo = repoFor(
        'alice',
        resultTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(repo.requestAlert(), throwsA(isA<TimeoutException>()));
    });

    test('未ログインなら依頼を書き込まず例外を投げる', () async {
      await expectLater(
        repoFor(null).requestAlert(),
        throwsA(isA<StateError>()),
      );
      final snap = await firestore.collection('safetyAlerts').get();
      expect(snap.docs, isEmpty);
    });
  });
}
