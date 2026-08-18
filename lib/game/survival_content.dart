import 'dart:math' as math;
import 'dart:ui';

export 'weapon_catalog.dart';

enum CrateLootKind { money, health, weapon }

enum PlayerClass {
  survivor,
  scout,
  tank,
  assault,
  berserker,
  reaper,
  demolitions,
  ghost,
  juggernaut,
  ranger,
  commander,
}

extension PlayerClassStats on PlayerClass {
  String get label => switch (this) {
        PlayerClass.survivor => 'Survivor',
        PlayerClass.scout => 'Scout',
        PlayerClass.tank => 'Vanguard',
        PlayerClass.assault => 'Assault',
        PlayerClass.berserker => 'Berserker',
        PlayerClass.reaper => 'Reaper',
        PlayerClass.demolitions => 'Demo',
        PlayerClass.ghost => 'Ghost',
        PlayerClass.juggernaut => 'Juggernaut',
        PlayerClass.ranger => 'Ranger',
        PlayerClass.commander => 'Commander',
      };

  String get blurb => switch (this) {
        PlayerClass.survivor => 'Balanced starter',
        PlayerClass.scout => 'Fast, fragile',
        PlayerClass.tank => 'Fast bruiser',
        PlayerClass.assault => 'Frontline fighter',
        PlayerClass.berserker => 'Glass cannon speed',
        PlayerClass.reaper => 'Soul harvest fighter',
        PlayerClass.demolitions => 'Close-range power',
        PlayerClass.ghost => 'Elusive speedster',
        PlayerClass.juggernaut => 'Walking fortress',
        PlayerClass.ranger => 'Mid-range hunter',
        PlayerClass.commander => 'Summons gunners',
      };

  String get description => switch (this) {
        PlayerClass.survivor =>
          'Jack-of-all-trades. Steady HP and speed for learning the arena.',
        PlayerClass.scout =>
          'Highest mobility. Hit and run, but one mistake hurts a lot.',
        PlayerClass.tank =>
          'Expensive frontliner. Solid speed and a knockback-invuln bash.',
        PlayerClass.assault =>
          'Above-average HP and solid pace. Built for mid-range fights.',
        PlayerClass.berserker =>
          'Near-scout speed with better HP than Scout. Aggressive skirmisher.',
        PlayerClass.reaper =>
          'Damage fills a Soul Bar that drains over time. Full bars heal a flat amount (scales with Reaper level, can overheal); ability summons a massive scythe.',
        PlayerClass.demolitions =>
          'Sturdy and deliberate. Best when fighting up close to packs.',
        PlayerClass.ghost =>
          'Fastest class. Trade armor for pure repositioning speed.',
        PlayerClass.juggernaut =>
          'Massive HP, glacial movement. Anchor the center of the map.',
        PlayerClass.ranger =>
          'Balanced hunter stats. Comfortable kiting across open ground.',
        PlayerClass.commander =>
          'Very expensive warlord. Summons armed helpers that gun down the horde.',
      };

  int get maxHealth => switch (this) {
        PlayerClass.survivor => 100,
        PlayerClass.scout => 70,
        PlayerClass.tank => 145,
        PlayerClass.assault => 120,
        PlayerClass.berserker => 85,
        PlayerClass.reaper => 100,
        PlayerClass.demolitions => 130,
        PlayerClass.ghost => 60,
        PlayerClass.juggernaut => 200,
        PlayerClass.ranger => 110,
        PlayerClass.commander => 125,
      };

  double get moveSpeed => switch (this) {
        PlayerClass.survivor => 0.95,
        PlayerClass.scout => 1.35,
        PlayerClass.tank => 1.18,
        PlayerClass.assault => 1.05,
        PlayerClass.berserker => 1.28,
        PlayerClass.reaper => 0.98,
        PlayerClass.demolitions => 0.88,
        PlayerClass.ghost => 1.48,
        PlayerClass.juggernaut => 0.55,
        PlayerClass.ranger => 1.12,
        PlayerClass.commander => 0.98,
      };

