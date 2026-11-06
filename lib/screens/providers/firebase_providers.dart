import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/domain/entities/app_update.dart';
import 'package:tekushare/screens/providers/app_update_provider.dart';
import 'package:tekushare/data/repositories/account_link_repository_impl.dart';
import 'package:tekushare/data/repositories/firestore_contact_repository_impl.dart';
import 'package:tekushare/data/repositories/firestore_photo_repository_impl.dart';
import 'package:tekushare/data/repositories/firestore_safety_alert_repository_impl.dart';
import 'package:tekushare/data/repositories/firestore_spot_repository_impl.dart';
import 'package:tekushare/data/repositories/firestore_walk_status_repository_impl.dart';
import 'package:tekushare/data/services/firebase_auth_service_impl.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/widgets/common/storage_photo.dart';

const _maxPhotoBytes = 10 * 1024 * 1024;

/// Firebase 実装を ProviderScope.overrides に渡すためのリスト。
/// main_*.dart の ProviderScope(overrides: firebaseProviderOverrides()) で使用する。
List<Override> firebaseProviderOverrides() => [
      installedBuildLoaderProvider.overrideWithValue(() async {
        final info = await PackageInfo.fromPlatform();
        return int.parse(info.buildNumber);
      }),
      appUpdateLoaderProvider.overrideWithValue(() async {
        if (kIsWeb ||
            (defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS)) {
          return null;
        }
        final platform =
            defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';
        final doc = await FirebaseFirestore.instance
            .collection('appUpdates')
            .doc('${AppConfig.flavor.name}_$platform')
            .get(const GetOptions(source: Source.server));
        final data = doc.data();
        return data == null ? null : AppUpdate.fromMap(data);
      }),
      // 写真は長期有効なダウンロードURLではなく、ログイン中のユーザー権限で取得する
      storagePhotoLoaderProvider.overrideWithValue(
        (path) => FirebaseStorage.instance.ref(path).getData(_maxPhotoBytes),
      ),
      authServiceProvider.overrideWithValue(
        FirebaseAuthServiceImpl(
          fb_auth.FirebaseAuth.instance,
          FirebaseFirestore.instance,
        ),
      ),
      spotRepositoryProvider.overrideWith((ref) {
        final uid = ref.watch(authStateProvider).value?.uid ?? '';
        return FirestoreSpotRepositoryImpl(FirebaseFirestore.instance, uid);
      }),
      photoRepositoryProvider.overrideWith((ref) {
        final uid = ref.watch(authStateProvider).value?.uid ?? '';
        return FirestorePhotoRepositoryImpl(
          FirebaseFirestore.instance,
          FirebaseStorage.instance,
          uid,
        );
      }),
      contactRepositoryProvider.overrideWith((ref) {
        final uid = ref.watch(authStateProvider).value?.uid ?? '';
        return FirestoreContactRepositoryImpl(FirebaseFirestore.instance, uid);
      }),
      accountLinkRepositoryProvider.overrideWith((_) {
        return AccountLinkRepositoryImpl(
          FirebaseFirestore.instance,
          fb_auth.FirebaseAuth.instance,
        );
      }),
      walkStatusRepositoryProvider.overrideWith((_) {
        return FirestoreWalkStatusRepositoryImpl(
          FirebaseFirestore.instance,
          fb_auth.FirebaseAuth.instance,
        );
      }),
      safetyAlertRepositoryProvider.overrideWith((_) {
        return FirestoreSafetyAlertRepositoryImpl(
          FirebaseFirestore.instance,
          fb_auth.FirebaseAuth.instance,
        );
      }),
    ];
