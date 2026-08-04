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
}