  Color get color => switch (this) {
        PlayerClass.survivor => const Color(0xFF80CBC4),
        PlayerClass.scout => const Color(0xFF81D4FA),
        PlayerClass.tank => const Color(0xFFFFA726),
        PlayerClass.assault => const Color(0xFFEF9A9A),
        PlayerClass.berserker => const Color(0xFFCE93D8),
        PlayerClass.reaper => const Color(0xFFB388FF),
        PlayerClass.demolitions => const Color(0xFFFFAB91),
        PlayerClass.ghost => const Color(0xFFB0BEC5),
        PlayerClass.juggernaut => const Color(0xFFFFCC80),
        PlayerClass.ranger => const Color(0xFF80CBC4),
        PlayerClass.commander => const Color(0xFFFFD54F),
      };

  int get moneyCost => switch (this) {
        PlayerClass.survivor => 0,
        PlayerClass.scout => 200,
        PlayerClass.tank => 680,
        PlayerClass.assault => 320,
        PlayerClass.berserker => 450,
        PlayerClass.reaper => 700,
        PlayerClass.demolitions => 390,
        PlayerClass.ghost => 480,
        PlayerClass.juggernaut => 560,
        PlayerClass.ranger => 420,
        PlayerClass.commander => 840,
      };

  int get killCost => switch (this) {
        PlayerClass.survivor => 0,
        PlayerClass.scout => 4,
        PlayerClass.tank => 16,
        PlayerClass.assault => 7,
        PlayerClass.berserker => 10,
        PlayerClass.reaper => 99,
        PlayerClass.demolitions => 8,
        PlayerClass.ghost => 11,
        PlayerClass.juggernaut => 12,
        PlayerClass.ranger => 9,
        PlayerClass.commander => 20,
      };

  String get abilityName => switch (this) {
        PlayerClass.survivor => 'Adrenaline',
        PlayerClass.scout => 'Dash',
        PlayerClass.tank => 'Shock Bash',
        PlayerClass.assault => 'Overdrive',
        PlayerClass.berserker => 'Blood Rage',
        PlayerClass.reaper => 'Soul Scythe',
        PlayerClass.demolitions => 'Satchel',
        PlayerClass.ghost => 'Phase Shift',
        PlayerClass.juggernaut => 'Shockwave',
        PlayerClass.ranger => 'Marked Shot',
        PlayerClass.commander => 'Gunline',
      };

  String get abilityDescription => switch (this) {
        PlayerClass.survivor => 'Brief speed surge and a small heal.',
        PlayerClass.scout => 'Dash hard in your aim direction.',
        PlayerClass.tank => 'Shove foes, gain invulnerability, then shove again.',
        PlayerClass.assault => 'Massively boost fire rate for a short burst.',
        PlayerClass.berserker => 'Huge damage and speed for a few seconds.',
        PlayerClass.reaper =>
          'Melee scythe swings that cleave up close and fill the Soul Bar fast.',
        PlayerClass.demolitions => 'Detonate a satchel blast at your aim point.',
        PlayerClass.ghost => 'Phase dash with brief invulnerability.',
        PlayerClass.juggernaut => 'Shockwave that damages nearby zombies.',
        PlayerClass.ranger => 'Fire a piercing marked shot for massive damage.',
        PlayerClass.commander => 'Summon gunner helpers with heavy rifles.',
      };

  /// Far more expensive than class unlocks.
  int get abilityMoneyCost => switch (this) {
        PlayerClass.survivor => 2600,
        PlayerClass.scout => 3100,
        PlayerClass.tank => 5800,
        PlayerClass.assault => 3900,
        PlayerClass.berserker => 4400,
        PlayerClass.reaper => 3900,
        PlayerClass.demolitions => 4200,
        PlayerClass.ghost => 4800,
        PlayerClass.juggernaut => 5500,
        PlayerClass.ranger => 4000,
        PlayerClass.commander => 3900,
      };

  int get abilityKillCost => switch (this) {
        PlayerClass.survivor => 40,
        PlayerClass.scout => 45,
        PlayerClass.tank => 75,
        PlayerClass.assault => 55,
        PlayerClass.berserker => 60,
        PlayerClass.reaper => 520,
        PlayerClass.demolitions => 55,
        PlayerClass.ghost => 65,
        PlayerClass.juggernaut => 70,
        PlayerClass.ranger => 55,
        PlayerClass.commander => 50,
      };

