import 'package:shared_preferences/shared_preferences.dart';

/// Player-tunable HUD / touch-control layout, saved across sessions.
class UiLayoutSettings {
  UiLayoutSettings({
    this.uiScale = 1,
    this.hudTop = 12,
    this.classBarTop = 62,
    this.weaponBarBottom = 13,
    this.controlsBottom = 168,
    this.controlsSideInset = 15,
    this.controlsScale = 1,
    this.autoEquipNewWeapons = false,
  });

  double uiScale;
  double hudTop;
  double classBarTop;
  double weaponBarBottom;
  double controlsBottom;
  double controlsSideInset;
  double controlsScale;
  /// When true, unlocking or upgrading a gun from loot equips it immediately.
  bool autoEquipNewWeapons;

  static const uiScaleMin = 0.75;
  static const uiScaleMax = 1.4;
  static const controlsScaleMin = 0.7;
  static const controlsScaleMax = 1.5;

  UiLayoutSettings copy() => UiLayoutSettings(
        uiScale: uiScale,
        hudTop: hudTop,
        classBarTop: classBarTop,
        weaponBarBottom: weaponBarBottom,
        controlsBottom: controlsBottom,
        controlsSideInset: controlsSideInset,
        controlsScale: controlsScale,
        autoEquipNewWeapons: autoEquipNewWeapons,
      );

  void reset() {
    uiScale = 1;
    hudTop = 12;
    classBarTop = 62;
    weaponBarBottom = 13;
    controlsBottom = 168;
    controlsSideInset = 15;
    controlsScale = 1;
    autoEquipNewWeapons = false;
  }

  static const _prefix = 'survival_ui_';

  static Future<UiLayoutSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UiLayoutSettings(
      uiScale: prefs.getDouble('${_prefix}uiScale') ?? 1,
      hudTop: prefs.getDouble('${_prefix}hudTop') ?? 12,
      classBarTop: prefs.getDouble('${_prefix}classBarTop') ?? 62,
      weaponBarBottom: prefs.getDouble('${_prefix}weaponBarBottom') ?? 13,
      controlsBottom: prefs.getDouble('${_prefix}controlsBottom') ?? 168,
      controlsSideInset: prefs.getDouble('${_prefix}controlsSideInset') ?? 15,
      controlsScale: prefs.getDouble('${_prefix}controlsScale') ?? 1,
      autoEquipNewWeapons:
          prefs.getBool('${_prefix}autoEquipNewWeapons') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_prefix}uiScale', uiScale);
    await prefs.setDouble('${_prefix}hudTop', hudTop);
    await prefs.setDouble('${_prefix}classBarTop', classBarTop);
    await prefs.setDouble('${_prefix}weaponBarBottom', weaponBarBottom);
    await prefs.setDouble('${_prefix}controlsBottom', controlsBottom);
    await prefs.setDouble('${_prefix}controlsSideInset', controlsSideInset);
    await prefs.setDouble('${_prefix}controlsScale', controlsScale);
    await prefs.setBool('${_prefix}autoEquipNewWeapons', autoEquipNewWeapons);
  }
}
