import 'dart:math' as math;
import 'dart:ui';

import 'survival_content.dart';

enum PropKind {
  rock,
  crateStack,
  rubble,
  pillar,
  barrel,
  lampPost,
  well,
  cart,
}

enum KeyKind { mini, boss }

extension KeyKindStyle on KeyKind {
  String get label => switch (this) {
        KeyKind.mini => 'Mini Key',
        KeyKind.boss => 'Boss Key',
      };

  Color get color => switch (this) {
        KeyKind.mini => const Color(0xFFFFD54F),
        KeyKind.boss => const Color(0xFFFF6E40),
      };
}

class SolidProp {
  SolidProp(
    this.position, {
    this.radius = 0.16,
    this.kind = PropKind.rock,
  });

  final Offset position;
  final double radius;
  final PropKind kind;
}

class House {
  House({
    required this.center,
    required this.width,
    required this.depth,
    required this.doorSide,
    this.facade = 0,
  });

  final Offset center;
  final double width;
  final double depth;
  /// 0 = north (-y), 1 = east (+x), 2 = south (+y), 3 = west (-x)
  final int doorSide;
  /// Paint-only facade variant: 0 timber, 1 plaster, 2 brick.
  final int facade;

  static const wallThickness = 0.13;
  static const doorWidth = 0.34;

  Rect get outer =>
      Rect.fromCenter(center: center, width: width, height: depth);
  Rect get inner => Rect.fromCenter(
        center: center,
        width: math.max(0.2, width - wallThickness * 2),
        height: math.max(0.2, depth - wallThickness * 2),
      );
}

class TreasureChest {
  TreasureChest({
    required this.position,
    required this.requiredKey,
    required this.lootKind,
    this.weapon,
    this.bonusMoney = 0,
    this.bonusHeal = 0,
  });

  final Offset position;
  final KeyKind requiredKey;
  CrateLootKind lootKind;
  WeaponKind? weapon;
  int bonusMoney;
  int bonusHeal;
  bool opened = false;
  /// Counts down while opened; at 0 the chest locks again with fresh loot.
  double respawnTimer = 0;

  bool get isRespawning => opened && respawnTimer > 0;
}

class WorldKeyDrop {
  WorldKeyDrop({required this.kind, required this.position});

  final KeyKind kind;
  Offset position;
  bool pickedUp = false;
}

/// Layout helpers for the wrapping arena (solids kept away from edges/center).
class SurvivalWorldBuilder {
  SurvivalWorldBuilder(this.random, {this.arenaHalf = 8.0});

  final math.Random random;
  final double arenaHalf;

