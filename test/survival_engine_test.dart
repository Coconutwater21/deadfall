import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deadfall/game/high_scores.dart';
import 'package:deadfall/game/survival_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('map wraps when walking off an edge', () {
    final engine = SurvivalEngine(random: Random(7));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;

    engine.player = Offset(engine.arenaBound - 0.01, 0);
    engine.setMovement(const Offset(1, 0));
    for (var i = 0; i < 80; i++) {
      engine.update(0.05);
    }
    expect(engine.player.dx, lessThan(0));
  });

  test('regenerates one hp every two seconds', () {
    final engine = SurvivalEngine(random: Random(2));
    engine.zombies.clear();
    engine.crates.clear();
    engine.firePits.clear();
    engine.poisonClouds.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.health = 40;

    for (var i = 0; i < 39; i++) {
      engine.update(0.05); // 1.95s
    }
    expect(engine.health, 40);

    engine.update(0.05); // 2.00s
    expect(engine.health, 41);
  });

  test('classes unlock by spending money and kills', () {
    final engine = SurvivalEngine(random: Random(5));
    expect(engine.unlockClass(PlayerClass.scout), isFalse);

    engine.money = PlayerClass.scout.moneyCost + 10;
    engine.kills = PlayerClass.scout.killCost + 3;
    expect(engine.unlockClass(PlayerClass.scout), isTrue);
    expect(engine.playerClass, PlayerClass.scout);
    expect(engine.money, 10);
    expect(engine.kills, 3);
  });

  test('weapon drop chances sum to 1 among locked guns', () {
    final engine = SurvivalEngine(random: Random(11));
    engine.debugAdvanceToWave(20);

    final locked = WeaponKind.values
        .where((k) => !engine.unlockedWeapons.contains(k))
        .toList();
    expect(locked, isNotEmpty);

    var sum = 0.0;
    for (final kind in locked) {
      final chance = engine.weaponDropChance(kind);
      expect(chance, greaterThan(0));
      expect(engine.weaponDropOddsLabel(kind), contains('%'));
      sum += chance;
    }
    expect(sum, closeTo(1.0, 1e-9));

    // Owned guns still show drop odds (scored as if they stayed in the pool).
    expect(engine.weaponDropChance(WeaponKind.pistol), greaterThan(0));
    expect(engine.weaponDropOddsLabel(WeaponKind.pistol), contains('%'));

    final early = SurvivalEngine(random: Random(12));
    expect(early.wave, lessThan(4));
    final epic = WeaponKind.values.firstWhere((k) => k.rarity == WeaponRarity.epic);
    expect(early.weaponDropWeight(epic), 0);
    expect(early.weaponDropOddsLabel(epic), 'Wave 4+');
  });

  test('weapon rarities are balanced and expanded', () {
    expect(WeaponRarity.ascendant.label, 'Ascendant');
    expect(WeaponKind.values.length, greaterThanOrEqualTo(45));
    expect(weaponProfiles.length, WeaponKind.values.length);
    expect(WeaponKind.voidCannon.rarity, WeaponRarity.mythic);
    expect(WeaponKind.apocalypseCannon.rarity, WeaponRarity.ascendant);
    expect(WeaponKind.railgun.pierces, isTrue);
    expect(WeaponKind.eternityRail.pierces, isTrue);
    expect(WeaponKind.grenadeLauncher.explosionRadius, greaterThan(0));
    expect(WeaponKind.novaStorm.explosionRadius, greaterThan(0));
    expect(PlayerClass.values.length, greaterThanOrEqualTo(8));
    expect(ZombieKind.values.length, greaterThanOrEqualTo(14));
    expect(SurvivalEngine.arenaHalf, greaterThanOrEqualTo(7));

    double avgDps(WeaponRarity rarity) {
      final guns = WeaponKind.values.where((w) => w.rarity == rarity).toList();
      expect(guns, isNotEmpty);
      return guns.map((w) => w.dps).reduce((a, b) => a + b) / guns.length;
    }

    final common = avgDps(WeaponRarity.common);
    final uncommon = avgDps(WeaponRarity.uncommon);
    final rare = avgDps(WeaponRarity.rare);
    final epic = avgDps(WeaponRarity.epic);
    final legendary = avgDps(WeaponRarity.legendary);
    final mythic = avgDps(WeaponRarity.mythic);
    final ascendant = avgDps(WeaponRarity.ascendant);

    expect(uncommon, greaterThan(common));
    expect(rare, greaterThan(uncommon));
    expect(epic, greaterThan(rare));
    expect(legendary, greaterThan(epic));
    expect(mythic, greaterThan(legendary));
    expect(ascendant, greaterThan(mythic));
  });

  test('railgun pierces through multiple zombies', () {
    final engine = SurvivalEngine(random: Random(11));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);
    engine.unlockedWeapons.add(WeaponKind.railgun);
    engine.equip(WeaponKind.railgun);

    final near = Zombie(
      id: 1,
      kind: ZombieKind.walker,
      position: const Offset(0.8, 0),
      health: 40,
      maxHealth: 40,
      speed: 0,
      reward: 1,
    );
    final far = Zombie(
      id: 2,
      kind: ZombieKind.walker,
      position: const Offset(2.0, 0),
      health: 40,
      maxHealth: 40,
      speed: 0,
      reward: 1,
    );
    engine.zombies.addAll([near, far]);
    engine.fire();

    expect(near.health, lessThan(40));
    expect(far.health, lessThan(40));
  });

  test('grenade launcher detonates with splash damage', () {
    final engine = SurvivalEngine(random: Random(13));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);
    engine.unlockedWeapons.add(WeaponKind.grenadeLauncher);
    engine.equip(WeaponKind.grenadeLauncher);

    final target = Zombie(
      id: 1,
      kind: ZombieKind.walker,
      position: const Offset(1.2, 0),
      health: 200,
      maxHealth: 200,
      speed: 0,
      reward: 1,
    );
    final splash = Zombie(
      id: 2,
      kind: ZombieKind.walker,
      position: const Offset(1.35, 0.35),
      health: 200,
      maxHealth: 200,
      speed: 0,
      reward: 1,
    );
    engine.zombies.addAll([target, splash]);
    engine.fire();

    expect(target.health, lessThan(200));
    expect(splash.health, lessThan(200));
    expect(engine.blastFlashes, isNotEmpty);
  });

  test('number keys buy locked classes when affordable', () {
    final engine = SurvivalEngine(random: Random(9));
    expect(engine.selectClassByHotkey(1), isFalse);
    expect(engine.unlockedClasses.contains(PlayerClass.scout), isFalse);

    engine.money = PlayerClass.scout.moneyCost;
    engine.kills = PlayerClass.scout.killCost;
    expect(engine.selectClassByHotkey(1), isTrue);
    expect(engine.unlockedClasses.contains(PlayerClass.scout), isTrue);
    expect(engine.playerClass, PlayerClass.scout);
    expect(engine.money, 0);
  });

  test('rpg ignites and blowdart spreads virus', () {
    final engine = SurvivalEngine(random: Random(17));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);

    final target = Zombie(
      id: 1,
      kind: ZombieKind.walker,
      position: const Offset(1.0, 0),
      health: 500,
      maxHealth: 500,
      speed: 0.2,
      reward: 1,
    );
    final neighbor = Zombie(
      id: 2,
      kind: ZombieKind.walker,
      position: const Offset(1.3, 0.15),
      health: 500,
      maxHealth: 500,
      speed: 0.2,
      reward: 1,
    );
    engine.zombies.addAll([target, neighbor]);

    engine.unlockedWeapons.add(WeaponKind.rpg);
    engine.equip(WeaponKind.rpg);
    engine.magazine[WeaponKind.rpg] = 1;
    engine.fire();
    expect(target.isBurning || neighbor.isBurning, isTrue);
    expect(engine.firePits, isNotEmpty);
    expect(engine.firePits.every((p) => p.friendly), isTrue);
    final hp = engine.health;
    engine.zombies.clear();
    engine.player = engine.firePits.first.position;
    for (var i = 0; i < 20; i++) {
      engine.update(0.05);
    }
    expect(engine.health, hp);

    engine.zombies
      ..clear()
      ..addAll([
        Zombie(
          id: 3,
          kind: ZombieKind.walker,
          position: const Offset(1.0, 0),
          health: 200,
          maxHealth: 200,
          speed: 0.25,
          reward: 1,
        ),
        Zombie(
          id: 4,
          kind: ZombieKind.walker,
          position: const Offset(1.25, 0.1),
          health: 200,
          maxHealth: 200,
          speed: 0.25,
          reward: 1,
        ),
      ]);
    engine.unlockedWeapons.add(WeaponKind.blowdart);
    engine.equip(WeaponKind.blowdart);
    engine.magazine[WeaponKind.blowdart] = 5;
    engine.fire();
    expect(engine.zombies.any((z) => z.isInfected), isTrue);
    for (var i = 0; i < 20; i++) {
      engine.update(0.05);
    }
    expect(engine.zombies.where((z) => z.isInfected).length, greaterThanOrEqualTo(2));
  });

  test('number keys select unlocked classes by slot', () {
    final engine = SurvivalEngine(random: Random(3));
    expect(engine.selectClassByHotkey(0), isTrue);
    expect(engine.playerClass, PlayerClass.survivor);

    expect(engine.selectClassByHotkey(1), isFalse);
    expect(engine.playerClass, PlayerClass.survivor);

    engine.money = PlayerClass.scout.moneyCost;
    engine.kills = PlayerClass.scout.killCost;
    expect(engine.selectClassByHotkey(1), isTrue);
    expect(engine.playerClass, PlayerClass.scout);
    expect(engine.unlockedClasses.contains(PlayerClass.scout), isTrue);
    expect(engine.money, 0);
    expect(engine.kills, 0);

    expect(engine.selectClassByHotkey(0), isTrue);
    expect(engine.playerClass, PlayerClass.survivor);
  });

  test('class abilities unlock at high cost and activate', () {
    final engine = SurvivalEngine(random: Random(21));
    expect(engine.activateAbility(), isFalse);
    expect(engine.unlockedAbilities, isEmpty);

    engine.money = PlayerClass.survivor.abilityMoneyCost;
    engine.kills = PlayerClass.survivor.abilityKillCost;
    expect(engine.unlockAbility(PlayerClass.survivor), isTrue);
    expect(engine.unlockedAbilities.contains(PlayerClass.survivor), isTrue);
    expect(engine.activateAbility(), isTrue);
    expect(engine.abilityCooldownLeft, greaterThan(0));
  });

  test('class ability and weapon upgrades scale stats and cap at max', () {
    final engine = SurvivalEngine(random: Random(31));
    final baseHp = engine.maxHealth;
    final baseDmg = engine.effectiveWeaponDamage;
    final baseCd = engine.abilityCooldownMax;

    expect(engine.canUpgradeClass(PlayerClass.survivor), isFalse);
    engine.money = 50000;
    engine.kills = 5000;
    expect(engine.upgradeClass(PlayerClass.survivor), isTrue);
    expect(engine.classLevel(PlayerClass.survivor), 1);
    expect(engine.maxHealth, greaterThan(baseHp));
    expect(engine.effectiveMoveSpeed,
        greaterThan(PlayerClass.survivor.moveSpeed));

    expect(engine.unlockAbility(PlayerClass.survivor), isTrue);
    final beforeAbilityCd = engine.abilityCooldownMax;
    expect(engine.upgradeAbility(PlayerClass.survivor), isTrue);
    expect(engine.abilityLevel(PlayerClass.survivor), 1);
    expect(engine.abilityCooldownMax, lessThan(beforeAbilityCd));
    expect(engine.abilityPower, greaterThan(1));

    final gun = WeaponKind.pistol;
    expect(engine.unlockedWeapons.contains(gun), isTrue);
    final beforeMag = engine.magazineSizeFor(gun);
    expect(engine.upgradeWeapon(gun), isTrue);
    expect(engine.weaponLevel(gun), 1);
    expect(engine.magazineSizeFor(gun), beforeMag + 1);
    engine.equip(gun);
    expect(engine.effectiveWeaponDamage, greaterThan(baseDmg));

    for (var i = 0; i < SurvivalUpgrades.maxLevel; i++) {
      engine.money = 100000;
      engine.kills = 10000;
      engine.upgradeClass(PlayerClass.survivor);
      engine.upgradeAbility(PlayerClass.survivor);
      engine.upgradeWeapon(gun);
    }
    expect(engine.classLevel(PlayerClass.survivor), SurvivalUpgrades.maxLevel);
    expect(engine.abilityLevel(PlayerClass.survivor), SurvivalUpgrades.maxLevel);
    expect(engine.weaponLevel(gun), SurvivalUpgrades.maxLevel);
    expect(engine.canUpgradeClass(PlayerClass.survivor), isFalse);
    expect(engine.canUpgradeAbility(PlayerClass.survivor), isFalse);
    expect(engine.canUpgradeWeapon(gun), isFalse);
    expect(engine.abilityCooldownMax, lessThan(baseCd));
  });

  test('survivor class mastery heals on kill', () {
    final engine = SurvivalEngine(random: Random(42));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    engine.money = 200000;
    engine.kills = 20000;
    for (var i = 0; i < SurvivalUpgrades.maxLevel; i++) {
      engine.upgradeClass(PlayerClass.survivor);
    }
    expect(engine.classMastered, isTrue);
    engine.health = 40;
    final prey = Zombie(
      id: 7702,
      kind: ZombieKind.walker,
      position: const Offset(0.4, 0),
      health: 1,
      maxHealth: 1,
      speed: 0,
      reward: 1,
    );
    engine.zombies.add(prey);
    engine.debugKill(prey);
    expect(engine.health, greaterThan(40));
  });

  test('mastered ability adds rally pulse damage', () {
    final engine = SurvivalEngine(random: Random(43));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    engine.money = 200000;
    engine.kills = 20000;
    engine.unlockAbility(PlayerClass.survivor);
    for (var i = 0; i < SurvivalUpgrades.maxLevel; i++) {
      engine.upgradeAbility(PlayerClass.survivor);
    }
    expect(engine.abilityMastered, isTrue);
    final near = Zombie(
      id: 7703,
      kind: ZombieKind.walker,
      position: const Offset(0.35, 0),
      health: 200,
      maxHealth: 200,
      speed: 0,
      reward: 1,
    );
    engine.zombies.add(near);
    engine.player = Offset.zero;
    expect(engine.activateAbility(), isTrue);
    expect(near.health, lessThan(200));
  });

  test('weapon mastery follows arsenal symbol', () {
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.pistol),
      'Ricochet Sovereign',
    );
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.dualPistols),
      SurvivalUpgrades.weaponMasteryName(WeaponKind.pistol),
    );
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.pepperbox),
      SurvivalUpgrades.weaponMasteryName(WeaponKind.shotgun),
    );
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.phantomBow),
      SurvivalUpgrades.weaponMasteryName(WeaponKind.sniper),
    );
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.rpg),
      'Apocalypse Core',
    );
    expect(
      SurvivalUpgrades.weaponMasteryName(WeaponKind.worldEnder),
      'Reality Fracture',
    );
    // Every weapon sharing a symbol shares a mastery.
    final bySymbol = <WeaponSymbol, Set<WeaponMastery>>{};
    for (final kind in WeaponKind.values) {
      bySymbol.putIfAbsent(kind.symbol, () => {}).add(kind.mastery);
    }
    for (final entry in bySymbol.entries) {
      expect(entry.value.length, 1, reason: '${entry.key} mixed masteries');
    }
  });

  test('pistol mastery ricochets on hit', () {
    final engine = SurvivalEngine(random: Random(91));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    engine.props.clear();
    engine.houses.clear();
    engine.money = 200000;
    engine.kills = 20000;
    engine.unlockedWeapons.add(WeaponKind.pistol);
    engine.equip(WeaponKind.pistol);
    for (var i = 0; i < SurvivalUpgrades.maxLevel; i++) {
      engine.upgradeWeapon(WeaponKind.pistol);
    }
    expect(engine.weaponMastered, isTrue);

    final primary = Zombie(
      id: 9101,
      kind: ZombieKind.walker,
      position: const Offset(0.5, 0),
      health: 400,
      maxHealth: 400,
      speed: 0,
      reward: 1,
    );
    final secondary = Zombie(
      id: 9102,
      kind: ZombieKind.walker,
      position: const Offset(0.75, 0),
      health: 400,
      maxHealth: 400,
      speed: 0,
      reward: 1,
    );
    engine.zombies.addAll([primary, secondary]);
    engine.player = Offset.zero;
    engine.setAim(const Offset(1, 0));
    engine.magazine[WeaponKind.pistol] = 12;
    engine.fire();
    expect(primary.health, lessThan(400));
    expect(secondary.health, lessThan(400));
  });

  test('mini-boss every 5 waves and citadel every 10', () {
    final engine = SurvivalEngine(random: Random(22));
    engine.debugAdvanceToWave(5);
    expect(engine.zombies.any((z) => z.kind.isMiniBoss), isTrue);

    engine.debugAdvanceToWave(10);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.citadelTower),
      isTrue,
    );
  });

  test('shadow ronin arrives on wave 20 with a stronger citadel', () {
    final engine = SurvivalEngine(random: Random(24));
    engine.debugAdvanceToWave(10);
    final firstCitadel = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    final firstHp = firstCitadel.maxHealth;

    engine.debugAdvanceToWave(20);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.shadowRonin),
      isTrue,
    );
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.citadelTower),
      isTrue,
    );
    final second = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    expect(second.maxHealth, greaterThan(firstHp));
    expect(second.specialTimer, greaterThanOrEqualTo(2));
  });

  test('citadel returns every 10 waves and attacks faster each mark', () {
    final engine = SurvivalEngine(random: Random(26));
    engine.debugAdvanceToWave(10);
    final mark1 = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    mark1.abilityCooldown = 0;
    mark1.clearWindUp();
    mark1.blockTimer = 0;
    for (var i = 0; i < 80 && engine.enemyBolts.isEmpty; i++) {
      if (mark1.isBlocking ||
          mark1.pendingAttack == EnemyAttackKind.block) {
        mark1.clearWindUp();
        mark1.blockTimer = 0;
        mark1.abilityCooldown = 0;
      }
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    final mark1Cooldown = mark1.abilityCooldown;
    final mark1Speed = engine.enemyBolts.first.velocity.distance;

    engine.enemyBolts.clear();
    engine.debugAdvanceToWave(30);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.citadelTower),
      isTrue,
    );
    final mark3 = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    expect(mark3.specialTimer, greaterThanOrEqualTo(3));
    mark3.abilityCooldown = 0;
    mark3.clearWindUp();
    mark3.blockTimer = 0;
    for (var i = 0; i < 80 && engine.enemyBolts.isEmpty; i++) {
      if (mark3.isBlocking ||
          mark3.pendingAttack == EnemyAttackKind.block) {
        mark3.clearWindUp();
        mark3.blockTimer = 0;
        mark3.abilityCooldown = 0;
      }
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    expect(mark3.abilityCooldown, lessThan(mark1Cooldown));
    expect(
      engine.enemyBolts.first.velocity.distance,
      greaterThan(mark1Speed),
    );
    expect(
      engine.enemyBolts.first.damage,
      greaterThan(36),
    );
  });

  test('citadel fireballs are compact comet shots', () {
    final engine = SurvivalEngine(random: Random(25));
    engine.debugAdvanceToWave(10);
    final tower = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    tower.abilityCooldown = 0;
    tower.clearWindUp();
    tower.blockTimer = 0;
    // Keep ticking until the primary X/+ barrage fires (skip blocks).
    for (var i = 0; i < 80 && engine.enemyBolts.isEmpty; i++) {
      if (tower.isBlocking ||
          tower.pendingAttack == EnemyAttackKind.block) {
        tower.clearWindUp();
        tower.blockTimer = 0;
        tower.abilityCooldown = 0;
      }
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    expect(engine.enemyBolts.first.radius, lessThanOrEqualTo(0.09));
    expect(engine.enemyBolts.first.radius, greaterThanOrEqualTo(0.07));
    expect(engine.enemyBolts.first.style, EnemyBoltStyle.citadel);
    expect(engine.enemyBolts.first.damage, greaterThanOrEqualTo(40));
  });

  test('citadel tower breaks into apocalypse lord', () {
    final engine = SurvivalEngine(random: Random(23));
    engine.debugAdvanceToWave(10);
    final tower = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.citadelTower);
    engine.debugKill(tower);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.apocalypseLord),
      isTrue,
    );
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.citadelTower),
      isFalse,
    );
  });

  test('world has blocking props, houses, and keyed chests', () {
    final engine = SurvivalEngine(random: Random(42));
    expect(engine.props, isNotEmpty);
    expect(engine.houses.length, greaterThanOrEqualTo(3));
    expect(engine.chests.length, greaterThanOrEqualTo(3));
    expect(engine.chests.any((c) => c.requiredKey == KeyKind.boss), isTrue);
    expect(engine.chests.any((c) => c.requiredKey == KeyKind.mini), isTrue);
    // Every chest sits inside a house interior.
    for (final chest in engine.chests) {
      expect(
        engine.houses.any((h) => h.inner.contains(chest.position)),
        isTrue,
      );
    }
    // Obstacles stay out of house footprints and yards.
    for (final prop in engine.props) {
      for (final house in engine.houses) {
        expect(
          house.outer
              .inflate(SurvivalWorldBuilder.houseClearance)
              .contains(prop.position),
          isFalse,
          reason: 'prop ${prop.kind} spawned too close to a house',
        );
      }
    }

    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    final rock = engine.props.first;
    engine.player = rock.position - Offset(rock.radius + 0.25, 0);
    engine.setMovement(const Offset(1, 0));
    for (var i = 0; i < 30; i++) {
      engine.update(0.05);
    }
    expect(
      (engine.player - rock.position).distance,
      greaterThan(rock.radius * 0.4),
    );
  });

  test('mini-boss drops key and chest opens with premium loot', () {
    final engine = SurvivalEngine(random: Random(44));
    engine.debugAdvanceToWave(5);
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.gameOver = false;
    engine.health = 100;
    final mini = engine.zombies.firstWhere((z) => z.kind.isMiniBoss);
    final deathPos = mini.position;
    engine.debugKill(mini);
    expect(engine.keyDrops.any((k) => k.kind == KeyKind.mini), isTrue);

    engine.zombies.clear();
    engine.setMovement(Offset.zero);
    // Stand on the key but not on a chest (house spawns can overlap).
    var pickup = deathPos;
    for (final chest in engine.chests) {
      if ((chest.position - pickup).distance <= 0.25) {
        pickup = deathPos + const Offset(0.35, 0.1);
        break;
      }
    }
    engine.player = pickup;
    for (var i = 0; i < 3; i++) {
      engine.update(0.05);
    }
    expect(engine.miniKeys, greaterThan(0));

    final chest =
        engine.chests.firstWhere((c) => c.requiredKey == KeyKind.mini);
    final beforeWeapons = engine.unlockedWeapons.length;
    final beforeMoney = engine.money;
    engine.player = chest.position;
    for (var i = 0; i < 3; i++) {
      engine.update(0.05);
    }
    expect(chest.opened, isTrue);
    expect(
      engine.unlockedWeapons.length > beforeWeapons ||
          engine.money > beforeMoney,
      isTrue,
    );
  });

  test('opened chests respawn with fresh loot', () {
    final engine = SurvivalEngine(random: Random(77));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    engine.gameOver = false;
    engine.health = 100;

    final chest =
        engine.chests.firstWhere((c) => c.requiredKey == KeyKind.mini);
    chest.opened = true;
    chest.respawnTimer = 0.2;
    chest.lootKind = CrateLootKind.money;
    chest.weapon = null;
    chest.bonusMoney = 1;
    chest.bonusHeal = 0;

    for (var i = 0; i < 8; i++) {
      engine.update(0.05);
    }

    expect(chest.opened, isFalse);
    expect(chest.respawnTimer, 0);
    expect(chest.bonusMoney, greaterThan(1));
  });

  test('meteor streaks from a corner toward the impact target', () {
    final hazard = SkyHazard(
      target: Offset.zero,
      origin: const Offset(4, -4),
      damage: 10,
      blastRadius: 0.32,
      height: 1.0,
    );
    expect(hazard.fallProgress, 0);
    expect(hazard.airWorld.dx, closeTo(4, 0.01));
    expect(hazard.airWorld.dy, closeTo(-4, 0.01));

    hazard.height = 0.5;
    expect(hazard.fallProgress, closeTo(0.5, 0.01));
    // Ease-in: progress^2 = 0.25 along the path.
    expect(hazard.airWorld.dx, closeTo(3, 0.05));
    expect(hazard.airWorld.dy, closeTo(-3, 0.05));

    hazard.height = 0;
    expect(hazard.airWorld, Offset.zero);
  });

  test('sky caller spawns corner-diving meteors with a ground target', () {
    final engine = SurvivalEngine(random: Random(55));
    engine.zombies.clear();
    engine.skyHazards.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.zombies.add(Zombie(
      id: 9001,
      kind: ZombieKind.skyCaller,
      position: const Offset(0.4, 0),
      health: 100,
      maxHealth: 100,
      speed: 0.1,
      reward: 1,
    ));
    for (var i = 0; i < 40 && engine.skyHazards.isEmpty; i++) {
      engine.update(0.05);
    }
    expect(engine.skyHazards, isNotEmpty);
    final meteor = engine.skyHazards.first;
    expect(meteor.summonsZombie, isFalse);
    expect((meteor.origin - meteor.target).distance, greaterThan(2.5));
    expect(meteor.startHeight, greaterThan(1));
  });

  test('enemy melee punches land immediately without wind-up', () {
    final engine = SurvivalEngine(random: Random(77));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.health = 100;
    final walker = Zombie(
      id: 7001,
      kind: ZombieKind.walker,
      position: const Offset(0.08, 0),
      health: 40,
      maxHealth: 40,
      speed: 0.01,
      reward: 1,
    )..attackCooldown = 0;
    engine.zombies.add(walker);

    engine.update(0.05);
    expect(walker.isWindingUp, isFalse);
    expect(walker.attackAnim, greaterThan(0));
    expect(engine.health, lessThan(100));
  });

  test('mini chests roll weaker loot than boss chests', () {
    final engine = SurvivalEngine(random: Random(88));
    final mini = engine.chests.where((c) => c.requiredKey == KeyKind.mini);
    final boss = engine.chests.where((c) => c.requiredKey == KeyKind.boss);
    expect(mini, isNotEmpty);
    expect(boss, isNotEmpty);

    for (final chest in mini) {
      if (chest.weapon != null) {
        expect(chest.weapon!.rarity.index, lessThanOrEqualTo(WeaponRarity.rare.index));
        expect(chest.weapon!.rarity.index, greaterThanOrEqualTo(WeaponRarity.uncommon.index));
      }
      expect(chest.bonusMoney, lessThan(200));
    }
    for (final chest in boss) {
      if (chest.weapon != null) {
        expect(chest.weapon!.rarity.index, greaterThanOrEqualTo(WeaponRarity.epic.index));
      }
      expect(chest.bonusMoney, greaterThanOrEqualTo(140));
    }

    final maxMiniMoney =
        mini.map((c) => c.bonusMoney).reduce((a, b) => a > b ? a : b);
    final minBossMoney =
        boss.map((c) => c.bonusMoney).reduce((a, b) => a < b ? a : b);
    expect(minBossMoney, greaterThan(maxMiniMoney));
  });

  test('ice weapons slow enemies on hit', () {
    final engine = SurvivalEngine(random: Random(119));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);
    engine.unlockedWeapons.add(WeaponKind.iceRifle);
    engine.equip(WeaponKind.iceRifle);
    expect(WeaponKind.iceRifle.appliesSlow, isTrue);

    final target = Zombie(
      id: 4401,
      kind: ZombieKind.walker,
      position: const Offset(0.45, 0),
      health: 200,
      maxHealth: 200,
      speed: 0.25,
      reward: 1,
    );
    engine.zombies.add(target);
    engine.fire();
    expect(target.isSlowed, isTrue);
    expect(target.slowFactor, lessThan(0.5));
    expect(target.health, lessThan(200));
  });

  test('ranged enemies charge before firing bolts', () {
    final engine = SurvivalEngine(random: Random(78));
    engine.zombies.clear();
    engine.skyHazards.clear();
    engine.enemyBolts.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    final spitter = Zombie(
      id: 7002,
      kind: ZombieKind.spitter,
      position: const Offset(0.9, 0),
      health: 40,
      maxHealth: 40,
      speed: 0.01,
      reward: 1,
    )..abilityCooldown = 0;
    engine.zombies.add(spitter);

    engine.update(0.05);
    expect(spitter.isWindingUp, isTrue);
    expect(engine.enemyBolts, isEmpty);

    for (var i = 0; i < 14; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
  });

  test('duplicate weapon drops free-upgrade owned guns', () {
    final engine = SurvivalEngine(random: Random(91));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.zombies.clear();
    const gun = WeaponKind.pistol;
    expect(engine.unlockedWeapons.contains(gun), isTrue);
    expect(engine.weaponLevel(gun), 0);
    final baseDamage = engine.effectiveWeaponDamage;

    engine.debugGrantWeapon(gun);
    expect(engine.weaponLevel(gun), 1);
    expect(engine.effectiveWeaponDamage, greaterThan(baseDamage));

    engine.debugGrantWeapon(gun);
    expect(engine.weaponLevel(gun), 2);

    for (var i = engine.weaponLevel(gun); i < SurvivalUpgrades.maxLevel; i++) {
      engine.debugGrantWeapon(gun);
    }
    expect(engine.weaponLevel(gun), SurvivalUpgrades.maxLevel);
    final moneyBefore = engine.money;
    engine.debugGrantWeapon(gun);
    expect(engine.weaponLevel(gun), SurvivalUpgrades.maxLevel);
    expect(engine.money, greaterThan(moneyBefore));
  });

  test('weapons can be upgraded with money and kills', () {
    final engine = SurvivalEngine(random: Random(92));
    const gun = WeaponKind.pistol;
    expect(engine.canUpgradeWeapon(gun), isFalse);
    engine.money = SurvivalUpgrades.weaponMoneyCost(gun, 0);
    engine.kills = SurvivalUpgrades.weaponKillCost(gun, 0);
    expect(engine.upgradeWeapon(gun), isTrue);
    expect(engine.weaponLevel(gun), 1);
    expect(engine.money, 0);
    expect(engine.kills, 0);
  });

  test('globlings explode into sticky goo that slows the player', () {
    final engine = SurvivalEngine(random: Random(101));
    engine.zombies.clear();
    engine.stickyGoos.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.health = 100;
    final glob = Zombie(
      id: 8801,
      kind: ZombieKind.globling,
      position: const Offset(0.08, 0),
      health: 20,
      maxHealth: 20,
      speed: 0.01,
      reward: 1,
    )..attackCooldown = 0;
    engine.zombies.add(glob);

    engine.update(0.05);
    expect(glob.isWindingUp, isTrue);
    expect(engine.stickyGoos, isEmpty);

    for (var i = 0; i < 12; i++) {
      engine.update(0.05);
    }
    expect(engine.zombies.where((z) => z.id == 8801), isEmpty);
    expect(engine.stickyGoos, isNotEmpty);
    expect(engine.health, lessThan(100));
    expect(engine.isSlowedByGoo, isTrue);
    expect(engine.gooSlowFactor, lessThan(0.5));
  });

  test('globlings spawn in packs', () {
    final engine = SurvivalEngine(random: Random(102));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    final before = engine.zombies.length;
    // Force pack via public spawn path used by waves.
    engine.debugSpawnGloblingPack();
    expect(engine.zombies.length, greaterThanOrEqualTo(before + 4));
    expect(
      engine.zombies.every((z) => z.kind == ZombieKind.globling),
      isTrue,
    );
  });

  test('high scores record total earned kills and money', () async {
    SharedPreferences.setMockInitialValues({});
    final engine = SurvivalEngine(random: Random(110));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;

    final walker = Zombie(
      id: 9101,
      kind: ZombieKind.walker,
      position: const Offset(0.08, 0),
      health: 1,
      maxHealth: 1,
      speed: 0.01,
      reward: 25,
    );
    engine.zombies.add(walker);
    engine.debugKill(walker);
    expect(engine.totalKills, 1);
    expect(engine.totalMoneyEarned, 25);

    // Spend currency — lifetime totals must stay.
    engine.money = 0;
    engine.kills = 0;
    expect(engine.totalMoneyEarned, 25);
    expect(engine.totalKills, 1);

    await engine.debugRecordHighScore();
    expect(engine.highScores, isNotEmpty);
    expect(engine.highScores.first.kills, 1);
    expect(engine.highScores.first.money, 25);
  });

  test('most weapons cannot shoot through house walls', () {
    final engine = SurvivalEngine(random: Random(120));
    engine.zombies.clear();
    engine.props.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.houses
      ..clear()
      ..add(House(
        center: const Offset(1.0, 0),
        width: 1.0,
        depth: 1.0,
        doorSide: 2, // door on south — west wall is solid
      ));
    engine.chests.clear();
    engine.player = const Offset(0.2, 0);
    engine.aimDirection = const Offset(1, 0);
    engine.equip(WeaponKind.pistol);

    final behindWall = Zombie(
      id: 1,
      kind: ZombieKind.walker,
      position: const Offset(1.0, 0), // inside house / past west wall
      health: 80,
      maxHealth: 80,
      speed: 0,
      reward: 1,
    );
    engine.zombies.add(behindWall);
    engine.fire();
    expect(behindWall.health, 80);
  });

  test('piercing weapons can still shoot through walls', () {
    final engine = SurvivalEngine(random: Random(121));
    engine.zombies.clear();
    engine.props.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.houses
      ..clear()
      ..add(House(
        center: const Offset(1.0, 0),
        width: 1.0,
        depth: 1.0,
        doorSide: 2,
      ));
    engine.chests.clear();
    engine.player = const Offset(0.2, 0);
    engine.aimDirection = const Offset(1, 0);
    engine.unlockedWeapons.add(WeaponKind.railgun);
    engine.equip(WeaponKind.railgun);

    final behindWall = Zombie(
      id: 1,
      kind: ZombieKind.walker,
      position: const Offset(1.0, 0),
      health: 80,
      maxHealth: 80,
      speed: 0,
      reward: 1,
    );
    engine.zombies.add(behindWall);
    engine.fire();
    expect(behindWall.health, lessThan(80));
  });

  test('haste mage aura makes nearby enemies 3x faster', () {
    final engine = SurvivalEngine(random: Random(210));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = const Offset(6, 6);

    final mage = Zombie(
      id: 9101,
      kind: ZombieKind.hasteMage,
      position: Offset.zero,
      health: 200,
      maxHealth: 200,
      speed: 0,
      reward: 1,
    )..abilityCooldown = 999;
    final near = Zombie(
      id: 9102,
      kind: ZombieKind.walker,
      position: const Offset(0.8, 0),
      health: 80,
      maxHealth: 80,
      speed: 0.2,
      reward: 1,
    )..abilityCooldown = 999;
    final far = Zombie(
      id: 9103,
      kind: ZombieKind.walker,
      position: const Offset(5.5, 0),
      health: 80,
      maxHealth: 80,
      speed: 0.2,
      reward: 1,
    )..abilityCooldown = 999;

    engine.zombies.addAll([mage, near, far]);
    engine.update(0.05);

    expect(1 + near.speedBoost, closeTo(3.0, 0.01));
    expect(far.speedBoost, 0);
  });

  test('haste mage heals up to five wounded allies with staff', () {
    final engine = SurvivalEngine(random: Random(211));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = const Offset(6, 6);

    final mage = Zombie(
      id: 9200,
      kind: ZombieKind.hasteMage,
      position: Offset.zero,
      health: 200,
      maxHealth: 200,
      speed: 0,
      reward: 1,
    )..abilityCooldown = 0;

    final allies = <Zombie>[];
    for (var i = 0; i < 6; i++) {
      final ally = Zombie(
        id: 9201 + i,
        kind: ZombieKind.walker,
        position: Offset(0.2 + i * 0.15, 0.1),
        health: 10,
        maxHealth: 100,
        speed: 0,
        reward: 1,
      )..abilityCooldown = 999;
      allies.add(ally);
    }
    engine.zombies.add(mage);
    engine.zombies.addAll(allies);

    expect(mage.isWindingUp, isFalse);
    engine.update(0.05);
    expect(mage.isWindingUp, isTrue);
    expect(mage.pendingAttack, EnemyAttackKind.ability);

    for (var i = 0; i < 14; i++) {
      engine.update(0.05);
    }

    final healed = allies.where((z) => z.health > 10).length;
    final untouched = allies.where((z) => z.health == 10).length;
    expect(healed, 5);
    expect(untouched, 1);
    expect(allies.every((z) => z.health <= z.maxHealth), isTrue);
  });

  test('zombies spawn from the map edge, not inside houses', () {
    final engine = SurvivalEngine(random: Random(301));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    expect(engine.houses, isNotEmpty);

    for (var i = 0; i < 40; i++) {
      engine.zombies.clear();
      engine.debugSpawnRegular(ZombieKind.walker);
      final z = engine.zombies.single;
      expect(
        engine.houses.any((h) => h.inner.contains(z.position)),
        isFalse,
      );
      expect(
        z.position.dx.abs() > engine.arenaBound - 0.5 ||
            z.position.dy.abs() > engine.arenaBound - 0.5,
        isTrue,
      );
    }
  });

  test('elite block negates weapon damage', () {
    final engine = SurvivalEngine(random: Random(302));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);
    engine.equip(WeaponKind.pistol);

    final boss = Zombie(
      id: 9301,
      kind: ZombieKind.ironColossus,
      position: const Offset(0.4, 0),
      health: 500,
      maxHealth: 500,
      speed: 0,
      reward: 1,
    )
      ..abilityCooldown = 999
      ..blockTimer = 2.0;
    engine.zombies.add(boss);
    engine.fire();
    expect(boss.health, 500);
    expect(boss.isBlocking, isTrue);
  });

  test('elite ground pound damages nearby player', () {
    final engine = SurvivalEngine(random: Random(303));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = const Offset(0.4, 0);
    engine.health = 100;

    final boss = Zombie(
      id: 9302,
      kind: ZombieKind.dreadlord,
      position: Offset.zero,
      health: 800,
      maxHealth: 800,
      speed: 0,
      reward: 1,
    )
      ..abilityCooldown = 999
      ..pendingAttack = EnemyAttackKind.groundPound
      ..windUpDuration = 0.05
      ..windUpTimer = 0.05
      ..telegraphRadius = 1.2
      ..attackFacing = const Offset(1, 0);
    engine.zombies.add(boss);

    for (var i = 0; i < 4; i++) {
      engine.update(0.05);
    }
    expect(engine.health, lessThan(100));
  });

  test('elite dash closes distance and can hit player', () {
    final engine = SurvivalEngine(random: Random(304));
    engine.zombies.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.player = const Offset(1.2, 0);
    engine.health = 100;

    final mini = Zombie(
      id: 9303,
      kind: ZombieKind.siegeBehemoth,
      position: Offset.zero,
      health: 400,
      maxHealth: 400,
      speed: 0,
      reward: 1,
    )
      ..abilityCooldown = 999
      ..pendingAttack = EnemyAttackKind.dash
      ..windUpDuration = 0.05
      ..windUpTimer = 0.05
      ..telegraphWorld = const Offset(1.2, 0)
      ..telegraphRadius = 0.28
      ..attackFacing = const Offset(1, 0);
    engine.zombies.add(mini);

    for (var i = 0; i < 4; i++) {
      engine.update(0.05);
    }
    expect(mini.position.dx, greaterThan(0.8));
    expect(engine.health, lessThan(100));
  });

  test('laser overseer debuts on waves 11 and 12 with two cannons', () {
    final engine = SurvivalEngine(random: Random(40));
    engine.debugAdvanceToWave(11);
    expect(
      engine.zombies.where((z) => z.kind == ZombieKind.laserOverseer).length,
      1,
    );
    expect(engine.laserCannons.length, 2);
    // One roughly on top edge, one on left edge.
    expect(
      engine.laserCannons.any((c) => c.position.dy <= -SurvivalEngine.arenaHalf + 1.2),
      isTrue,
    );
    expect(
      engine.laserCannons.any((c) => c.position.dx <= -SurvivalEngine.arenaHalf + 1.2),
      isTrue,
    );

    engine.debugAdvanceToWave(12);
    expect(
      engine.zombies.where((z) => z.kind == ZombieKind.laserOverseer).length,
      1,
    );
    expect(engine.laserCannons.length, 2);
  });

  test('wave 15+ every 5 spawns at least two laser overseers', () {
    final engine = SurvivalEngine(random: Random(41));
    for (final w in [15, 20, 25]) {
      engine.debugAdvanceToWave(w);
      expect(
        engine.zombies.where((z) => z.kind == ZombieKind.laserOverseer).length,
        greaterThanOrEqualTo(2),
        reason: 'wave $w',
      );
      expect(engine.laserCannons.length, greaterThanOrEqualTo(4), reason: 'wave $w');
    }
  });

  test('laser cannons do not overlap and despawn with overseer', () {
    final engine = SurvivalEngine(random: Random(42));
    engine.debugAdvanceToWave(15);
    expect(engine.laserCannons.length, greaterThanOrEqualTo(4));
    for (var i = 0; i < engine.laserCannons.length; i++) {
      for (var j = i + 1; j < engine.laserCannons.length; j++) {
        expect(
          (engine.laserCannons[i].position - engine.laserCannons[j].position)
              .distance,
          greaterThanOrEqualTo(LaserCannon.minSpacing - 0.01),
        );
      }
    }
    final overseer = engine.zombies
        .firstWhere((z) => z.kind == ZombieKind.laserOverseer);
    final ownerId = overseer.id;
    final before = engine.laserCannons.length;
    engine.debugKill(overseer);
    expect(
      engine.laserCannons.where((c) => c.ownerId == ownerId),
      isEmpty,
    );
    expect(engine.laserCannons.length, lessThan(before));
  });

  test('laser cannon fires a damaging beam for five seconds', () {
    final engine = SurvivalEngine(random: Random(43));
    engine.debugAdvanceToWave(11);
    engine.paused = false;
    final cannon = engine.laserCannons.first;
    cannon.phase = LaserCannonPhase.firing;
    cannon.phaseTimer = 5.0;
    cannon.position = const Offset(-2, 0);
    cannon.target = const Offset(4, 0);
    cannon.aim = const Offset(1, 0);
    engine.player = const Offset(1, 0);
    final startHp = engine.health;
    for (var i = 0; i < 20; i++) {
      engine.update(0.05);
    }
    expect(engine.health, lessThan(startHp));
  });

  test('knife thrower fires infinite-range knives; fanatic fires three', () {
    final engine = SurvivalEngine(random: Random(61));
    engine.zombies.clear();
    engine.player = Offset.zero;
    engine.debugSpawnRegular(ZombieKind.knifeThrower);
    final thrower = engine.zombies.single;
    final throwerHp = thrower.maxHealth;
    final throwerSpeed = thrower.speed;
    thrower.position = const Offset(2.5, 0);
    thrower.abilityCooldown = 0;
    thrower.clearWindUp();
    for (var i = 0; i < 40 && engine.enemyBolts.isEmpty; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    expect(engine.enemyBolts.first.style, EnemyBoltStyle.knife);
    expect(engine.enemyBolts.first.velocity.distance, greaterThan(4.5));
    expect(engine.enemyBolts.first.life, closeTo(5.0, 0.01));

    engine.enemyBolts.clear();
    engine.zombies.clear();
    engine.debugSpawnRegular(ZombieKind.knifeFanatic);
    final fanatic = engine.zombies.single;
    fanatic.position = const Offset(1.2, 0);
    fanatic.abilityCooldown = 0;
    fanatic.clearWindUp();
    for (var i = 0; i < 40 && engine.enemyBolts.length < 3; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts.length, greaterThanOrEqualTo(3));
    expect(
      engine.enemyBolts.every((b) => b.style == EnemyBoltStyle.knife),
      isTrue,
    );
    expect(fanatic.maxHealth, greaterThan(throwerHp));
    expect(fanatic.speed, greaterThan(throwerSpeed));
  });

  test('knife projectiles stop on house walls', () {
    final engine = SurvivalEngine(random: Random(63));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.crates.clear();
    engine.chests.clear();
    engine.poisonClouds.clear();
    engine.firePits.clear();
    engine.skyHazards.clear();
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.props
      ..clear()
      ..add(SolidProp(const Offset(0.5, 0), radius: 0.2));
    engine.houses.clear();
    engine.player = const Offset(3.0, 0);
    engine.health = 50000;
    final hp = engine.health;
    engine.enemyBolts.add(EnemyBolt(
      position: const Offset(-0.2, 0),
      velocity: const Offset(4.0, 0),
      damage: 50,
      color: const Color(0xFFFFFFFF),
      style: EnemyBoltStyle.knife,
      life: 5,
    ));
    // Standard (non-knife) bolt for contrast still exists in the list type.
    for (var i = 0; i < 40; i++) {
      engine.update(0.05);
      if (engine.enemyBolts.isEmpty) break;
    }
    expect(engine.enemyBolts, isEmpty);
    // Knife damage is 50 — cover must have stopped it before the player.
    expect(engine.health, greaterThan(hp - 40));
  });

  test('ghost enemies phase walls and sometimes phase bullets', () {
    final engine = SurvivalEngine(random: Random(62));
    engine.zombies.clear();
    engine.props
      ..clear()
      ..add(SolidProp(const Offset(0.6, 0), radius: 0.22));
    engine.player = Offset.zero;
    engine.debugSpawnRegular(ZombieKind.walker);
    final ghost = engine.zombies.single
      ..isGhost = true
      ..position = const Offset(1.4, 0);
    final startX = ghost.position.dx;
    for (var i = 0; i < 50; i++) {
      engine.update(0.05);
    }
    // Should close distance through the rock instead of sticking behind it.
    expect(ghost.position.dx, lessThan(startX - 0.2));

    var phased = 0;
    for (var i = 0; i < 80; i++) {
      if (engine.debugBulletPhasesThrough(ghost)) phased++;
    }
    expect(phased, greaterThan(10));
    expect(phased, lessThan(50));
  });

  test('void sovereign arrives on wave 21 and every 25', () {
    final engine = SurvivalEngine(random: Random(71));
    engine.debugAdvanceToWave(21);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.voidSovereign),
      isTrue,
    );
    engine.debugAdvanceToWave(25);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.voidSovereign),
      isTrue,
    );
  });

  test('vanguard shock bash pushes then reprises after invuln', () {
    final engine = SurvivalEngine(random: Random(72));
    engine.money = 99999;
    engine.kills = 999;
    expect(engine.unlockClass(PlayerClass.tank), isTrue);
    expect(engine.unlockAbility(PlayerClass.tank), isTrue);
    engine.selectClass(PlayerClass.tank);
    engine.zombies.clear();
    engine.debugSpawnRegular(ZombieKind.walker);
    final foe = engine.zombies.single..position = const Offset(0.4, 0);
    engine.player = Offset.zero;
    final start = foe.position.dx;
    expect(engine.activateAbility(), isTrue);
    expect(engine.isShielded, isTrue);
    expect(foe.position.dx, greaterThan(start));
    // Wait out invuln / second push timer.
    for (var i = 0; i < 50; i++) {
      engine.update(0.05);
    }
    expect(foe.position.dx, greaterThan(start + 0.3));
  });

  test('commander gunline summons shooting helpers', () {
    final engine = SurvivalEngine(random: Random(73));
    engine.money = 99999;
    engine.kills = 999;
    expect(engine.unlockClass(PlayerClass.commander), isTrue);
    expect(engine.unlockAbility(PlayerClass.commander), isTrue);
    engine.selectClass(PlayerClass.commander);
    engine.zombies.clear();
    engine.debugSpawnRegular(ZombieKind.walker);
    engine.zombies.single.position = const Offset(1.5, 0);
    engine.player = Offset.zero;
    // Keep the debug walker as the only threat (no wave respawn mid-test).
    engine.waveActive = true;
    engine.nextWaveTimer = 99;
    expect(engine.activateAbility(), isTrue);
    expect(engine.gunAllies.length, greaterThanOrEqualTo(3));
    // Spawned toward the nearest enemy (on +x from the commander).
    for (final ally in engine.gunAllies) {
      expect(ally.position.dx, greaterThan(0.3));
    }
    final hp = engine.zombies.single.health;
    var damaged = false;
    for (var i = 0; i < 40; i++) {
      engine.update(0.05);
      if (engine.zombies.isEmpty ||
          engine.zombies.single.health < hp) {
        damaged = true;
        break;
      }
    }
    expect(damaged, isTrue);
  });

  test('commander gunline reorients toward nearest enemy', () {
    final engine = SurvivalEngine(random: Random(74));
    engine.money = 99999;
    engine.kills = 999;
    engine.unlockClass(PlayerClass.commander);
    engine.unlockAbility(PlayerClass.commander);
    engine.selectClass(PlayerClass.commander);
    engine.zombies.clear();
    engine.debugSpawnRegular(ZombieKind.walker);
    engine.zombies.single.position = const Offset(1.5, 0);
    engine.player = Offset.zero;
    engine.waveActive = true;
    engine.nextWaveTimer = 99;
    expect(engine.activateAbility(), isTrue);
    for (final ally in engine.gunAllies) {
      expect(ally.formationOffset.dx, greaterThan(0.3));
    }

    // Move the threat above the commander — the line should pivot to face it.
    engine.zombies.single.position = const Offset(0, -1.5);
    for (var i = 0; i < 12; i++) {
      engine.update(0.05);
    }
    for (final ally in engine.gunAllies) {
      expect(ally.formationOffset.dy, lessThan(-0.3));
      expect(ally.position.dy, lessThan(-0.2));
    }
  });

  test('commander gunners take damage and can die', () {
    final engine = SurvivalEngine(random: Random(75));
    engine.money = 99999;
    engine.kills = 999;
    engine.unlockClass(PlayerClass.commander);
    engine.unlockAbility(PlayerClass.commander);
    engine.selectClass(PlayerClass.commander);
    engine.zombies.clear();
    engine.player = Offset.zero;
    expect(engine.activateAbility(), isTrue);
    final ally = engine.gunAllies.first;
    final startHp = ally.health;
    engine.debugSpawnRegular(ZombieKind.walker);
    final walker = engine.zombies.single
      ..position = ally.position
      ..attackCooldown = 0;
    for (var i = 0; i < 30; i++) {
      engine.update(0.05);
      if (engine.gunAllies.every((a) => a.health < startHp) ||
          engine.gunAllies.length < 3) {
        break;
      }
    }
    expect(
      engine.gunAllies.any((a) => a.health < startHp) ||
          engine.gunAllies.length < 3,
      isTrue,
    );
    // Finish them off.
    while (engine.gunAllies.isNotEmpty) {
      final target = engine.gunAllies.first;
      target.health = 1;
      walker.position = target.position;
      walker.attackCooldown = 0;
      engine.update(0.05);
      if (engine.gunAllies.length > 20) break; // safety
    }
    expect(engine.gunAllies, isEmpty);
  });

  test('more supply crates can be on the field', () {
    final engine = SurvivalEngine(random: Random(74));
    expect(engine.crates.length, greaterThanOrEqualTo(4));
  });

  test('hammer mauler leap-smashes onto the player', () {
    final engine = SurvivalEngine(random: Random(77));
    engine.zombies.clear();
    engine.player = Offset.zero;
    engine.debugSpawnRegular(ZombieKind.hammerMauler);
    final mauler = engine.zombies.single;
    mauler.position = const Offset(1.4, 0);
    mauler.abilityCooldown = 0;
    mauler.clearWindUp();
    final startHp = engine.health;

    for (var i = 0; i < 40 && !mauler.isWindingUp; i++) {
      engine.update(0.05);
    }
    expect(mauler.isWindingUp, isTrue);
    expect(mauler.pendingAttack, EnemyAttackKind.ability);
    expect(mauler.telegraphWorld, isNotNull);

    for (var i = 0; i < 40 && mauler.isWindingUp; i++) {
      engine.update(0.05);
    }
    expect(mauler.isWindingUp, isFalse);
    expect(
      (mauler.position - Offset.zero).distance,
      lessThan(0.35),
    );
    expect(engine.health, lessThan(startHp));
    expect(engine.blastFlashes, isNotEmpty);
  });

  test('high score store keeps top entries', () async {
    final first = await HighScoreStore.record(HighScoreEntry(
      wave: 3,
      kills: 20,
      money: 100,
      className: 'Survivor',
      playerName: 'Alex',
      at: DateTime.now(),
    ));
    expect(first, isNotEmpty);
    expect(first.first.playerName, 'Alex');
    final second = await HighScoreStore.record(HighScoreEntry(
      wave: 8,
      kills: 90,
      money: 400,
      className: 'Scout',
      playerName: 'Blake',
      at: DateTime.now(),
    ));
    expect(second.first.wave, 8);
    expect(second.first.playerName, 'Blake');
  });

  test('submitting a high score name writes the player name', () async {
    SharedPreferences.setMockInitialValues({});
    final engine = SurvivalEngine(random: Random(88));
    engine.awaitingNameEntry = true;
    engine.pendingScore = HighScoreEntry(
      wave: 7,
      kills: 55,
      money: 220,
      className: 'Commander',
      at: DateTime.now(),
    );
    await engine.submitHighScoreName('  Casey  ');
    expect(engine.awaitingNameEntry, isFalse);
    expect(engine.highScores, isNotEmpty);
    expect(engine.highScores.first.playerName, 'Casey');
    expect(engine.highScores.first.className, 'Commander');
    expect(HighScoreStore.sanitizeName(''), 'Anonymous');
  });

  test('necro bad ending triggers after 2s solo then ascends', () {
    final engine = SurvivalEngine(random: Random(404));
    engine.debugSetupNecroBadEndingSolo();
    engine.player = const Offset(2.8, 2.8);
    engine.health = 50000;
    expect(engine.badEndingCutscene, isFalse);

    // 1.5s is not enough.
    for (var i = 0; i < 30; i++) {
      engine.update(0.05);
    }
    expect(engine.gameOver, isFalse);
    expect(engine.debugNecroSoloTimer, greaterThan(1.4));
    expect(engine.badEndingCutscene, isFalse);

    // Cross 2s.
    for (var i = 0; i < 20; i++) {
      if (engine.badEndingCutscene) break;
      engine.update(0.05);
    }
    expect(engine.badEndingCutscene, isTrue);
    expect(engine.paused, isTrue);

    final before = engine.zombies.length;
    engine.resolveBadEnding();
    expect(engine.badEndingCutscene, isFalse);
    expect(engine.badEndingActive, isTrue);
    expect(engine.paused, isFalse);
    expect(
      engine.zombies.any((z) => z.isAscendedNecromancer),
      isTrue,
    );
    expect(
      engine.zombies.where((z) => z.kind.isBoss).length,
      greaterThanOrEqualTo(SurvivalEngine.allBossKinds.length),
    );
    expect(
      engine.zombies.where((z) => z.kind.isMiniBoss).length,
      greaterThanOrEqualTo(SurvivalEngine.allMiniBossKinds.length),
    );
    expect(engine.zombies.length, greaterThan(before));

    final ascended =
        engine.zombies.firstWhere((z) => z.isAscendedNecromancer);
    expect(ascended.maxHealth, greaterThan(7000));
    expect(ascended.damageMult, greaterThan(3.5));
  });

  test('reaper soul bar fills from damage and scythe ability', () {
    final engine = SurvivalEngine(random: Random(77));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.money = 99999;
    engine.kills = 999;
    expect(engine.unlockClass(PlayerClass.reaper), isTrue);
    expect(engine.unlockAbility(PlayerClass.reaper), isTrue);
    engine.selectClass(PlayerClass.reaper);
    engine.player = Offset.zero;
    engine.aimDirection = const Offset(1, 0);
    engine.zombies
      ..clear()
      ..add(Zombie(
        id: 1,
        kind: ZombieKind.walker,
        position: const Offset(0.55, 0),
        health: 5000,
        maxHealth: 5000,
        speed: 0.1,
        reward: 1,
      ));

    expect(engine.activateAbility(), isTrue);
    expect(engine.soulScytheActive, isTrue);
    final before = engine.soulCharge;
    engine.setFiring(true);
    // Each click starts a swing; damage lands across the swing window.
    for (var i = 0; i < 12; i++) {
      engine.fire();
      for (var s = 0; s < 10; s++) {
        engine.update(0.04);
      }
    }
    expect(engine.soulCharge, greaterThan(before));
  });

  test('reaper soul bar drains over time and heals by class level', () {
    final engine = SurvivalEngine(random: Random(78));
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.money = 99999;
    engine.kills = 999;
    expect(engine.unlockClass(PlayerClass.reaper), isTrue);
    engine.selectClass(PlayerClass.reaper);
    for (var i = 0; i < 3; i++) {
      engine.upgradeClass(PlayerClass.reaper);
    }
    expect(engine.classLevel(PlayerClass.reaper), 3);
    expect(engine.soulSurgeHealAmount, 54); // 18 + 3*12

    engine.health = 40;
    // Force a full soul surge via enough charge.
    engine.debugAddSoulCharge(1.0);
    expect(engine.health, 40 + 54);

    // At full HP, surges still push into overheal.
    engine.health = engine.maxHealth;
    engine.debugAddSoulCharge(1.0);
    expect(engine.health, greaterThan(engine.maxHealth));
    expect(engine.health, engine.maxHealth + 54);

    engine.debugAddSoulCharge(0.5);
    final charged = engine.soulCharge;
    expect(charged, greaterThan(0.4));
    // update() clamps dt to 0.05 — need ~7s of drain to empty 0.5 charge.
    for (var i = 0; i < 160; i++) {
      engine.update(0.05);
    }
    expect(engine.soulCharge, lessThan(charged));
    expect(engine.soulCharge, lessThan(0.05));
  });

  test('missileer fires player-speed homing missile; dies with firer', () {
    final engine = SurvivalEngine(random: Random(81));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.player = Offset.zero;
    engine.health = 50000;
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.debugSpawnRegular(ZombieKind.missileer);
    final firer = engine.zombies.single;
    firer.position = const Offset(2.0, 0);
    firer.abilityCooldown = 0;
    firer.clearWindUp();

    for (var i = 0; i < 50 && engine.enemyBolts.isEmpty; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    final missile = engine.enemyBolts.single;
    expect(missile.style, EnemyBoltStyle.missile);
    expect(missile.ownerId, firer.id);

    // Slightly under player move speed so strafing works.
    expect(
      missile.velocity.distance,
      closeTo(engine.effectiveMoveSpeed * 0.82, 0.05),
    );

    // Killing the firer removes the missile without damaging the player.
    final hp = engine.health;
    engine.debugKill(firer);
    expect(engine.enemyBolts, isEmpty);
    expect(engine.health, hp);
  });

  test('missileer missile explodes on player contact', () {
    final engine = SurvivalEngine(random: Random(82));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.player = Offset.zero;
    engine.health = 50000;
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.debugSpawnRegular(ZombieKind.missileer);
    final firer = engine.zombies.single;
    firer.position = const Offset(3.0, 0);
    firer.abilityCooldown = 999;

    engine.enemyBolts.add(EnemyBolt(
      position: const Offset(0.05, 0),
      velocity: Offset.zero,
      damage: 20,
      color: const Color(0xFFFF8F00),
      radius: 0.032,
      life: 5,
      style: EnemyBoltStyle.missile,
      ownerId: firer.id,
    ));
    final hp = engine.health;
    engine.update(0.05);
    expect(engine.health, lessThan(hp));
    expect(engine.enemyBolts, isEmpty);
  });

  test('missileer missile dies on solid cover', () {
    final engine = SurvivalEngine(random: Random(83));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.props.clear();
    engine.houses.clear();
    engine.player = const Offset(5, 0);
    engine.health = 50000;
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.debugSpawnRegular(ZombieKind.missileer);
    final firer = engine.zombies.single;
    firer.abilityCooldown = 999;
    engine.props.add(SolidProp(
      const Offset(0.2, 0),
      radius: 0.2,
      kind: PropKind.rock,
    ));
    engine.enemyBolts.add(EnemyBolt(
      position: Offset.zero,
      velocity: const Offset(2.5, 0),
      damage: 20,
      color: const Color(0xFFFF8F00),
      radius: 0.032,
      life: 5,
      style: EnemyBoltStyle.missile,
      ownerId: firer.id,
    ));
    final hp = engine.health;
    for (var i = 0; i < 20 && engine.enemyBolts.isNotEmpty; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isEmpty);
    expect(engine.health, hp);
  });

  test('blazeburst first spawns as mini-boss on wave 15', () {
    final engine = SurvivalEngine(random: Random(76));
    engine.debugAdvanceToWave(5);
    expect(
      engine.zombies.any((z) => z.kind == ZombieKind.blazeburst),
      isFalse,
    );

    engine.debugAdvanceToWave(15);
    expect(
      engine.zombies.where((z) => z.kind == ZombieKind.blazeburst).length,
      1,
    );
  });

  test('blazeburst mid-range fireball splits into shard ring on expire', () {
    final engine = SurvivalEngine(random: Random(77));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.player = Offset.zero;
    engine.health = 50000;
    engine.waveActive = false;
    engine.nextWaveTimer = 999;
    engine.debugSpawnRegular(ZombieKind.blazeburst);
    final boss = engine.zombies.single;
    expect(boss.kind.isMiniBoss, isTrue);
    boss.position = const Offset(1.5, 0);
    boss.abilityCooldown = 0;
    boss.abilityPhase = 0;
    boss.clearWindUp();

    for (var i = 0; i < 50 && engine.enemyBolts.isEmpty; i++) {
      engine.update(0.05);
    }
    expect(engine.enemyBolts, isNotEmpty);
    final primary = engine.enemyBolts.firstWhere(
      (b) => b.style == EnemyBoltStyle.fireball,
    );
    expect(primary.splitRemaining, 1);
    expect(primary.shardCount, 10);

    // Expire the primary without hitting the player.
    primary.life = 0.01;
    primary.position = const Offset(3.0, 0);
    engine.update(0.05);
    final shards = engine.enemyBolts
        .where((b) => b.style == EnemyBoltStyle.fireball)
        .toList();
    expect(shards.length, 10);
    expect(shards.every((b) => b.splitRemaining == 0), isTrue);
    expect(engine.firePits, isNotEmpty);
  });

  test('blazeburst split-nova fireballs can split twice', () {
    final engine = SurvivalEngine(random: Random(79));
    engine.zombies.clear();
    engine.enemyBolts.clear();
    engine.player = Offset.zero;
    engine.health = 50000;
    engine.waveActive = false;
    engine.nextWaveTimer = 999;

    // Seed a gen-2 fireball as if the nova just fired.
    engine.enemyBolts.add(EnemyBolt(
      position: const Offset(2.0, 0),
      velocity: Offset.zero,
      damage: 12,
      color: const Color(0xFFFF9100),
      radius: 0.07,
      life: 0.01,
      style: EnemyBoltStyle.fireball,
      splitRemaining: 2,
      shardCount: 6,
    ));
    engine.update(0.05);
    final gen1 = engine.enemyBolts
        .where((b) => b.style == EnemyBoltStyle.fireball)
        .toList();
    expect(gen1.length, 6);
    expect(gen1.every((b) => b.splitRemaining == 1), isTrue);

    for (final b in gen1) {
      b.life = 0.01;
      b.velocity = Offset.zero;
    }
    engine.update(0.05);
    final gen0 = engine.enemyBolts
        .where((b) => b.style == EnemyBoltStyle.fireball)
        .toList();
    expect(gen0.length, 6 * 6);
    expect(gen0.every((b) => b.splitRemaining == 0), isTrue);
  });
}