  double get abilityCooldown => switch (this) {
        PlayerClass.survivor => 10,
        PlayerClass.scout => 6,
        PlayerClass.tank => 12,
        PlayerClass.assault => 12,
        PlayerClass.berserker => 13,
        PlayerClass.reaper => 16,
        PlayerClass.demolitions => 11,
        PlayerClass.ghost => 9,
        PlayerClass.juggernaut => 12,
        PlayerClass.ranger => 10,
        PlayerClass.commander => 18,
      };
}

enum ZombieKind {
  walker,
  runner,
  brute,
  spitter,
  skyCaller,
  necromancer,
  exploder,
  screamer,
  bloater,
  stalker,
  jumper,
  wraith,
  hiveMother,
  acidBomber,
  shieldBearer,
  frostbite,
  // New regulars
  swarmling,
  globling,
  boneGolem,
  hammerMauler,
  plagueDoctor,
  pyrofiend,
  riftWalker,
  hasteMage,
  // Ranged specialists
  knifeThrower,
  knifeFanatic,
  sharpshooter,
  scatterGunner,
  emberCaster,
  iceLancer,
  hexWitch,
  railSniper,
  harpooner,
  boltSlinger,
  toxinDart,
  zapper,
  /// Fires a small, weakly-homing missile that dies on solids, impact, or firer death.
  missileer,
  // Mini-bosses (every 5 waves, not multiples of 10)
  siegeBehemoth,
  broodQueen,
  ironColossus,
  /// Waves 11–12, then packs of 2+ from wave 15 every 5 waves.
  laserOverseer,
  /// Mid-range cluster fireballs; rare self-nova that splits twice.
  blazeburst,
  // Bosses (every 10 waves)
  dreadlord,
  citadelTower,
  apocalypseLord,
  /// Wave 20+ (every 20): katana teleport assassin.
  shadowRonin,
  /// Wave 21 and every 25: strongest apex threat.
  voidSovereign,
}

extension ZombieKindStats on ZombieKind {
  String get label => switch (this) {
        ZombieKind.walker => 'Walker',
        ZombieKind.runner => 'Runner',
        ZombieKind.brute => 'Brute',
        ZombieKind.spitter => 'Spitter',
        ZombieKind.skyCaller => 'Sky Caller',
        ZombieKind.necromancer => 'Necromancer',
        ZombieKind.exploder => 'Exploder',
        ZombieKind.screamer => 'Screamer',
        ZombieKind.bloater => 'Bloater',
        ZombieKind.stalker => 'Stalker',
        ZombieKind.jumper => 'Jumper',
        ZombieKind.wraith => 'Wraith',
        ZombieKind.hiveMother => 'Hive Mother',
        ZombieKind.acidBomber => 'Acid Bomber',
        ZombieKind.shieldBearer => 'Shield Bearer',
        ZombieKind.frostbite => 'Frostbite',
        ZombieKind.swarmling => 'Swarmling',
        ZombieKind.globling => 'Globling',
        ZombieKind.boneGolem => 'Bone Golem',
        ZombieKind.hammerMauler => 'Hammer Mauler',
        ZombieKind.plagueDoctor => 'Plague Doc',
        ZombieKind.pyrofiend => 'Pyrofiend',
        ZombieKind.riftWalker => 'Rift Walker',
        ZombieKind.hasteMage => 'Haste Mage',
        ZombieKind.knifeThrower => 'Knife Thrower',
        ZombieKind.knifeFanatic => 'Knife Fanatic',
        ZombieKind.sharpshooter => 'Sharpshooter',
        ZombieKind.scatterGunner => 'Scatter Gunner',
        ZombieKind.emberCaster => 'Ember Caster',
        ZombieKind.iceLancer => 'Ice Lancer',
        ZombieKind.hexWitch => 'Hex Witch',
        ZombieKind.railSniper => 'Rail Sniper',
        ZombieKind.harpooner => 'Harpooner',
        ZombieKind.boltSlinger => 'Bolt Slinger',
        ZombieKind.toxinDart => 'Toxin Dart',
        ZombieKind.zapper => 'Zapper',
        ZombieKind.missileer => 'Missileer',
        ZombieKind.siegeBehemoth => 'Siege Behemoth',
        ZombieKind.broodQueen => 'Brood Queen',
        ZombieKind.ironColossus => 'Iron Colossus',
        ZombieKind.laserOverseer => 'Laser Overseer',
        ZombieKind.blazeburst => 'Blazeburst',
        ZombieKind.dreadlord => 'Dreadlord',
        ZombieKind.citadelTower => 'Citadel Tower',
        ZombieKind.apocalypseLord => 'Apocalypse Lord',
        ZombieKind.shadowRonin => 'Shadow Ronin',
        ZombieKind.voidSovereign => 'Void Sovereign',
      };

