import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deadfall/game/ui_layout_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ui layout settings persist and reset', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = UiLayoutSettings(
      uiScale: 1.2,
      hudTop: 24,
      classBarTop: 90,
      weaponBarBottom: 20,
      controlsBottom: 200,
      controlsSideInset: 22,
      controlsScale: 1.1,
    );
    await settings.save();

    final loaded = await UiLayoutSettings.load();
    expect(loaded.uiScale, closeTo(1.2, 0.001));
    expect(loaded.hudTop, 24);
    expect(loaded.controlsScale, closeTo(1.1, 0.001));

    loaded.reset();
    expect(loaded.uiScale, 1);
    expect(loaded.hudTop, 12);
    expect(loaded.controlsBottom, 168);
  });

  test('compact density kicks in on narrow viewports', () {
    expect(UiLayoutSettings.isCompact(const Size(390, 844)), isTrue);
    expect(UiLayoutSettings.isCompact(const Size(1280, 800)), isFalse);
    expect(UiLayoutSettings.densityFor(const Size(390, 844)), closeTo(0.68, 0.001));
    expect(UiLayoutSettings.densityFor(const Size(1280, 800)), 1);
  });

  test('resetFor applies compact defaults on phones', () {
    final settings = UiLayoutSettings(
      uiScale: 1.3,
      hudTop: 40,
      classBarTop: 120,
      controlsBottom: 240,
    );
    settings.resetFor(const Size(390, 844));
    expect(settings.hudTop, 8);
    expect(settings.classBarTop, 40);
    expect(settings.controlsBottom, 96);
    expect(settings.uiScale, 1);

    settings.hudTop = 40;
    settings.resetFor(const Size(1280, 800));
    expect(settings.hudTop, 12);
    expect(settings.controlsBottom, 168);
  });
}
