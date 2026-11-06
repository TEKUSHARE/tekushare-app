import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/screens/widgets/common/app_confirm_dialog.dart';

void main() {
  group('AppConfirmDialog', () {
    testWidgets('確認処理が例外を投げても処理中のまま固まらず、もう一度押せる', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppConfirmDialog(
              message: '消去しますか？',
              confirmLabel: '消去する',
              onConfirm: () async {
                calls++;
                throw Exception('failed');
              },
              onCancel: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('消去する'));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.text('消去する'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
