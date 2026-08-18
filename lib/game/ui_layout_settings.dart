import 'dart:ui' show Size;

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
    this.musicEnabled = true,
    this.muted = false,
    this.musicVolume = 1,
    this.sfxVolume = 1,
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
  /// When false, background music is silenced (SFX still play).
  bool musicEnabled;
  bool muted;
  double musicVolume;
  double sfxVolume;

  static const uiScaleMin = 0.75;
  static const uiScaleMax = 1.6;
  static const controlsScaleMin = 0.7;
  static const controlsScaleMax = 1.8;

  /// Narrow phone / side-panel viewports need a denser HUD.
  static bool isCompact(Size size) =>
      size.width < 740 || size.shortestSide < 640;

  /// Soft density so phones start readable; player sliders still scale on top.
  static double densityFor(Size size) => isCompact(size) ? 0.68 : 1.0;

  /// Phone-friendly layout used by Reset on compact screens.
  void applyCompactDefaults() {
    uiScale = 1;
    hudTop = 8;
    classBarTop = 40;
    weaponBarBottom = 8;
    controlsBottom = 96;
    controlsSideInset = 10;
    controlsScale = 1;
  }

  UiLayoutSettings copy() => UiLayoutSettings(
        uiScale: uiScale,
        hudTop: hudTop,
        classBarTop: classBarTop,
        weaponBarBottom: weaponBarBottom,
        controlsBottom: controlsBottom,
        controlsSideInset: controlsSideInset,
        controlsScale: controlsScale,
        autoEquipNewWeapons: autoEquipNewWeapons,
        musicEnabled: musicEnabled,
        muted: muted,
        musicVolume: musicVolume,
        sfxVolume: sfxVolume,
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
    musicEnabled = true;
    muted = false;
    musicVolume = 1;
    sfxVolume = 1;
  }

  void resetFor(Size size) {
    reset();
    if (isCompact(size)) {
      applyCompactDefaults();
    }
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
      musicEnabled: prefs.getBool('${_prefix}musicEnabled') ?? true,
      muted: prefs.getBool('${_prefix}muted') ?? false,
      musicVolume: prefs.getDouble('${_prefix}musicVolume') ?? 1,
      sfxVolume: prefs.getDouble('${_prefix}sfxVolume') ?? 1,
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
    await prefs.setBool('${_prefix}musicEnabled', musicEnabled);
    await prefs.setBool('${_prefix}muted', muted);
    await prefs.setDouble('${_prefix}musicVolume', musicVolume);
    await prefs.setDouble('${_prefix}sfxVolume', sfxVolume);
  }
}
