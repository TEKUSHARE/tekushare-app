import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tekushare/infrastructure/recording_position_filter.dart';

Position _pos(double accuracy) => Position(
      latitude: 35,
      longitude: 139,
      timestamp: DateTime(2026),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('RecordingPositionFilter', () {
    late DateTime now;
    late RecordingPositionFilter filter;

    setUp(() {
      now = DateTime(2026, 11, 7, 10);
      filter = RecordingPositionFilter(now: () => now);
    });

    test('誤差30m以内の位置は常に採用する', () {
      expect(filter.accept(_pos(5)), isTrue);
      expect(filter.accept(_pos(30)), isTrue);
    });

    test('屋内や「正確な位置情報」オフのような誤差の大きい位置は採用しない', () {
      expect(filter.accept(_pos(65)), isFalse);
      expect(filter.accept(_pos(3000)), isFalse);
    });

    test('最初の位置は誤差50m以内なら採用する', () {
      expect(filter.accept(_pos(45)), isTrue);
    });

    test('採用から10秒以内は誤差30〜50mの位置を採用せず、10秒経ったら採用する', () {
      expect(filter.accept(_pos(10)), isTrue);

      now = now.add(const Duration(seconds: 5));
      expect(filter.accept(_pos(45)), isFalse);

      now = now.add(const Duration(seconds: 5));
      expect(filter.accept(_pos(45)), isTrue);
    });
  });
}
