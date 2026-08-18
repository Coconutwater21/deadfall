import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'game_audio.dart';
import 'high_scores.dart';
import 'survival_content.dart';
import 'survival_upgrades.dart';
import 'survival_world.dart';

export 'game_audio.dart';
export 'survival_content.dart';
export 'survival_upgrades.dart';
export 'survival_world.dart';
export 'high_scores.dart';

class Zombie {
  Zombie({
    required this.id,
    required this.kind,
    required this.position,
    required this.health,
    required this.maxHealth,
    required this.speed,
    required this.reward,
  });

  final int id;
  final ZombieKind kind;
  Offset position;
  double health;
  double maxHealth;
  double speed;
  final int reward;
  double attackCooldown = 0;
  double abilityCooldown = 0;
  double hitFlash = 0;
  double speedBoost = 0;
  double attackAnim = 0;
  Offset attackFacing = const Offset(0, -1);
  /// Alternating attack patterns (citadel X / + barrages).
  int abilityPhase = 0;
  double burnTimer = 0;
  double burnDps = 0;
  double virusTimer = 0;
  double virusDps = 0;
  double virusSpreadCooldown = 0;
  /// Weapon chill / snare. While > 0, movement is multiplied by [slowFactor].
  double slowTimer = 0;
  double slowFactor = 1;
  /// Extra timer (Shadow Ronin mini-boss summons, etc.).
  double specialTimer = 0;
  /// While > 0, weapon hits and blasts are blocked.
  double blockTimer = 0;
  /// Spectral form: phases through walls; bullets sometimes pass through.
  bool isGhost = false;
  /// Raised / summoned by a Necromancer (counts for the good-ending trigger).
  bool isNecroMinion = false;
  /// Post good-ending Necromancer boss form.
  bool isAscendedNecromancer = false;
  /// Multiplies melee (and similar contact) damage.
  double damageMult = 1;

  /// Counts down while a telegraph plays before the attack commits.
  double windUpTimer = 0;
  double windUpDuration = 0;
  EnemyAttackKind? pendingAttack;
  /// Ground warning radius in world units (0 = slash / bolt charge only).
  double telegraphRadius = 0;
  /// Optional fixed warn point (meteor / poison / fire drop).
  Offset? telegraphWorld;

  bool get isWindingUp => windUpTimer > 0 && pendingAttack != null;
  double get windUpProgress {
    if (windUpDuration <= 0) return 1;
    return (1 - windUpTimer / windUpDuration).clamp(0.0, 1.0);
  }

  double get radius => kind.radius;
  double get hitRadius => kind.hitRadius;
  bool get isBurning => burnTimer > 0;
  bool get isInfected => virusTimer > 0;
  bool get isSlowed => slowTimer > 0;
  bool get isBlocking => blockTimer > 0;
  bool get brute =>
      kind == ZombieKind.brute ||
      kind == ZombieKind.bloater ||
      kind == ZombieKind.hiveMother ||
      kind == ZombieKind.shieldBearer ||
      kind == ZombieKind.boneGolem ||
      kind == ZombieKind.hammerMauler ||
      kind.isMiniBoss ||
      kind.isBoss ||
      isAscendedNecromancer;

  /// World-space points covering feet → torso → head for hitscan.
  List<Offset> get bodyHitPoints {
    // Screen-up in this isometric mapping leans toward (-1, -1).
    const up = Offset(-0.707, -0.707);
    final r = radius;
    return [
      position,
      position + up * (r * 1.6),
      position + up * (r * 3.1),
    ];
  }

  void clearWindUp() {
    windUpTimer = 0;
    windUpDuration = 0;
    pendingAttack = null;
    telegraphRadius = 0;
    telegraphWorld = null;
  }
}

/// What an enemy is charging before it lands / fires.
enum EnemyAttackKind {
  melee,
  exploder,
  globling,
  ability,
  dash,
  block,
  groundPound,
}

class EnemyBolt {
  EnemyBolt({
    required this.position,
    required this.velocity,
    required this.damage,
    required this.color,
    this.life = 2.4,
    this.radius = 0.04,
    this.style = EnemyBoltStyle.standard,
    this.splitRemaining = 0,
    this.shardCount = 8,
    this.ownerId,
  });

  Offset position;
  Offset velocity;
  final double damage;
  final Color color;
  double life;
  final double radius;
  final EnemyBoltStyle style;
  /// How many more explosion generations this fireball can create.
  final int splitRemaining;
  /// Child count when this fireball detonates (if [splitRemaining] > 0).
  final int shardCount;
  /// Firer id for linked missiles — cleared when that zombie dies.
  final int? ownerId;
  bool detonated = false;
}

enum EnemyBoltStyle { standard, citadel, apocalypse, knife, fireball, missile }

class SkyHazard {
  SkyHazard({
    required this.target,
    required this.damage,
    required this.blastRadius,
    this.height = 1,
    this.summonsZombie = false,
    this.summonsNecroMinion = false,
    Offset? origin,
    this.screenCorner,
  })  : startHeight = height,
        origin = origin ?? target;

  /// Impact point on the ground.
  final Offset target;

  /// World XY where the meteor enters (fallback when [screenCorner] is null).
  final Offset origin;

  /// Screen corner index: 0=TL, 1=TR, 2=BL, 3=BR. Preferred for meteors.
  final int? screenCorner;

  final double damage;
  final double blastRadius;
  final bool summonsZombie;
  /// When [summonsZombie] is true, tag the spawn as a Necromancer minion.
  final bool summonsNecroMinion;
  final double startHeight;
  double height;
  bool detonated = false;

  /// 0 at spawn → 1 just before impact.
  double get fallProgress => startHeight <= 0
      ? 1.0
      : (1.0 - (height / startHeight)).clamp(0.0, 1.0);

  /// Current air position: streaks from [origin] toward [target].
  Offset get airWorld {
    final t = fallProgress;
    final eased = math.pow(t, 1.35).toDouble(); // light hang, then dive
    return Offset.lerp(origin, target, eased)!;
  }
}

class CorpseMark {
  CorpseMark(this.position, {this.life = 12});
  final Offset position;
  double life;
}

class PoisonCloud {
  PoisonCloud(this.position, {this.life = 3.5, this.radius = 0.28});
  final Offset position;
  double life;
  final double radius;
}

class StickyGoo {
  StickyGoo(
    this.position, {
    this.life = 6.5,
    this.radius = 0.34,
    this.slowFactor = 0.42,
  });

  final Offset position;
  double life;
  final double radius;
  /// Multiplier applied to player move speed while standing in the goo.
  final double slowFactor;
}

class FirePit {
  FirePit(
    this.position, {
    this.life = 5.0,
    this.radius = 0.3,
    this.dps = 14,
    this.friendly = false,
  });

  final Offset position;
  double life;
  final double radius;
  final double dps;
  /// Player-created pits never hurt the player or gun allies.
  final bool friendly;
}

enum LaserCannonPhase { charging, firing, relocating, cooldown }

/// Edge-mounted laser turret deployed by [ZombieKind.laserOverseer].
class LaserCannon {
  LaserCannon({
    required this.ownerId,
    required this.position,
    this.aim = const Offset(1, 0),
    Offset? target,
    this.phase = LaserCannonPhase.charging,
    this.phaseTimer = 1.4,
  }) : target = target ?? Offset.zero;

  final int ownerId;
  Offset position;
  Offset aim;
  /// World point the beam is locked onto (picked at random each charge).
  Offset target;
  LaserCannonPhase phase;
  double phaseTimer;

  static const double beamRange = 14.5;
  static const double beamHalfWidth = 0.78;
  static const double fireDuration = 5.0;
  static const double chargeDuration = 2.4;
  static const double relocateDuration = 0.45;
  static const double cooldownDuration = 1.5;
  static const double minSpacing = 1.45;

  Offset get beamEnd => position + aim * beamRange;
}

class SupplyCrate {
  SupplyCrate({
    required this.position,
    required this.lootKind,
    this.weapon,
    this.rarity = WeaponRarity.common,
  });

  final Offset position;
  final CrateLootKind lootKind;
  final WeaponKind? weapon;
  /// Rarity for money/health crates; weapon crates use [weapon]'s rarity.
  final WeaponRarity rarity;
  double height = 1;
  bool opened = false;

  WeaponRarity get displayRarity => weapon?.rarity ?? rarity;
}

class BulletTracer {
  BulletTracer(
    this.from,
    this.to,
    this.color, {
    this.strokeWidth = 2.2,
    this.life = 0.09,
    this.damage,
  });
  final Offset from;
  final Offset to;
  final Color color;
  final double strokeWidth;
  double life;
  /// Damage this shot would deal (shown near the tracer tip).
  final int? damage;
}

/// Rising combat text spawned when a bullet (or blast) damages a zombie.
class DamageFloater {
  DamageFloater({
    required this.position,
    required this.amount,
    this.color = const Color(0xFFFFF176),
    this.life = 0.7,
    this.blocked = false,
  }) : maxLife = life;

  Offset position;
  final int amount;
  final Color color;
  double life;
  final double maxLife;
  final bool blocked;
}

class BlastFlash {
  BlastFlash(this.position, this.color, {this.radius = 0.55, this.life = 0.28});
  final Offset position;
  final Color color;
  final double radius;
  double life;
}

/// Armed helper spawned by the Commander class.
class GunAlly {
  GunAlly({
    required this.position,
    required this.health,
    required this.formationOffset,
    this.life = 14,
  }) : maxHealth = health;

  Offset position;
  /// Offset from the Commander; refreshed each tick to face the nearest enemy.
  Offset formationOffset;
  double health;
  final double maxHealth;
  double life;
  double fireCooldown = 0.35;
  double hitFlash = 0;
  Offset aim = const Offset(1, 0);

  static const double hitRadius = 0.15;
}

class SurvivalEngine extends ChangeNotifier {
  SurvivalEngine({math.Random? random}) : _random = random ?? math.Random() {
    start();
  }

  /// Half-extent of the square arena (full map ~16×16 world units).
  static const double arenaHalf = 8.0;
  static const double healthRegenInterval = 2.0;
  static const double overhealDecayPerSecond = 7;
  /// Damage that must be dealt as Reaper to fill one Soul Bar.
  static const double soulBarDamageNeeded = 520;
  /// Soul Bar empties on its own if you stop dealing damage.
  static const double soulBarDrainPerSecond = 0.12;

  /// Screen-space axes mapped into the isometric world.
  static const Offset screenRight = Offset(0.70710678, -0.70710678);
  static const Offset screenDown = Offset(0.70710678, 0.70710678);

  final math.Random _random;

  /// Optional SFX hook — wired by the UI's [GameAudio].
  void Function(AudioCue cue, {WeaponKind? weapon})? onAudioCue;

  final List<Zombie> zombies = [];
  final List<SupplyCrate> crates = [];
  final List<BulletTracer> tracers = [];
  final List<DamageFloater> damageFloaters = [];
  final List<BlastFlash> blastFlashes = [];
  final List<EnemyBolt> enemyBolts = [];
  final List<SkyHazard> skyHazards = [];
  final List<CorpseMark> corpses = [];
  final List<PoisonCloud> poisonClouds = [];
  final List<StickyGoo> stickyGoos = [];
  final List<FirePit> firePits = [];
  final List<LaserCannon> laserCannons = [];
  final List<GunAlly> gunAllies = [];
  final List<SolidProp> props = [];
  final List<House> houses = [];
  final List<TreasureChest> chests = [];
  final List<WorldKeyDrop> keyDrops = [];
  final Set<WeaponKind> unlockedWeapons = {WeaponKind.pistol};
  final Set<PlayerClass> unlockedClasses = {PlayerClass.survivor};
  final Set<PlayerClass> unlockedAbilities = {};
  final Map<PlayerClass, int> classLevels = {};
  final Map<PlayerClass, int> abilityLevels = {};
  final Map<WeaponKind, int> weaponLevels = {};
  final Map<WeaponKind, int> magazine = {};

  Offset player = Offset.zero;
  Offset aimDirection = const Offset(0, -1);
  WeaponKind weapon = WeaponKind.pistol;
  PlayerClass playerClass = PlayerClass.survivor;
  int health = PlayerClass.survivor.maxHealth;
  int money = 0;
  int wave = 0;
  int kills = 0;
  /// Lifetime money gained this run (spending does not reduce this).
  int totalMoneyEarned = 0;
  /// Lifetime kills this run (spending kill currency does not reduce this).
  int totalKills = 0;
  int bestWave = 0;
  int miniKeys = 0;
  int bossKeys = 0;
  bool gameOver = false;
  bool paused = false;
  /// When false, loot unlocks/upgrades a gun without switching to it.
  bool autoEquipNewWeapons = false;
  /// Cutscene: only Necromancer + minions survived for 2s.
  bool badEndingCutscene = false;
  /// Ascended Necromancer fight is underway.
  bool badEndingActive = false;
  bool waveActive = false;
  double nextWaveTimer = 1.5;
  double waveBannerTimer = 0;
  String notification = '';
  double notificationTimer = 0;

  static const List<ZombieKind> allMiniBossKinds = [
    ZombieKind.siegeBehemoth,
    ZombieKind.broodQueen,
    ZombieKind.ironColossus,
    ZombieKind.laserOverseer,
    ZombieKind.blazeburst,
  ];

  /// Mini-bosses eligible to summon/spawn at the current wave.
  List<ZombieKind> get _availableMiniBossKinds => wave < 15
      ? allMiniBossKinds
          .where((k) => k != ZombieKind.blazeburst)
          .toList(growable: false)
      : allMiniBossKinds;

  static const List<ZombieKind> allBossKinds = [
    ZombieKind.dreadlord,
    ZombieKind.citadelTower,
    ZombieKind.apocalypseLord,
    ZombieKind.shadowRonin,
    ZombieKind.voidSovereign,
  ];

  int _nextZombieId = 0;
  int _remainingToSpawn = 0;
  double _spawnTimer = 0;
  double _shotCooldown = 0;
  double _reloadTimer = 0;
  double _crateTimer = 13;
  double _damageFlash = 0;
  double _regenTimer = 0;
  double _overhealDecayAcc = 0;
  double _poisonAcc = 0;
  double _abilityCooldown = 0;
  double _shieldTimer = 0;
  double _invulnTimer = 0;
  /// Vanguard Shock Bash: second knockback after invuln window.
  double _vanguardSecondPushTimer = 0;
  double _speedBuffTimer = 0;
  double _damageBuffTimer = 0;
  double _overdriveTimer = 0;
  double _scytheTimer = 0;
  double _scytheSwingPhase = 0;
  double _scytheSwingAngle = 0;
  /// 0 = idle; (0,1] = progress through the current melee swing.
  double _scytheAttackProgress = 0;
  /// Alternates each swing so the blade chops left→right then right→left.
  int _scytheSwingDir = 1;
  final Set<int> _scytheHitIds = {};
  double _soulCharge = 0;
  double _speedBuffMult = 1;
  double _damageBuffMult = 1;
  double _lootHintTimer = 0;
  double _masteryPulseTimer = 0;
  double _aftershockTimer = 0;
  double _aftershockRadius = 0;
  double _aftershockDamage = 0;
  /// SMG mastery: temporary fire-rate frenzy after kills.
  double _stormTimer = 0;
  /// Minigun mastery heat (0–1), builds while firing.
  double _weaponHeat = 0;
  /// Bow mastery: branded prey takes bonus damage.
  int? _hunterMarkId;
  double _hunterMarkTimer = 0;
  /// Launcher mastery: delayed cluster bombs.
  final List<({Offset at, double timer, double radius, int damage, Color color})>
      _clusterBombs = [];
  /// Seconds with only Necromancer + his minions left (good-ending trigger).
  double _necroSoloTimer = 0;
  double _ascendedMiniSpawnTimer = 0;
  bool _firing = false;
  bool _scoreRecorded = false;
  /// Timestamp of the score just written on death (for leaderboard highlight).
  DateTime? lastRecordedScoreAt;
  /// True when this death qualifies for the board and we're waiting on a name.
  bool awaitingNameEntry = false;
  HighScoreEntry? pendingScore;
  Offset _moveInput = Offset.zero;
  List<HighScoreEntry> highScores = [];
  final Map<int, int> _meteorCorners = {};
  final Map<int, bool> _necroRaise = {};
  double _gameTime = 0;
  final List<Offset> _playerHistory = [];
  final List<double> _playerHistoryTime = [];

  double get damageFlash => _damageFlash;
  int get enemiesRemaining => zombies.length + _remainingToSpawn;
  double get arenaBound => arenaHalf;
  int get maxHealth =>
      (playerClass.maxHealth * SurvivalUpgrades.classHealthMult(classLevel(playerClass)))
          .round();
  int get ammoInMag => magazine[weapon] ?? 0;
  int get magazineSize =>
      weapon.magazineSize + SurvivalUpgrades.weaponMagBonus(weaponLevel(weapon));
  bool get isReloading => _reloadTimer > 0;
  double get reloadProgress =>
      isReloading ? 1 - (_reloadTimer / effectiveReloadSeconds) : 1;
  double get reloadSecondsLeft => _reloadTimer;
  bool get abilityUnlocked => unlockedAbilities.contains(playerClass);
  bool get isShielded => _shieldTimer > 0 || _invulnTimer > 0;
  double get abilityCooldownLeft => _abilityCooldown;
  double get abilityCooldownMax =>
      playerClass.abilityCooldown *
      SurvivalUpgrades.abilityCooldownMult(abilityLevel(playerClass));
  bool get abilityReady =>
      abilityUnlocked && _abilityCooldown <= 0 && !gameOver && !paused;
  double get abilityPower =>
      SurvivalUpgrades.abilityPowerMult(abilityLevel(playerClass));
  /// 0–1 fill for the Reaper Soul Bar.
  double get soulCharge =>
      playerClass == PlayerClass.reaper ? _soulCharge.clamp(0.0, 1.0) : 0;
  bool get soulScytheActive => _scytheTimer > 0;
  double get soulScytheSecondsLeft => _scytheTimer;
  /// Radians offset from aim used to animate / hit with the scythe.
  double get soulScytheSwingAngle => _scytheSwingAngle;
  bool get soulScytheSwinging =>
      _scytheAttackProgress > 0 && _scytheAttackProgress < 1;
  double get gameTime => _gameTime;
  double get effectiveMoveSpeed =>
      playerClass.moveSpeed *
      SurvivalUpgrades.classSpeedMult(classLevel(playerClass));
  double get gooSlowFactor {
    var slow = 1.0;
    for (final goo in stickyGoos) {
      if ((player - goo.position).distance <= goo.radius) {
        slow = math.min(slow, goo.slowFactor);
      }
    }
    return slow;
  }

  bool get isSlowedByGoo => gooSlowFactor < 0.999;
  double get effectiveWeaponCooldown =>
      weapon.cooldown *
      SurvivalUpgrades.weaponCooldownMult(weaponLevel(weapon));
  double get effectiveReloadSeconds =>
      weapon.reloadSeconds *
      SurvivalUpgrades.weaponReloadMult(weaponLevel(weapon));

  int classLevel(PlayerClass kind) => classLevels[kind] ?? 0;
  int abilityLevel(PlayerClass kind) => abilityLevels[kind] ?? 0;
  int weaponLevel(WeaponKind kind) => weaponLevels[kind] ?? 0;

  bool get classMastered =>
      SurvivalUpgrades.isMastered(classLevel(playerClass));
  bool get abilityMastered =>
      SurvivalUpgrades.isMastered(abilityLevel(playerClass));
  bool get weaponMastered => SurvivalUpgrades.isMastered(weaponLevel(weapon));

  bool isClassMastered(PlayerClass kind) =>
      SurvivalUpgrades.isMastered(classLevel(kind));
  bool isAbilityMastered(PlayerClass kind) =>
      SurvivalUpgrades.isMastered(abilityLevel(kind));
  bool isWeaponMastered(WeaponKind kind) =>
      SurvivalUpgrades.isMastered(weaponLevel(kind));

  double get effectiveWeaponDamage {
    var dmg = weapon.damage *
        SurvivalUpgrades.weaponDamageMult(weaponLevel(weapon));
    if (classMastered &&
        playerClass == PlayerClass.berserker &&
        health <= maxHealth * 0.6) {
      dmg *= 2.0;
    }
    if (classMastered && playerClass == PlayerClass.ranger) {
      dmg *= 1.35;
    }
    if (weaponMastered &&
        weapon.mastery == WeaponMastery.overheat &&
        _weaponHeat > 0.2) {
      dmg *= 1.0 + _weaponHeat * 1.4;
    }
    return dmg;
  }

  List<WeaponKind> get unlockedSorted {
    final list = unlockedWeapons.toList()
      ..sort((a, b) {
        final rarity = a.rarity.index.compareTo(b.rarity.index);
        if (rarity != 0) return rarity;
        return a.index.compareTo(b.index);
      });
    return list;
  }

  void start() {
    zombies.clear();
    crates.clear();
    tracers.clear();
    damageFloaters.clear();
    blastFlashes.clear();
    enemyBolts.clear();
    skyHazards.clear();
    corpses.clear();
    poisonClouds.clear();
    stickyGoos.clear();
    firePits.clear();
    laserCannons.clear();
    gunAllies.clear();
    keyDrops.clear();
    _meteorCorners.clear();
    _necroRaise.clear();
    _poisonAcc = 0;
    _gameTime = 0;
    _playerHistory.clear();
    _playerHistoryTime.clear();

    unlockedWeapons
      ..clear()
      ..add(WeaponKind.pistol);
    unlockedClasses
      ..clear()
      ..add(PlayerClass.survivor);
    unlockedAbilities.clear();
    classLevels.clear();
    abilityLevels.clear();
    weaponLevels.clear();
    magazine
      ..clear()
      ..addAll({
        for (final kind in WeaponKind.values) kind: kind.magazineSize,
      });
    player = Offset.zero;
    aimDirection = const Offset(0, -1);
    weapon = WeaponKind.pistol;
    playerClass = PlayerClass.survivor;
    health = maxHealth;
    money = 0;
    wave = 0;
    kills = 0;
    totalMoneyEarned = 0;
    totalKills = 0;
    miniKeys = 0;
    bossKeys = 0;
    gameOver = false;
    paused = false;
    badEndingCutscene = false;
    badEndingActive = false;
    waveActive = false;
    nextWaveTimer = 1.5;
    _remainingToSpawn = 0;
    _spawnTimer = 0;
    _shotCooldown = 0;
    _reloadTimer = 0;
    _crateTimer = 4 + _random.nextDouble() * 3;
    _regenTimer = 0;
    _overhealDecayAcc = 0;
    _poisonAcc = 0;
    _abilityCooldown = 0;
    _shieldTimer = 0;
    _invulnTimer = 0;
    _vanguardSecondPushTimer = 0;
    _speedBuffTimer = 0;
    _damageBuffTimer = 0;
    _overdriveTimer = 0;
    _scytheTimer = 0;
    _scytheSwingPhase = 0;
    _scytheSwingAngle = 0;
    _scytheAttackProgress = 0;
    _scytheSwingDir = 1;
    _scytheHitIds.clear();
    _soulCharge = 0;
    _speedBuffMult = 1;
    _damageBuffMult = 1;
    // Seed the arena with several crates right away.
    for (var i = 0; i < 4; i++) {
      _dropCrate();
    }
    _damageBuffTimer = 0;
    _overdriveTimer = 0;
    _scytheTimer = 0;
    _scytheSwingPhase = 0;
    _scytheSwingAngle = 0;
    _scytheAttackProgress = 0;
    _scytheSwingDir = 1;
    _scytheHitIds.clear();
    _soulCharge = 0;
    _speedBuffMult = 1;
    _damageBuffMult = 1;
    _masteryPulseTimer = 0;
    _aftershockTimer = 0;
    _aftershockRadius = 0;
    _aftershockDamage = 0;
    _stormTimer = 0;
    _weaponHeat = 0;
    _hunterMarkId = null;
    _hunterMarkTimer = 0;
    _clusterBombs.clear();
    _necroSoloTimer = 0;
    _ascendedMiniSpawnTimer = 0;
    _scoreRecorded = false;
    lastRecordedScoreAt = null;
    awaitingNameEntry = false;
    pendingScore = null;
    _buildWorld();
    for (var i = 0; i < 4; i++) {
      _dropCrate();
    }
    notifyListeners();
  }

  void _buildWorld() {
    final built = SurvivalWorldBuilder(_random, arenaHalf: arenaHalf).build();
    props
      ..clear()
      ..addAll(built.props);

    houses.clear();
    for (final house in built.houses) {
      houses.add(House(
        center: house.center,
        width: house.width,
        depth: house.depth,
        doorSide: house.doorSide,
        facade: house.facade,
      ));
    }

    chests.clear();
    for (final chest in built.chests) {
      final loot = _rollChestLoot(chest.requiredKey);
      chests.add(TreasureChest(
        position: chest.position,
        requiredKey: chest.requiredKey,
        lootKind: loot.kind,
        weapon: loot.weapon,
        bonusMoney: loot.money,
        bonusHeal: loot.heal,
      ));
    }
  }