  ({
    List<SolidProp> props,
    List<House> houses,
    List<TreasureChest> chests,
  }) build() {
    final props = <SolidProp>[];
    final houses = <House>[];
    final chests = <TreasureChest>[];

    // Weighted toward Old Town street dressing.
    const townWeighted = <PropKind>[
      PropKind.barrel,
      PropKind.barrel,
      PropKind.barrel,
      PropKind.lampPost,
      PropKind.lampPost,
      PropKind.crateStack,
      PropKind.crateStack,
      PropKind.cart,
      PropKind.well,
      PropKind.rock,
      PropKind.rubble,
      PropKind.pillar,
      PropKind.rubble,
    ];

    for (var i = 0; i < 48; i++) {
      final pos = _safePoint(minCenter: 1.35);
      if (_tooClose(pos, props.map((p) => p.position), 0.4)) continue;
      final kind = townWeighted[random.nextInt(townWeighted.length)];
      final radius = switch (kind) {
        PropKind.rock => 0.14 + random.nextDouble() * 0.08,
        PropKind.crateStack => 0.12 + random.nextDouble() * 0.05,
        PropKind.rubble => 0.11 + random.nextDouble() * 0.06,
        PropKind.pillar => 0.1 + random.nextDouble() * 0.04,
        PropKind.barrel => 0.09 + random.nextDouble() * 0.04,
        PropKind.lampPost => 0.07 + random.nextDouble() * 0.03,
        PropKind.well => 0.15 + random.nextDouble() * 0.04,
        PropKind.cart => 0.13 + random.nextDouble() * 0.05,
      };
      props.add(SolidProp(pos, radius: radius, kind: kind));
    }

    // Houses in four map quadrants, each with a keyed chest inside.
    final houseCenters = <Offset>[
      Offset(-arenaHalf * 0.45, -arenaHalf * 0.4),
      Offset(arenaHalf * 0.42, -arenaHalf * 0.38),
      Offset(-arenaHalf * 0.4, arenaHalf * 0.42),
      Offset(arenaHalf * 0.38, arenaHalf * 0.4),
    ];
    for (var i = 0; i < houseCenters.length; i++) {
      final house = House(
        center: houseCenters[i],
        width: 1.15 + random.nextDouble() * 0.2,
        depth: 0.95 + random.nextDouble() * 0.2,
        doorSide: (i + 1) % 4,
        facade: i % 3,
      );
      houses.add(house);
      chests.add(TreasureChest(
        position: house.center,
        requiredKey: i < 2 ? KeyKind.mini : KeyKind.boss,
        lootKind: CrateLootKind.weapon,
      ));
    }

    // Keep house interiors clear of rubble.
    props.removeWhere((prop) {
      for (final house in houses) {
        if (house.outer.inflate(0.2).contains(prop.position)) return true;
      }
      return false;
    });

    // Cluster a few barrels near each house porch for market feel.
    for (final house in houses) {
      final porch = _doorOutward(house) * 0.55;
      for (var n = 0; n < 2; n++) {
        final jitter = Offset(
          (random.nextDouble() - 0.5) * 0.45,
          (random.nextDouble() - 0.5) * 0.45,
        );
        final pos = house.center + porch + jitter;
        if (pos.distance < 1.1) continue;
        if (_tooClose(pos, props.map((p) => p.position), 0.32)) continue;
        props.add(SolidProp(
          pos,
          radius: 0.09 + random.nextDouble() * 0.03,
          kind: n == 0 ? PropKind.barrel : PropKind.crateStack,
        ));
      }
      // Lamp by the door.
      final lampPos = house.center +
          _doorOutward(house) * 0.72 +
          _doorTangent(house) * (0.28 + random.nextDouble() * 0.1);
      if (!_tooClose(lampPos, props.map((p) => p.position), 0.28)) {
        props.add(SolidProp(lampPos, radius: 0.08, kind: PropKind.lampPost));
      }
    }

    return (props: props, houses: houses, chests: chests);
  }

  Offset _doorOutward(House house) => switch (house.doorSide) {
        0 => const Offset(0, -1),
        1 => const Offset(1, 0),
        2 => const Offset(0, 1),
        _ => const Offset(-1, 0),
      };

  Offset _doorTangent(House house) => switch (house.doorSide) {
        0 || 2 => const Offset(1, 0),
        _ => const Offset(0, 1),
      };

  Offset _safePoint({required double minCenter}) {
    final pad = arenaHalf - 1.1;
    for (var attempt = 0; attempt < 40; attempt++) {
      final p = Offset(
        (random.nextDouble() * 2 - 1) * pad,
        (random.nextDouble() * 2 - 1) * pad,
      );
      if (p.distance >= minCenter) return p;
    }
    return Offset(pad * 0.6, pad * 0.4);
  }

  bool _tooClose(Offset p, Iterable<Offset> others, double minDist) {
    for (final o in others) {
      if ((p - o).distance < minDist) return true;
    }
    return false;
  }
}

/// Returns true if [point] is blocked by house walls (door gaps are open).
bool houseBlocksPoint(House house, Offset point, double radius) {
  final outer = house.outer.inflate(radius * 0.35);
  if (!outer.contains(point)) return false;
  final inner = house.inner.deflate(radius * 0.15);
  if (inner.contains(point)) return false;

  // Inside the wall ring — allow the door gap.
  final c = house.center;
  final halfW = house.width / 2;
  final halfD = house.depth / 2;
  final gap = House.doorWidth / 2 + radius * 0.5;
  switch (house.doorSide) {
    case 0: // north (-y)
      if ((point.dy - (c.dy - halfD)).abs() <= House.wallThickness + radius &&
          (point.dx - c.dx).abs() <= gap) {
        return false;
      }
    case 1: // east (+x)
      if ((point.dx - (c.dx + halfW)).abs() <= House.wallThickness + radius &&
          (point.dy - c.dy).abs() <= gap) {
        return false;
      }
    case 2: // south (+y)
      if ((point.dy - (c.dy + halfD)).abs() <= House.wallThickness + radius &&
          (point.dx - c.dx).abs() <= gap) {
        return false;
      }
    case 3: // west (-x)
      if ((point.dx - (c.dx - halfW)).abs() <= House.wallThickness + radius &&
          (point.dy - c.dy).abs() <= gap) {
        return false;
      }
  }
  return true;
}
