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
        PlayerClass.survivor => 'Phoenix Protocol',
        PlayerClass.scout => 'Phantom Stride',
        PlayerClass.tank => 'Adamant Aegis',
        PlayerClass.assault => 'Bottomless Mag',
        PlayerClass.berserker => 'Blood Sovereign',
        PlayerClass.reaper => 'Soul Tyrant',
        PlayerClass.demolitions => 'Cataclysm',
        PlayerClass.ghost => 'Living Shadow',
        PlayerClass.juggernaut => 'Earthquake Heart',
        PlayerClass.ranger => 'Deadeye Pierce',
        PlayerClass.commander => 'War Marshal',
      };

  static String classMasteryBlurb(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor =>
            'Kills restore a huge chunk of HP (can overheal)',
        PlayerClass.scout =>
            'Kills grant a long speed surge + brief invulnerability',
        PlayerClass.tank => 'Take half damage and pulse back when hit',
        PlayerClass.assault => 'Most shots cost no ammo',
        PlayerClass.berserker => 'Below 60% HP deal double damage',
        PlayerClass.reaper => 'Souls fill faster; surges heal a bit more',
        PlayerClass.demolitions => 'Explosions become enormous',
        PlayerClass.ghost => 'Reloading phases you for a long window',
        PlayerClass.juggernaut => 'Frequent devastating quake pulses',
        PlayerClass.ranger => 'Always pierces and deals bonus damage',
        PlayerClass.commander => 'Gunline fires extremely fast',
      };

  /// Max-level ability bonus name (extra effect on cast).
  static String abilityMasteryName(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Nova Rally',
        PlayerClass.scout => 'Guillotine Dash',
        PlayerClass.tank => 'Seismic Reprise',
        PlayerClass.assault => 'Full Auto Reset',
        PlayerClass.berserker => 'Crimson Ascension',
        PlayerClass.reaper => 'Harvest Apocalypse',
        PlayerClass.demolitions => 'Triple Payload',
        PlayerClass.ghost => 'Rift Guillotine',
        PlayerClass.juggernaut => 'Tectonic Aftershock',
        PlayerClass.ranger => 'Glacial Erasure',
        PlayerClass.commander => 'Death Squad',
      };

  static String abilityMasteryBlurb(PlayerClass kind) => switch (kind) {
        PlayerClass.survivor => 'Huge heal + massive damage nova',
        PlayerClass.scout => 'Dash obliterates everything in the path',
        PlayerClass.tank => 'Both shoves deal heavy damage',
        PlayerClass.assault => 'Full reload + longer overdrive',
        PlayerClass.berserker => 'Huge heal and stronger rage',
        PlayerClass.reaper => 'Longer scythe + opening wipe cleave',
        PlayerClass.demolitions => 'Three overlapping satchel blasts',
        PlayerClass.ghost => 'Phase path deals lethal damage',
        PlayerClass.juggernaut => 'Delayed second quake nearly as strong',
        PlayerClass.ranger => 'Beam freezes and shreds every target',
        PlayerClass.commander => 'Five elite gunners with huge HP',
      };

  /// Max-level weapon special — keyed off the arsenal symbol / mastery family.
  static String weaponMasteryName(WeaponKind kind) =>
      switch (kind.mastery) {
        WeaponMastery.ricochet => 'Ricochet Sovereign',
        WeaponMastery.storm => 'Bullet Storm',
        WeaponMastery.creed => 'Killshot Creed',
        WeaponMastery.shotgun => 'Point-Blank Tyrant',
        WeaponMastery.rail => 'Rail Judgment',
        WeaponMastery.brand => 'Hunter\'s Brand',
        WeaponMastery.inferno => 'Eternal Inferno',
        WeaponMastery.launcher => 'Apocalypse Core',
        WeaponMastery.overheat => 'Overheat Fury',
        WeaponMastery.beam => 'Prism Cascade',
        WeaponMastery.exotic => 'Reality Fracture',
      };

  static String weaponMasteryBlurb(WeaponKind kind) =>
      switch (kind.mastery) {
        WeaponMastery.ricochet =>
            'Shots ricochet to nearby foes and execute the wounded',
        WeaponMastery.storm =>
            'Free bullets + kill-triggered fire-rate frenzy',
        WeaponMastery.creed =>
            'Frequent critical hits and low-HP executions',
        WeaponMastery.shotgun =>
            'Close range deals crushing bonus damage + knockback',
        WeaponMastery.rail =>
            'Always pierces; hits detonate past the target',
        WeaponMastery.brand =>
            'Marks prey for massive bonus damage',
        WeaponMastery.inferno =>
            'Infernal burns and huge fire pits on kill',
        WeaponMastery.launcher =>
            'Gigantic blasts with delayed cluster bombs',
        WeaponMastery.overheat =>
            'Heat builds into piercing mega-damage',
        WeaponMastery.beam =>
            'Chains across multiple enemies and chills them',
        WeaponMastery.exotic =>
            'Random void pull, execute, or nova on hit',
      };
}
