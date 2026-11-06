import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tekushare/app.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/domain/entities/contact.dart';
import 'package:tekushare/domain/entities/spot.dart';
import 'package:tekushare/domain/repositories/contact_repository.dart';
import 'package:tekushare/domain/repositories/photo_repository.dart';
import 'package:tekushare/domain/repositories/spot_repository.dart';
import 'package:tekushare/screens/pages/home/view/home_page.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';

class _FakeAuthService implements AuthService {
  @override
  Stream<AuthUser?> watchAuthState() => const Stream.empty();
  @override
  Future<void> registerWithEmail(
      String email, String displayName, String password) async {}
  @override
  Future<void> signInWithEmail(String email, String password) async {}
  @override
  Future<void> setDisplayName(String name) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteUser() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> reloadCurrentUser() async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async => '';

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {}

  @override
  Future<void> applyEmailVerificationCode(String oobCode) async {}
}

class _FakeSpotRepository implements SpotRepository {
  @override
  Future<void> saveSpot(Spot spot) async {}
  @override
  Stream<List<Spot>> getSpots() => Stream.value([]);
  @override
  Future<void> updateSpotStatus(String id, SpotStatus status) async {}
  @override
  Future<void> deleteSpot(String id) async {}
}

class _FakePhotoRepository implements PhotoRepository {
  @override
  Future<String> attachPhoto(String spotId, String imagePath) async =>
      imagePath;
  @override
  Future<void> removePhoto(String spotId, String imagePath) async {}
}

class _FakeContactRepository implements ContactRepository {
  @override
  Stream<List<Contact>> watchContacts() => Stream.value([]);
  @override
  Future<void> saveContact(Contact contact) async {}
  @override
  Future<void> deleteContact(String id) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConfig.setFlavor(Flavor.dev);
  });

  Future<void> launchApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthUser(uid: '', displayName: 'テストユーザー'),
            ),
          ),
          spotRepositoryProvider.overrideWithValue(_FakeSpotRepository()),
          photoRepositoryProvider.overrideWithValue(_FakePhotoRepository()),
          contactRepositoryProvider.overrideWithValue(_FakeContactRepository()),
        ],
        child: const TekuShareApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('app launch flow', () {
    testWidgets('launches app and shows home screen', (tester) async {
      await launchApp(tester);

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    testWidgets('navigates to list tab via bottom nav', (tester) async {
      await launchApp(tester);

      await tester.tap(find.text(AppStrings.navList));
      await tester.pumpAndSettle();

      expect(find.byType(SpotListPage), findsOneWidget);
    });
  });
}