  Color get color => switch (this) {
        ZombieKind.walker => const Color(0xFF668B52),
        ZombieKind.runner => const Color(0xFF9CCC65),
        ZombieKind.brute => const Color(0xFF8E3B31),
        ZombieKind.spitter => const Color(0xFF8BC34A),
        ZombieKind.skyCaller => const Color(0xFF7E57C2),
        ZombieKind.necromancer => const Color(0xFF5E35B1),
        ZombieKind.exploder => const Color(0xFFFF7043),
        ZombieKind.screamer => const Color(0xFFFFCA28),
        ZombieKind.bloater => const Color(0xFF6D4C41),
        ZombieKind.stalker => const Color(0xFF455A64),
        ZombieKind.jumper => const Color(0xFF26A69A),
        ZombieKind.wraith => const Color(0xFF90A4AE),
        ZombieKind.hiveMother => const Color(0xFF8D6E63),
        ZombieKind.acidBomber => const Color(0xFFCDDC39),
        ZombieKind.shieldBearer => const Color(0xFF78909C),
        ZombieKind.frostbite => const Color(0xFF4FC3F7),
        ZombieKind.swarmling => const Color(0xFFC5E1A5),
        ZombieKind.globling => const Color(0xFF76FF03),
        ZombieKind.boneGolem => const Color(0xFFECEFF1),
        ZombieKind.hammerMauler => const Color(0xFFA1887F),
        ZombieKind.plagueDoctor => const Color(0xFF9CCC65),
        ZombieKind.pyrofiend => const Color(0xFFFF6D00),
        ZombieKind.riftWalker => const Color(0xFFB388FF),
        ZombieKind.hasteMage => const Color(0xFF00E5FF),
        ZombieKind.knifeThrower => const Color(0xFF90A4AE),
        ZombieKind.knifeFanatic => const Color(0xFFFF8A65),
        ZombieKind.sharpshooter => const Color(0xFF5D4037),
        ZombieKind.scatterGunner => const Color(0xFF8D6E63),
        ZombieKind.emberCaster => const Color(0xFFFF5722),
        ZombieKind.iceLancer => const Color(0xFF29B6F6),
        ZombieKind.hexWitch => const Color(0xFFAB47BC),
        ZombieKind.railSniper => const Color(0xFF26C6DA),
        ZombieKind.harpooner => const Color(0xFF78909C),
        ZombieKind.boltSlinger => const Color(0xFFA1887F),
        ZombieKind.toxinDart => const Color(0xFF9CCC65),
        ZombieKind.zapper => const Color(0xFFFFEE58),
        ZombieKind.missileer => const Color(0xFFFF8F00),
        ZombieKind.siegeBehemoth => const Color(0xFFBF360C),
        ZombieKind.broodQueen => const Color(0xFFAD1457),
        ZombieKind.ironColossus => const Color(0xFF546E7A),
        ZombieKind.laserOverseer => const Color(0xFFFF00E5),
        ZombieKind.blazeburst => const Color(0xFFFF6D00),
        ZombieKind.dreadlord => const Color(0xFF6A1B9A),
        ZombieKind.citadelTower => const Color(0xFFFF1744),
        ZombieKind.apocalypseLord => const Color(0xFFD50000),
        ZombieKind.shadowRonin => const Color(0xFF1A237E),
        ZombieKind.voidSovereign => const Color(0xFFEA80FC),
      };

  Color get darkColor => Color.lerp(color, const Color(0xFF000000), 0.55)!;

  bool get isMiniBoss =>
      this == ZombieKind.siegeBehemoth ||
      this == ZombieKind.broodQueen ||
      this == ZombieKind.ironColossus ||
      this == ZombieKind.laserOverseer ||
      this == ZombieKind.blazeburst;

  bool get isBoss =>
      this == ZombieKind.dreadlord ||
      this == ZombieKind.citadelTower ||
      this == ZombieKind.apocalypseLord ||
      this == ZombieKind.shadowRonin ||
      this == ZombieKind.voidSovereign;