  /// Mini-key chests: mid loot. Boss-key chests: high-end loot.
  ({CrateLootKind kind, WeaponKind? weapon, int money, int heal})
      _rollChestLoot(KeyKind key) {
    if (key == KeyKind.mini) {
      final gun = _rollWeaponDropRarityBand(
        minRarity: WeaponRarity.uncommon,
        maxRarity: WeaponRarity.rare,
      );
      if (gun != null) {
        return (
          kind: CrateLootKind.weapon,
          weapon: gun,
          money: 40 + wave * 7 + _random.nextInt(35),
          heal: 10 + _random.nextInt(15),
        );
      }
      return (
        kind: CrateLootKind.money,
        weapon: null,
        money: 90 + wave * 10 + _random.nextInt(50),
        heal: 18 + _random.nextInt(18),
      );
    }

    final gun = _rollWeaponDropMinRarity(WeaponRarity.epic);
    if (gun != null) {
      return (
        kind: CrateLootKind.weapon,
        weapon: gun,
        money: 140 + wave * 18 + _random.nextInt(90),
        heal: 35 + _random.nextInt(35),
      );
    }
    return (
      kind: CrateLootKind.money,
      weapon: null,
      money: 260 + wave * 28 + _random.nextInt(140),
      heal: 50 + _random.nextInt(40),
    );
  }

  ({CrateLootKind kind, WeaponKind? weapon, int money, int heal})
      _rollPremiumLoot() {
    final gun = _rollWeaponDropMinRarity(WeaponRarity.rare);
    if (gun != null) {
      return (
        kind: CrateLootKind.weapon,
        weapon: gun,
        money: 80 + wave * 12 + _random.nextInt(60),
        heal: 20 + _random.nextInt(25),
      );
    }
    return (
      kind: CrateLootKind.money,
      weapon: null,
      money: 180 + wave * 20 + _random.nextInt(120),
      heal: 35 + _random.nextInt(30),
    );
  }

  WeaponKind? _rollWeaponDropRarityBand({
    required WeaponRarity minRarity,
    required WeaponRarity maxRarity,
  }) {
    final band = WeaponKind.values
        .where((candidate) =>
            candidate.rarity.index >= minRarity.index &&
            candidate.rarity.index <= maxRarity.index)
        .toList();
    if (band.isEmpty) return null;

    final locked = band
        .where((candidate) => !unlockedWeapons.contains(candidate))
        .toList();
    final pool = locked.isNotEmpty ? locked : band;
    pool.sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    final top = pool.take(math.max(1, pool.length ~/ 2)).toList();
    return top[_random.nextInt(top.length)];
  }

  WeaponKind? _rollWeaponDropMinRarity(WeaponRarity minRarity) {
    final locked = WeaponKind.values
        .where((candidate) =>
            !unlockedWeapons.contains(candidate) &&
            candidate.rarity.index >= minRarity.index)
        .toList();
    if (locked.isEmpty) {
      // Fall back to any locked weapon, preferring higher rarity.
      final any = WeaponKind.values
          .where((candidate) => !unlockedWeapons.contains(candidate))
          .toList()
        ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
      if (any.isEmpty) {
        // All owned — still drop something in-band for free upgrades.
        final ownedBand = WeaponKind.values
            .where((candidate) => candidate.rarity.index >= minRarity.index)
            .toList();
        if (ownedBand.isEmpty) return null;
        return ownedBand[_random.nextInt(ownedBand.length)];
      }
      return any.first;
    }
    locked.sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    // Bias toward higher rarities among eligible.
    final top = locked.take(math.max(1, locked.length ~/ 2)).toList();
    return top[_random.nextInt(top.length)];
  }

  Future<void> loadHighScores() async {
    highScores = await HighScoreStore.load();
    notifyListeners();
  }

  Future<void> _recordHighScoreIfNeeded() async {
    if (_scoreRecorded || awaitingNameEntry) return;
    final entry = HighScoreEntry(
      wave: wave,
      kills: totalKills,
      money: totalMoneyEarned,
      className: playerClass.label,
      at: DateTime.now(),
    );
    highScores = await HighScoreStore.load();
    if (!await HighScoreStore.wouldQualify(entry)) {
      _scoreRecorded = true;
      notifyListeners();
      return;
    }
    pendingScore = entry;
    awaitingNameEntry = true;
    notifyListeners();
  }

  /// Save the pending run onto the leaderboard under [name].
  Future<void> submitHighScoreName(String name) async {
    final pending = pendingScore;
    if (!awaitingNameEntry || pending == null || _scoreRecorded) return;
    final entry = pending.copyWith(
      playerName: HighScoreStore.sanitizeName(name),
    );
    _scoreRecorded = true;
    awaitingNameEntry = false;
    pendingScore = null;
    highScores = await HighScoreStore.record(entry);
    lastRecordedScoreAt =
        highScores.any((e) => e.at == entry.at) ? entry.at : null;
    notifyListeners();
  }

  bool isOwnLeaderboardEntry(HighScoreEntry entry) =>
      lastRecordedScoreAt != null && entry.at == lastRecordedScoreAt;

  void _earnMoney(int amount) {
    if (amount <= 0) return;
    money += amount;
    totalMoneyEarned += amount;
  }

  void _registerKill(Zombie zombie) {
    kills++;
    totalKills++;
    _earnMoney(zombie.reward);
    _onMasteryKill(zombie);
    if (zombie.kind == ZombieKind.exploder ||
        zombie.kind == ZombieKind.bloater) {
      _sfx(AudioCue.explosion);
    } else if (zombie.kind.isBoss || zombie.isAscendedNecromancer) {
      _sfx(AudioCue.deathBoss);
    } else if (zombie.kind.isMiniBoss) {
      _sfx(AudioCue.deathMiniBoss);
    } else {
      _sfx(AudioCue.kill);
    }
  }

  void _onMasteryKill(Zombie zombie) {
    if (classMastered) {
      switch (playerClass) {
        case PlayerClass.survivor:
          _heal((maxHealth * 0.22).round().clamp(22, 80));
        case PlayerClass.scout:
          _speedBuffTimer = math.max(_speedBuffTimer, 2.4);
          _speedBuffMult = math.max(_speedBuffMult, 1.95);
          _invulnTimer = math.max(_invulnTimer, 0.55);
        case PlayerClass.reaper:
          _addSoulCharge(45, mult: 1.15);
        case PlayerClass.tank:
          _heal(8);
        default:
          break;
      }
    }
    if (!weaponMastered) return;
    switch (weapon.mastery) {
      case WeaponMastery.storm:
        _stormTimer = math.max(_stormTimer, 2.8);
        _shotCooldown = 0;
      case WeaponMastery.inferno:
        firePits.add(FirePit(
          zombie.position,
          life: 5.5,
          radius: 0.42,
          dps: 55 + wave * 0.9,
          friendly: true,
        ));
        // Spread inferno to nearby corpses of combat.
        for (final other in zombies) {
          if (other.id == zombie.id) continue;
          if (_wrappedDelta(zombie.position, other.position).distance > 0.55) {
            continue;
          }
          _applyBurn(other, duration: 5.0, dps: 48);
        }
      case WeaponMastery.brand:
        // Branded kill detonates a seeking shard nova.
        _masteryPulseAt(zombie.position, 0.7, effectiveWeaponDamage * 1.1);
      case WeaponMastery.ricochet:
        _heal(3);
      case WeaponMastery.overheat:
        final mag = magazine[weapon] ?? 0;
        magazine[weapon] = math.min(magazineSize, mag + 4);
      default:
        break;
    }
  }

  void setMovement(Offset value) => _moveInput = value;
  void setFiring(bool value) => _firing = value;

  void _sfx(AudioCue cue, {WeaponKind? weapon}) =>
      onAudioCue?.call(cue, weapon: weapon);

  /// True while any mini-boss, boss, or ascended necro is alive.
  bool get hasLivingElite => zombies.any(
        (z) =>
            z.kind.isBoss ||
            z.kind.isMiniBoss ||
            z.isAscendedNecromancer,
      );

  /// Pick elite BGM from the current wave / living bosses.
  ///
  /// Decade waves (10, 20, 30…) get escalating milestone themes. Mini-boss
  /// waves keep the generic boss bed. Bad ending uses the wave-50+ apex track.
  GameMusic get eliteMusicTrack {
    var hasRonin = false;
    var hasCitadelFight = false;
    var hasOtherElite = false;
    for (final z in zombies) {
      if (z.kind == ZombieKind.shadowRonin) {
        hasRonin = true;
      } else if (z.kind == ZombieKind.citadelTower ||
          z.kind == ZombieKind.apocalypseLord) {
        hasCitadelFight = true;
      } else if (z.kind.isBoss ||
          z.kind.isMiniBoss ||
          z.isAscendedNecromancer) {
        hasOtherElite = true;
      }
    }
    final hasElite =
        hasRonin || hasCitadelFight || hasOtherElite || badEndingCutscene;

    if (badEndingActive) return GameMusic.bossW50;
    if (!hasElite) return GameMusic.none;

    // Decade milestone fights: theme scales with wave tier forever.
    if (wave >= 10 && wave % 10 == 0) {
      return switch (wave ~/ 10) {
        1 => GameMusic.bossCitadel,
        2 => GameMusic.bossRonin,
        3 => GameMusic.bossW30,
        4 => GameMusic.bossW40,
        _ => GameMusic.bossW50, // 50, 60, 70…
      };
    }

    // Off-decade elites (mini-bosses, void on 25, etc.).
    if (hasRonin) return GameMusic.bossRonin;
    if (hasCitadelFight) return GameMusic.bossCitadel;
    return GameMusic.boss;
  }

  void setAim(Offset worldPoint) {
    final delta = worldPoint - player;
    if (delta.distance > 0.01) aimDirection = delta / delta.distance;
  }

  void aimAtNearest() {
    if (zombies.isEmpty) return;
    Zombie nearest = zombies.first;
    double distance = _wrappedDelta(player, nearest.position).distanceSquared;
    for (final zombie in zombies.skip(1)) {
      final candidate = _wrappedDelta(player, zombie.position).distanceSquared;
      if (candidate < distance) {
        nearest = zombie;
        distance = candidate;
      }
    }
    final delta = _wrappedDelta(player, nearest.position);
    if (delta.distance > 0.01) {
      aimDirection = delta / delta.distance;
    }
  }

  bool canUnlockClass(PlayerClass kind) =>
      !unlockedClasses.contains(kind) &&
      money >= kind.moneyCost &&
      kills >= kind.killCost;

  bool unlockClass(PlayerClass kind) {
    if (unlockedClasses.contains(kind)) return selectClass(kind);
    if (!canUnlockClass(kind)) return false;
    money -= kind.moneyCost;
    kills -= kind.killCost;
    unlockedClasses.add(kind);
    return selectClass(kind);
  }

  bool selectClass(PlayerClass kind) {
    if (!unlockedClasses.contains(kind)) return false;
    final oldMax = maxHealth;
    final ratio = oldMax == 0 ? 1.0 : health / oldMax;
    playerClass = kind;
    final newMax = maxHealth;
    health = (newMax * ratio).round().clamp(1, newMax);
    if (kind != PlayerClass.reaper) {
      _scytheTimer = 0;
      _scytheSwingPhase = 0;
      _scytheSwingAngle = 0;
      _scytheAttackProgress = 0;
      _scytheHitIds.clear();
    }
    _showMessage('${kind.label} ready');
    notifyListeners();
    return true;
  }

