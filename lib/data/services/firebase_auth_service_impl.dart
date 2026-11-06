import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class FirebaseAuthServiceImpl implements AuthService {
  FirebaseAuthServiceImpl(this._auth, this._firestore) {
    _auth.setLanguageCode('ja');
  }
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// アカウント連携で相手の表示名を引けるよう、Firestore側にも同期する。
  /// 付随的な処理なので失敗してもAuth側の成功を巻き込まない。
  Future<void> _syncUserDoc(String uid, String displayName) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      await _firestore.collection('users').doc(uid).set({
        'displayName': displayName,
        'updatedAt': Timestamp.now(),
        // 未設定のときだけデフォルト値を書き込む（既存の設定を上書きしない）
        if (data?['shareWantToGo'] == null) 'shareWantToGo': true,
        if (data?['shareVisited'] == null) 'shareVisited': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('users/$uid の同期に失敗しました: $e');
    }
  }

  @override
  Stream<AuthUser?> watchAuthState() {
    return _auth.userChanges().map((user) {
      if (user == null) return null;
      return AuthUser(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        emailVerified: user.emailVerified,
      );
    });
  }

  @override
  Future<void> registerWithEmail(
      String email, String displayName, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(displayName);
      await credential.user?.reload();
      final uid = credential.user?.uid;
      if (uid != null) await _syncUserDoc(uid, displayName);
      await credential.user?.sendEmailVerification();
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) return;
      await user.reload();
      final reloaded = _auth.currentUser;
      if (reloaded == null || !reloaded.emailVerified) {
        await _auth.signOut();
        throw const AuthException('email-not-verified');
      }
      final name = reloaded.displayName;
      if (name != null && name.isNotEmpty) {
        await _syncUserDoc(reloaded.uid, name);
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> setDisplayName(String name) async {
    try {
      await _auth.currentUser?.updateDisplayName(name);
      await _auth.currentUser?.reload();
      final uid = _auth.currentUser?.uid;
      if (uid != null) await _syncUserDoc(uid, name);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  /// このユーザーの FCM トークン登録を解除する。
  /// 別アカウントへ切り替えた端末に、前ユーザー宛ての通知が届き続けるのを防ぐ。
  /// 付随的な処理なので失敗してもサインアウト自体は妨げない。
  Future<void> _clearFcmToken(String uid) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('fcm')
          .delete();
    } catch (e) {
      debugPrint('FCMトークンの解除に失敗しました: $e');
    }
  }

  @override
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await _clearFcmToken(uid);
    await _auth.signOut();
  }

  @override
  Future<void> deleteUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // 最後のログインから時間が経っていると requires-recent-login になる。
      // 呼び出し側で再認証（reauthenticateWithPassword）へ誘導する
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthException('user-not-found');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final settings = ActionCodeSettings(
        url: 'https://tekushare.web.app',
        handleCodeInApp: true,
        androidPackageName: AppConfig.packageName,
        androidInstallApp: true,
        iOSBundleId: AppConfig.iosBundleId,
      );
      await _auth.sendPasswordResetEmail(
          email: email, actionCodeSettings: settings);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    try {
      final settings = ActionCodeSettings(
        url: 'https://tekushare.web.app',
        handleCodeInApp: true,
        androidPackageName: AppConfig.packageName,
        androidInstallApp: true,
        iOSBundleId: AppConfig.iosBundleId,
      );
      await _auth.currentUser?.sendEmailVerification(settings);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> applyEmailVerificationCode(String oobCode) async {
    try {
      await _auth.applyActionCode(oobCode);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> reloadCurrentUser() async {
    try {
      await _auth.currentUser?.reload();
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    try {
      return await _auth.verifyPasswordResetCode(code);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    try {
      await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.code);
    }
  }
}