  bool get isImmobile => this == ZombieKind.citadelTower;

  double baseHp(int wave) {
    final core = switch (this) {
      ZombieKind.walker => 58.0,
      ZombieKind.runner => 38.0,
      ZombieKind.brute => 145.0,
      ZombieKind.spitter => 52.0,
      ZombieKind.skyCaller => 70.0,
      ZombieKind.necromancer => 85.0,
      ZombieKind.exploder => 44.0,
      ZombieKind.screamer => 48.0,
      ZombieKind.bloater => 190.0,
      ZombieKind.stalker => 32.0,
      ZombieKind.jumper => 50.0,
      ZombieKind.wraith => 40.0,
      ZombieKind.hiveMother => 120.0,
      ZombieKind.acidBomber => 55.0,
      ZombieKind.shieldBearer => 110.0,
      ZombieKind.frostbite => 65.0,
      ZombieKind.swarmling => 22.0,
      ZombieKind.globling => 26.0,
      ZombieKind.boneGolem => 210.0,
      ZombieKind.hammerMauler => 150.0,
      ZombieKind.plagueDoctor => 75.0,
      ZombieKind.pyrofiend => 68.0,
      ZombieKind.riftWalker => 55.0,
      ZombieKind.hasteMage => 95.0,
      ZombieKind.knifeThrower => 62.0,
      ZombieKind.knifeFanatic => 118.0,
      ZombieKind.sharpshooter => 70.0,
      ZombieKind.scatterGunner => 80.0,
      ZombieKind.emberCaster => 72.0,
      ZombieKind.iceLancer => 68.0,
      ZombieKind.hexWitch => 78.0,
      ZombieKind.railSniper => 58.0,
      ZombieKind.harpooner => 88.0,
      ZombieKind.boltSlinger => 64.0,
      ZombieKind.toxinDart => 60.0,
      ZombieKind.zapper => 74.0,
      ZombieKind.missileer => 82.0,
      ZombieKind.siegeBehemoth => 520.0,
      ZombieKind.broodQueen => 480.0,
      ZombieKind.ironColossus => 620.0,
      ZombieKind.laserOverseer => 540.0,
      ZombieKind.blazeburst => 510.0,
      ZombieKind.dreadlord => 980.0,
      ZombieKind.citadelTower => 1500.0,
      ZombieKind.apocalypseLord => 1750.0,
      ZombieKind.shadowRonin => 2100.0,
      ZombieKind.voidSovereign => 3200.0,
    };
    final scale = isBoss || isMiniBoss ? (1 + wave * 0.18) : (1 + wave * 0.13);
    return core * scale;
  }

  double baseSpeed(int wave) {
    final core = switch (this) {
      ZombieKind.walker => 0.20,
      ZombieKind.runner => 0.38,
      ZombieKind.brute => 0.13,
      ZombieKind.spitter => 0.16,
      ZombieKind.skyCaller => 0.15,
      ZombieKind.necromancer => 0.14,
      ZombieKind.exploder => 0.29,
      ZombieKind.screamer => 0.18,
      ZombieKind.bloater => 0.10,
      ZombieKind.stalker => 0.44,
      ZombieKind.jumper => 0.22,
      ZombieKind.wraith => 0.33,
      ZombieKind.hiveMother => 0.12,
      ZombieKind.acidBomber => 0.21,
      ZombieKind.shieldBearer => 0.14,
      ZombieKind.frostbite => 0.17,
      ZombieKind.swarmling => 0.48,
      ZombieKind.globling => 0.36,
      ZombieKind.boneGolem => 0.09,
      ZombieKind.hammerMauler => 0.14,
      ZombieKind.plagueDoctor => 0.15,
      ZombieKind.pyrofiend => 0.19,
      ZombieKind.riftWalker => 0.28,
      ZombieKind.hasteMage => 0.14,
      ZombieKind.knifeThrower => 0.17,
      ZombieKind.knifeFanatic => 0.30,
      ZombieKind.sharpshooter => 0.13,
      ZombieKind.scatterGunner => 0.18,
      ZombieKind.emberCaster => 0.15,
      ZombieKind.iceLancer => 0.16,
      ZombieKind.hexWitch => 0.14,
      ZombieKind.railSniper => 0.12,
      ZombieKind.harpooner => 0.15,
      ZombieKind.boltSlinger => 0.19,
      ZombieKind.toxinDart => 0.20,
      ZombieKind.zapper => 0.16,
      ZombieKind.missileer => 0.14,
      ZombieKind.siegeBehemoth => 0.11,
      ZombieKind.broodQueen => 0.22,
      ZombieKind.ironColossus => 0.08,
      ZombieKind.laserOverseer => 0.12,
      ZombieKind.blazeburst => 0.13,
      ZombieKind.dreadlord => 0.16,
      ZombieKind.citadelTower => 0.0,
      ZombieKind.apocalypseLord => 0.18,
      ZombieKind.shadowRonin => 0.62,
      ZombieKind.voidSovereign => 0.48,
    };
    if (isImmobile) return 0;
    return core + math.min(wave * 0.0035, 0.07);
  }