  bool canUpgradeClass(PlayerClass kind) {
    if (!unlockedClasses.contains(kind)) return false;
    final level = classLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) return false;
    return money >= SurvivalUpgrades.classMoneyCost(kind, level) &&
        kills >= SurvivalUpgrades.classKillCost(kind, level);
  }

  bool upgradeClass(PlayerClass kind) {
    if (!canUpgradeClass(kind)) return false;
    final level = classLevel(kind);
    money -= SurvivalUpgrades.classMoneyCost(kind, level);
    kills -= SurvivalUpgrades.classKillCost(kind, level);
    final oldMax = kind == playerClass ? maxHealth : 0;
    classLevels[kind] = level + 1;
    if (kind == playerClass && oldMax > 0) {
      final ratio = health / oldMax;
      health = (maxHealth * ratio).round().clamp(1, maxHealth);
    }
    if (SurvivalUpgrades.isMastered(classLevel(kind))) {
      _showMessage(
        '${kind.label} MASTERY: ${SurvivalUpgrades.classMasteryName(kind).toUpperCase()}',
      );
    } else {
      _showMessage('${kind.label} L${classLevel(kind)}');
    }
    notifyListeners();
    return true;
  }

  bool canUpgradeAbility(PlayerClass kind) {
    if (!unlockedAbilities.contains(kind)) return false;
    final level = abilityLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) return false;
    return money >= SurvivalUpgrades.abilityMoneyCost(kind, level) &&
        kills >= SurvivalUpgrades.abilityKillCost(kind, level);
  }

  bool upgradeAbility(PlayerClass kind) {
    if (!canUpgradeAbility(kind)) return false;
    final level = abilityLevel(kind);
    money -= SurvivalUpgrades.abilityMoneyCost(kind, level);
    kills -= SurvivalUpgrades.abilityKillCost(kind, level);
    abilityLevels[kind] = level + 1;
    if (SurvivalUpgrades.isMastered(abilityLevel(kind))) {
      _showMessage(
        '${kind.abilityName} MASTERY: ${SurvivalUpgrades.abilityMasteryName(kind).toUpperCase()}',
      );
    } else {
      _showMessage('${kind.abilityName} L${abilityLevel(kind)}');
    }
    notifyListeners();
    return true;
  }

  bool canUpgradeWeapon(WeaponKind kind) {
    if (!unlockedWeapons.contains(kind)) return false;
    final level = weaponLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) return false;
    return money >= SurvivalUpgrades.weaponMoneyCost(kind, level) &&
        kills >= SurvivalUpgrades.weaponKillCost(kind, level);
  }

  bool upgradeWeapon(WeaponKind kind) {
    if (!canUpgradeWeapon(kind)) return false;
    final level = weaponLevel(kind);
    money -= SurvivalUpgrades.weaponMoneyCost(kind, level);
    kills -= SurvivalUpgrades.weaponKillCost(kind, level);
    _levelUpWeapon(kind);
    if (SurvivalUpgrades.isMastered(weaponLevel(kind))) {
      _showMessage(
        '${kind.label} MASTERY: ${SurvivalUpgrades.weaponMasteryName(kind).toUpperCase()}',
      );
    } else {
      _showMessage('${kind.label} L${weaponLevel(kind)}');
    }
    notifyListeners();
    return true;
  }

  /// Upgrade the gun you're holding (no need to find it in the bar).
  bool tryUpgradeEquippedWeapon() {
    if (gameOver || paused) return false;
    final kind = weapon;
    final level = weaponLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) {
      _showMessage('${kind.label} MAX');
      return false;
    }
    if (!canUpgradeWeapon(kind)) {
      _showMessage(
        'GUN +\$${SurvivalUpgrades.weaponMoneyCost(kind, level)}/'
        '${SurvivalUpgrades.weaponKillCost(kind, level)}k',
      );
      return false;
    }
    return upgradeWeapon(kind);
  }

  /// Upgrade the class you're currently playing.
  bool tryUpgradeEquippedClass() {
    if (gameOver || paused) return false;
    final kind = playerClass;
    final level = classLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) {
      _showMessage('${kind.label} MAX');
      return false;
    }
    if (!canUpgradeClass(kind)) {
      _showMessage(
        'CLASS +\$${SurvivalUpgrades.classMoneyCost(kind, level)}/'
        '${SurvivalUpgrades.classKillCost(kind, level)}k',
      );
      return false;
    }
    return upgradeClass(kind);
  }

  /// Unlock or upgrade the ability for your current class.
  bool tryUpgradeEquippedAbility() {
    if (gameOver || paused) return false;
    final kind = playerClass;
    if (!unlockedAbilities.contains(kind)) {
      if (canUnlockAbility(kind)) return unlockAbility(kind);
      _showMessage(
        '${kind.abilityName}: \$${kind.abilityMoneyCost} + ${kind.abilityKillCost} kills',
      );
      return false;
    }
    final level = abilityLevel(kind);
    if (level >= SurvivalUpgrades.maxLevel) {
      _showMessage('${kind.abilityName} MAX');
      return false;
    }
    if (!canUpgradeAbility(kind)) {
      _showMessage(
        'ABL +\$${SurvivalUpgrades.abilityMoneyCost(kind, level)}/'
        '${SurvivalUpgrades.abilityKillCost(kind, level)}k',
      );
      return false;
    }
    return upgradeAbility(kind);
  }

  void _levelUpWeapon(WeaponKind kind) {
    final level = weaponLevel(kind);
    final oldMagSize =
        kind.magazineSize + SurvivalUpgrades.weaponMagBonus(level);
    weaponLevels[kind] = level + 1;
    final newMagSize = magazineSizeFor(kind);
    final current = magazine[kind] ?? 0;
    if (current >= oldMagSize) {
      magazine[kind] = newMagSize;
    }
  }

  /// Unlock a new gun, or free-upgrade a duplicate (refunds cash at max).
  void _grantWeapon(WeaponKind gun, {required String source, int moneyBonus = 0}) {
    final alreadyOwned = unlockedWeapons.contains(gun);
    if (!alreadyOwned) {
      unlockedWeapons.add(gun);
      magazine[gun] = magazineSizeFor(gun);
      if (autoEquipNewWeapons) {
        weapon = gun;
        _reloadTimer = 0;
      }
      _showMessage(
        '$source: ${gun.rarity.label.toUpperCase()} ${gun.label.toUpperCase()}'
        '${autoEquipNewWeapons ? '' : ' (UNLOCKED)'}'
        '${moneyBonus > 0 ? ' +\$$moneyBonus' : ''}',
      );
      return;
    }

    if (weaponLevel(gun) >= SurvivalUpgrades.maxLevel) {
      final refund = 55 + wave * 10;
      _earnMoney(refund);
      _showMessage(
        '$source: ${gun.label.toUpperCase()} MAX +\$$refund'
        '${moneyBonus > 0 ? ' +\$$moneyBonus' : ''}',
      );
      return;
    }

    _levelUpWeapon(gun);
    if (autoEquipNewWeapons) {
      weapon = gun;
      _reloadTimer = 0;
      magazine[gun] = magazineSizeFor(gun);
    } else {
      magazine[gun] = magazineSizeFor(gun);
    }
    _showMessage(
      '$source: ${gun.label.toUpperCase()} UPGRADED → L${weaponLevel(gun)}'
      '${moneyBonus > 0 ? ' +\$$moneyBonus' : ''}',
    );
  }

  int magazineSizeFor(WeaponKind kind) =>
      kind.magazineSize + SurvivalUpgrades.weaponMagBonus(weaponLevel(kind));

  /// Number-key slots: 1–9 map to classes 0–8, 0 maps to class 9.
  /// Buys the class if locked and affordable; selects if already owned.
  bool selectClassByHotkey(int slot) {
    final classes = PlayerClass.values;
    if (slot < 0 || slot >= classes.length) return false;
    final kind = classes[slot];
    if (unlockedClasses.contains(kind)) {
      return selectClass(kind);
    }
    if (canUnlockClass(kind)) {
      final ok = unlockClass(kind);
      if (ok) _showMessage('BOUGHT ${kind.label.toUpperCase()}');
      return ok;
    }
    _showMessage(
      'NEED \$${kind.moneyCost} + ${kind.killCost} kills for ${kind.label}',
    );
    return false;
  }

  bool canUnlockAbility(PlayerClass kind) =>
      unlockedClasses.contains(kind) &&
      !unlockedAbilities.contains(kind) &&
      money >= kind.abilityMoneyCost &&
      kills >= kind.abilityKillCost;

  bool unlockAbility(PlayerClass kind) {
    if (unlockedAbilities.contains(kind)) return true;
    if (!canUnlockAbility(kind)) return false;
    money -= kind.abilityMoneyCost;
    kills -= kind.abilityKillCost;
    unlockedAbilities.add(kind);
    _showMessage('${kind.abilityName} UNLOCKED');
    notifyListeners();
    return true;
  }

  bool activateAbility() {
    if (gameOver || paused) return false;
    if (!unlockedAbilities.contains(playerClass)) {
      if (canUnlockAbility(playerClass)) {
        return unlockAbility(playerClass);
      }
      _showMessage(
        '${playerClass.abilityName}: \$${playerClass.abilityMoneyCost} + ${playerClass.abilityKillCost} kills',
      );
      return false;
    }
    if (_abilityCooldown > 0) {
        _showMessage(
          '${playerClass.abilityName} ${_abilityCooldown.toStringAsFixed(1)}s',
        );
      return false;
    }

    switch (playerClass) {
      case PlayerClass.survivor:
        _speedBuffTimer = 4.5 * abilityPower;
        _speedBuffMult = 1.55 + (abilityPower - 1) * 0.35;
        _heal(((abilityMastered ? 48 : 18) * abilityPower).round());
        if (abilityMastered) {
          _masteryPulseNearby(1.35, 140 * abilityPower);
        }
        _showMessage(abilityMastered ? 'NOVA RALLY' : 'ADRENALINE');
      case PlayerClass.scout:
        final from = player;
        player = _moveWithCollision(
          player,
          player + aimDirection * (1.35 * abilityPower),
          radius: 0.055,
        );
        tracers.add(BulletTracer(
          from,
          player,
          playerClass.color,
          strokeWidth: 5,
          life: 0.18,
        ));
        if (abilityMastered) {
          _damageAlongSegment(from, player, 180 * abilityPower, 0.32);
        }
        _showMessage(abilityMastered ? 'GUILLOTINE DASH' : 'DASH');
      case PlayerClass.tank:
        _pushNearbyEnemies(
          distance: 0.95 * abilityPower,
          force: 0.62 * abilityPower,
          damage: abilityMastered ? 95 * abilityPower : 0,
        );
        _invulnTimer = 1.85 * abilityPower;
        _vanguardSecondPushTimer = 1.85 * abilityPower;
        blastFlashes.add(BlastFlash(
          player,
          playerClass.color,
          radius: 0.9,
          life: 0.28,
        ));
        _showMessage(abilityMastered ? 'SEISMIC BASH' : 'SHOCK BASH');
      case PlayerClass.assault:
        _overdriveTimer = (abilityMastered ? 8.0 : 5.0) * abilityPower;
        if (abilityMastered) {
          magazine[weapon] = magazineSize;
          _reloadTimer = 0;
        }
        _showMessage(abilityMastered ? 'FULL AUTO RESET' : 'OVERDRIVE');
      case PlayerClass.berserker:
        _damageBuffTimer = 5.0 * abilityPower;
        _damageBuffMult =
            (abilityMastered ? 2.8 : 2.1) + (abilityPower - 1) * 0.4;
        _speedBuffTimer = 5.0 * abilityPower;
        _speedBuffMult = 1.4 + (abilityPower - 1) * 0.25;
        if (abilityMastered) {
          _heal((55 * abilityPower).round());
          _invulnTimer = math.max(_invulnTimer, 1.1);
        }
        _showMessage(abilityMastered ? 'CRIMSON ASCENSION' : 'BLOOD RAGE');
      case PlayerClass.reaper:
        final duration =
            (4.2 * abilityPower) * (abilityMastered ? 1.35 : 1.0);
        _scytheTimer = math.max(_scytheTimer, duration);
        _scytheSwingPhase = 0;
        _scytheSwingDir = 1;
        _scytheSwingAngle = -1.05;
        _scytheAttackProgress = 0;
        _scytheHitIds.clear();
        _speedBuffTimer = math.max(_speedBuffTimer, duration);
        _speedBuffMult = math.max(_speedBuffMult, 1.08);
        _reloadTimer = 0;
        if (abilityMastered) {
          _reaperOpeningCleave();
          _masteryPulseNearby(0.85, 70 * abilityPower);
        }
        _showMessage(
          abilityMastered ? 'HARVEST APOCALYPSE' : 'SOUL SCYTHE',
        );
      case PlayerClass.demolitions:
        final impact = _wrap(player + aimDirection * 1.5);
        final radius = 0.85 + (abilityPower - 1) * 0.15;
        _detonateWeaponBlast(
          impact,
          (140 * abilityPower).round(),
          radius,
          playerClass.color,
        );
        if (abilityMastered) {
          for (final dist in [2.0, 2.7]) {
            final impactN = _wrap(player + aimDirection * dist);
            _detonateWeaponBlast(
              impactN,
              (120 * abilityPower).round(),
              radius * 0.95,
              playerClass.color,
            );
          }
        }
        _cullDeadZombies();
        _showMessage(abilityMastered ? 'TRIPLE PAYLOAD' : 'SATCHEL');
      case PlayerClass.ghost:
        final from = player;
        _invulnTimer = 1.6 * abilityPower;
        player = _moveWithCollision(
          player,
          player + aimDirection * (1.1 * abilityPower),
          radius: 0.055,
        );
        if (abilityMastered) {
          _damageAlongSegment(from, player, 200 * abilityPower, 0.28);
        }
        _showMessage(abilityMastered ? 'RIFT GUILLOTINE' : 'PHASE SHIFT');
      case PlayerClass.juggernaut:
        var hit = 0;
        final radius = 1.1 + (abilityPower - 1) * 0.2;
        final dmg = 160 * abilityPower;
        for (final zombie in List<Zombie>.from(zombies)) {
          if (_wrappedDelta(player, zombie.position).distance <= radius) {
            if (_tryBlockDamage(zombie)) continue;
            zombie.health -= dmg * zombie.kind.damageTakenFactor;
            zombie.hitFlash = 0.12;
            hit++;
          }
        }
        blastFlashes.add(BlastFlash(player, playerClass.color, radius: radius));
        if (abilityMastered) {
          _aftershockTimer = 0.4;
          _aftershockRadius = radius * 1.05;
          _aftershockDamage = dmg * 0.95;
        }
        _cullDeadZombies();
        _showMessage(
          abilityMastered
              ? 'TECTONIC AFTERSHOCK ($hit)'
              : 'SHOCKWAVE ($hit)',
        );
      case PlayerClass.ranger:
        final beamRange =
            _rayOcclusionDistance(player, aimDirection, 6.0);
        final hits = <({Zombie zombie, double along})>[];
        for (final zombie in zombies) {
          final along =
              _rayHitDistance(player, aimDirection, beamRange, zombie);
          if (along.isFinite) hits.add((zombie: zombie, along: along));
        }
        hits.sort((a, b) => a.along.compareTo(b.along));
        tracers.add(BulletTracer(
          player,
          player + aimDirection * beamRange,
          playerClass.color,
          strokeWidth: 5.5,
          life: 0.2,
        ));
        final shot = (abilityMastered ? 480 : 320) * abilityPower;
        for (final hit in hits) {
          if (_tryBlockDamage(hit.zombie)) continue;
          hit.zombie.health -= shot * hit.zombie.kind.damageTakenFactor;
          hit.zombie.hitFlash = 0.14;
          if (abilityMastered) {
            _applySlow(hit.zombie, duration: 4.5, factor: 0.18);
          }
        }
        _cullDeadZombies();
        _showMessage(abilityMastered ? 'GLACIAL ERASURE' : 'MARKED SHOT');
      case PlayerClass.commander:
        // Fresh squad rings up around the Commander.
        gunAllies.clear();
        final count = abilityMastered ? 5 : 3;
        final slots = _gunlineFormationOffsets(count);
        for (var i = 0; i < count; i++) {
          final offset = slots[i];
          final at = _wrap(player + offset);
          gunAllies.add(GunAlly(
            position: at,
            formationOffset: offset,
            health: 110 + wave * 5.0 + (abilityMastered ? 120 : 0),
            life: 22 * abilityPower,
          ));
          blastFlashes.add(BlastFlash(
            at,
            const Color(0xFFFFD54F),
            radius: 0.32,
            life: 0.28,
          ));
        }
        _showMessage(abilityMastered ? 'DEATH SQUAD' : 'GUNLINE');
    }

    _abilityCooldown = abilityCooldownMax;
    _sfx(AudioCue.ability);
    notifyListeners();
    return true;
  }

  void equip(WeaponKind kind) {
    if (!unlockedWeapons.contains(kind)) return;
    if (weapon == kind) return;
    _reloadTimer = 0;
    _shotCooldown = 0;
    weapon = kind;
    magazine.putIfAbsent(kind, () => magazineSizeFor(kind));
    _showMessage('${kind.rarity.label} ${kind.label}');
    notifyListeners();
  }

  void equipByHotkey(int slot) {
    final list = unlockedSorted;
    if (slot < 0 || slot >= list.length) return;
    equip(list[slot]);
  }

  void cycleWeapon(int direction) {
    final list = unlockedSorted;
    if (list.length <= 1) return;
    final index = list.indexOf(weapon);
    final next = (index + direction) % list.length;
    equip(list[next < 0 ? list.length - 1 : next]);
  }

  bool reload({bool auto = false}) {
    if (gameOver || paused) return false;
    if (_reloadTimer > 0) return false;
    final current = magazine[weapon] ?? 0;
    if (current >= magazineSize) {
      if (!auto) _showMessage('MAG FULL');
      return false;
    }
    _reloadTimer = effectiveReloadSeconds;
    _firing = false;
    if (classMastered && playerClass == PlayerClass.ghost) {
      _invulnTimer = math.max(_invulnTimer, 1.45);
    }
    if (!auto) _showMessage('RELOADING...');
    _sfx(AudioCue.reload);
    notifyListeners();
    return true;
  }

  void update(double rawDt) {
    if (paused || gameOver) return;
    final dt = rawDt.clamp(0.0, 0.05);

    _shotCooldown = math.max(0, _shotCooldown - dt);
    _damageFlash = math.max(0, _damageFlash - dt);
    notificationTimer = math.max(0, notificationTimer - dt);
    waveBannerTimer = math.max(0, waveBannerTimer - dt);
    _regenTimer += dt;
    _abilityCooldown = math.max(0, _abilityCooldown - dt);
    _shieldTimer = math.max(0, _shieldTimer - dt);
    _invulnTimer = math.max(0, _invulnTimer - dt);
    if (_vanguardSecondPushTimer > 0) {
      _vanguardSecondPushTimer -= dt;
      if (_vanguardSecondPushTimer <= 0) {
        _vanguardSecondPushTimer = 0;
        _pushNearbyEnemies(
          distance: 1.05 * abilityPower,
          force: 0.78 * abilityPower,
          damage: abilityMastered ? 130 * abilityPower : 18 * abilityPower,
        );
        blastFlashes.add(BlastFlash(
          player,
          const Color(0xFFFFE082),
          radius: 1.05,
          life: 0.3,
        ));
        _showMessage('VANGUARD REPRISE');
        _cullDeadZombies();
      }
    }
    _speedBuffTimer = math.max(0, _speedBuffTimer - dt);
    _damageBuffTimer = math.max(0, _damageBuffTimer - dt);
    _overdriveTimer = math.max(0, _overdriveTimer - dt);
    _scytheTimer = math.max(0, _scytheTimer - dt);
    _tickSoulScythe(dt);
    _lootHintTimer = math.max(0, _lootHintTimer - dt);
    _tickSoulBar(dt);
    _tickMasteryTimers(dt);
    if (_speedBuffTimer <= 0) _speedBuffMult = 1;
    if (_damageBuffTimer <= 0) _damageBuffMult = 1;

    if (_reloadTimer > 0) {
      _reloadTimer -= dt;
      if (_reloadTimer <= 0) {
        _reloadTimer = 0;
        magazine[weapon] = magazineSize;
        _showMessage('RELOADED');
      }
    }

    _updateCrates(dt);
    _updateChestRespawns(dt);
    _updateWorldLoot();
    _updatePlayer(dt);
    _recordPlayerTrail(dt);
    _regenHealth();
    _decayOverheal(dt);
    _updateWaves(dt);
    _updateZombies(dt);
    _tickNecroBadEnding(dt);
    _updateEnemyProjectiles(dt);
    _updateSkyHazards(dt);
    _updateCorpses(dt);
    _updatePoisonClouds(dt);
    _updateStickyGoos(dt);
    _updateFirePits(dt);
    _updateLaserCannons(dt);
    _updateGunAllies(dt);

    if (_firing) fire();
    for (final tracer in tracers) {
      tracer.life -= dt;
    }
    tracers.removeWhere((tracer) => tracer.life <= 0);
    for (final floater in damageFloaters) {
      floater.life -= dt;
      // Drift upward in world space while fading.
      floater.position = Offset(
        floater.position.dx,
        floater.position.dy - dt * 0.55,
      );
    }
    damageFloaters.removeWhere((f) => f.life <= 0);
    for (final blast in blastFlashes) {
      blast.life -= dt;
    }
    blastFlashes.removeWhere((blast) => blast.life <= 0);
    notifyListeners();
  }

  void _updatePlayer(double dt) {
    var screenMove = _moveInput;
    if (screenMove.distance > 1) {
      screenMove = screenMove / screenMove.distance;
    }
    final movement = Offset(
      screenMove.dx * screenRight.dx + screenMove.dy * screenDown.dx,
      screenMove.dx * screenRight.dy + screenMove.dy * screenDown.dy,
    );
    player = _moveWithCollision(
      player,
      player +
          movement *
              (effectiveMoveSpeed * _speedBuffMult * gooSlowFactor * dt),
      radius: 0.055,
    );
  }

  void _recordPlayerTrail(double dt) {
    _gameTime += dt;
    _playerHistory.add(player);
    _playerHistoryTime.add(_gameTime);
    while (_playerHistoryTime.isNotEmpty &&
        _gameTime - _playerHistoryTime.first > 1.2) {
      _playerHistory.removeAt(0);
      _playerHistoryTime.removeAt(0);
    }
  }

  Offset get _playerPosOneSecondAgo {
    if (_playerHistory.isEmpty) return player;
    final targetT = _gameTime - 1.0;
    var best = _playerHistory.first;
    var bestDiff = double.infinity;
    for (var i = 0; i < _playerHistory.length; i++) {
      final d = (_playerHistoryTime[i] - targetT).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = _playerHistory[i];
      }
    }
    return best;
  }

  bool _collides(Offset point, double radius) {
    for (final prop in props) {
      if ((point - prop.position).distance <= prop.radius + radius) {
        return true;
      }
    }
    for (final house in houses) {
      if (houseBlocksPoint(house, point, radius)) return true;
    }
    for (final chest in chests) {
      if (!chest.opened &&
          (point - chest.position).distance <= 0.14 + radius) {
        return true;
      }
    }
    return false;
  }

  Offset _moveWithCollision(Offset from, Offset to, {double radius = 0.055}) {
    final full = _wrap(to);
    if (!_collides(full, radius)) return full;
    final xOnly = _wrap(Offset(to.dx, from.dy));
    if (!_collides(xOnly, radius)) return xOnly;
    final yOnly = _wrap(Offset(from.dx, to.dy));
    if (!_collides(yOnly, radius)) return yOnly;
    return from;
  }

  Offset _wrap(Offset p) {
    final span = arenaHalf * 2;
    var x = p.dx;
    var y = p.dy;
    while (x > arenaHalf) {
      x -= span;
    }
    while (x < -arenaHalf) {
      x += span;
    }
    while (y > arenaHalf) {
      y -= span;
    }
    while (y < -arenaHalf) {
      y += span;
    }
    return Offset(x, y);
  }

  /// 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right.
  /// Prefer top corners so meteors dive in from the sky edge of the view.
  int _rollMeteorScreenCorner() {
    if (_random.nextDouble() < 0.8) return _random.nextInt(2);
    return 2 + _random.nextInt(2);
  }

  /// Shortest vector from [from] to [to] on the wrapping map.
  Offset _wrappedDelta(Offset from, Offset to) {
    final span = arenaHalf * 2;
    var dx = to.dx - from.dx;
    var dy = to.dy - from.dy;
    if (dx > arenaHalf) dx -= span;
    if (dx < -arenaHalf) dx += span;
    if (dy > arenaHalf) dy -= span;
    if (dy < -arenaHalf) dy += span;
    return Offset(dx, dy);
  }

  void _regenHealth() {
    if (health >= maxHealth) {
      _regenTimer = 0;
      return;
    }
    final interval = healthRegenInterval;
    while (_regenTimer >= interval && health < maxHealth) {
      _regenTimer -= interval;
      health += 1;
    }
  }

  void _heal(int amount) {
    if (amount <= 0 || health >= maxHealth) return;
    health = math.min(maxHealth, health + amount);
  }

  /// Crate heals can push past max HP; excess drains over time.
  void _healFromCrate(int amount) {
    if (amount <= 0) return;
    final cap = math.max(maxHealth, (maxHealth * 2).round());
    health = math.min(cap, health + amount);
  }

  void _decayOverheal(double dt) {
    if (health <= maxHealth) {
      _overhealDecayAcc = 0;
      return;
    }
    _overhealDecayAcc += overhealDecayPerSecond * dt;
    final lose = _overhealDecayAcc.floor();
    if (lose <= 0) return;
    _overhealDecayAcc -= lose;
    health = math.max(maxHealth, health - lose);
  }

  void _tickSoulBar(double dt) {
    if (playerClass != PlayerClass.reaper || gameOver) return;
    if (_soulCharge <= 0) {
      _soulCharge = 0;
      return;
    }
    _soulCharge = math.max(0, _soulCharge - soulBarDrainPerSecond * dt);
  }

  /// Flat heal when a Soul Bar fills — scales with Reaper class level.
  int get soulSurgeHealAmount {
    final level = classLevel(PlayerClass.reaper);
    final base = 18 + level * 12; // L0=18 … L5=78
    return classMastered ? base + 15 : base;
  }

  void _tickMasteryTimers(double dt) {
    if (_stormTimer > 0) _stormTimer = math.max(0, _stormTimer - dt);
    if (_hunterMarkTimer > 0) {
      _hunterMarkTimer = math.max(0, _hunterMarkTimer - dt);
      if (_hunterMarkTimer <= 0) _hunterMarkId = null;
    }
    if (_weaponHeat > 0 &&
        !(weaponMastered &&
            weapon.mastery == WeaponMastery.overheat &&
            _firing)) {
      _weaponHeat = math.max(0, _weaponHeat - dt * 0.55);
    }
    if (_clusterBombs.isNotEmpty) {
      for (var i = _clusterBombs.length - 1; i >= 0; i--) {
        final bomb = _clusterBombs[i];
        final next = bomb.timer - dt;
        if (next <= 0) {
          _detonateWeaponBlast(
            bomb.at,
            bomb.damage,
            bomb.radius,
            bomb.color,
            ignite: weapon.ignites,
          );
          _clusterBombs.removeAt(i);
        } else {
          _clusterBombs[i] = (
            at: bomb.at,
            timer: next,
            radius: bomb.radius,
            damage: bomb.damage,
            color: bomb.color,
          );
        }
      }
      if (_clusterBombs.isNotEmpty) _cullDeadZombies();
    }

    if (classMastered && playerClass == PlayerClass.juggernaut) {
      _masteryPulseTimer -= dt;
      if (_masteryPulseTimer <= 0) {
        _masteryPulseTimer = 3.2;
        if (zombies.isNotEmpty) {
          _masteryPulseNearby(1.15, 70 + wave * 1.4);
          _cullDeadZombies();
        }
      }
    } else {
      _masteryPulseTimer = 0;
    }

    if (_aftershockTimer > 0) {
      _aftershockTimer -= dt;
      if (_aftershockTimer <= 0) {
        _aftershockTimer = 0;
        _masteryPulseNearby(_aftershockRadius, _aftershockDamage);
        blastFlashes.add(BlastFlash(
          player,
          playerClass.color,
          radius: _aftershockRadius,
          life: 0.3,
        ));
        _cullDeadZombies();
        _showMessage('AFTERSHOCK');
      }
    }
  }

  void _masteryPulseNearby(double radius, double damage) {
    _masteryPulseAt(player, radius, damage);
  }

  void _masteryPulseAt(Offset center, double radius, double damage) {
    if (radius <= 0 || damage <= 0) return;
    for (final zombie in List<Zombie>.from(zombies)) {
      if (_wrappedDelta(center, zombie.position).distance > radius) continue;
      if (_tryBlockDamage(zombie)) continue;
      zombie.health -= damage * zombie.kind.damageTakenFactor;
      zombie.hitFlash = 0.1;
      _spawnDamageFloater(zombie.position, damage * zombie.kind.damageTakenFactor);
    }
    blastFlashes.add(BlastFlash(
      center,
      playerClass.color,
      radius: radius,
      life: 0.22,
    ));
  }

  void _damageAlongSegment(
    Offset from,
    Offset to,
    double damage,
    double hitRadius,
  ) {
    for (final zombie in List<Zombie>.from(zombies)) {
      if (!_segmentHitsPoint(from, to, zombie.position, hitRadius)) continue;
      if (_tryBlockDamage(zombie)) continue;
      zombie.health -= damage * zombie.kind.damageTakenFactor;
      zombie.hitFlash = 0.12;
    }
    _cullDeadZombies();
  }

  bool _segmentHitsPoint(
    Offset from,
    Offset to,
    Offset point,
    double hitRadius,
  ) {
    final delta = to - from;
    final len2 = delta.distanceSquared;
    if (len2 < 1e-8) {
      return (point - from).distance <= hitRadius;
    }
    final toPoint = point - from;
    var t = (toPoint.dx * delta.dx + toPoint.dy * delta.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final closest = from + delta * t;
    return (point - closest).distance <= hitRadius;
  }

  void _updateWaves(double dt) {
    if (!waveActive) {
      nextWaveTimer -= dt;
      if (nextWaveTimer <= 0) _startWave();
      return;
    }

    if (_remainingToSpawn > 0) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnZombie();
        _remainingToSpawn--;
        _spawnTimer = math.max(0.22, 0.75 - wave * 0.02);
      }
    } else if (zombies.isEmpty) {
      waveActive = false;
      badEndingActive = false;
      _necroSoloTimer = 0;
      bestWave = math.max(bestWave, wave);
      nextWaveTimer = 5;
      final bonus = 20 + wave * 4;
      _earnMoney(bonus);
      _showMessage('WAVE CLEARED  +\$$bonus');
    }
  }

  bool get _isOnlyNecroAndMinions {
    if (zombies.isEmpty) return false;
    var hasNecro = false;
    for (final z in zombies) {
      if (z.kind == ZombieKind.necromancer) {
        hasNecro = true;
      } else if (!z.isNecroMinion) {
        return false;
      }
    }
    return hasNecro;
  }

  void _tickNecroBadEnding(double dt) {
    if (badEndingCutscene || gameOver) return;
    if (badEndingActive) {
      _tickAscendedMiniBossSpawns(dt);
      return;
    }
    if (_remainingToSpawn == 0 && _isOnlyNecroAndMinions) {
      final before = _necroSoloTimer;
      _necroSoloTimer += dt;
      if (before < 0.05 && _necroSoloTimer >= 0.05) {
        _showMessage('THE DEAD GO QUIET...');
      } else if (before < 1 && _necroSoloTimer >= 1) {
        _showMessage('SOMETHING STIRS...');
      }
      if (_necroSoloTimer >= 2) {
        _necroSoloTimer = 0;
        badEndingCutscene = true;
        paused = true;
        _showMessage('THE BAD ENDING');
        _sfx(AudioCue.bossAlert);
      }
    } else {
      _necroSoloTimer = 0;
    }
  }

  void _tickAscendedMiniBossSpawns(double dt) {
    if (!zombies.any((z) => z.isAscendedNecromancer)) return;
    _ascendedMiniSpawnTimer -= dt;
    if (_ascendedMiniSpawnTimer > 0) return;
    if (zombies.length >= 38) {
      _ascendedMiniSpawnTimer = 3.5;
      return;
    }
    final pool = _availableMiniBossKinds;
    final mini = pool[_random.nextInt(pool.length)];
    _spawnZombie(forcedKind: mini, at: _edgeSpawnPoint());
    _showMessage('NECRO SUMMONS ${mini.label.toUpperCase()}');
    _ascendedMiniSpawnTimer = 7 + _random.nextDouble() * 4;
  }

  /// Player dismissed the bad-ending cutscene — ascend and open the gauntlet.
  void resolveBadEnding() {
    if (!badEndingCutscene) return;
    badEndingCutscene = false;
    badEndingActive = true;
    paused = false;
    _remainingToSpawn = 0;
    waveActive = true;
    _necroSoloTimer = 0;

    for (final necro in zombies.where((z) => z.kind == ZombieKind.necromancer)) {
      necro.isAscendedNecromancer = true;
      necro.damageMult = 4.2;
      necro.speed = math.max(necro.speed, 0.26);
      final hp = 8200 + wave * 180.0;
      necro.maxHealth = hp;
      necro.health = hp;
      necro.abilityCooldown = 0.55;
      necro.specialTimer = 6;
      necro.isGhost = false;
    }

    final roster = [...allMiniBossKinds, ...allBossKinds];
    for (var i = 0; i < roster.length; i++) {
      final ang = (i / roster.length) * math.pi * 2;
      final at = Offset(math.cos(ang) * 1.85, math.sin(ang) * 1.85);
      _spawnZombie(forcedKind: roster[i], at: _wrap(at));
    }
    _ascendedMiniSpawnTimer = 8;
    waveBannerTimer = 3.2;
    _showMessage('THE BAD ENDING — EVERY BOSS AWAKENS');
    _sfx(AudioCue.bossAlert);
    notifyListeners();
  }

  void _startWave() {
    wave++;
    waveActive = true;
    waveBannerTimer = 2.4;
    _remainingToSpawn = 6 + wave * 3;
    if (wave % 5 == 0) _remainingToSpawn += 4;
    var eliteSpawned = false;

    if (wave % 20 == 0) {
      _spawnZombie(forcedKind: ZombieKind.shadowRonin, at: Offset.zero);
      _remainingToSpawn = math.max(4, _remainingToSpawn ~/ 2);
      _showMessage('SHADOW RONIN HAS ENTERED THE ARENA');
      eliteSpawned = true;
    }
    if (wave % 10 == 0) {
      _spawnZombie(forcedKind: ZombieKind.citadelTower, at: Offset.zero);
      _remainingToSpawn = math.max(4, _remainingToSpawn ~/ 2);
      final tier = _citadelTier;
      _showMessage(tier <= 1
          ? 'CITADEL RISES AT THE CENTER'
          : 'CITADEL MARK $tier RISES — STRONGER & FASTER');
      eliteSpawned = true;
    } else if (wave % 5 == 0) {
      // Blazeburst debuts at wave 15, then joins the every-5 rotation.
      final mini = wave < 15
          ? switch ((wave ~/ 5) % 3) {
              0 => ZombieKind.siegeBehemoth,
              1 => ZombieKind.broodQueen,
              _ => ZombieKind.ironColossus,
            }
          : switch ((wave ~/ 5) % 4) {
              0 => ZombieKind.siegeBehemoth,
              1 => ZombieKind.broodQueen,
              2 => ZombieKind.ironColossus,
              _ => ZombieKind.blazeburst,
            };
      _spawnZombie(forcedKind: mini);
      _showMessage(wave == 15 && mini == ZombieKind.blazeburst
          ? 'BLAZEBURST IGNITES THE ARENA'
          : 'MINI-BOSS: ${mini.label.toUpperCase()}');
      eliteSpawned = true;
    }

    // Laser Overseer: debut waves 11–12, then packs of 2+ from 15 / every 5.
    if (wave == 11 || wave == 12) {
      _spawnZombie(forcedKind: ZombieKind.laserOverseer);
      _showMessage('LASER OVERSEER DEPLOYS CANNONS');
      eliteSpawned = true;
    } else if (wave >= 15 && wave % 5 == 0) {
      _spawnZombie(forcedKind: ZombieKind.laserOverseer);
      _spawnZombie(forcedKind: ZombieKind.laserOverseer);
      _showMessage('DUAL LASER OVERSEERS — CANNONS ONLINE');
      eliteSpawned = true;
    }

    // Void Sovereign: wave 21 debut, then every 25 waves.
    if (wave == 21 || wave % 25 == 0) {
      _spawnZombie(forcedKind: ZombieKind.voidSovereign, at: Offset.zero);
      _remainingToSpawn = math.max(3, _remainingToSpawn ~/ 2);
      _showMessage('VOID SOVEREIGN DESCENDS — DODGE EVERYTHING');
      eliteSpawned = true;
    }
    _sfx(eliteSpawned ? AudioCue.bossAlert : AudioCue.wave);
    _spawnTimer = 0;
  }

  /// Citadel appearance count: wave 10 → 1, 20 → 2, 30 → 3, …
  int get _citadelTier => math.max(1, wave ~/ 10);

  /// Extra HP / damage multiplier for repeated citadel fights.
  double get _citadelPowerScale {
    final tier = _citadelTier;
    return 1 + (tier - 1) * 0.42;
  }

  void _spawnZombie({
    ZombieKind? forcedKind,
    Offset? at,
    bool asNecroMinion = false,
  }) {
    final position = at ?? _edgeSpawnPoint();
    final kind = forcedKind ?? _rollZombieKind();
    _addZombie(kind, position, asNecroMinion: asNecroMinion);

    // Globlings rush in packs.
    if (forcedKind == null && kind == ZombieKind.globling) {
      final extras = 3 + _random.nextInt(3); // 3–5 extras → 4–6 total
      for (var i = 0; i < extras; i++) {
        if (zombies.length >= 42) break;
        final jitter = Offset(
          (_random.nextDouble() - 0.5) * 0.55,
          (_random.nextDouble() - 0.5) * 0.55,
        );
        _addZombie(ZombieKind.globling, _wrap(position + jitter));
      }
      _remainingToSpawn = math.max(0, _remainingToSpawn - extras);
      if (_random.nextDouble() < 0.45) {
        _showMessage('GLOB SWARM');
      }
    }
    // Hammer Maulers sometimes arrive with a partner.
    if (forcedKind == null && kind == ZombieKind.hammerMauler) {
      if (_random.nextDouble() < 0.4) {
        final jitter = Offset(
          (_random.nextDouble() - 0.5) * 0.7,
          (_random.nextDouble() - 0.5) * 0.7,
        );
        if (zombies.length < 42) {
          _addZombie(ZombieKind.hammerMauler, _wrap(position + jitter));
          _remainingToSpawn = math.max(0, _remainingToSpawn - 1);
        }
      }
    }
  }

  void _addZombie(
    ZombieKind kind,
    Offset position, {
    bool asNecroMinion = false,
  }) {
    var hp = kind.baseHp(wave);
    var speed = kind.baseSpeed(wave);
    if (kind == ZombieKind.citadelTower) {
      hp *= _citadelPowerScale;
    }
    final ghost = !kind.isBoss &&
        !kind.isMiniBoss &&
        _random.nextDouble() < 0.20;
    if (ghost) {
      speed *= 2.4;
    }
    final zombie = Zombie(
      id: _nextZombieId++,
      kind: kind,
      position: position,
      health: hp,
      maxHealth: hp,
      speed: speed,
      reward: kind == ZombieKind.citadelTower
          ? (kind.reward(wave) * _citadelPowerScale).round()
          : kind.reward(wave),
    )
      ..isGhost = ghost
      ..isNecroMinion = asNecroMinion
      ..abilityCooldown = kind == ZombieKind.citadelTower
          ? math.max(0.25, 0.55 - (_citadelTier - 1) * 0.08)
          : 0.6 + _random.nextDouble() * 1.2
      ..specialTimer = kind == ZombieKind.shadowRonin
          ? 20
          : (kind == ZombieKind.citadelTower ? _citadelTier.toDouble() : 0);
    zombies.add(zombie);
    if (kind == ZombieKind.laserOverseer) {
      _deployLaserCannons(zombie);
    }
  }

  void _deployLaserCannons(Zombie owner) {
    final top = _pickLaserCannonSlot(preferTop: true);
    final left = _pickLaserCannonSlot(preferTop: false, avoid: [top]);
    final topTarget = _rollLaserStrikePoint();
    final leftTarget = _rollLaserStrikePoint();
    laserCannons.add(LaserCannon(
      ownerId: owner.id,
      position: top,
      target: topTarget,
      aim: _aimToward(top, topTarget),
      phaseTimer: 1.4 + _random.nextDouble() * 0.7,
    ));
    laserCannons.add(LaserCannon(
      ownerId: owner.id,
      position: left,
      target: leftTarget,
      aim: _aimToward(left, leftTarget),
      phaseTimer: 2.6 + _random.nextDouble() * 0.9,
    ));
  }

  Offset _aimTowardPlayer(Offset from) => _aimToward(from, player);

  Offset _aimToward(Offset from, Offset to) {
    final delta = to - from;
    final dist = delta.distance;
    if (dist < 1e-4) return const Offset(1, 0);
    return delta / dist;
  }

  /// Random arena point for the next laser strike (not player-tracking).
  Offset _rollLaserStrikePoint() {
    final half = arenaHalf - 0.55;
    return Offset(
      (_random.nextDouble() * 2 - 1) * half,
      (_random.nextDouble() * 2 - 1) * half,
    );
  }

  void _lockLaserOnRandomSpot(LaserCannon cannon) {
    cannon.target = _rollLaserStrikePoint();
    cannon.aim = _aimToward(cannon.position, cannon.target);
  }

  /// Non-overlapping slot on the top edge ([preferTop]) or left edge.
  Offset _pickLaserCannonSlot({
    required bool preferTop,
    List<Offset> avoid = const [],
  }) {
    final candidates = preferTop
        ? _laserTopSlots()
        : _laserLeftSlots();
    final occupied = [
      ...laserCannons.map((c) => c.position),
      ...avoid,
    ];
    final free = candidates.where((slot) {
      for (final other in occupied) {
        if ((slot - other).distance < LaserCannon.minSpacing) return false;
      }
      return true;
    }).toList();
    if (free.isNotEmpty) {
      return free[_random.nextInt(free.length)];
    }
    // Fallback: farthest from current cannons among preferred edge.
    var best = candidates.first;
    var bestScore = -1.0;
    for (final slot in candidates) {
      var nearest = double.infinity;
      for (final other in occupied) {
        nearest = math.min(nearest, (slot - other).distance);
      }
      if (nearest > bestScore) {
        bestScore = nearest;
        best = slot;
      }
    }
    return best;
  }

  List<Offset> _laserTopSlots() {
    const pad = 0.55;
    final half = arenaHalf - pad;
    final span = half * 2;
    return [
      for (var i = 0; i < 7; i++)
        Offset(-half + 0.35 + i * ((span - 0.7) / 6), -half),
    ];
  }

  List<Offset> _laserLeftSlots() {
    const pad = 0.55;
    final half = arenaHalf - pad;
    final span = half * 2;
    return [
      for (var i = 0; i < 7; i++)
        Offset(-half, -half + 0.35 + i * ((span - 0.7) / 6)),
    ];
  }

  void _updateLaserCannons(double dt) {
    // Drop turrets whose overseer died.
    final livingOwners = {
      for (final z in zombies)
        if (z.kind == ZombieKind.laserOverseer) z.id,
    };
    laserCannons.removeWhere((c) => !livingOwners.contains(c.ownerId));

    for (final cannon in laserCannons) {
      cannon.phaseTimer -= dt;
      switch (cannon.phase) {
        case LaserCannonPhase.charging:
          // Keep aim locked on the pre-picked random spot (red telegraph).
          cannon.aim = _aimToward(cannon.position, cannon.target);
          if (cannon.phaseTimer <= 0) {
            cannon.phase = LaserCannonPhase.firing;
            cannon.phaseTimer = LaserCannon.fireDuration;
            cannon.aim = _aimToward(cannon.position, cannon.target);
          }
        case LaserCannonPhase.firing:
          // Aim stays locked for the full burst (set when charge completed).
          final halfW = LaserCannon.beamHalfWidth;
          final dist = _pointToSegmentDistance(
            player,
            cannon.position,
            cannon.beamEnd,
          );
          if (dist <= halfW + 0.04) {
            final dps = 48 + wave * 2.4;
            _hurtPlayer(dps * dt, allowFractional: true);
            if (gameOver) return;
          }
          for (final ally in gunAllies) {
            if (ally.health <= 0) continue;
            final allyDist = _pointToSegmentDistance(
              ally.position,
              cannon.position,
              cannon.beamEnd,
            );
            if (allyDist <= halfW + GunAlly.hitRadius) {
              _hurtGunAlly(ally, (48 + wave * 2.4) * dt);
            }
          }
          if (cannon.phaseTimer <= 0) {
            cannon.phase = LaserCannonPhase.relocating;
            cannon.phaseTimer = LaserCannon.relocateDuration;
          }
        case LaserCannonPhase.relocating:
          if (cannon.phaseTimer <= 0) {
            final next = _pickLaserCannonSlot(
              preferTop: false,
              avoid: [
                for (final other in laserCannons)
                  if (!identical(other, cannon)) other.position,
              ],
            );
            blastFlashes.add(BlastFlash(
              cannon.position,
              const Color(0xFFFF00E5),
              radius: 0.35,
              life: 0.2,
            ));
            cannon.position = next;
            _lockLaserOnRandomSpot(cannon);
            blastFlashes.add(BlastFlash(
              next,
              const Color(0xFF00E5FF),
              radius: 0.4,
              life: 0.25,
            ));
            cannon.phase = LaserCannonPhase.cooldown;
            cannon.phaseTimer = LaserCannon.cooldownDuration;
          }
        case LaserCannonPhase.cooldown:
          if (cannon.phaseTimer <= 0) {
            _lockLaserOnRandomSpot(cannon);
            cannon.phase = LaserCannonPhase.charging;
            cannon.phaseTimer = LaserCannon.chargeDuration;
          }
      }
    }
  }

  double _pointToSegmentDistance(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 < 1e-8) return (point - a).distance;
    var t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final closest = a + ab * t;
    return (point - closest).distance;
  }

  Offset _edgeSpawnPoint() {
    final side = _random.nextInt(4);
    final edge = (_random.nextDouble() * 2 - 1) * (arenaHalf - 0.2);
    final spawnPad = arenaHalf + 0.18;
    return switch (side) {
      0 => Offset(-spawnPad, edge),
      1 => Offset(spawnPad, edge),
      2 => Offset(edge, -spawnPad),
      _ => Offset(edge, spawnPad),
    };
  }

  Offset _moveEnemy(Zombie zombie, Offset from, Offset to) {
    if (zombie.isGhost) return _wrap(to);
    return _moveWithCollision(from, to, radius: zombie.radius);
  }

  bool _bulletPhasesThrough(Zombie zombie) =>
      zombie.isGhost && _random.nextDouble() < 0.30;

  void _pushNearbyEnemies({
    required double distance,
    required double force,
    double damage = 0,
  }) {
    for (final zombie in zombies) {
      final delta = _wrappedDelta(player, zombie.position);
      final dist = delta.distance;
      if (dist > distance || dist < 1e-5) continue;
      final dir = delta / dist;
      zombie.position = _wrap(zombie.position + dir * force);
      zombie.clearWindUp();
      zombie.attackAnim = 0.55;
      if (damage > 0 && !_tryBlockDamage(zombie)) {
        zombie.health -= damage * zombie.kind.damageTakenFactor;
        zombie.hitFlash = 0.12;
      }
    }
  }

  /// Gunline slots facing the nearest enemy (falls back to aim).
  List<Offset> _gunlineFormationOffsets(int count) {
    final forward = _nearestEnemyDirection();
    final right = Offset(-forward.dy, forward.dx);
    const depth = 0.78;
    if (count >= 5) {
      return [
        forward * depth + right * -0.70,
        forward * depth + right * -0.35,
        forward * depth,
        forward * depth + right * 0.35,
        forward * depth + right * 0.70,
      ];
    }
    if (count >= 4) {
      return [
        forward * depth + right * -0.58,
        forward * depth + right * -0.2,
        forward * depth + right * 0.2,
        forward * depth + right * 0.58,
      ];
    }
    return [
      forward * depth + right * -0.48,
      forward * depth,
      forward * depth + right * 0.48,
    ];
  }

  Offset _nearestEnemyDirection() {
    if (zombies.isEmpty) {
      if (aimDirection.distance > 1e-4) {
        return aimDirection / aimDirection.distance;
      }
      return const Offset(0, -1);
    }
    Zombie? nearest;
    var best = double.infinity;
    for (final zombie in zombies) {
      final d = _wrappedDelta(player, zombie.position).distance;
      if (d < best) {
        best = d;
        nearest = zombie;
      }
    }
    final delta = _wrappedDelta(player, nearest!.position);
    if (delta.distance < 1e-4) return const Offset(0, -1);
    return delta / delta.distance;
  }

  /// Nearest living threat for a zombie: Commander or a gunner.
  Offset _zombieHuntPoint(Zombie zombie) {
    var best = player;
    var bestScore = _wrappedDelta(zombie.position, player).distance;
    for (final ally in gunAllies) {
      if (ally.health <= 0) continue;
      final d = _wrappedDelta(zombie.position, ally.position).distance;
      // Slight bias so gunners draw aggro when similarly close.
      final score = d * 0.88;
      if (score < bestScore) {
        bestScore = score;
        best = ally.position;
      }
    }
    return best;
  }

  void _hurtGunAlly(GunAlly ally, double amount) {
    if (amount <= 0 || ally.health <= 0) return;
    ally.health -= amount;
    ally.hitFlash = 0.22;
    if (ally.health <= 0) {
      ally.health = 0;
      ally.life = 0;
      blastFlashes.add(BlastFlash(
        ally.position,
        const Color(0xFFFFD54F),
        radius: 0.28,
        life: 0.22,
      ));
      _showMessage('GUNNER DOWN');
    }
  }

  void _hurtGunAlliesInRadius(Offset center, double radius, double damage) {
    for (final ally in List<GunAlly>.from(gunAllies)) {
      if (ally.health <= 0) continue;
      if (_wrappedDelta(ally.position, center).distance <= radius + GunAlly.hitRadius) {
        _hurtGunAlly(ally, damage);
      }
    }
  }

  GunAlly? _nearestLivingGunAlly(Offset from, double maxDist) {
    GunAlly? best;
    var bestDist = maxDist;
    for (final ally in gunAllies) {
      if (ally.health <= 0) continue;
      final d = _wrappedDelta(from, ally.position).distance;
      if (d < bestDist) {
        bestDist = d;
        best = ally;
      }
    }
    return best;
  }

  /// True if this zombie bashed a nearby gunner (sets attack cooldown).
  bool _tryMeleeGunAlly(Zombie zombie) {
    if (zombie.attackCooldown > 0 || gunAllies.isEmpty) return false;
    final reach =
        zombie.radius + zombie.kind.meleeReach + GunAlly.hitRadius + 0.04;
    final ally = _nearestLivingGunAlly(zombie.position, reach);
    if (ally == null) return false;
    final delta = _wrappedDelta(zombie.position, ally.position);
    zombie.attackAnim = 1.0;
    zombie.attackFacing =
        delta.distance > 1e-4 ? delta / delta.distance : zombie.attackFacing;
    _hurtGunAlly(
      ally,
      zombie.kind.meleeDamage.toDouble() * zombie.damageMult,
    );
    zombie.attackCooldown = zombie.kind == ZombieKind.hammerMauler
        ? 1.25
        : (zombie.brute ? 1.05 : 0.7);
    return true;
  }

  void _updateGunAllies(double dt) {
    final fireRate = classMastered && playerClass == PlayerClass.commander
        ? 0.12
        : 0.36;
    final dmgMult = abilityMastered && playerClass == PlayerClass.commander
        ? 2.1
        : 1.0;
    // Re-face the nearest enemy every tick so the line always aims as a unit.
    final slots = _gunlineFormationOffsets(gunAllies.length);
    for (var i = 0; i < gunAllies.length; i++) {
      final ally = gunAllies[i];
      if (i < slots.length) {
        ally.formationOffset = slots[i];
      }
      ally.life -= dt;
      ally.fireCooldown = math.max(0, ally.fireCooldown - dt);
      ally.hitFlash = math.max(0, ally.hitFlash - dt);

      // Hold the formation slot relative to the Commander.
      final desired = _wrap(player + ally.formationOffset);
      final toSlot = _wrappedDelta(ally.position, desired);
      if (toSlot.distance > 0.001) {
        // Snap-follow so the ring stays tight even when dashing.
        final step = math.min(1.0, 18 * dt);
        ally.position = _wrap(ally.position + toSlot * step);
      }

      if (ally.fireCooldown > 0 || ally.health <= 0 || zombies.isEmpty) {
        continue;
      }
      Zombie? target;
      var best = 4.5;
      for (final zombie in zombies) {
        final d = _wrappedDelta(ally.position, zombie.position).distance;
        if (d < best) {
          best = d;
          target = zombie;
        }
      }
      if (target == null) continue;
      final delta = _wrappedDelta(ally.position, target.position);
      if (delta.distance < 1e-4) continue;
      final dir = delta / delta.distance;
      ally.aim = dir;
      ally.fireCooldown = fireRate;
      final range = _rayOcclusionDistance(ally.position, dir, 4.8);
      final shot = (38 + wave * 1.6) * dmgMult;
      tracers.add(BulletTracer(
        ally.position,
        ally.position + dir * range,
        const Color(0xFFFFD54F),
        strokeWidth: 3.4,
        life: 0.1,
        damage: shot.round(),
      ));
      for (final zombie in zombies) {
        final along = _rayHitDistance(ally.position, dir, range, zombie);
        if (!along.isFinite) continue;
        if (_tryBlockDamage(zombie)) continue;
        if (_bulletPhasesThrough(zombie)) continue;
        final dealt = shot * zombie.kind.damageTakenFactor;
        zombie.health -= dealt;
        zombie.hitFlash = 0.08;
        _spawnDamageFloater(
          zombie.position,
          dealt,
          color: const Color(0xFFFFD54F),
        );
      }
    }
    gunAllies.removeWhere((a) => a.life <= 0 || a.health <= 0);
    _cullDeadZombies();
  }

  ZombieKind _rollZombieKind() {
    // Heavy melee / close-range bias — ranged kinds appear sparsely.
    final weighted = <ZombieKind>[
      ZombieKind.walker,
      ZombieKind.walker,
      ZombieKind.walker,
      ZombieKind.walker,
      ZombieKind.walker,
      ZombieKind.walker,
      ZombieKind.runner,
      ZombieKind.runner,
      ZombieKind.runner,
      ZombieKind.runner,
      ZombieKind.runner,
    ];
    if (wave >= 2) {
      weighted.addAll([
        ZombieKind.globling,
        ZombieKind.globling,
        ZombieKind.globling,
        ZombieKind.globling,
        ZombieKind.exploder,
        ZombieKind.exploder,
        ZombieKind.jumper,
        ZombieKind.jumper,
        ZombieKind.jumper,
        // rare ranged
        ZombieKind.spitter,
        ZombieKind.boltSlinger,
      ]);
    }
    if (wave >= 3) {
      weighted.addAll([
        ZombieKind.brute,
        ZombieKind.brute,
        ZombieKind.brute,
        ZombieKind.screamer,
        ZombieKind.screamer,
        ZombieKind.stalker,
        ZombieKind.stalker,
        ZombieKind.stalker,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        // rare ranged
        ZombieKind.acidBomber,
        ZombieKind.toxinDart,
      ]);
    }
    if (wave >= 4) {
      weighted.addAll([
        ZombieKind.wraith,
        ZombieKind.wraith,
        ZombieKind.wraith,
        ZombieKind.jumper,
        ZombieKind.brute,
        // rare ranged
        ZombieKind.skyCaller,
        ZombieKind.frostbite,
        ZombieKind.knifeThrower,
      ]);
    }
    if (wave >= 5) {
      weighted.addAll([
        ZombieKind.bloater,
        ZombieKind.bloater,
        ZombieKind.bloater,
        ZombieKind.shieldBearer,
        ZombieKind.shieldBearer,
        ZombieKind.shieldBearer,
        ZombieKind.walker,
        ZombieKind.runner,
        // rare ranged / support
        ZombieKind.necromancer,
        ZombieKind.harpooner,
      ]);
    }
    if (wave >= 7) {
      weighted.addAll([
        ZombieKind.hiveMother,
        ZombieKind.hiveMother,
      ]);
    }
    if (wave >= 6) {
      weighted.addAll([
        ZombieKind.swarmling,
        ZombieKind.swarmling,
        ZombieKind.swarmling,
        ZombieKind.swarmling,
        ZombieKind.boneGolem,
        ZombieKind.boneGolem,
        ZombieKind.boneGolem,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.pyrofiend,
        ZombieKind.pyrofiend,
        ZombieKind.pyrofiend,
        // rare ranged / support
        ZombieKind.plagueDoctor,
        ZombieKind.hasteMage,
        ZombieKind.sharpshooter,
        ZombieKind.knifeFanatic,
      ]);
    }
    if (wave >= 8) {
      weighted.addAll([
        ZombieKind.stalker,
        ZombieKind.stalker,
        ZombieKind.wraith,
        ZombieKind.wraith,
        ZombieKind.riftWalker,
        ZombieKind.riftWalker,
        ZombieKind.riftWalker,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.hammerMauler,
        ZombieKind.boneGolem,
        ZombieKind.brute,
        // rare ranged
        ZombieKind.necromancer,
        ZombieKind.railSniper,
        ZombieKind.hexWitch,
        ZombieKind.missileer,
      ]);
    }
    return weighted[_random.nextInt(weighted.length)];
  }

  void _updateZombies(double dt) {
    for (final zombie in zombies) {
      zombie.speedBoost = 0;
      zombie.attackAnim = math.max(0, zombie.attackAnim - dt * 3.2);
      _tickStatusEffects(zombie, dt);
    }
    _spreadVirus(dt);

    for (final screamer
        in zombies.where((z) => z.kind == ZombieKind.screamer)) {
      for (final other in zombies) {
        if (other.id == screamer.id) continue;
        if (_wrappedDelta(other.position, screamer.position).distance < 0.75) {
          other.speedBoost = math.max(other.speedBoost, 0.35);
        }
      }
    }

    // Haste Mage: enormous ring makes allies 3x faster.
    const mageAuraRadius = 2.95;
    const mageHasteBoost = 2.0; // 1 + 2.0 = 3x speed
    for (final mage in zombies.where((z) => z.kind == ZombieKind.hasteMage)) {
      for (final other in zombies) {
        if (_wrappedDelta(other.position, mage.position).distance <=
            mageAuraRadius) {
          other.speedBoost = math.max(other.speedBoost, mageHasteBoost);
        }
      }
    }

    final snapshot = List<Zombie>.from(zombies);
    for (final zombie in snapshot) {
      if (!zombies.contains(zombie)) continue;
      zombie.attackCooldown = math.max(0, zombie.attackCooldown - dt);
      zombie.abilityCooldown = math.max(0, zombie.abilityCooldown - dt);
      zombie.hitFlash = math.max(0, zombie.hitFlash - dt);
      zombie.blockTimer = math.max(0, zombie.blockTimer - dt);

      if (zombie.kind == ZombieKind.shadowRonin) {
        zombie.specialTimer -= dt;
        if (zombie.specialTimer <= 0) {
          zombie.specialTimer = 20;
          final mini = switch (_random.nextInt(3)) {
            0 => ZombieKind.siegeBehemoth,
            1 => ZombieKind.broodQueen,
            _ => ZombieKind.ironColossus,
          };
          if (zombies.length < 32) {
            _spawnZombie(
              forcedKind: mini,
              at: _wrap(zombie.position +
                  Offset(
                    (_random.nextDouble() - 0.5) * 0.8,
                    (_random.nextDouble() - 0.5) * 0.8,
                  )),
            );
            _showMessage('RONIN SUMMONS ${mini.label.toUpperCase()}');
          }
        }
      }

      final hunt = _zombieHuntPoint(zombie);
      final delta = _wrappedDelta(zombie.position, hunt);
      final distance = delta.distance;
      final toPlayer = _wrappedDelta(zombie.position, player);
      final playerDistance = toPlayer.distance;
      final facing =
          distance > 0.001 ? delta / distance : const Offset(0, -1);

      if (zombie.isWindingUp) {
        zombie.windUpTimer = math.max(0, zombie.windUpTimer - dt);
        if (zombie.pendingAttack != EnemyAttackKind.ability ||
            zombie.telegraphWorld == null) {
          zombie.attackFacing = facing;
        }
        if (zombie.windUpTimer <= 0) {
          _commitEnemyAttack(zombie);
          if (gameOver) return;
        }
        continue;
      }

      if (zombie.kind.isImmobile) {
        if (_tryMeleeGunAlly(zombie)) {
          if (gameOver) return;
        } else if (playerDistance <= zombie.radius + 0.1 &&
            zombie.attackCooldown <= 0) {
          // Quick tower bash — no wind-up.
          zombie.attackAnim = 1.0;
          zombie.attackFacing = playerDistance > 0.001
              ? toPlayer / playerDistance
              : facing;
          _hurtPlayer(zombie.kind.meleeDamage.toDouble() * zombie.damageMult);
          zombie.attackCooldown = 0.55;
          if (gameOver) return;
        } else {
          _tickZombieAbility(zombie);
        }
        if (gameOver) return;
        continue;
      }

      final virusSlow = zombie.isInfected ? 0.38 : 1.0;
      final gunSlow = zombie.isSlowed ? zombie.slowFactor : 1.0;
      final blockSlow = zombie.isBlocking ? 0.15 : 1.0;
      final moveSpeed = zombie.speed *
          (1 + zombie.speedBoost) *
          virusSlow *
          gunSlow *
          blockSlow;

      // Bash gunners that get in the way / that we're hunting.
      if (_tryMeleeGunAlly(zombie)) {
        if (gameOver) return;
        continue;
      }

      if (zombie.kind.prefersRange && playerDistance < zombie.kind.preferredRange) {
        if (playerDistance > 0.08) {
          zombie.position = _moveEnemy(
            zombie,
            zombie.position,
            zombie.position - toPlayer / playerDistance * (moveSpeed * 0.35 * dt),
          );
        }
      } else if (distance > zombie.radius + zombie.kind.meleeReach) {
        zombie.position = _moveEnemy(
          zombie,
          zombie.position,
          zombie.position + delta / distance * (moveSpeed * dt),
        );
      } else if (zombie.attackCooldown <= 0) {
        // In melee range of hunt target — if it's a gunner, bash them;
        // otherwise wind up on the Commander.
        if (_tryMeleeGunAlly(zombie)) {
          if (gameOver) return;
          continue;
        }
        if (playerDistance > zombie.radius + zombie.kind.meleeReach + 0.08) {
          continue;
        }
        final facePlayer = playerDistance > 0.001
            ? toPlayer / playerDistance
            : facing;
        if (zombie.kind == ZombieKind.exploder) {
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.exploder,
            facing: facePlayer,
            duration: 0.52,
            telegraphRadius: 0.4,
          );
        } else if (zombie.kind == ZombieKind.globling) {
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.globling,
            facing: facePlayer,
            duration: 0.26,
            telegraphRadius: 0.36,
          );
        } else if (zombie.kind == ZombieKind.hammerMauler) {
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.melee,
            facing: facePlayer,
            duration: 0.9,
            telegraphRadius: zombie.kind.meleeReach + 0.14,
          );
        } else {
          // Basic punches land immediately; only big specials telegraph.
          zombie.attackAnim = 1.0;
          zombie.attackFacing = facePlayer;
          _hurtPlayer(zombie.kind.meleeDamage.toDouble() * zombie.damageMult);
          zombie.attackCooldown = zombie.brute ? 1.15 : 0.8;
          if (gameOver) return;
        }
      }

      if (!zombie.isWindingUp) {
        _tickZombieAbility(zombie);
      }
      if (gameOver) return;
    }

    _cullDeadZombies();
  }

  void _beginWindUp(
    Zombie zombie, {
    required EnemyAttackKind attack,
    required Offset facing,
    required double duration,
    double telegraphRadius = 0,
    Offset? telegraphWorld,
  }) {
    if (zombie.isWindingUp) return;
    zombie.pendingAttack = attack;
    zombie.windUpDuration = duration;
    zombie.windUpTimer = duration;
    zombie.attackFacing = facing;
    zombie.telegraphRadius = telegraphRadius;
    zombie.telegraphWorld = telegraphWorld;
  }

  void _commitEnemyAttack(Zombie zombie) {
    final attack = zombie.pendingAttack;
    zombie.windUpTimer = 0;
    zombie.windUpDuration = 0;
    zombie.pendingAttack = null;
    if (attack == null || !zombies.contains(zombie)) {
      zombie.clearWindUp();
      return;
    }

    switch (attack) {
      case EnemyAttackKind.melee:
        zombie.attackAnim = 1.0;
        _hurtPlayer(zombie.kind.meleeDamage.toDouble() * zombie.damageMult);
        zombie.attackCooldown = zombie.kind == ZombieKind.hammerMauler
            ? 1.55
            : zombie.kind.isImmobile
                ? 0.55
                : (zombie.brute ? 1.15 : 0.8);
      case EnemyAttackKind.exploder:
        _detonateExploder(zombie);
      case EnemyAttackKind.globling:
        _detonateGlobling(zombie);
      case EnemyAttackKind.ability:
        zombie.attackAnim = 1.0;
        _commitZombieAbility(zombie);
      case EnemyAttackKind.dash:
        _commitEliteDash(zombie);
      case EnemyAttackKind.block:
        _commitEliteBlock(zombie);
      case EnemyAttackKind.groundPound:
        _commitEliteGroundPound(zombie);
    }
    zombie.clearWindUp();
  }

  void _tickStatusEffects(Zombie zombie, double dt) {
    if (zombie.burnTimer > 0) {
      zombie.burnTimer -= dt;
      zombie.health -= zombie.burnDps * dt;
      zombie.hitFlash = math.max(zombie.hitFlash, 0.04);
    }
    if (zombie.virusTimer > 0) {
      zombie.virusTimer -= dt;
      final dps = zombie.virusDps > 0 ? zombie.virusDps : 6;
      zombie.health -= dps * dt;
      zombie.hitFlash = math.max(zombie.hitFlash, 0.03);
      zombie.virusSpreadCooldown =
          math.max(0, zombie.virusSpreadCooldown - dt);
      if (zombie.virusTimer <= 0) {
        zombie.virusTimer = 0;
        zombie.virusDps = 0;
      }
    }
    if (zombie.slowTimer > 0) {
      zombie.slowTimer -= dt;
      if (zombie.slowTimer <= 0) {
        zombie.slowTimer = 0;
        zombie.slowFactor = 1;
      }
    }
  }

  void _spreadVirus(double dt) {
    final infected = zombies.where((z) => z.isInfected).toList();
    for (final carrier in infected) {
      if (carrier.virusSpreadCooldown > 0) continue;
      carrier.virusSpreadCooldown = 0.3;
      for (final other in zombies) {
        if (other.id == carrier.id || other.isInfected) continue;
        if (_wrappedDelta(carrier.position, other.position).distance <= 0.68) {
          _applyVirus(
            other,
            duration: math.max(5.5, carrier.virusTimer * 0.85),
            dps: math.max(18, carrier.virusDps * 0.9),
          );
        }
      }
    }
  }

  void _applyBurn(Zombie zombie, {double duration = 3.2, double dps = 22}) {
    zombie.burnTimer = math.max(zombie.burnTimer, duration);
    zombie.burnDps = math.max(zombie.burnDps, dps);
  }

  void _applyVirus(
    Zombie zombie, {
    double duration = 10.0,
    double dps = 30,
  }) {
    zombie.virusTimer = math.max(zombie.virusTimer, duration);
    zombie.virusDps = math.max(zombie.virusDps, dps);
    zombie.virusSpreadCooldown = 0.15;
    zombie.hitFlash = 0.1;
  }

  void _applySlow(Zombie zombie, {double duration = 2.6, double factor = 0.42}) {
    zombie.slowTimer = math.max(zombie.slowTimer, duration);
    zombie.slowFactor = math.min(zombie.slowFactor, factor);
    zombie.hitFlash = math.max(zombie.hitFlash, 0.06);
  }

  void _tickZombieAbility(Zombie zombie) {
    if (zombie.abilityCooldown > 0 || zombie.isWindingUp) return;
    if (zombie.isBlocking) return;
    final delta = _wrappedDelta(zombie.position, player);
    final dist = delta.distance;
    final facing = dist > 0.001 ? delta / dist : const Offset(0, -1);

    if (_tryEliteCombatSkill(zombie, facing, dist)) return;

    switch (zombie.kind) {
      case ZombieKind.spitter:
      case ZombieKind.frostbite:
        if (dist < 0.2 || dist > 1.9) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.34,
        );
      case ZombieKind.knifeThrower:
        if (dist < 0.12) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.22,
        );
      case ZombieKind.knifeFanatic:
        if (dist < 0.12 || dist > 1.55) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.28,
        );
      case ZombieKind.sharpshooter:
      case ZombieKind.railSniper:
      case ZombieKind.missileer:
        if (dist < 0.35) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: zombie.kind == ZombieKind.railSniper
              ? 0.38
              : zombie.kind == ZombieKind.missileer
                  ? 0.55
                  : 0.48,
        );
      case ZombieKind.scatterGunner:
        if (dist < 0.15 || dist > 1.25) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.3,
        );
      case ZombieKind.emberCaster:
      case ZombieKind.iceLancer:
      case ZombieKind.hexWitch:
      case ZombieKind.harpooner:
      case ZombieKind.boltSlinger:
      case ZombieKind.toxinDart:
      case ZombieKind.zapper:
        if (dist < 0.18 || dist > 2.2) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.32,
        );
      case ZombieKind.skyCaller:
        final scatter = Offset(
          (_random.nextDouble() - 0.5) * 0.7,
          (_random.nextDouble() - 0.5) * 0.7,
        );
        final target = _wrap(player + scatter);
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.4,
          telegraphRadius: 0.32,
          telegraphWorld: target,
        );
        zombie.telegraphWorld = target;
        _meteorCorners[zombie.id] = _rollMeteorScreenCorner();
        _showMessage('METEOR INCOMING');
      case ZombieKind.necromancer:
        if (zombie.isAscendedNecromancer) {
          if (zombies.length >= 40) {
            zombie.abilityCooldown = 1.4;
            return;
          }
          final callMini = _random.nextDouble() < 0.7;
          zombie.abilityPhase = callMini ? 1 : 0;
          final Offset at;
          if (callMini) {
            at = _edgeSpawnPoint();
            _necroRaise[zombie.id] = false;
          } else if (corpses.isNotEmpty && _random.nextBool()) {
            at = corpses[_random.nextInt(corpses.length)].position;
            _necroRaise[zombie.id] = true;
          } else {
            at = _wrap(zombie.position +
                Offset(
                  (_random.nextDouble() - 0.5) * 0.7,
                  (_random.nextDouble() - 0.5) * 0.7,
                ));
            _necroRaise[zombie.id] = false;
          }
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.ability,
            facing: facing,
            duration: 0.55,
            telegraphRadius: callMini ? 0.28 : 0.18,
            telegraphWorld: at,
          );
          if (callMini) {
            _showMessage('MINI-BOSS RITUAL');
          }
          return;
        }
        if (zombies.length >= 28) {
          zombie.abilityCooldown = 2;
          return;
        }
        final raise = corpses.isNotEmpty && _random.nextBool();
        Offset? at;
        if (raise) {
          at = corpses[_random.nextInt(corpses.length)].position;
        } else {
          at = _wrap(zombie.position +
              Offset(
                (_random.nextDouble() - 0.5) * 0.5,
                (_random.nextDouble() - 0.5) * 0.5,
              ));
        }
        _necroRaise[zombie.id] = raise;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.42,
          telegraphRadius: 0.16,
          telegraphWorld: at,
        );
      case ZombieKind.screamer:
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.48,
          telegraphRadius: 1.05,
        );
      case ZombieKind.stalker:
      case ZombieKind.wraith:
        if (dist <= 0.35) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.26,
        );
      case ZombieKind.jumper:
        if (dist <= 0.25) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.36,
          telegraphRadius: 0.22,
          telegraphWorld: _wrap(zombie.position + facing * 0.85),
        );
      case ZombieKind.hammerMauler:
        if (dist < 0.3 || dist > 2.6) return;
        final smashAt = _wrap(player +
            Offset(
              (_random.nextDouble() - 0.5) * 0.18,
              (_random.nextDouble() - 0.5) * 0.18,
            ));
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 1.65,
          telegraphRadius: 0.34,
          telegraphWorld: smashAt,
        );
        _showMessage('HAMMER SMASH');
      case ZombieKind.hiveMother:
        if (zombies.length >= 26) {
          zombie.abilityCooldown = 4.5;
          return;
        }
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.45,
          telegraphRadius: 0.2,
        );
      case ZombieKind.acidBomber:
        if (dist >= 1.6) return;
        final drop = _wrap(player +
            Offset(
              (_random.nextDouble() - 0.5) * 0.3,
              (_random.nextDouble() - 0.5) * 0.3,
            ));
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.36,
          telegraphRadius: 0.24,
          telegraphWorld: drop,
        );
      case ZombieKind.plagueDoctor:
        final drop = _wrap(zombie.position +
            Offset(
              (_random.nextDouble() - 0.5) * 0.5,
              (_random.nextDouble() - 0.5) * 0.5,
            ));
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.34,
          telegraphRadius: 0.3,
          telegraphWorld: drop,
        );
      case ZombieKind.hasteMage:
        final wounded = zombies.any((z) =>
            z.id != zombie.id &&
            z.health < z.maxHealth &&
            _wrappedDelta(z.position, zombie.position).distance <= 2.4);
        if (!wounded) {
          zombie.abilityCooldown = 1.2;
          return;
        }
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.55,
          telegraphRadius: 2.4,
        );
      case ZombieKind.pyrofiend:
        final drop = _wrap(player +
            Offset(
              (_random.nextDouble() - 0.5) * 0.6,
              (_random.nextDouble() - 0.5) * 0.6,
            ));
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 1.05,
          telegraphRadius: 0.34,
          telegraphWorld: drop,
        );
        _showMessage('PYRE INCOMING');
      case ZombieKind.riftWalker:
        if (dist <= 0.4) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.3,
          telegraphRadius: 0.18,
          telegraphWorld: _wrap(zombie.position + facing * 1.2),
        );
      case ZombieKind.siegeBehemoth:
        if (dist <= 0.2) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.42,
        );
      case ZombieKind.blazeburst:
        final rareNova = _random.nextDouble() < 0.16;
        zombie.abilityPhase = rareNova ? 1 : 0;
        if (rareNova) {
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.ability,
            facing: facing,
            duration: 0.95,
            telegraphRadius: 0.85,
          );
          _showMessage('BLAZEBURST: SPLIT NOVA');
        } else {
          if (dist < 0.35 || dist > 2.4) return;
          _beginWindUp(
            zombie,
            attack: EnemyAttackKind.ability,
            facing: facing,
            duration: 0.48,
            telegraphRadius: 0.22,
            telegraphWorld: _wrap(zombie.position + facing * 1.55),
          );
        }
      case ZombieKind.broodQueen:
        if (zombies.length >= 30) {
          zombie.abilityCooldown = 3.6;
          return;
        }
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.44,
          telegraphRadius: 0.22,
        );
      case ZombieKind.ironColossus:
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.55,
          telegraphRadius: 0.95,
        );
      case ZombieKind.dreadlord:
        if (dist <= 0.15) return;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.28,
        );
      case ZombieKind.citadelTower:
        final tier = math.max(1, zombie.specialTimer.round());
        final windUp = math.max(0.12, 0.32 - (tier - 1) * 0.045);
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: windUp,
          telegraphRadius: 0.45,
        );
        _showMessage(zombie.abilityPhase.isEven
            ? 'CITADEL CHARGING: X'
            : 'CITADEL CHARGING: +');
      case ZombieKind.apocalypseLord:
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: 0.3,
          telegraphRadius: dist > 0.2 ? 0 : 0.35,
        );
      case ZombieKind.shadowRonin:
        final teleport = zombie.abilityPhase.isOdd;
        final dest = teleport ? _playerPosOneSecondAgo : null;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: teleport ? 0.28 : 0.34,
          telegraphRadius: teleport ? 0.2 : 0.28,
          telegraphWorld: dest,
        );
        if (teleport) _showMessage('SHADOW STEP');
      case ZombieKind.voidSovereign:
        final mode = zombie.abilityPhase % 6;
        final duration = switch (mode) {
          0 => 0.22,
          1 => 0.48,
          2 => 0.26,
          3 => 0.3,
          4 => 0.4,
          _ => 0.24,
        };
        final telegraph = switch (mode) {
          1 => 0.85,
          3 => 0.45,
          4 => 0.28,
          _ => 0.0,
        };
        final world = switch (mode) {
          1 || 3 => player,
          4 => _wrap(player +
              Offset(
                (_random.nextDouble() - 0.5) * 0.9,
                (_random.nextDouble() - 0.5) * 0.9,
              )),
          _ => null,
        };
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.ability,
          facing: facing,
          duration: duration,
          telegraphRadius: telegraph,
          telegraphWorld: world,
        );
        _showMessage(switch (mode) {
          0 => 'VOID: SPIRAL NOVA',
          1 => 'VOID: COLLAPSE RING',
          2 => 'VOID: AXIS SWEEP',
          3 => 'VOID: BLINK SLAM',
          4 => 'VOID: RIFT RAIN',
          _ => 'VOID: KNIFE STORM',
        });
      default:
        zombie.abilityCooldown = 999;
    }
  }

  /// Dash / block / ground pound for selected bosses and mini-bosses.
  bool _tryEliteCombatSkill(Zombie zombie, Offset facing, double dist) {
    final skills = zombie.kind.eliteSkills;
    if (skills.isEmpty) return false;
    // Primary kit still dominates; later citadels lean harder into barrages.
    final chance = zombie.kind == ZombieKind.citadelTower
        ? math.max(0.08, 0.22 - (math.max(1, zombie.specialTimer.round()) - 1) * 0.04)
        : zombie.kind == ZombieKind.voidSovereign
            ? 0.28
            : 0.48;
    if (_random.nextDouble() > chance) return false;

    final skill = skills[_random.nextInt(skills.length)];
    switch (skill) {
      case EliteCombatSkill.dash:
        if (zombie.kind.isImmobile || dist < 0.28) return false;
        final leap = zombie.kind.isBoss ? 1.75 : 1.35;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.dash,
          facing: facing,
          duration: 0.36,
          telegraphRadius: 0.28,
          telegraphWorld: _wrap(zombie.position + facing * leap),
        );
        _showMessage('${zombie.kind.label.toUpperCase()}: DASH');
        return true;
      case EliteCombatSkill.block:
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.block,
          facing: facing,
          duration: 0.2,
          telegraphRadius: math.max(0.35, zombie.radius * 3.2),
        );
        _showMessage('${zombie.kind.label.toUpperCase()}: BLOCK');
        return true;
      case EliteCombatSkill.groundPound:
        final radius = zombie.kind.isBoss ? 1.3 : 1.05;
        _beginWindUp(
          zombie,
          attack: EnemyAttackKind.groundPound,
          facing: facing,
          duration: 0.72,
          telegraphRadius: radius,
        );
        _showMessage('${zombie.kind.label.toUpperCase()}: GROUND POUND');
        return true;
    }
  }

  void _commitEliteDash(Zombie zombie) {
    final facing = zombie.attackFacing.distance > 0.001
        ? zombie.attackFacing / zombie.attackFacing.distance
        : const Offset(0, -1);
    final from = zombie.position;
    final dest = zombie.telegraphWorld ?? _wrap(from + facing * 1.4);
    zombie.position = _wrap(dest);
    zombie.attackAnim = 1.0;
    zombie.attackFacing = facing;
    blastFlashes.add(BlastFlash(
      from,
      zombie.kind.color,
      radius: 0.35,
      life: 0.18,
    ));
    blastFlashes.add(BlastFlash(
      zombie.position,
      const Color(0xFFFFAB40),
      radius: 0.42,
      life: 0.22,
    ));
    final hitRadius = zombie.kind.isBoss ? 0.3 : 0.26;
    final dashDamage = (zombie.kind.isBoss ? 26 : 18) + wave * 0.7;
    if (_dashHitsPlayer(from, zombie.position, hitRadius)) {
      _hurtPlayer(dashDamage);
    }
    for (final ally in gunAllies) {
      if (ally.health <= 0) continue;
      if (_dashHitsPoint(from, zombie.position, ally.position, hitRadius)) {
        _hurtGunAlly(ally, dashDamage);
      }
    }
    zombie.abilityCooldown = zombie.kind.isBoss ? 2.1 : 2.5;
  }

  void _commitEliteBlock(Zombie zombie) {
    zombie.blockTimer = zombie.kind.isBoss ? 2.6 : 2.1;
    zombie.attackAnim = 0.55;
    blastFlashes.add(BlastFlash(
      zombie.position,
      const Color(0xFF90CAF9),
      radius: 0.55,
      life: 0.28,
    ));
    zombie.abilityCooldown = 3.0;
  }

  void _commitEliteGroundPound(Zombie zombie) {
    final radius = zombie.telegraphRadius > 0
        ? zombie.telegraphRadius
        : (zombie.kind.isBoss ? 1.3 : 1.05);
    blastFlashes.add(BlastFlash(
      zombie.position,
      const Color(0xFFFF6D00),
      radius: radius,
      life: 0.4,
    ));
    blastFlashes.add(BlastFlash(
      zombie.position,
      zombie.kind.color,
      radius: radius * 0.55,
      life: 0.25,
    ));
    zombie.attackAnim = 1.0;
    final poundDamage = (zombie.kind.isBoss ? 34 : 22) + wave * 0.85;
    if (_wrappedDelta(zombie.position, player).distance <= radius + 0.05) {
      _hurtPlayer(poundDamage);
    }
    _hurtGunAlliesInRadius(zombie.position, radius + 0.05, poundDamage);
    zombie.abilityCooldown = zombie.kind.isBoss ? 2.8 : 3.1;
  }

  void _commitZombieAbility(Zombie zombie) {
    final delta = _wrappedDelta(zombie.position, player);
    final dist = delta.distance;
    final facing = dist > 0.001 ? delta / dist : zombie.attackFacing;

    switch (zombie.kind) {
      case ZombieKind.spitter:
      case ZombieKind.frostbite:
        if (dist < 0.15) {
          zombie.abilityCooldown =
              zombie.kind == ZombieKind.frostbite ? 1.95 : 1.7;
          return;
        }
        final dir = facing;
        enemyBolts.add(EnemyBolt(
          position: zombie.position + dir * 0.08,
          velocity: dir * (zombie.kind == ZombieKind.frostbite ? 1.0 : 1.15),
          damage: (zombie.kind == ZombieKind.frostbite ? 6 : 5) + wave * 0.28,
          color: zombie.kind == ZombieKind.frostbite
              ? const Color(0xFF81D4FA)
              : const Color(0xFFAED581),
        ));
        zombie.abilityCooldown =
            zombie.kind == ZombieKind.frostbite ? 1.95 : 1.7;
      case ZombieKind.knifeThrower:
        if (dist < 0.1) {
          zombie.abilityCooldown = 1.4;
          return;
        }
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.1,
          velocity: facing * 5.6,
          damage: 6 + wave * 0.28,
          color: const Color(0xFFECEFF1),
          radius: 0.028,
          life: 5.0,
          style: EnemyBoltStyle.knife,
        ));
        zombie.abilityCooldown = 2.7;
      case ZombieKind.knifeFanatic:
        if (dist < 0.1) {
          zombie.abilityCooldown = 1.25;
          return;
        }
        for (final angled in [-0.28, 0.0, 0.28]) {
          final cosA = math.cos(angled);
          final sinA = math.sin(angled);
          final shot = Offset(
            facing.dx * cosA - facing.dy * sinA,
            facing.dx * sinA + facing.dy * cosA,
          );
          enemyBolts.add(EnemyBolt(
            position: zombie.position + shot * 0.1,
            velocity: shot * 3.35,
            damage: 5 + wave * 0.24,
            color: const Color(0xFFFFAB91),
            radius: 0.03,
            life: 5.0,
            style: EnemyBoltStyle.knife,
          ));
        }
        zombie.abilityCooldown = 3.05;
      case ZombieKind.sharpshooter:
        if (dist < 0.2) {
          zombie.abilityCooldown = 1.0;
          return;
        }
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.1,
          velocity: facing * 2.9,
          damage: 10 + wave * 0.48,
          color: const Color(0xFF8D6E63),
          radius: 0.035,
          life: 5.5,
        ));
        zombie.abilityCooldown = 2.35;
      case ZombieKind.railSniper:
        if (dist < 0.2) {
          zombie.abilityCooldown = 0.9;
          return;
        }
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.12,
          velocity: facing * 6.4,
          damage: 8 + wave * 0.4,
          color: const Color(0xFF00BCD4),
          radius: 0.022,
          life: 6.0,
        ));
        zombie.abilityCooldown = 2.1;
      case ZombieKind.missileer:
        if (dist < 0.25) {
          zombie.abilityCooldown = 0.85;
          return;
        }
        // One live missile per firer — must explode or the firer must die.
        if (enemyBolts.any(
            (b) => b.style == EnemyBoltStyle.missile && b.ownerId == zombie.id)) {
          zombie.abilityCooldown = 0.6;
          return;
        }
        final launchDir = dist > 0.01 ? facing : const Offset(0, -1);
        // Slightly slower than the player so strafing can shake them.
        final launchSpeed =
            effectiveMoveSpeed * _speedBuffMult * gooSlowFactor * 0.82;
        enemyBolts.add(EnemyBolt(
          position: zombie.position + launchDir * 0.14,
          velocity: launchDir * launchSpeed,
          damage: 16 + wave * 0.55,
          color: const Color(0xFFFF8F00),
          radius: 0.032,
          life: 18.0,
          style: EnemyBoltStyle.missile,
          ownerId: zombie.id,
        ));
        _showMessage('MISSILE LOCK');
        zombie.abilityCooldown = 3.4;
      case ZombieKind.scatterGunner:
        if (dist < 0.12) {
          zombie.abilityCooldown = 0.9;
          return;
        }
        for (final angled in [-0.42, -0.2, 0.0, 0.2, 0.42]) {
          final cosA = math.cos(angled);
          final sinA = math.sin(angled);
          final shot = Offset(
            facing.dx * cosA - facing.dy * sinA,
            facing.dx * sinA + facing.dy * cosA,
          );
          enemyBolts.add(EnemyBolt(
            position: zombie.position + shot * 0.08,
            velocity: shot * 2.1,
            damage: 3.5 + wave * 0.15,
            color: const Color(0xFFBCAAA4),
            radius: 0.03,
            life: 1.6,
          ));
        }
        zombie.abilityCooldown = 1.8;
      case ZombieKind.emberCaster:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.09,
          velocity: facing * 1.55,
          damage: 6 + wave * 0.28,
          color: const Color(0xFFFF6E40),
          radius: 0.05,
          life: 3.0,
        ));
        zombie.abilityCooldown = 1.85;
      case ZombieKind.iceLancer:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.09,
          velocity: facing * 1.7,
          damage: 5.5 + wave * 0.28,
          color: const Color(0xFF40C4FF),
          radius: 0.04,
          life: 3.2,
        ));
        zombie.abilityCooldown = 1.8;
      case ZombieKind.hexWitch:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.09,
          velocity: facing * 1.35,
          damage: 7 + wave * 0.32,
          color: const Color(0xFFCE93D8),
          radius: 0.055,
          life: 3.4,
        ));
        zombie.abilityCooldown = 1.9;
      case ZombieKind.harpooner:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.1,
          velocity: facing * 2.4,
          damage: 7 + wave * 0.35,
          color: const Color(0xFF90A4AE),
          radius: 0.045,
          life: 5.0,
          style: EnemyBoltStyle.knife,
        ));
        zombie.abilityCooldown = 1.95;
      case ZombieKind.boltSlinger:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.08,
          velocity: facing * 1.85,
          damage: 4 + wave * 0.2,
          color: const Color(0xFFBCAAA4),
          radius: 0.035,
          life: 2.8,
        ));
        zombie.abilityCooldown = 1.55;
      case ZombieKind.toxinDart:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.08,
          velocity: facing * 2.0,
          damage: 3.5 + wave * 0.18,
          color: const Color(0xFFC5E1A5),
          radius: 0.03,
          life: 2.9,
        ));
        zombie.abilityCooldown = 1.65;
      case ZombieKind.zapper:
        enemyBolts.add(EnemyBolt(
          position: zombie.position + facing * 0.1,
          velocity: facing * 3.5,
          damage: 5.5 + wave * 0.28,
          color: const Color(0xFFFFF176),
          radius: 0.032,
          life: 2.6,
        ));
        zombie.abilityCooldown = 1.7;
      case ZombieKind.skyCaller:
        final target = zombie.telegraphWorld ??
            _wrap(player +
                Offset(
                  (_random.nextDouble() - 0.5) * 0.7,
                  (_random.nextDouble() - 0.5) * 0.7,
                ));
        final corner = _meteorCorners.remove(zombie.id) ??
            _rollMeteorScreenCorner();
        skyHazards.add(SkyHazard(
          target: target,
          screenCorner: corner,
          damage: 4.0 + wave * 0.2,
          blastRadius: 0.32,
          height: 1.45,
        ));
        zombie.abilityCooldown = 3.5;
      case ZombieKind.necromancer:
        final at = zombie.telegraphWorld ?? zombie.position;
        if (zombie.isAscendedNecromancer && zombie.abilityPhase == 1) {
          final pool = _availableMiniBossKinds;
          final mini = pool[_random.nextInt(pool.length)];
          _spawnZombie(forcedKind: mini, at: at);
          _showMessage('${mini.label.toUpperCase()} RISES');
          zombie.abilityCooldown = 2.4;
          zombie.abilityPhase = 0;
        } else {
          final raise = _necroRaise.remove(zombie.id) ?? false;
          if (raise) {
            corpses.removeWhere((c) => (c.position - at).distance < 0.05);
            _spawnZombie(
              forcedKind: ZombieKind.walker,
              at: at,
              asNecroMinion: true,
            );
            if (zombie.isAscendedNecromancer && zombies.length < 36) {
              _spawnZombie(
                forcedKind: ZombieKind.runner,
                at: _wrap(at + const Offset(0.12, -0.08)),
                asNecroMinion: true,
              );
            }
            _showMessage('RISEN FROM THE DEAD');
          } else {
            skyHazards.add(SkyHazard(
              target: at,
              damage: 0,
              blastRadius: 0.12,
              height: zombie.isAscendedNecromancer ? 0.55 : 0.85,
              summonsZombie: true,
              summonsNecroMinion: true,
            ));
            _showMessage('NECRO SUMMON');
          }
          zombie.abilityCooldown = zombie.isAscendedNecromancer ? 1.6 : 3.4;
        }
      case ZombieKind.screamer:
        if (_wrappedDelta(zombie.position, player).distance <= 1.05) {
          _hurtPlayer(5);
        }
        for (final other in zombies) {
          if (_wrappedDelta(other.position, zombie.position).distance < 0.9) {
            other.speedBoost = math.max(other.speedBoost, 0.55);
          }
        }
        zombie.abilityCooldown = 4.2;
      case ZombieKind.stalker:
      case ZombieKind.wraith:
        if (dist > 0.35) {
          zombie.position = _wrap(zombie.position +
              facing * (zombie.kind == ZombieKind.wraith ? 0.7 : 0.45));
          zombie.attackAnim = 0.7;
        }
        zombie.abilityCooldown = zombie.kind == ZombieKind.wraith ? 2.1 : 2.6;
      case ZombieKind.jumper:
        if (dist > 0.25) {
          final leapFrom = dist;
          zombie.position = _wrap(zombie.position + facing * 0.85);
          zombie.attackAnim = 1.0;
          zombie.attackFacing = facing;
          if (leapFrom < 1.1) {
            _hurtPlayer(8);
          }
        }
        zombie.abilityCooldown = 2.9;
      case ZombieKind.hammerMauler:
        final land = zombie.telegraphWorld ?? player;
        final from = zombie.position;
        zombie.position = _wrap(land);
        zombie.attackAnim = 1.0;
        zombie.attackFacing = facing;
        const smashRadius = 0.34;
        blastFlashes.add(BlastFlash(
          land,
          const Color(0xFFFFB74D),
          radius: smashRadius + 0.15,
          life: 0.32,
        ));
        blastFlashes.add(BlastFlash(
          land,
          const Color(0xFF6D4C41),
          radius: smashRadius * 0.7,
          life: 0.2,
        ));
        tracers.add(BulletTracer(
          from,
          land,
          const Color(0xAA8D6E63),
          strokeWidth: 6,
          life: 0.2,
        ));
        if (_wrappedDelta(player, land).distance <= smashRadius + 0.06) {
          _hurtPlayer(12 + wave * 0.4);
        }
        _hurtGunAlliesInRadius(land, smashRadius + 0.06, 12 + wave * 0.4);
        firePits.add(FirePit(
          land,
          life: 0.9,
          radius: smashRadius * 0.7,
          dps: 4 + wave * 0.12,
        ));
        zombie.abilityCooldown = 2.85;
      case ZombieKind.hiveMother:
        if (zombies.length < 26) {
          final offset = Offset(
            (_random.nextDouble() - 0.5) * 0.4,
            (_random.nextDouble() - 0.5) * 0.4,
          );
          _spawnZombie(
            forcedKind: ZombieKind.runner,
            at: _wrap(zombie.position + offset),
          );
          _showMessage('HIVE SPAWN');
        }
        zombie.abilityCooldown = 4.5;
      case ZombieKind.acidBomber:
        final drop = zombie.telegraphWorld ?? player;
        poisonClouds.add(PoisonCloud(drop, life: 2.8, radius: 0.24));
        zombie.abilityCooldown = 3.9;
      case ZombieKind.plagueDoctor:
        final drop = zombie.telegraphWorld ?? zombie.position;
        poisonClouds.add(PoisonCloud(drop, life: 3.2, radius: 0.3));
        zombie.abilityCooldown = 3.25;
      case ZombieKind.hasteMage:
        final candidates = zombies
            .where((z) =>
                z.id != zombie.id &&
                z.health < z.maxHealth &&
                _wrappedDelta(z.position, zombie.position).distance <= 2.4)
            .toList()
          ..sort((a, b) =>
              (a.health / a.maxHealth).compareTo(b.health / b.maxHealth));
        final healAmount = 42.0 + wave * 2.5;
        var healed = 0;
        for (final ally in candidates.take(5)) {
          ally.health = math.min(ally.maxHealth, ally.health + healAmount);
          ally.hitFlash = 0.12;
          blastFlashes.add(BlastFlash(
            ally.position,
            const Color(0xFF69F0AE),
            radius: 0.28,
            life: 0.28,
          ));
          healed++;
        }
        if (healed > 0) {
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFF00E5FF),
            radius: 0.55,
            life: 0.3,
          ));
          _showMessage('MAGE HEALS $healed');
        }
        zombie.abilityCooldown = 3.4;
      case ZombieKind.pyrofiend:
        final drop = zombie.telegraphWorld ?? player;
        firePits.add(FirePit(
          drop,
          life: 2.8,
          radius: 0.28,
          dps: 16 + wave * 0.4,
        ));
        zombie.abilityCooldown = 2.9;
      case ZombieKind.riftWalker:
        if (dist > 0.4) {
          zombie.position = _wrap(zombie.position + facing * 1.2);
          zombie.attackAnim = 0.9;
        }
        zombie.abilityCooldown = 2.4;
      case ZombieKind.siegeBehemoth:
        if (dist > 0.2) {
          enemyBolts.add(EnemyBolt(
            position: zombie.position + facing * 0.12,
            velocity: facing * 1.05,
            damage: 20 + wave * 0.7,
            color: zombie.kind.color,
            radius: 0.06,
            life: 3.0,
          ));
        }
        zombie.abilityCooldown = 2.2;
      case ZombieKind.blazeburst:
        if (zombie.abilityPhase == 1) {
          // Rare: pause already telegraphed — fireballs around self that split twice.
          const count = 5;
          for (var i = 0; i < count; i++) {
            final angle = (i / count) * math.pi * 2 + _random.nextDouble() * 0.2;
            final dir = Offset(math.cos(angle), math.sin(angle));
            enemyBolts.add(EnemyBolt(
              position: zombie.position + dir * 0.16,
              velocity: dir * 0.95,
              damage: 11 + wave * 0.45,
              color: const Color(0xFFFF9100),
              radius: 0.07,
              life: 0.55,
              style: EnemyBoltStyle.fireball,
              splitRemaining: 2,
              shardCount: 6,
            ));
          }
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFFFF6D00),
            radius: 0.55,
            life: 0.28,
          ));
          zombie.abilityCooldown = 5.8;
        } else {
          // Mid-range lob toward the player; explodes into a shard ring.
          final aim = dist > 0.01 ? facing : const Offset(0, -1);
          enemyBolts.add(EnemyBolt(
            position: zombie.position + aim * 0.14,
            velocity: aim * 1.35,
            damage: 14 + wave * 0.55,
            color: const Color(0xFFFF3D00),
            radius: 0.085,
            life: 1.55,
            style: EnemyBoltStyle.fireball,
            splitRemaining: 1,
            shardCount: 10,
          ));
          zombie.abilityCooldown = 2.65;
        }
        zombie.abilityPhase = 0;
      case ZombieKind.broodQueen:
        if (zombies.length < 30) {
          _spawnZombie(
            forcedKind: ZombieKind.swarmling,
            at: _wrap(zombie.position +
                Offset(
                  (_random.nextDouble() - 0.5) * 0.35,
                  (_random.nextDouble() - 0.5) * 0.35,
                )),
          );
          _spawnZombie(
            forcedKind: ZombieKind.swarmling,
            at: _wrap(zombie.position +
                Offset(
                  (_random.nextDouble() - 0.5) * 0.35,
                  (_random.nextDouble() - 0.5) * 0.35,
                )),
          );
          _showMessage('BROOD SWARM');
        }
        zombie.abilityCooldown = 3.6;
      case ZombieKind.ironColossus:
        blastFlashes.add(BlastFlash(
          zombie.position,
          zombie.kind.color,
          radius: 0.9,
          life: 0.35,
        ));
        if (_wrappedDelta(zombie.position, player).distance < 0.95) {
          _hurtPlayer(16 + wave * 0.5);
        }
        zombie.abilityCooldown = 3.2;
      case ZombieKind.dreadlord:
        if (dist > 0.15) {
          final dir = facing;
          for (final angled in [-0.35, 0.0, 0.35]) {
            final cosA = math.cos(angled);
            final sinA = math.sin(angled);
            final shot = Offset(
              dir.dx * cosA - dir.dy * sinA,
              dir.dx * sinA + dir.dy * cosA,
            );
            enemyBolts.add(EnemyBolt(
              position: zombie.position + shot * 0.12,
              velocity: shot * 2.05,
              damage: 30 + wave * 1.4,
              color: const Color(0xFFE040FB),
              radius: 0.13,
              life: 3.2,
            ));
          }
        }
        zombie.abilityCooldown = 1.05;
      case ZombieKind.citadelTower:
        final useX = zombie.abilityPhase.isEven;
        final tier = math.max(1, zombie.specialTimer.round());
        final power = 1 + (tier - 1) * 0.42;
        final shotSpeed = 2.55 * (1 + (tier - 1) * 0.24);
        final dirs = useX
            ? const [
                Offset(1, 1),
                Offset(1, -1),
                Offset(-1, 1),
                Offset(-1, -1),
              ]
            : const [
                Offset(1, 0),
                Offset(-1, 0),
                Offset(0, 1),
                Offset(0, -1),
              ];
        for (final raw in dirs) {
          final dir = raw / raw.distance;
          enemyBolts.add(EnemyBolt(
            position: zombie.position + dir * 0.22,
            velocity: dir * shotSpeed,
            damage: (26 + wave * 1.25) * power,
            color: const Color(0xFFFF3D00),
            radius: 0.08,
            life: 4.0,
            style: EnemyBoltStyle.citadel,
          ));
        }
        zombie.abilityPhase++;
        zombie.abilityCooldown = math.max(0.28, 0.85 - (tier - 1) * 0.12);
        _showMessage(useX ? 'CITADEL: X BARRAGE' : 'CITADEL: + BARRAGE');
      case ZombieKind.apocalypseLord:
        if (dist > 0.2) {
          final dir = facing;
          for (final angled in [-0.45, -0.15, 0.15, 0.45]) {
            final cosA = math.cos(angled);
            final sinA = math.sin(angled);
            final shot = Offset(
              dir.dx * cosA - dir.dy * sinA,
              dir.dx * sinA + dir.dy * cosA,
            );
            enemyBolts.add(EnemyBolt(
              position: zombie.position + shot * 0.14,
              velocity: shot * 2.45,
              damage: 44.0 + wave * 1.7,
              color: const Color(0xFFFF1744),
              radius: 0.075,
              life: 3.5,
              style: EnemyBoltStyle.apocalypse,
            ));
          }
        }
        if (zombies.length < 28 && _random.nextDouble() < 0.35) {
          _spawnZombie(
            forcedKind: ZombieKind.riftWalker,
            at: _wrap(zombie.position + const Offset(0.25, 0)),
          );
        }
        zombie.abilityCooldown = 0.95;
      case ZombieKind.shadowRonin:
        final teleport = zombie.abilityPhase.isOdd;
        zombie.abilityPhase++;
        if (teleport) {
          final dest = zombie.telegraphWorld ?? _playerPosOneSecondAgo;
          blastFlashes.add(BlastFlash(
            zombie.position,
            zombie.kind.color,
            radius: 0.35,
            life: 0.2,
          ));
          zombie.position = _wrap(dest);
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFF7C4DFF),
            radius: 0.4,
            life: 0.25,
          ));
          zombie.attackAnim = 0.8;
          zombie.abilityCooldown = 0.85;
        } else {
          final from = zombie.position;
          final dash = facing * 1.45;
          zombie.position = _wrap(from + dash);
          zombie.attackAnim = 1.0;
          zombie.attackFacing = facing;
          final hit = _dashHitsPlayer(from, zombie.position, 0.24);
          if (hit) {
            _hurtPlayer(28 + wave * 0.9);
            final heal = 90 + wave * 4.0;
            zombie.health =
                math.min(zombie.maxHealth, zombie.health + heal);
            blastFlashes.add(BlastFlash(
              player,
              const Color(0xFFE91E63),
              radius: 0.35,
              life: 0.22,
            ));
            _showMessage('KATANA LIFESTEAL');
          }
          zombie.abilityCooldown = 0.95;
        }
      case ZombieKind.voidSovereign:
        final mode = zombie.abilityPhase % 6;
        zombie.abilityPhase++;
        switch (mode) {
          case 0:
            // Spiral nova — 10 ultra-fast bolts, hard to slip through.
            for (var i = 0; i < 10; i++) {
              final ang = i * (math.pi * 2 / 10) + wave * 0.07;
              final dir = Offset(math.cos(ang), math.sin(ang));
              enemyBolts.add(EnemyBolt(
                position: zombie.position + dir * 0.2,
                velocity: dir * 4.8,
                damage: 28 + wave * 1.5,
                color: const Color(0xFFE040FB),
                radius: 0.055,
                life: 3.8,
              ));
            }
            zombie.abilityCooldown = 0.7;
          case 1:
            // Collapse ring on the player's feet.
            final at = zombie.telegraphWorld ?? player;
            blastFlashes.add(BlastFlash(
              at,
              const Color(0xFFEA80FC),
              radius: 0.95,
              life: 0.35,
            ));
            if (_wrappedDelta(player, at).distance <= 0.9) {
              _hurtPlayer(34 + wave * 1.2);
            }
            // Secondary delayed pulse via sky hazard faux.
            skyHazards.add(SkyHazard(
              target: at,
              screenCorner: _rollMeteorScreenCorner(),
              damage: 26.0 + wave,
              blastRadius: 0.7,
              height: 0.55,
            ));
            zombie.abilityCooldown = 0.85;
          case 2:
            // Axis + diagonal sweeps.
            for (final raw in [
              const Offset(1, 0),
              const Offset(-1, 0),
              const Offset(0, 1),
              const Offset(0, -1),
              const Offset(1, 1),
              const Offset(1, -1),
              const Offset(-1, 1),
              const Offset(-1, -1),
            ]) {
              final dir = raw / raw.distance;
              enemyBolts.add(EnemyBolt(
                position: zombie.position + dir * 0.18,
                velocity: dir * 5.2,
                damage: 24 + wave * 1.3,
                color: const Color(0xFFCE93D8),
                radius: 0.045,
                life: 5.0,
                style: EnemyBoltStyle.knife,
              ));
            }
            zombie.abilityCooldown = 0.65;
          case 3:
            // Blink onto the player and slam.
            final dest = zombie.telegraphWorld ?? player;
            blastFlashes.add(BlastFlash(
              zombie.position,
              zombie.kind.color,
              radius: 0.4,
              life: 0.2,
            ));
            zombie.position = _wrap(dest);
            blastFlashes.add(BlastFlash(
              zombie.position,
              const Color(0xFFFF4081),
              radius: 0.7,
              life: 0.3,
            ));
            if (_wrappedDelta(player, zombie.position).distance <= 0.55) {
              _hurtPlayer(40 + wave * 1.4);
            }
            zombie.abilityCooldown = 0.75;
          case 4:
            // Triple rift rain around the player.
            for (var i = 0; i < 3; i++) {
              final scatter = Offset(
                (_random.nextDouble() - 0.5) * 1.1,
                (_random.nextDouble() - 0.5) * 1.1,
              );
              final target = _wrap(player + scatter);
              skyHazards.add(SkyHazard(
                target: target,
                screenCorner: _rollMeteorScreenCorner(),
                damage: 22 + wave * 1.1,
                blastRadius: 0.38,
                height: 1.1 + i * 0.15,
              ));
            }
            _showMessage('VOID RIFTS INCOMING');
            zombie.abilityCooldown = 0.9;
          default:
            // Knife storm aimed at the player.
            for (final angled in [-0.55, -0.28, 0.0, 0.28, 0.55]) {
              final cosA = math.cos(angled);
              final sinA = math.sin(angled);
              final shot = Offset(
                facing.dx * cosA - facing.dy * sinA,
                facing.dx * sinA + facing.dy * cosA,
              );
              enemyBolts.add(EnemyBolt(
                position: zombie.position + shot * 0.14,
                velocity: shot * 5.8,
                damage: 20.0 + wave,
                color: const Color(0xFFF3E5F5),
                radius: 0.03,
                life: 5.0,
                style: EnemyBoltStyle.knife,
              ));
            }
            zombie.abilityCooldown = 0.6;
        }
      default:
        zombie.abilityCooldown = 999;
    }
  }

  bool _dashHitsPlayer(Offset from, Offset to, double hitRadius) {
    return _dashHitsPoint(from, to, player, hitRadius);
  }

  bool _dashHitsPoint(
    Offset from,
    Offset to,
    Offset point,
    double hitRadius,
  ) {
    final delta = _wrappedDelta(from, to);
    final len2 = delta.distanceSquared;
    if (len2 < 1e-8) {
      return _wrappedDelta(from, point).distance <= hitRadius;
    }
    final toPoint = _wrappedDelta(from, point);
    var t =
        (toPoint.dx * delta.dx + toPoint.dy * delta.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final closest = from + delta * t;
    return _wrappedDelta(closest, point).distance <= hitRadius;
  }

  void _updateEnemyProjectiles(double dt) {
    final spawned = <EnemyBolt>[];
    final livingIds = {for (final z in zombies) z.id};
    for (final bolt in enemyBolts) {
      if (bolt.style == EnemyBoltStyle.missile) {
        final ownerAlive =
            bolt.ownerId != null && livingIds.contains(bolt.ownerId);
        if (!ownerAlive) {
          // Firer died — missile drops without exploding on the player.
          blastFlashes.add(BlastFlash(
            bolt.position,
            const Color(0xFF90A4AE),
            radius: 0.18,
            life: 0.18,
          ));
          bolt.life = 0;
          continue;
        }
        // Soft homing: limited turn rate + slightly under player speed.
        final seekSpeed =
            effectiveMoveSpeed * _speedBuffMult * gooSlowFactor * 0.82;
        final toPlayer = _wrappedDelta(bolt.position, player);
        if (toPlayer.distance > 1e-5) {
          final desired = toPlayer / toPlayer.distance;
          final speed = bolt.velocity.distance;
          final current = speed > 1e-5
              ? Offset(bolt.velocity.dx / speed, bolt.velocity.dy / speed)
              : desired;
          // ~1.6 rad/s turn — easy to dodge by circling.
          final turn = (1.6 * dt).clamp(0.0, 0.28);
          var blended = Offset(
            current.dx + (desired.dx - current.dx) * turn,
            current.dy + (desired.dy - current.dy) * turn,
          );
          final bLen = blended.distance;
          if (bLen > 1e-5) blended = blended / bLen;
          bolt.velocity = blended * seekSpeed;
        }
        // Missiles chase until impact / firer death / solid hit.
        bolt.life = math.max(bolt.life, 1.0);
      } else {
        bolt.life -= dt;
      }
      final next = bolt.position + bolt.velocity * dt;
      // Knives and missiles are physical — they stop on walls/props.
      if ((bolt.style == EnemyBoltStyle.knife ||
              bolt.style == EnemyBoltStyle.missile) &&
          _segmentHitsCover(bolt.position, next)) {
        if (bolt.style == EnemyBoltStyle.missile) {
          blastFlashes.add(BlastFlash(
            bolt.position,
            const Color(0xFF90A4AE),
            radius: 0.14,
            life: 0.16,
          ));
        }
        bolt.life = 0;
      } else {
        bolt.position = _wrap(next);
      }
      var hitSomething = false;
      if (bolt.life > 0 &&
          _wrappedDelta(bolt.position, player).distance <= 0.07 + bolt.radius) {
        _hurtPlayer(bolt.damage);
        hitSomething = true;
        if (bolt.style == EnemyBoltStyle.missile) {
          blastFlashes.add(BlastFlash(
            bolt.position,
            bolt.color,
            radius: 0.28,
            life: 0.28,
          ));
        }
        if (gameOver) {
          bolt.life = 0;
        }
      }
      if (bolt.life > 0) {
        for (final ally in gunAllies) {
          if (ally.health <= 0) continue;
          if (_wrappedDelta(bolt.position, ally.position).distance <=
              GunAlly.hitRadius + bolt.radius) {
            _hurtGunAlly(ally, bolt.damage);
            hitSomething = true;
            if (bolt.style == EnemyBoltStyle.missile) {
              blastFlashes.add(BlastFlash(
                bolt.position,
                bolt.color,
                radius: 0.22,
                life: 0.22,
              ));
            }
            break;
          }
        }
      }
      if (hitSomething) bolt.life = 0;
      if (bolt.life <= 0 &&
          bolt.style == EnemyBoltStyle.fireball &&
          !bolt.detonated) {
        bolt.detonated = true;
        spawned.addAll(_detonateFireball(bolt));
      }
    }
    enemyBolts.removeWhere((b) => b.life <= 0);
    enemyBolts.addAll(spawned);
  }

  /// Explode a fireball; if [EnemyBolt.splitRemaining] > 0, spawn a ring of
  /// child fireballs (which may themselves split again).
  List<EnemyBolt> _detonateFireball(EnemyBolt bolt) {
    blastFlashes.add(BlastFlash(
      bolt.position,
      bolt.color,
      radius: bolt.radius * 4.5 + 0.12,
      life: 0.22,
    ));
    firePits.add(FirePit(
      bolt.position,
      life: 0.85 + bolt.splitRemaining * 0.25,
      radius: math.max(0.12, bolt.radius * 2.2),
      dps: 6 + wave * 0.2,
    ));
    if (bolt.splitRemaining <= 0 || bolt.shardCount <= 0) return const [];

    final children = <EnemyBolt>[];
    final childSplit = bolt.splitRemaining - 1;
    final childDamage = bolt.damage * (childSplit > 0 ? 0.55 : 0.4);
    final childRadius = bolt.radius * (childSplit > 0 ? 0.72 : 0.55);
    final childLife = childSplit > 0 ? 0.48 : 0.78;
    final childSpeed = childSplit > 0 ? 1.05 : 1.25;
    final childShards = childSplit > 0 ? 6 : 0;
    final spin = _random.nextDouble() * math.pi * 2;
    for (var i = 0; i < bolt.shardCount; i++) {
      final angle = spin + (i / bolt.shardCount) * math.pi * 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      children.add(EnemyBolt(
        position: bolt.position + dir * (bolt.radius + 0.04),
        velocity: dir * childSpeed,
        damage: childDamage,
        color: childSplit > 0
            ? const Color(0xFFFFAB40)
            : const Color(0xFFFFCC80),
        radius: childRadius,
        life: childLife,
        style: EnemyBoltStyle.fireball,
        splitRemaining: childSplit,
        shardCount: childShards,
      ));
    }
    return children;
  }

  /// True if the segment from [from] to [to] passes through solid cover.
  bool _segmentHitsCover(Offset from, Offset to) {
    final delta = to - from;
    final dist = delta.distance;
    if (dist < 1e-6) return _blocksShot(from);
    final dir = delta / dist;
    const step = 0.035;
    for (var along = 0.0; along <= dist; along += step) {
      if (_blocksShot(from + dir * along)) return true;
    }
    return _blocksShot(to);
  }

  void _updateSkyHazards(double dt) {
    for (final hazard in skyHazards) {
      if (hazard.detonated) continue;
      hazard.height = math.max(0, hazard.height - dt * 1.25);
      if (hazard.height > 0) continue;
      hazard.detonated = true;
      if (hazard.summonsZombie) {
        if (zombies.length < 30 ||
            (hazard.summonsNecroMinion && zombies.length < 38)) {
          _spawnZombie(
            forcedKind:
                _random.nextBool() ? ZombieKind.walker : ZombieKind.runner,
            at: hazard.target,
            asNecroMinion: hazard.summonsNecroMinion,
          );
        }
        continue;
      }
      // Impact bump, then lingering fire pit does the real work.
      if ((hazard.target - player).distance <= hazard.blastRadius) {
        _hurtPlayer(hazard.damage);
        if (gameOver) return;
      }
      _hurtGunAlliesInRadius(
        hazard.target,
        hazard.blastRadius,
        hazard.damage,
      );
      firePits.add(FirePit(
        hazard.target,
        life: 5.2,
        radius: hazard.blastRadius + 0.06,
        dps: 12 + wave * 0.4,
      ));
    }
    skyHazards.removeWhere((h) => h.detonated);
  }

  void _updateCorpses(double dt) {
    for (final corpse in corpses) {
      corpse.life -= dt;
    }
    corpses.removeWhere((c) => c.life <= 0);
  }

  void _updatePoisonClouds(double dt) {
    for (final cloud in poisonClouds) {
      cloud.life -= dt;
      if ((cloud.position - player).distance <= cloud.radius) {
        _hurtPlayer(5.5 * dt, allowFractional: true);
        if (gameOver) return;
      }
      _hurtGunAlliesInRadius(cloud.position, cloud.radius, 5.5 * dt);
    }
    poisonClouds.removeWhere((c) => c.life <= 0);
  }

  void _updateStickyGoos(double dt) {
    for (final goo in stickyGoos) {
      goo.life -= dt;
    }
    stickyGoos.removeWhere((g) => g.life <= 0);
  }

  void _updateFirePits(double dt) {
    for (final pit in firePits) {
      pit.life -= dt;
      if (pit.friendly) continue;
      if ((pit.position - player).distance <= pit.radius) {
        _hurtPlayer(pit.dps * dt, allowFractional: true);
        if (gameOver) return;
      }
      _hurtGunAlliesInRadius(pit.position, pit.radius, pit.dps * dt);
    }
    firePits.removeWhere((p) => p.life <= 0);
  }

  void _hurtPlayer(double amount, {bool allowFractional = false}) {
    if (amount <= 0 || gameOver) return;
    if (_shieldTimer > 0 || _invulnTimer > 0) {
      if (abilityMastered &&
          playerClass == PlayerClass.tank &&
          _shieldTimer > 0) {
        _masteryPulseNearby(0.95, 55 + wave * 1.2);
      }
      return;
    }
    var incoming = amount;
    if (classMastered && playerClass == PlayerClass.tank) {
      incoming *= 0.5;
      // Adamant Aegis: retaliate when struck.
      if (_random.nextDouble() < 0.55) {
        _masteryPulseNearby(0.7, 35 + wave * 0.8);
      }
    }
    if (allowFractional) {
      _poisonAcc += incoming;
      if (_poisonAcc < 1) return;
      final dealt = _poisonAcc.floor();
      _poisonAcc -= dealt;
      health = math.max(0, health - dealt);
    } else {
      health = math.max(0, health - math.max(1, incoming.round()));
    }
    _damageFlash = 0.18;
    _sfx(AudioCue.hurt);
    if (health <= 0) {
      health = 0;
      gameOver = true;
      _firing = false;
      bestWave = math.max(bestWave, wave - (waveActive ? 1 : 0));
      _recordHighScoreIfNeeded();
      _sfx(AudioCue.gameOver);
    }
  }

  void _detonateExploder(Zombie zombie) {
    final pos = zombie.position;
    zombie.clearWindUp();
    _meteorCorners.remove(zombie.id);
    _necroRaise.remove(zombie.id);
    zombies.remove(zombie);
    if ((pos - player).distance < 0.38) {
      _hurtPlayer(22 + wave * 0.5);
    }
    _hurtGunAlliesInRadius(pos, 0.38, 22 + wave * 0.5);
    // Visible short fire flash instead of near-invisible poison tick.
    firePits.add(FirePit(pos, life: 1.4, radius: 0.3, dps: 18));
    corpses.add(CorpseMark(pos, life: 8));
    _registerKill(zombie);
  }

  void _detonateGlobling(Zombie zombie) {
    final pos = zombie.position;
    zombie.clearWindUp();
    _meteorCorners.remove(zombie.id);
    _necroRaise.remove(zombie.id);
    zombies.remove(zombie);
    if ((pos - player).distance < 0.4) {
      _hurtPlayer(11 + wave * 0.35);
    }
    _hurtGunAlliesInRadius(pos, 0.4, 11 + wave * 0.35);
    stickyGoos.add(StickyGoo(
      pos,
      life: 6.8,
      radius: 0.36,
      slowFactor: 0.4,
    ));
    blastFlashes.add(BlastFlash(
      pos,
      const Color(0xFF76FF03),
      radius: 0.42,
      life: 0.28,
    ));
    corpses.add(CorpseMark(pos, life: 5));
    _registerKill(zombie);
  }

  void _killZombie(Zombie zombie) {
    if (!zombies.remove(zombie)) return;
    zombie.clearWindUp();
    _meteorCorners.remove(zombie.id);
    _necroRaise.remove(zombie.id);
    if (zombie.kind == ZombieKind.laserOverseer) {
      laserCannons.removeWhere((c) => c.ownerId == zombie.id);
      _showMessage('LASER CANNONS OFFLINE');
    }
    // Linked missiles die with their firer (no player damage).
    final linkedMissiles = enemyBolts
        .where((b) =>
            b.style == EnemyBoltStyle.missile && b.ownerId == zombie.id)
        .toList();
    for (final bolt in linkedMissiles) {
      blastFlashes.add(BlastFlash(
        bolt.position,
        const Color(0xFF90A4AE),
        radius: 0.18,
        life: 0.18,
      ));
      bolt.life = 0;
    }
    enemyBolts.removeWhere((b) => b.life <= 0);
    _registerKill(zombie);
    corpses.add(CorpseMark(zombie.position));

    switch (zombie.kind) {
      case ZombieKind.exploder:
        if ((zombie.position - player).distance < 0.4) {
          _hurtPlayer(18 + wave * 0.4);
        }
        _hurtGunAlliesInRadius(zombie.position, 0.4, 18 + wave * 0.4);
      case ZombieKind.globling:
        stickyGoos.add(StickyGoo(
          zombie.position,
          life: 5.5,
          radius: 0.3,
          slowFactor: 0.45,
        ));
        blastFlashes.add(BlastFlash(
          zombie.position,
          const Color(0xFF76FF03),
          radius: 0.32,
          life: 0.22,
        ));
      case ZombieKind.bloater:
        poisonClouds.add(PoisonCloud(zombie.position));
        _showMessage('TOXIC BURST');
      case ZombieKind.necromancer:
        if (zombie.isAscendedNecromancer) {
          keyDrops.add(
            WorldKeyDrop(kind: KeyKind.boss, position: zombie.position),
          );
          if (zombies.length < 36) {
            final pool = _availableMiniBossKinds;
            final mini = pool[_random.nextInt(pool.length)];
            _spawnZombie(
              forcedKind: mini,
              at: zombie.position + const Offset(0.2, 0),
            );
          }
          _showMessage('THE ASCENDED FALLS — BOSS KEY DROPPED');
        } else if (zombies.length < 28) {
          _spawnZombie(
            forcedKind: ZombieKind.walker,
            at: zombie.position + const Offset(0.12, 0),
            asNecroMinion: true,
          );
          _spawnZombie(
            forcedKind: ZombieKind.walker,
            at: zombie.position + const Offset(-0.12, 0.08),
            asNecroMinion: true,
          );
          _showMessage('DEATH SPAWN');
        }
      case ZombieKind.citadelTower:
        _spawnZombie(
          forcedKind: ZombieKind.apocalypseLord,
          at: zombie.position,
        );
        blastFlashes.add(BlastFlash(
          zombie.position,
          const Color(0xFFFF1744),
          radius: 1.4,
          life: 0.55,
        ));
        _showMessage('THE CITADEL BREAKS — APOCALYPSE LORD RISES');
        _sfx(AudioCue.bossAlert);
      default:
        break;
    }

    if (zombie.kind.isMiniBoss) {
      keyDrops.add(WorldKeyDrop(kind: KeyKind.mini, position: zombie.position));
      _showMessage('MINI KEY DROPPED');
    } else if (zombie.kind == ZombieKind.apocalypseLord ||
        zombie.kind == ZombieKind.dreadlord ||
        zombie.kind == ZombieKind.shadowRonin ||
        zombie.kind == ZombieKind.voidSovereign) {
      keyDrops.add(WorldKeyDrop(kind: KeyKind.boss, position: zombie.position));
      _showMessage('BOSS KEY DROPPED');
    }

    if (totalKills % 10 == 0) {
      _showMessage('$totalKills KILLS');
    }
  }

  double _rayHitDistance(
    Offset origin,
    Offset direction,
    double maxRange,
    Zombie zombie,
  ) {
    var best = double.infinity;
    for (final sample in zombie.bodyHitPoints) {
      final to = sample - origin;
      final along = to.dx * direction.dx + to.dy * direction.dy;
      if (along <= 0 || along > maxRange) continue;
      final closest = origin + direction * along;
      if ((sample - closest).distance <= zombie.hitRadius) {
        best = math.min(best, along);
      }
    }
    return best;
  }

  /// True if a bullet at [point] would hit solid cover (props / house walls).
  bool _blocksShot(Offset point) {
    for (final prop in props) {
      if ((point - prop.position).distance <= prop.radius * 0.9) {
        return true;
      }
    }
    for (final house in houses) {
      if (houseBlocksPoint(house, point, 0.025)) return true;
    }
    for (final chest in chests) {
      if (!chest.opened &&
          (point - chest.position).distance <= 0.13) {
        return true;
      }
    }
    return false;
  }

  /// Distance along [direction] to the first wall/prop, or [maxRange] if clear.
  double _rayOcclusionDistance(
    Offset origin,
    Offset direction,
    double maxRange,
  ) {
    const step = 0.045;
    for (var along = step; along <= maxRange; along += step) {
      if (_blocksShot(origin + direction * along)) {
        return math.max(0.05, along - step * 0.5);
      }
    }
    return maxRange;
  }

  void fire() {
    if (_shotCooldown > 0 || gameOver || paused) return;
    if (_scytheTimer > 0) {
      _startSoulScytheSwing();
      return;
    }
    if (_reloadTimer > 0) return;
    final ammo = magazine[weapon] ?? 0;
    if (ammo <= 0) {
      reload(auto: true);
      return;
    }

    final freeShot = (classMastered &&
            playerClass == PlayerClass.assault &&
            _random.nextDouble() < 0.45) ||
        (weaponMastered &&
            weapon.mastery == WeaponMastery.storm &&
            _random.nextDouble() < 0.4);
    if (!freeShot) {
      magazine[weapon] = ammo - 1;
    }
    var shotCd =
        effectiveWeaponCooldown * (_overdriveTimer > 0 ? 0.35 : 1.0);
    if (_stormTimer > 0) shotCd *= 0.45;
    _shotCooldown = shotCd;
    if (weaponMastered && weapon.mastery == WeaponMastery.overheat) {
      _weaponHeat = math.min(1.0, _weaponHeat + 0.08);
    }
    final maxRange = weapon.range;
    final pierce = weapon.pierces ||
        (classMastered && playerClass == PlayerClass.ranger) ||
        (weaponMastered &&
            (weapon.mastery == WeaponMastery.rail ||
                (weapon.mastery == WeaponMastery.overheat &&
                    _weaponHeat > 0.55)));
    var blastRadius = weapon.explosionRadius;
    if (blastRadius > 0) {
      if (classMastered && playerClass == PlayerClass.demolitions) {
        blastRadius *= 2.0;
      }
      if (weaponMastered &&
          weapon.mastery == WeaponMastery.launcher) {
        blastRadius *= 1.85;
      } else if (weaponMastered && blastRadius > 0) {
        blastRadius *= 1.35;
      }
    }
    final shotDamage = effectiveWeaponDamage.round();
    final tracerDamage =
        (effectiveWeaponDamage * _damageBuffMult).round().clamp(1, 999999);

    final pelletCount = weapon.pellets +
        (weaponMastered && weapon.mastery == WeaponMastery.shotgun
            ? 3
            : 0) +
        (weaponMastered &&
                weapon.mastery == WeaponMastery.storm &&
                _stormTimer > 0
            ? 2
            : 0);

    for (var pellet = 0; pellet < pelletCount; pellet++) {
      final spread = (_random.nextDouble() - 0.5) * weapon.spread;
      final cosA = math.cos(spread);
      final sinA = math.sin(spread);
      final direction = Offset(
        aimDirection.dx * cosA - aimDirection.dy * sinA,
        aimDirection.dx * sinA + aimDirection.dy * cosA,
      );

      // Most guns stop at walls; only piercers punch through cover.
      final occludedRange =
          pierce ? maxRange : _rayOcclusionDistance(player, direction, maxRange);

      final hits = <({Zombie zombie, double along})>[];
      for (final zombie in zombies) {
        final along =
            _rayHitDistance(player, direction, occludedRange, zombie);
        if (along.isFinite) {
          hits.add((zombie: zombie, along: along));
        }
      }
      hits.sort((a, b) => a.along.compareTo(b.along));

      if (pierce) {
        tracers.add(
          BulletTracer(
            player,
            player + direction * occludedRange,
            weapon.color,
            strokeWidth: 4.2,
            life: 0.14,
            damage: tracerDamage,
          ),
        );
        for (final hit in hits) {
          if (_bulletPhasesThrough(hit.zombie)) continue;
          _applyWeaponHit(hit.zombie);
        }
      } else if (blastRadius > 0) {
        double impactAlong = occludedRange;
        for (final hit in hits) {
          if (_bulletPhasesThrough(hit.zombie)) continue;
          impactAlong = hit.along;
          break;
        }
        final impact = player + direction * impactAlong;
        tracers.add(
          BulletTracer(
            player,
            impact,
            weapon.color,
            strokeWidth: 3.4,
            life: 0.12,
            damage: tracerDamage,
          ),
        );
        _detonateWeaponBlast(
          impact,
          shotDamage,
          blastRadius,
          weapon.color,
          ignite: weapon.ignites,
        );
        if (weaponMastered &&
            weapon.mastery == WeaponMastery.launcher) {
          for (final delay in [0.2, 0.4, 0.65]) {
            final jitter = Offset(
              (_random.nextDouble() - 0.5) * 0.7,
              (_random.nextDouble() - 0.5) * 0.7,
            );
            _clusterBombs.add((
              at: _wrap(impact + jitter),
              timer: delay,
              radius: blastRadius * 0.7,
              damage: (shotDamage * 0.7).round(),
              color: weapon.color,
            ));
          }
        }
      } else {
        ({Zombie zombie, double along})? hit;
        for (final candidate in hits) {
          if (_bulletPhasesThrough(candidate.zombie)) continue;
          hit = candidate;
          break;
        }
        final end = hit != null
            ? player + direction * hit.along
            : player + direction * occludedRange;
        tracers.add(BulletTracer(
          player,
          end,
          weapon.color,
          damage: tracerDamage,
        ));
        if (hit != null) {
          _applyWeaponHit(hit.zombie);
        }
      }
    }

    _cullDeadZombies();

    // Per-weapon muzzle report (includes launchers / exotic blasts).
    _sfx(AudioCue.shoot, weapon: weapon);

    if ((magazine[weapon] ?? 0) <= 0) {
      reload(auto: true);
    }
  }

  void _spawnDamageFloater(
    Offset at,
    double dealt, {
    Color? color,
    bool blocked = false,
  }) {
    final jitter = Offset(
      (_random.nextDouble() - 0.5) * 0.12,
      (_random.nextDouble() - 0.5) * 0.08,
    );
    damageFloaters.add(DamageFloater(
      position: _wrap(at + jitter),
      amount: blocked ? 0 : dealt.round().clamp(0, 999999),
      color: blocked
          ? const Color(0xFF90CAF9)
          : (color ?? weapon.color),
      blocked: blocked,
      life: blocked ? 0.45 : 0.7,
    ));
  }

  void _applyWeaponHit(Zombie zombie) {
    if (_tryBlockDamage(zombie)) return;
    var damageMult = _damageBuffMult;
    if (weaponMastered &&
        weapon.mastery == WeaponMastery.brand &&
        _hunterMarkId == zombie.id) {
      damageMult *= 1.9;
    }
    if (weaponMastered && weapon.mastery == WeaponMastery.shotgun) {
      final dist = _wrappedDelta(player, zombie.position).distance;
      if (dist < 0.85) {
        damageMult *= 1.0 + (0.85 - dist) * 2.4; // up to ~3x at point blank
      }
    }
    if (weaponMastered &&
        weapon.mastery == WeaponMastery.creed &&
        _random.nextDouble() < 0.38) {
      damageMult *= 2.6;
      blastFlashes.add(BlastFlash(
        zombie.position,
        const Color(0xFFFFF59D),
        radius: 0.28,
        life: 0.16,
      ));
    }
    final dealt =
        effectiveWeaponDamage * damageMult * zombie.kind.damageTakenFactor;
    zombie.health -= dealt;
    zombie.hitFlash = 0.08;
    _spawnDamageFloater(zombie.position, dealt);
    _addSoulCharge(dealt);
    if (weapon.ignites ||
        (weaponMastered && weapon.mastery == WeaponMastery.inferno)) {
      _applyBurn(
        zombie,
        duration: weaponMastered ? 7.0 : 3.5,
        dps: weaponMastered ? 72 : 28,
      );
    }
    if (weapon.appliesVirus) {
      _applyVirus(
        zombie,
        duration: weaponMastered ? 18.0 : 12.0,
        dps: weaponMastered ? 70 : 32,
      );
    }
    if (weapon.appliesSlow ||
        (weaponMastered && weapon.mastery == WeaponMastery.beam)) {
      _applySlow(
        zombie,
        duration: weaponMastered
            ? 4.5
            : (weapon.rarity.index >= WeaponRarity.legendary.index ? 3.2 : 2.4),
        factor: weaponMastered
            ? 0.2
            : (weapon.rarity.index >= WeaponRarity.legendary.index ? 0.35 : 0.45),
      );
    }
    if (weaponMastered) {
      _applyWeaponMasteryHit(zombie, dealt);
    }
  }

  void _applyWeaponMasteryHit(Zombie zombie, double dealtDamage) {
    switch (weapon.mastery) {
      case WeaponMastery.ricochet:
        // Ricochet Sovereign — bounce to up to 3 nearby foes.
        var bounces = 0;
        var from = zombie.position;
        var exclude = {zombie.id};
        while (bounces < 3) {
          Zombie? next;
          var best = 0.85;
          for (final other in zombies) {
            if (exclude.contains(other.id) || other.health <= 0) continue;
            final d = _wrappedDelta(from, other.position).distance;
            if (d < best) {
              best = d;
              next = other;
            }
          }
          if (next == null || _tryBlockDamage(next)) break;
          final chain = dealtDamage * (0.9 - bounces * 0.15);
          next.health -= chain;
          next.hitFlash = 0.1;
          _spawnDamageFloater(next.position, chain);
          tracers.add(BulletTracer(
            from,
            next.position,
            weapon.color,
            strokeWidth: 2.4,
            life: 0.1,
          ));
          from = next.position;
          exclude.add(next.id);
          bounces++;
        }
        if (zombie.health > 0 &&
            zombie.health / zombie.maxHealth <= 0.28 &&
            _random.nextDouble() < 0.7) {
          zombie.health = 0;
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFFFFD54F),
            radius: 0.35,
            life: 0.2,
          ));
        }
      case WeaponMastery.storm:
        if (_random.nextDouble() < 0.35) {
          zombie.health -= dealtDamage * 0.55;
          _spawnDamageFloater(zombie.position, dealtDamage * 0.55);
        }
      case WeaponMastery.creed:
        if (zombie.health > 0 &&
            zombie.health / zombie.maxHealth <= 0.32 &&
            _random.nextDouble() < 0.65) {
          zombie.health = 0;
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFFFFECB3),
            radius: 0.4,
            life: 0.22,
          ));
        }
      case WeaponMastery.shotgun:
        final dist = _wrappedDelta(player, zombie.position).distance;
        if (dist < 1.0) {
          final shove = _wrappedDelta(player, zombie.position);
          if (shove.distance > 0.01) {
            final dir = shove / shove.distance;
            zombie.position = _wrap(zombie.position + dir * 0.35);
          }
          _masteryPulseAt(
            zombie.position,
            0.55,
            effectiveWeaponDamage * 0.75,
          );
        }
      case WeaponMastery.rail:
        _masteryPulseAt(
          zombie.position,
          0.65,
          effectiveWeaponDamage * 0.9,
        );
        if ((zombie.kind.isBoss || zombie.kind.isMiniBoss) &&
            zombie.health > 0 &&
            zombie.health / zombie.maxHealth <= 0.22) {
          zombie.health = 0;
        }
      case WeaponMastery.brand:
        _hunterMarkId = zombie.id;
        _hunterMarkTimer = 5.5;
        blastFlashes.add(BlastFlash(
          zombie.position,
          const Color(0xFFFFAB40),
          radius: 0.25,
          life: 0.15,
        ));
      case WeaponMastery.inferno:
        // Extra radial scorch.
        for (final other in zombies) {
          if (other.id == zombie.id) continue;
          if (_wrappedDelta(zombie.position, other.position).distance > 0.4) {
            continue;
          }
          _applyBurn(other, duration: 4.0, dps: 40);
        }
      case WeaponMastery.launcher:
        // Handled via blast radius + cluster bombs in fire().
        break;
      case WeaponMastery.overheat:
        if (_weaponHeat > 0.7 && _random.nextDouble() < 0.4) {
          _masteryPulseAt(
            zombie.position,
            0.45,
            effectiveWeaponDamage * 0.6,
          );
        }
      case WeaponMastery.beam:
        // Prism Cascade — chain to 3 enemies.
        var chained = 0;
        var fromPos = zombie.position;
        final hitIds = {zombie.id};
        while (chained < 3) {
          Zombie? next;
          var best = 1.1;
          for (final other in zombies) {
            if (hitIds.contains(other.id) || other.health <= 0) continue;
            final d = _wrappedDelta(fromPos, other.position).distance;
            if (d < best) {
              best = d;
              next = other;
            }
          }
          if (next == null || _tryBlockDamage(next)) break;
          final chain =
              dealtDamage * (0.85 - chained * 0.18) * next.kind.damageTakenFactor;
          next.health -= chain;
          next.hitFlash = 0.1;
          _applySlow(next, duration: 2.8, factor: 0.3);
          _spawnDamageFloater(next.position, chain);
          tracers.add(BulletTracer(
            fromPos,
            next.position,
            weapon.color,
            strokeWidth: 3.2,
            life: 0.12,
          ));
          fromPos = next.position;
          hitIds.add(next.id);
          chained++;
        }
      case WeaponMastery.exotic:
        final roll = _random.nextDouble();
        if (roll < 0.34) {
          // Void pull.
          for (final other in zombies) {
            final delta = _wrappedDelta(other.position, zombie.position);
            if (delta.distance > 1.1 || delta.distance < 0.01) continue;
            other.position = _wrap(
              other.position + (delta / delta.distance) * 0.28,
            );
          }
          blastFlashes.add(BlastFlash(
            zombie.position,
            const Color(0xFF7E57C2),
            radius: 0.9,
            life: 0.25,
          ));
        } else if (roll < 0.67) {
          if (zombie.health / zombie.maxHealth <= 0.4) {
            zombie.health = 0;
          } else {
            zombie.health -= dealtDamage * 1.5;
            _spawnDamageFloater(zombie.position, dealtDamage * 1.5);
          }
        } else {
          _masteryPulseAt(
            zombie.position,
            0.95,
            effectiveWeaponDamage * 1.35,
          );
        }
    }
  }

  bool _tryBlockDamage(Zombie zombie) {
    if (!zombie.isBlocking) return false;
    zombie.hitFlash = 0.05;
    blastFlashes.add(BlastFlash(
      zombie.position,
      const Color(0xFFBBDEFB),
      radius: 0.32,
      life: 0.1,
    ));
    _spawnDamageFloater(zombie.position, 0, blocked: true);
    return true;
  }

  void _detonateWeaponBlast(
    Offset center,
    int damage,
    double radius,
    Color color, {
    bool ignite = false,
  }) {
    blastFlashes.add(BlastFlash(center, color, radius: radius));
    final scaled = damage * _damageBuffMult;
    for (final zombie in zombies) {
      if ((zombie.position - center).distance <= radius + zombie.hitRadius) {
        if (_bulletPhasesThrough(zombie)) continue;
        if (_tryBlockDamage(zombie)) continue;
        final dealt = scaled * zombie.kind.damageTakenFactor;
        zombie.health -= dealt;
        zombie.hitFlash = 0.1;
        _spawnDamageFloater(zombie.position, dealt, color: color);
        _addSoulCharge(dealt);
        if (ignite || weapon.ignites) {
          _applyBurn(zombie, duration: 4.0, dps: 32);
        }
      }
    }
    if (ignite || weapon.ignites) {
      firePits.add(FirePit(
        center,
        life: 2.8,
        radius: math.min(0.55, radius * 0.55),
        dps: 24,
        friendly: true,
      ));
    }
  }

  void _addSoulCharge(double damage, {double mult = 1}) {
    if (playerClass != PlayerClass.reaper || damage <= 0 || gameOver) return;
    var gain = (damage * mult) / soulBarDamageNeeded;
    if (classMastered) gain *= 1.35;
    if (_scytheTimer > 0) gain *= 1.35;
    _soulCharge += gain;
    var surges = 0;
    final heal = soulSurgeHealAmount;
    while (_soulCharge >= 1) {
      _soulCharge -= 1;
      surges++;
      _healFromCrate(heal);
      blastFlashes.add(BlastFlash(
        player,
        const Color(0xFFB388FF),
        radius: 0.55,
        life: 0.28,
      ));
    }
    if (surges > 0) {
      _showMessage(
        surges == 1 ? 'SOUL SURGE +$heal' : 'SOUL SURGE x$surges (+$heal)',
      );
    }
  }

  void _reaperOpeningCleave() {
    final radius = 0.9 * abilityPower;
    final dmg = 36 * abilityPower * _damageBuffMult;
    for (final zombie in List<Zombie>.from(zombies)) {
      if (_wrappedDelta(player, zombie.position).distance >
          radius + zombie.hitRadius) {
        continue;
      }
      if (_tryBlockDamage(zombie)) continue;
      final dealt = dmg * zombie.kind.damageTakenFactor;
      zombie.health -= dealt;
      zombie.hitFlash = 0.14;
      _addSoulCharge(dealt, mult: 1.2);
      final push = _wrappedDelta(player, zombie.position);
      if (push.distance > 0.001) {
        zombie.position = _wrap(
          zombie.position + (push / push.distance) * 0.14,
        );
      }
    }
    blastFlashes.add(BlastFlash(
      player,
      const Color(0xFFE1BEE7),
      radius: radius,
      life: 0.32,
    ));
    _cullDeadZombies();
  }

  void _tickSoulScythe(double dt) {
    if (_scytheTimer <= 0) {
      _scytheSwingPhase = 0;
      _scytheSwingAngle = 0;
      _scytheAttackProgress = 0;
      _scytheHitIds.clear();
      return;
    }

    if (_scytheAttackProgress > 0 && _scytheAttackProgress < 1) {
      final swingDuration = abilityMastered ? 0.26 : 0.32;
      _scytheAttackProgress =
          math.min(1.0, _scytheAttackProgress + dt / swingDuration);
      final t = _scytheAttackProgress;
      final eased = t * t * (3 - 2 * t);
      final from = -_scytheSwingDir * 1.25;
      final to = _scytheSwingDir * 1.25;
      _scytheSwingAngle = from + (to - from) * eased;

      // Active melee window — blade is cutting through the arc.
      if (t >= 0.18 && t <= 0.88) {
        _soulScytheMeleeSweep();
      }

      if (_scytheAttackProgress >= 1) {
        _scytheAttackProgress = 0;
        _scytheSwingAngle = to * 0.9;
        _scytheHitIds.clear();
      }
    } else {
      // Idle ready stance on the side the next swing starts from.
      final rest = -_scytheSwingDir * 1.05;
      _scytheSwingAngle += (rest - _scytheSwingAngle) * math.min(1.0, dt * 10);
    }
  }

  void _startSoulScytheSwing() {
    if (_scytheAttackProgress > 0 && _scytheAttackProgress < 1) return;
    _scytheSwingDir = -_scytheSwingDir;
    _scytheAttackProgress = 0.001;
    _scytheHitIds.clear();
    // Melee cadence — one committed swing, then recovery.
    _shotCooldown = abilityMastered ? 0.38 : 0.48;
    final facing = aimDirection.distance > 0.01
        ? aimDirection
        : const Offset(0, -1);
    final wind = _rotateOffset(facing, -_scytheSwingDir * 1.2);
    blastFlashes.add(BlastFlash(
      _wrap(player + wind * 0.35),
      const Color(0x66E1BEE7),
      radius: 0.22,
      life: 0.1,
    ));
  }

  Offset _rotateOffset(Offset v, double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  void _soulScytheMeleeSweep() {
    final facing = aimDirection.distance > 0.01
        ? aimDirection
        : const Offset(0, -1);
    final swingDir = _rotateOffset(facing, _scytheSwingAngle);
    final range = 1.15 * (0.95 + abilityPower * 0.1);
    final halfArc = -0.15;
    final dmg = (48 + wave * 1.15) * abilityPower * _damageBuffMult;
    var hits = 0;
    for (final zombie in List<Zombie>.from(zombies)) {
      if (_scytheHitIds.contains(zombie.id)) continue;
      final delta = _wrappedDelta(player, zombie.position);
      final dist = delta.distance;
      if (dist > range + zombie.hitRadius || dist < 0.001) continue;
      final dir = delta / dist;
      final aligned = dir.dx * swingDir.dx + dir.dy * swingDir.dy;
      if (aligned < halfArc) continue;
      if (_tryBlockDamage(zombie)) continue;

      final dealt = dmg * zombie.kind.damageTakenFactor;
      zombie.health -= dealt;
      zombie.hitFlash = 0.14;
      _scytheHitIds.add(zombie.id);
      _addSoulCharge(dealt, mult: 1.55);
      final shove = _rotateOffset(dir, _scytheSwingDir * 0.55);
      zombie.position = _wrap(zombie.position + shove * 0.22);
      hits++;
    }

    if (hits > 0 ||
        (_scytheAttackProgress > 0.35 && _scytheAttackProgress < 0.55)) {
      final tip = _wrap(player + swingDir * range * 0.92);
      final left = Offset(-swingDir.dy, swingDir.dx);
      tracers.add(BulletTracer(
        _wrap(player + left * 0.05 * _scytheSwingDir.toDouble()),
        tip,
        const Color(0xFFE1BEE7),
        strokeWidth: 9,
        life: 0.08,
      ));
      if (hits > 0) {
        blastFlashes.add(BlastFlash(
          tip,
          const Color(0xFFCE93D8),
          radius: 0.28 + hits * 0.03,
          life: 0.1,
        ));
      }
    }
    if (hits > 0) _cullDeadZombies();
  }

  void _cullDeadZombies() {
    final dead = zombies.where((zombie) => zombie.health <= 0).toList();
    for (final zombie in dead) {
      _killZombie(zombie);
      if (gameOver) return;
    }
  }

  void _updateWorldLoot() {
    // Pickup keys.
    for (final drop in keyDrops) {
      if (drop.pickedUp) continue;
      if ((drop.position - player).distance < 0.35) {
        drop.pickedUp = true;
        if (drop.kind == KeyKind.mini) {
          miniKeys++;
        } else {
          bossKeys++;
        }
        _showMessage('${drop.kind.label.toUpperCase()} ACQUIRED');
        _sfx(AudioCue.pickup);
      }
    }
    keyDrops.removeWhere((d) => d.pickedUp);

    // Open chests with keys (chests live inside houses).
    for (final chest in chests) {
      if (chest.opened) continue;
      if ((chest.position - player).distance > 0.22) continue;
      final hasKey = chest.requiredKey == KeyKind.mini
          ? miniKeys > 0
          : bossKeys > 0;
      if (!hasKey) {
        if (_lootHintTimer <= 0) {
          _showMessage('LOCKED — NEED ${chest.requiredKey.label.toUpperCase()}');
          _lootHintTimer = 1.6;
        }
        continue;
      }
      if (chest.requiredKey == KeyKind.mini) {
        miniKeys--;
      } else {
        bossKeys--;
      }
      chest.opened = true;
      chest.respawnTimer = chest.requiredKey == KeyKind.boss ? 55 : 40;
      _sfx(AudioCue.pickup);
      _grantPremiumLoot(
        prefix: 'CHEST',
        kind: chest.lootKind,
        weapon: chest.weapon,
        moneyBonus: chest.bonusMoney,
        healBonus: chest.bonusHeal,
      );
    }
  }

  void _updateChestRespawns(double dt) {
    for (final chest in chests) {
      if (!chest.opened || chest.respawnTimer <= 0) continue;
      chest.respawnTimer = math.max(0, chest.respawnTimer - dt);
      if (chest.respawnTimer > 0) continue;
      _respawnChest(chest);
    }
  }

  void _respawnChest(TreasureChest chest) {
    final loot = _rollChestLoot(chest.requiredKey);
    chest.opened = false;
    chest.lootKind = loot.kind;
    chest.weapon = loot.weapon;
    chest.bonusMoney = loot.money;
    chest.bonusHeal = loot.heal;
    chest.respawnTimer = 0;
    blastFlashes.add(BlastFlash(
      chest.position,
      chest.requiredKey.color,
      radius: 0.28,
      life: 0.35,
    ));
    _showMessage('${chest.requiredKey.label.toUpperCase()} CHEST RESTOCKED');
  }

  void _grantPremiumLoot({
    required String prefix,
    required CrateLootKind kind,
    WeaponKind? weapon,
    int moneyBonus = 0,
    int healBonus = 0,
  }) {
    if (moneyBonus > 0) _earnMoney(moneyBonus);
    if (healBonus > 0) _heal(healBonus);

    switch (kind) {
      case CrateLootKind.weapon:
        if (weapon != null) {
          _grantWeapon(weapon, source: prefix, moneyBonus: moneyBonus);
          return;
        }
        // Fall through to money if weapon somehow null.
        final amount = moneyBonus > 0 ? moneyBonus : 120 + wave * 15;
        if (moneyBonus <= 0) _earnMoney(amount);
        _showMessage('$prefix: +\$$amount');
      case CrateLootKind.money:
        final amount = moneyBonus > 0 ? moneyBonus : 150 + wave * 18;
        if (moneyBonus <= 0) _earnMoney(amount);
        _showMessage(
          '$prefix: +\$$amount${healBonus > 0 ? ' +$healBonus HP' : ''}',
        );
      case CrateLootKind.health:
        final amount = healBonus > 0 ? healBonus : 40 + _random.nextInt(30);
        if (healBonus <= 0) _heal(amount);
        _showMessage(
          '$prefix: +$amount HP${moneyBonus > 0 ? ' +\$$moneyBonus' : ''}',
        );
    }
  }

  void _updateCrates(double dt) {
    _crateTimer -= dt;
    if (_crateTimer <= 0 && crates.length < 7) {
      _dropCrate();
      _crateTimer = 6 + _random.nextDouble() * 5;
    }

    for (final crate in crates) {
      crate.height = math.max(0, crate.height - dt * 0.42);
      if (crate.height <= 0 &&
          !crate.opened &&
          (crate.position - player).distance < 0.16) {
        crate.opened = true;
        _sfx(AudioCue.pickup);
        switch (crate.lootKind) {
          case CrateLootKind.money:
            final amount = _crateMoneyAmount(crate.displayRarity);
            _earnMoney(amount);
            _showMessage(
              'CRATE (${crate.displayRarity.label.toUpperCase()}): +\$$amount',
            );
          case CrateLootKind.health:
            final amount = _crateHealAmount(crate.displayRarity);
            _healFromCrate(amount);
            _showMessage(
              health > maxHealth
                  ? 'CRATE (${crate.displayRarity.label.toUpperCase()}): +$amount HP (OVERHEAL)'
                  : 'CRATE (${crate.displayRarity.label.toUpperCase()}): +$amount HP',
            );
          case CrateLootKind.weapon:
            _grantWeapon(crate.weapon!, source: 'CRATE');
        }
      }
    }
    crates.removeWhere((crate) => crate.opened);
  }

  void _dropCrate() {
    final pad = arenaHalf - 0.35;
    final position = Offset(
      (_random.nextDouble() * 2 - 1) * pad,
      (_random.nextDouble() * 2 - 1) * pad,
    );

    final roll = _random.nextDouble();
    late CrateLootKind lootKind;
    WeaponKind? weaponDrop;

    if (roll < 0.34) {
      lootKind = CrateLootKind.health;
    } else if (roll < 0.58) {
      lootKind = CrateLootKind.money;
    } else {
      lootKind = CrateLootKind.weapon;
      weaponDrop = _rollWeaponDrop();
      if (weaponDrop == null) {
        lootKind =
            _random.nextBool() ? CrateLootKind.health : CrateLootKind.money;
      }
    }

    crates.add(SupplyCrate(
      position: position,
      lootKind: lootKind,
      weapon: weaponDrop,
      rarity: weaponDrop?.rarity ?? _rollCrateRarity(),
    ));
    _showMessage('SUPPLY DROP INBOUND');
  }

  /// Money / HP crate rarity — higher tiers unlock as waves climb.
  /// Mythic+ is intentionally scarce (separate low-odds gate).
  WeaponRarity _rollCrateRarity() {
    final roll = _random.nextDouble();
    if (wave >= 18 && roll < 0.012) return WeaponRarity.ascendant;
    if (wave >= 14 && roll < 0.03) return WeaponRarity.mythic;

    final weighted = <WeaponRarity>[
      WeaponRarity.common,
      WeaponRarity.common,
      WeaponRarity.common,
      WeaponRarity.common,
      WeaponRarity.uncommon,
      WeaponRarity.uncommon,
    ];
    if (wave >= 2) {
      weighted.addAll([WeaponRarity.rare, WeaponRarity.rare]);
    }
    if (wave >= 4) {
      weighted.addAll([WeaponRarity.epic, WeaponRarity.rare]);
    }
    if (wave >= 7) weighted.add(WeaponRarity.legendary);
    return weighted[_random.nextInt(weighted.length)];
  }

  double _crateRarityMult(WeaponRarity rarity) => switch (rarity) {
        WeaponRarity.common => 1.0,
        WeaponRarity.uncommon => 1.4,
        WeaponRarity.rare => 1.85,
        WeaponRarity.epic => 2.4,
        WeaponRarity.legendary => 3.2,
        WeaponRarity.mythic => 4.2,
        WeaponRarity.ascendant => 5.5,
      };

  int _crateMoneyAmount(WeaponRarity rarity) {
    final base = 45 + wave * 6;
    return math.max(1, (base * _crateRarityMult(rarity)).round());
  }

  int _crateHealAmount(WeaponRarity rarity) {
    final base = 25 + _random.nextInt(21);
    return math.max(1, (base * _crateRarityMult(rarity)).round());
  }

  WeaponKind? _rollWeaponDrop() {
    final locked = WeaponKind.values
        .where((candidate) => !unlockedWeapons.contains(candidate))
        .toList();
    if (locked.isEmpty) return null;

    final weighted = <WeaponKind>[];
    for (final kind in locked) {
      final weight = weaponDropWeight(kind);
      for (var i = 0; i < weight; i++) {
        weighted.add(kind);
      }
    }
    if (weighted.isEmpty) {
      return locked[_random.nextInt(locked.length)];
    }
    return weighted[_random.nextInt(weighted.length)];
  }

  /// Integer bag weight for [kind] in supply-crate weapon rolls (0 = ineligible).
  int weaponDropWeight(WeaponKind kind) => switch (kind.rarity) {
        WeaponRarity.common => 10,
        WeaponRarity.uncommon => 7,
        WeaponRarity.rare => wave >= 2 ? 5 : 1,
        WeaponRarity.epic => wave >= 4 ? 3 : 0,
        WeaponRarity.legendary => wave >= 7 ? 2 : 0,
        WeaponRarity.mythic => wave >= 14 ? 1 : 0,
        WeaponRarity.ascendant => wave >= 18 ? 1 : 0,
      };

  /// Earliest wave where [kind] can appear in normal supply weapon drops.
  int? weaponDropUnlockWave(WeaponKind kind) => switch (kind.rarity) {
        WeaponRarity.epic => 4,
        WeaponRarity.legendary => 7,
        WeaponRarity.mythic => 14,
        WeaponRarity.ascendant => 18,
        _ => null,
      };

  /// Chance that a weapon supply crate yields [kind] (0–1).
  ///
  /// Owned guns are still scored as if they remained in the pool so the UI can
  /// keep showing odds after unlock; the live roller only picks locked guns.
  double weaponDropChance(WeaponKind kind) {
    final pool = WeaponKind.values
        .where((candidate) =>
            !unlockedWeapons.contains(candidate) || candidate == kind)
        .toList();
    if (pool.isEmpty) return 0;

    var total = 0;
    for (final candidate in pool) {
      total += weaponDropWeight(candidate);
    }
    if (total <= 0) {
      // Fallback: equal odds among every gun in the display pool.
      return 1.0 / pool.length;
    }
    return weaponDropWeight(kind) / total;
  }

  /// Short UI label for drop odds (e.g. `8% drop`, `Wave 14+`).
  String weaponDropOddsLabel(WeaponKind kind) {
    final unlockWave = weaponDropUnlockWave(kind);
    if (weaponDropWeight(kind) <= 0 &&
        unlockWave != null &&
        wave < unlockWave) {
      return 'Wave $unlockWave+';
    }
    final chance = weaponDropChance(kind);
    if (chance <= 0) return '—';
    final pct = chance * 100;
    if (pct < 0.5) return '<1% drop';
    if (pct < 10) return '${pct.toStringAsFixed(1)}% drop';
    return '${pct.round()}% drop';
  }

  void togglePause() {
    if (gameOver || badEndingCutscene) return;
    paused = !paused;
    notifyListeners();
  }

  @visibleForTesting
  void debugAdvanceToWave(int target) {
    while (wave < target) {
      zombies.clear();
      laserCannons.clear();
      waveActive = false;
      nextWaveTimer = 0;
      _startWave();
    }
  }

  @visibleForTesting
  void debugKill(Zombie zombie) => _killZombie(zombie);

  @visibleForTesting
  void debugAddSoulCharge(double bars) {
    if (playerClass != PlayerClass.reaper) return;
    _addSoulCharge(bars * soulBarDamageNeeded);
  }

  @visibleForTesting
  void debugGrantWeapon(WeaponKind kind) =>
      _grantWeapon(kind, source: 'TEST');

  @visibleForTesting
  void debugSpawnGloblingPack() {
    const position = Offset(2, 0);
    zombies.clear();
    _addZombie(ZombieKind.globling, position);
    for (var i = 0; i < 4; i++) {
      _addZombie(
        ZombieKind.globling,
        _wrap(position + Offset(0.12 * i, 0.06 * i)),
      );
    }
  }

  @visibleForTesting
  void debugSpawnRegular(ZombieKind kind) {
    _spawnZombie(forcedKind: kind);
  }

  @visibleForTesting
  void debugSetupNecroBadEndingSolo({int minions = 2}) {
    zombies.clear();
    laserCannons.clear();
    _remainingToSpawn = 0;
    waveActive = true;
    wave = math.max(wave, 5);
    badEndingCutscene = false;
    badEndingActive = false;
    _necroSoloTimer = 0;
    _addZombie(ZombieKind.necromancer, Offset.zero);
    for (var i = 0; i < minions; i++) {
      _addZombie(
        ZombieKind.walker,
        Offset(0.25 + i * 0.15, 0.1 * i),
        asNecroMinion: true,
      );
    }
  }

  @visibleForTesting
  double get debugNecroSoloTimer => _necroSoloTimer;

  @visibleForTesting
  bool debugBulletPhasesThrough(Zombie zombie) => _bulletPhasesThrough(zombie);

  @visibleForTesting
  Future<void> debugRecordHighScore() async {
    awaitingNameEntry = false;
    pendingScore = null;
    _scoreRecorded = false;
    final entry = HighScoreEntry(
      wave: wave,
      kills: totalKills,
      money: totalMoneyEarned,
      className: playerClass.label,
      at: DateTime.now(),
      playerName: 'Tester',
    );
    _scoreRecorded = true;
    highScores = await HighScoreStore.record(entry);
    lastRecordedScoreAt =
        highScores.any((e) => e.at == entry.at) ? entry.at : null;
    notifyListeners();
  }

  /// Test helper: open the name-entry prompt for the current run stats.
  Future<void> debugPromptHighScoreName() async {
    awaitingNameEntry = false;
    pendingScore = null;
    _scoreRecorded = false;
    await _recordHighScoreIfNeeded();
  }

  /// Center-aim impact preview for the HUD laser / reticle.
  ({
    Offset impact,
    bool hitEnemy,
    double along,
    double blastRadius,
  }) get aimPreview {
    final dir = aimDirection.distance > 0.001
        ? aimDirection / aimDirection.distance
        : const Offset(0, -1);
    final maxRange = weapon.range;
    final pierce = weapon.pierces ||
        (classMastered && playerClass == PlayerClass.ranger) ||
        (weaponMastered &&
            (weapon.mastery == WeaponMastery.rail ||
                (weapon.mastery == WeaponMastery.overheat &&
                    _weaponHeat > 0.55)));
    final occluded =
        pierce ? maxRange : _rayOcclusionDistance(player, dir, maxRange);

    var blastRadius = weapon.explosionRadius;
    if (blastRadius > 0) {
      if (classMastered && playerClass == PlayerClass.demolitions) {
        blastRadius *= 2.0;
      }
      if (weaponMastered &&
          weapon.mastery == WeaponMastery.launcher) {
        blastRadius *= 1.85;
      } else if (weaponMastered && blastRadius > 0) {
        blastRadius *= 1.35;
      }
    }

    ({Zombie zombie, double along})? firstHit;
    for (final zombie in zombies) {
      final along = _rayHitDistance(player, dir, occluded, zombie);
      if (!along.isFinite) continue;
      if (_bulletPhasesThrough(zombie)) continue;
      if (firstHit == null || along < firstHit.along) {
        firstHit = (zombie: zombie, along: along);
      }
    }

    if (pierce) {
      // Piercers keep flying; preview marks max clear range (or first soft hit).
      final along = firstHit?.along ?? occluded;
      return (
        impact: player + dir * along,
        hitEnemy: firstHit != null,
        along: along,
        blastRadius: blastRadius,
      );
    }

    final along = firstHit?.along ?? occluded;
    return (
      impact: player + dir * along,
      hitEnemy: firstHit != null,
      along: along,
      blastRadius: blastRadius,
    );
  }

  void _showMessage(String message) {
    notification = message;
    notificationTimer = 2.2;
  }
}
