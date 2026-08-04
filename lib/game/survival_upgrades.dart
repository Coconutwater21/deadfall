import 'dart:math' as math;

import 'survival_content.dart';

/// Shared upgrade caps and cost curves for survival progression.
abstract final class SurvivalUpgrades {
  static const int maxLevel = 5;

  static bool isMastered(int level) => level >= maxLevel;

  static int classMoneyCost(PlayerClass kind, int currentLevel) {
    final base = math.max(140, (kind.moneyCost * 0.95).round());
    return _scale(base == 0 ? 160 : base, currentLevel);
  }

  static int classKillCost(PlayerClass kind, int currentLevel) {
    final base = math.max(3, (kind.killCost * 0.22).round());
    return _scale(base == 0 ? 3 : base, currentLevel);
  }

  static int abilityMoneyCost(PlayerClass kind, int currentLevel) {
    return _scale((kind.abilityMoneyCost * 0.48).round(), currentLevel);
  }

  static int abilityKillCost(PlayerClass kind, int currentLevel) {
    return _scale((kind.abilityKillCost * 0.12).round(), currentLevel);
  }

  static int weaponMoneyCost(WeaponKind kind, int currentLevel) {
    final base = switch (kind.rarity) {
      WeaponRarity.common => 150,
      WeaponRarity.uncommon => 230,
      WeaponRarity.rare => 360,
      WeaponRarity.epic => 560,
      WeaponRarity.legendary => 780,
      WeaponRarity.mythic => 1050,
      WeaponRarity.ascendant => 1450,
    };
    return _scale(base, currentLevel);
  }

  static int weaponKillCost(WeaponKind kind, int currentLevel) {
    final base = switch (kind.rarity) {
      WeaponRarity.common => 4,
      WeaponRarity.uncommon => 6,
      WeaponRarity.rare => 9,
      WeaponRarity.epic => 12,
      WeaponRarity.legendary => 16,
      WeaponRarity.mythic => 20,
      WeaponRarity.ascendant => 26,
    };
    return _scale(base, currentLevel);
  }

  static int _scale(int base, int currentLevel) {
    final level = currentLevel.clamp(0, maxLevel);
    return (base * math.pow(1.45, level)).round();
  }

  static double classHealthMult(int level) => 1 + level * 0.1;
  static double classSpeedMult(int level) => 1 + level * 0.04;

  static double abilityCooldownMult(int level) =>
      math.max(0.55, 1 - level * 0.08);
  static double abilityPowerMult(int level) => 1 + level * 0.14;

  static double weaponDamageMult(int level) => 1 + level * 0.12;
  static int weaponMagBonus(int level) => level; // +1 round per level
  static double weaponReloadMult(int level) => math.max(0.6, 1 - level * 0.07);
  static double weaponCooldownMult(int level) => math.max(0.7, 1 - level * 0.05);

  /// Max-level class passive name.
  static String classMasteryName(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Second Wind',
        PlayerClass.scout => 'Afterimage',
        PlayerClass.tank => 'Bulwark Plate',
        PlayerClass.assault => 'Free Fire',
        PlayerClass.berserker => 'Frenzy',
        PlayerClass.reaper => 'Soul Reservoir',
        PlayerClass.demolitions => 'Bigger Booms',
        PlayerClass.ghost => 'Fade Reload',
        PlayerClass.juggernaut => 'Quake Step',
        PlayerClass.ranger => 'Through-Shot',
        PlayerClass.commander => 'Squad Lead',
      };

  static String classMasteryBlurb(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Kills heal you',
        PlayerClass.scout => 'Kills grant a speed burst',
        PlayerClass.tank => 'Take less damage',
        PlayerClass.assault => 'Shots can cost no ammo',
        PlayerClass.berserker => 'Low HP deals more damage',
        PlayerClass.reaper => 'Soul Bar fills faster and heals more',
        PlayerClass.demolitions => 'Explosions hit a wider area',
        PlayerClass.ghost => 'Reloading phases you briefly',
        PlayerClass.juggernaut => 'Periodic quake pulses',
        PlayerClass.ranger => 'Your gun always pierces',
        PlayerClass.commander => 'Helpers fire faster',
      };

  /// Max-level ability bonus name (extra effect on cast).
  static String abilityMasteryName(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Rally Pulse',
        PlayerClass.scout => 'Blade Dash',
        PlayerClass.tank => 'Reprise Slam',
        PlayerClass.assault => 'Hot Swap',
        PlayerClass.berserker => 'Blood Pact',
        PlayerClass.reaper => 'Reaper\'s Wake',
        PlayerClass.demolitions => 'Twin Charges',
        PlayerClass.ghost => 'Rift Slash',
        PlayerClass.juggernaut => 'Aftershock',
        PlayerClass.ranger => 'Frost Mark',
        PlayerClass.commander => 'Elite Rifles',
      };

  static String abilityMasteryBlurb(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Also pulses nearby damage',
        PlayerClass.scout => 'Dash cuts through enemies',
        PlayerClass.tank => 'Second shove also damages',
        PlayerClass.assault => 'Also reloads your mag',
        PlayerClass.berserker => 'Also heals on rage',
        PlayerClass.reaper => 'Longer scythe + opening cleave',
        PlayerClass.demolitions => 'Throws a second charge',
        PlayerClass.ghost => 'Phase path damages enemies',
        PlayerClass.juggernaut => 'A delayed second quake',
        PlayerClass.ranger => 'Beam chills every target',
        PlayerClass.commander => 'Helpers deal bonus damage',
      };

  /// Max-level weapon special name.
  static String weaponMasteryName(WeaponKind kind) {
    if (kind.explosionRadius > 0) return 'Blast Core';
    if (kind.ignites) return 'Inferno Tip';
    if (kind.appliesSlow) return 'Deep Freeze';
    if (kind.appliesVirus) return 'Plague Vector';
    if (kind.pierces) return 'Chain Pierce';
    return 'Master Strike';
  }

  static String weaponMasteryBlurb(WeaponKind kind) {
    if (kind.explosionRadius > 0) return 'Bigger blast radius';
    if (kind.ignites) return 'Kills leave fire pits';
    if (kind.appliesSlow) return 'Stronger, longer chill';
    if (kind.appliesVirus) return 'Longer, hungrier virus';
    if (kind.pierces) return 'Hits can chain nearby';
    return 'Chance to execute or splash';
  }
}