  int reward(int wave) => switch (this) {
        ZombieKind.walker => 8 + wave,
        ZombieKind.runner => 10 + wave,
        ZombieKind.brute => 24 + wave,
        ZombieKind.spitter => 14 + wave,
        ZombieKind.skyCaller => 18 + wave,
        ZombieKind.necromancer => 22 + wave,
        ZombieKind.exploder => 12 + wave,
        ZombieKind.screamer => 16 + wave,
        ZombieKind.bloater => 20 + wave,
        ZombieKind.stalker => 15 + wave,
        ZombieKind.jumper => 13 + wave,
        ZombieKind.wraith => 17 + wave,
        ZombieKind.hiveMother => 26 + wave,
        ZombieKind.acidBomber => 15 + wave,
        ZombieKind.shieldBearer => 19 + wave,
        ZombieKind.frostbite => 16 + wave,
        ZombieKind.swarmling => 6 + wave,
        ZombieKind.globling => 7 + wave,
        ZombieKind.boneGolem => 28 + wave,
        ZombieKind.hammerMauler => 30 + wave,
        ZombieKind.plagueDoctor => 20 + wave,
        ZombieKind.pyrofiend => 18 + wave,
        ZombieKind.riftWalker => 21 + wave,
        ZombieKind.hasteMage => 28 + wave,
        ZombieKind.knifeThrower => 18 + wave,
        ZombieKind.knifeFanatic => 24 + wave,
        ZombieKind.sharpshooter => 20 + wave,
        ZombieKind.scatterGunner => 17 + wave,
        ZombieKind.emberCaster => 19 + wave,
        ZombieKind.iceLancer => 18 + wave,
        ZombieKind.hexWitch => 22 + wave,
        ZombieKind.railSniper => 21 + wave,
        ZombieKind.harpooner => 19 + wave,
        ZombieKind.boltSlinger => 15 + wave,
        ZombieKind.toxinDart => 16 + wave,
        ZombieKind.zapper => 20 + wave,
        ZombieKind.missileer => 23 + wave,
        ZombieKind.siegeBehemoth => 90 + wave * 4,
        ZombieKind.broodQueen => 85 + wave * 4,
        ZombieKind.ironColossus => 100 + wave * 4,
        ZombieKind.laserOverseer => 95 + wave * 4,
        ZombieKind.blazeburst => 90 + wave * 4,
        ZombieKind.dreadlord => 180 + wave * 6,
        ZombieKind.citadelTower => 120 + wave * 5,
        ZombieKind.apocalypseLord => 260 + wave * 8,
        ZombieKind.shadowRonin => 320 + wave * 10,
        ZombieKind.voidSovereign => 480 + wave * 14,
      };

  double get radius => switch (this) {
        ZombieKind.walker => 0.05,
        ZombieKind.runner => 0.045,
        ZombieKind.brute => 0.075,
        ZombieKind.spitter => 0.05,
        ZombieKind.skyCaller => 0.055,
        ZombieKind.necromancer => 0.058,
        ZombieKind.exploder => 0.048,
        ZombieKind.screamer => 0.052,
        ZombieKind.bloater => 0.085,
        ZombieKind.stalker => 0.042,
        ZombieKind.jumper => 0.05,
        ZombieKind.wraith => 0.046,
        ZombieKind.hiveMother => 0.08,
        ZombieKind.acidBomber => 0.05,
        ZombieKind.shieldBearer => 0.07,
        ZombieKind.frostbite => 0.052,
        ZombieKind.swarmling => 0.032,
        ZombieKind.globling => 0.036,
        ZombieKind.boneGolem => 0.09,
        ZombieKind.hammerMauler => 0.082,
        ZombieKind.plagueDoctor => 0.055,
        ZombieKind.pyrofiend => 0.052,
        ZombieKind.riftWalker => 0.05,
        ZombieKind.hasteMage => 0.056,
        ZombieKind.knifeThrower => 0.048,
        ZombieKind.knifeFanatic => 0.055,
        ZombieKind.sharpshooter => 0.05,
        ZombieKind.scatterGunner => 0.054,
        ZombieKind.emberCaster => 0.052,
        ZombieKind.iceLancer => 0.05,
        ZombieKind.hexWitch => 0.054,
        ZombieKind.railSniper => 0.046,
        ZombieKind.harpooner => 0.056,
        ZombieKind.boltSlinger => 0.049,
        ZombieKind.toxinDart => 0.047,
        ZombieKind.zapper => 0.051,
        ZombieKind.missileer => 0.053,
        ZombieKind.siegeBehemoth => 0.12,
        ZombieKind.broodQueen => 0.11,
        ZombieKind.ironColossus => 0.13,
        ZombieKind.laserOverseer => 0.115,
        ZombieKind.blazeburst => 0.11,
        ZombieKind.dreadlord => 0.12,
        ZombieKind.citadelTower => 0.16,
        ZombieKind.apocalypseLord => 0.14,
        ZombieKind.shadowRonin => 0.07,
        ZombieKind.voidSovereign => 0.13,
      };

  double get hitRadius => radius * (isBoss || isMiniBoss ? 2.2 : 2.6);

  int get meleeDamage => switch (this) {
        ZombieKind.walker => 9,
        ZombieKind.runner => 8,
        ZombieKind.brute => 18,
        ZombieKind.spitter => 6,
        ZombieKind.skyCaller => 8,
        ZombieKind.necromancer => 7,
        ZombieKind.exploder => 10,
        ZombieKind.screamer => 7,
        ZombieKind.bloater => 14,
        ZombieKind.stalker => 16,
        ZombieKind.jumper => 12,
        ZombieKind.wraith => 11,
        ZombieKind.hiveMother => 10,
        ZombieKind.acidBomber => 8,
        ZombieKind.shieldBearer => 9,
        ZombieKind.frostbite => 10,
        ZombieKind.swarmling => 5,
        ZombieKind.globling => 4,
        ZombieKind.boneGolem => 22,
        ZombieKind.hammerMauler => 12,
        ZombieKind.plagueDoctor => 8,
        ZombieKind.pyrofiend => 12,
        ZombieKind.riftWalker => 14,
        ZombieKind.hasteMage => 6,
        ZombieKind.knifeThrower => 8,
        ZombieKind.knifeFanatic => 10,
        ZombieKind.sharpshooter => 7,
        ZombieKind.scatterGunner => 9,
        ZombieKind.emberCaster => 7,
        ZombieKind.iceLancer => 7,
        ZombieKind.hexWitch => 6,
        ZombieKind.railSniper => 6,
        ZombieKind.harpooner => 9,
        ZombieKind.boltSlinger => 7,
        ZombieKind.toxinDart => 6,
        ZombieKind.zapper => 8,
        ZombieKind.missileer => 7,
        ZombieKind.siegeBehemoth => 28,
        ZombieKind.broodQueen => 20,
        ZombieKind.ironColossus => 32,
        ZombieKind.laserOverseer => 22,
        ZombieKind.blazeburst => 18,
        ZombieKind.dreadlord => 30,
        ZombieKind.citadelTower => 20,
        ZombieKind.apocalypseLord => 36,
        ZombieKind.shadowRonin => 34,
        ZombieKind.voidSovereign => 42,
      };

  double get meleeReach => switch (this) {
        ZombieKind.brute => 0.09,
        ZombieKind.bloater => 0.1,
        ZombieKind.stalker => 0.07,
        ZombieKind.jumper => 0.08,
        ZombieKind.shieldBearer => 0.085,
        ZombieKind.boneGolem => 0.11,
        ZombieKind.hammerMauler => 0.13,
        ZombieKind.siegeBehemoth => 0.14,
        ZombieKind.broodQueen => 0.12,
        ZombieKind.ironColossus => 0.15,
        ZombieKind.laserOverseer => 0.12,
        ZombieKind.blazeburst => 0.11,
        ZombieKind.dreadlord => 0.13,
        ZombieKind.citadelTower => 0.18,
        ZombieKind.apocalypseLord => 0.15,
        ZombieKind.shadowRonin => 0.16,
        ZombieKind.voidSovereign => 0.18,
        _ => 0.055,
      };

  bool get prefersRange =>
      this == ZombieKind.spitter ||
      this == ZombieKind.skyCaller ||
      this == ZombieKind.necromancer ||
      this == ZombieKind.frostbite ||
      this == ZombieKind.acidBomber ||
      this == ZombieKind.plagueDoctor ||
      this == ZombieKind.hasteMage ||
      this == ZombieKind.knifeThrower ||
      this == ZombieKind.knifeFanatic ||
      this == ZombieKind.sharpshooter ||
      this == ZombieKind.scatterGunner ||
      this == ZombieKind.emberCaster ||
      this == ZombieKind.iceLancer ||
      this == ZombieKind.hexWitch ||
      this == ZombieKind.railSniper ||
      this == ZombieKind.harpooner ||
      this == ZombieKind.boltSlinger ||
      this == ZombieKind.toxinDart ||
      this == ZombieKind.zapper ||
      this == ZombieKind.missileer ||
      this == ZombieKind.blazeburst ||
      this == ZombieKind.citadelTower;

  double get preferredRange => switch (this) {
        ZombieKind.spitter => 1.15,
        ZombieKind.skyCaller => 1.35,
        ZombieKind.necromancer => 1.25,
        ZombieKind.frostbite => 1.2,
        ZombieKind.acidBomber => 1.1,
        ZombieKind.plagueDoctor => 1.3,
        ZombieKind.hasteMage => 1.55,
        ZombieKind.knifeThrower => 1.8,
        ZombieKind.knifeFanatic => 1.05,
        ZombieKind.sharpshooter => 1.9,
        ZombieKind.scatterGunner => 0.85,
        ZombieKind.emberCaster => 1.25,
        ZombieKind.iceLancer => 1.3,
        ZombieKind.hexWitch => 1.4,
        ZombieKind.railSniper => 2.1,
        ZombieKind.harpooner => 1.45,
        ZombieKind.boltSlinger => 1.2,
        ZombieKind.toxinDart => 1.15,
        ZombieKind.zapper => 1.35,
        ZombieKind.missileer => 1.75,
        ZombieKind.blazeburst => 1.55,
        ZombieKind.citadelTower => 99,
        _ => 0,
      };

  double get damageTakenFactor => switch (this) {
        ZombieKind.shieldBearer => 0.55,
        ZombieKind.ironColossus => 0.65,
        ZombieKind.citadelTower => 0.85,
        ZombieKind.apocalypseLord => 0.75,
        ZombieKind.voidSovereign => 0.7,
        _ => 1.0,
      };

  /// Shared elite moves (dash / block / ground pound) layered on top of
  /// each boss or mini-boss's primary ability.
  List<EliteCombatSkill> get eliteSkills => switch (this) {
        ZombieKind.siegeBehemoth => const [
            EliteCombatSkill.dash,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.broodQueen => const [
            EliteCombatSkill.dash,
          ],
        ZombieKind.ironColossus => const [
            EliteCombatSkill.block,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.laserOverseer => const [
            EliteCombatSkill.block,
          ],
        ZombieKind.blazeburst => const [
            EliteCombatSkill.dash,
            EliteCombatSkill.block,
          ],
        ZombieKind.dreadlord => const [
            EliteCombatSkill.dash,
            EliteCombatSkill.block,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.apocalypseLord => const [
            EliteCombatSkill.dash,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.shadowRonin => const [
            EliteCombatSkill.block,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.voidSovereign => const [
            EliteCombatSkill.dash,
            EliteCombatSkill.block,
            EliteCombatSkill.groundPound,
          ],
        ZombieKind.citadelTower => const [
            EliteCombatSkill.block,
          ],
        _ => const [],
      };
}

enum EliteCombatSkill { dash, block, groundPound }
