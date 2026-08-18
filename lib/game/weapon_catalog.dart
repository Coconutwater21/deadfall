import 'dart:ui';

enum WeaponRarity {
  common,
  uncommon,
  rare,
  epic,
  legendary,
  mythic,
  ascendant,
}

extension WeaponRarityStyle on WeaponRarity {
  String get label => switch (this) {
        WeaponRarity.common => 'Common',
        WeaponRarity.uncommon => 'Uncommon',
        WeaponRarity.rare => 'Rare',
        WeaponRarity.epic => 'Epic',
        WeaponRarity.legendary => 'Legendary',
        WeaponRarity.mythic => 'Mythic',
        WeaponRarity.ascendant => 'Ascendant',
      };

  Color get color => switch (this) {
        WeaponRarity.common => const Color(0xFFB0BEC5),
        WeaponRarity.uncommon => const Color(0xFF66BB6A),
        WeaponRarity.rare => const Color(0xFF42A5F5),
        WeaponRarity.epic => const Color(0xFFAB47BC),
        WeaponRarity.legendary => const Color(0xFFFFB300),
        WeaponRarity.mythic => const Color(0xFF00E5FF),
        WeaponRarity.ascendant => const Color(0xFFFF1744),
      };
}

/// Target raw DPS bands (all pellets hitting one target):
/// Common 95–125 · Uncommon 145–185 · Rare 210–270 ·
/// Epic 300–360 · Legendary 420–520 · Mythic 580–720 · Ascendant 820–980
/// Pierce / blast weapons sit lower on raw DPS because of multi-target value.
enum WeaponKind {
  // Common
  pistol,
  revolver,
  smg,
  machinePistol,
  carbine,
  nailgun,
  pepperbox,
  dualPistols,
  // Uncommon
  shotgun,
  assaultRifle,
  burstCarbine,
  combatShotgun,
  battleRifle,
  pdw,
  leverAction,
  autoShotgun,
  // Rare
  sniper,
  crossbow,
  flamethrower,
  iceRifle,
  marksmanRifle,
  toxinSprayer,
  harpoonGun,
  pulseRifle,
  // Epic
  minigun,
  railgun,
  plasmaCannon,
  grenadeLauncher,
  rocketPod,
  gaussRifle,
  shredder,
  arcCaster,
  // Legendary
  laserLance,
  thunderCannon,
  solarBeam,
  cryoCannon,
  clusterLauncher,
  phantomBow,
  stormCaller,
  rpg,
  // Mythic
  voidCannon,
  starSplitter,
  singularity,
  dragonBreath,
  prismLance,
  oblivionCaster,
  blowdart,
  // Ascendant
  apocalypseCannon,
  eternityRail,
  novaStorm,
  worldEnder,
  genesisBlaster,
}

class WeaponProfile {
  const WeaponProfile({
    required this.label,
    required this.rarity,
    required this.damage,
    required this.cooldown,
    required this.magazineSize,
    required this.reloadSeconds,
    required this.spread,
    required this.range,
    required this.description,
    this.pellets = 1,
    this.pierces = false,
    this.explosionRadius = 0,
    this.ignites = false,
    this.appliesVirus = false,
    this.appliesSlow = false,
  });

  final String label;
  final WeaponRarity rarity;
  final int damage;
  final double cooldown;
  final int magazineSize;
  final double reloadSeconds;
  final int pellets;
  final double spread;
  final double range;
  final bool pierces;
  final double explosionRadius;
  final bool ignites;
  final bool appliesVirus;
  final bool appliesSlow;
  final String description;

  double get dps => (damage * pellets) / cooldown;
  int get dpsRounded => dps.round();
  Color get color => rarity.color;
}

extension WeaponStats on WeaponKind {
  WeaponProfile get profile => weaponProfiles[this]!;

  String get label => profile.label;
  WeaponRarity get rarity => profile.rarity;
  int get damage => profile.damage;
  double get cooldown => profile.cooldown;
  int get magazineSize => profile.magazineSize;
  double get reloadSeconds => profile.reloadSeconds;
  int get pellets => profile.pellets;
  double get spread => profile.spread;
  double get range => profile.range;
  bool get pierces => profile.pierces;
  double get explosionRadius => profile.explosionRadius;
  bool get ignites => profile.ignites;
  bool get appliesVirus => profile.appliesVirus;
  bool get appliesSlow => profile.appliesSlow;
  String get description => profile.description;
  Color get color => profile.color;
  double get dps => profile.dps;
  int get dpsRounded => profile.dpsRounded;

  /// Innate on-shot special (status / blast / pierce), shown in the weapon bar.
  String get specialAbility {
    if (explosionRadius > 0) {
      return pellets > 1
          ? 'Explodes on impact ($pellets pellets)'
          : 'Explodes on impact';
    }
    if (ignites) return 'Ignites enemies on hit';
    if (appliesVirus) return 'Applies a spreading virus';
    if (appliesSlow) return 'Chills and slows on hit';
    if (pierces) return 'Pierces through enemies in a line';
    if (pellets > 1) return 'Fires $pellets pellets per shot';
    return 'Direct hits — no status effect';
  }

  /// Visual silhouette family for world-space weapon painting.
  WeaponBodyStyle get bodyStyle => switch (this) {
        WeaponKind.pistol ||
        WeaponKind.revolver ||
        WeaponKind.machinePistol ||
        WeaponKind.dualPistols ||
        WeaponKind.pepperbox =>
          WeaponBodyStyle.pistol,
        WeaponKind.smg ||
        WeaponKind.pdw ||
        WeaponKind.nailgun ||
        WeaponKind.shredder =>
          WeaponBodyStyle.smg,
        WeaponKind.carbine ||
        WeaponKind.assaultRifle ||
        WeaponKind.burstCarbine ||
        WeaponKind.battleRifle ||
        WeaponKind.leverAction ||
        WeaponKind.pulseRifle =>
          WeaponBodyStyle.rifle,
        WeaponKind.shotgun ||
        WeaponKind.combatShotgun ||
        WeaponKind.autoShotgun =>
          WeaponBodyStyle.shotgun,
        WeaponKind.sniper ||
        WeaponKind.marksmanRifle ||
        WeaponKind.railgun ||
        WeaponKind.gaussRifle ||
        WeaponKind.eternityRail =>
          WeaponBodyStyle.sniper,
        WeaponKind.crossbow ||
        WeaponKind.harpoonGun ||
        WeaponKind.phantomBow ||
        WeaponKind.blowdart =>
          WeaponBodyStyle.bow,
        WeaponKind.flamethrower ||
        WeaponKind.dragonBreath ||
        WeaponKind.toxinSprayer ||
        WeaponKind.cryoCannon =>
          WeaponBodyStyle.flamer,
        WeaponKind.grenadeLauncher ||
        WeaponKind.rocketPod ||
        WeaponKind.clusterLauncher ||
        WeaponKind.rpg ||
        WeaponKind.novaStorm ||
        WeaponKind.thunderCannon ||
        WeaponKind.stormCaller =>
          WeaponBodyStyle.launcher,
        WeaponKind.minigun || WeaponKind.arcCaster => WeaponBodyStyle.minigun,
        WeaponKind.laserLance ||
        WeaponKind.solarBeam ||
        WeaponKind.prismLance ||
        WeaponKind.iceRifle =>
          WeaponBodyStyle.beam,
        WeaponKind.plasmaCannon ||
        WeaponKind.singularity ||
        WeaponKind.oblivionCaster ||
        WeaponKind.voidCannon ||
        WeaponKind.apocalypseCannon ||
        WeaponKind.starSplitter ||
        WeaponKind.genesisBlaster ||
        WeaponKind.worldEnder =>
          WeaponBodyStyle.exotic,
      };

  Color get bodyColor => switch (bodyStyle) {
        WeaponBodyStyle.pistol => const Color(0xFF78909C),
        WeaponBodyStyle.smg => const Color(0xFF546E7A),
        WeaponBodyStyle.rifle => const Color(0xFF5D4037),
        WeaponBodyStyle.shotgun => const Color(0xFF6D4C41),
        WeaponBodyStyle.sniper => const Color(0xFF37474F),
        WeaponBodyStyle.bow => const Color(0xFF8D6E63),
        WeaponBodyStyle.flamer => const Color(0xFFBF360C),
        WeaponBodyStyle.launcher => const Color(0xFF455A64),
        WeaponBodyStyle.minigun => const Color(0xFF263238),
        WeaponBodyStyle.beam => const Color(0xFF006064),
        WeaponBodyStyle.exotic => const Color(0xFF4A148C),
      };

  /// UI arsenal symbol — weapons sharing a symbol share a mastery.
  WeaponSymbol get symbol => switch (this) {
        WeaponKind.pistol || WeaponKind.dualPistols => WeaponSymbol.sidearm,
        WeaponKind.revolver || WeaponKind.leverAction => WeaponSymbol.revolver,
        WeaponKind.smg || WeaponKind.pdw => WeaponSymbol.smg,
        WeaponKind.machinePistol || WeaponKind.nailgun =>
          WeaponSymbol.machinePistol,
        WeaponKind.carbine ||
        WeaponKind.assaultRifle ||
        WeaponKind.battleRifle ||
        WeaponKind.pulseRifle =>
          WeaponSymbol.rifle,
        WeaponKind.pepperbox ||
        WeaponKind.shotgun ||
        WeaponKind.combatShotgun ||
        WeaponKind.autoShotgun =>
          WeaponSymbol.shotgun,
        WeaponKind.burstCarbine || WeaponKind.shredder => WeaponSymbol.burst,
        WeaponKind.sniper ||
        WeaponKind.marksmanRifle ||
        WeaponKind.phantomBow =>
          WeaponSymbol.marksman,
        WeaponKind.crossbow || WeaponKind.harpoonGun => WeaponSymbol.crossbow,
        WeaponKind.flamethrower || WeaponKind.dragonBreath =>
          WeaponSymbol.flamer,
        WeaponKind.iceRifle || WeaponKind.cryoCannon => WeaponSymbol.cryo,
        WeaponKind.toxinSprayer || WeaponKind.blowdart => WeaponSymbol.toxin,
        WeaponKind.minigun || WeaponKind.arcCaster => WeaponSymbol.minigun,
        WeaponKind.railgun ||
        WeaponKind.gaussRifle ||
        WeaponKind.prismLance ||
        WeaponKind.eternityRail =>
          WeaponSymbol.rail,
        WeaponKind.plasmaCannon ||
        WeaponKind.singularity ||
        WeaponKind.oblivionCaster =>
          WeaponSymbol.plasma,
        WeaponKind.grenadeLauncher ||
        WeaponKind.rocketPod ||
        WeaponKind.clusterLauncher ||
        WeaponKind.novaStorm ||
        WeaponKind.rpg =>
          WeaponSymbol.launcher,
        WeaponKind.laserLance || WeaponKind.solarBeam => WeaponSymbol.beam,
        WeaponKind.thunderCannon || WeaponKind.stormCaller =>
          WeaponSymbol.thunder,
        WeaponKind.voidCannon || WeaponKind.apocalypseCannon =>
          WeaponSymbol.voidCore,
        WeaponKind.starSplitter ||
        WeaponKind.genesisBlaster ||
        WeaponKind.worldEnder =>
          WeaponSymbol.star,
      };

  /// Mastery effect family — derived from [symbol] so matching icons match.
  WeaponMastery get mastery => switch (symbol) {
        WeaponSymbol.sidearm || WeaponSymbol.revolver => WeaponMastery.ricochet,
        WeaponSymbol.smg ||
        WeaponSymbol.machinePistol ||
        WeaponSymbol.burst =>
          WeaponMastery.storm,
        WeaponSymbol.rifle => WeaponMastery.creed,
        WeaponSymbol.shotgun => WeaponMastery.shotgun,
        WeaponSymbol.marksman || WeaponSymbol.rail => WeaponMastery.rail,
        WeaponSymbol.crossbow || WeaponSymbol.toxin => WeaponMastery.brand,
        WeaponSymbol.flamer => WeaponMastery.inferno,
        WeaponSymbol.cryo || WeaponSymbol.beam => WeaponMastery.beam,
        WeaponSymbol.minigun => WeaponMastery.overheat,
        WeaponSymbol.launcher || WeaponSymbol.thunder => WeaponMastery.launcher,
        WeaponSymbol.plasma ||
        WeaponSymbol.voidCore ||
        WeaponSymbol.star =>
          WeaponMastery.exotic,
      };
}

enum WeaponBodyStyle {
  pistol,
  smg,
  rifle,
  shotgun,
  sniper,
  bow,
  flamer,
  launcher,
  minigun,
  beam,
  exotic,
}

/// Arsenal tile icon groups.
enum WeaponSymbol {
  sidearm,
  revolver,
  smg,
  machinePistol,
  rifle,
  shotgun,
  burst,
  marksman,
  crossbow,
  flamer,
  cryo,
  toxin,
  minigun,
  rail,
  plasma,
  launcher,
  beam,
  thunder,
  voidCore,
  star,
}

/// Shared mastery effect keyed by [WeaponKind.symbol].
enum WeaponMastery {
  ricochet,
  storm,
  creed,
  shotgun,
  rail,
  brand,
  inferno,
  launcher,
  overheat,
  beam,
  exotic,
}

const Map<WeaponKind, WeaponProfile> weaponProfiles = {
  // —— Common (~100–120 DPS) ——
  WeaponKind.pistol: WeaponProfile(
    label: 'Pistol',
    rarity: WeaponRarity.common,
    damage: 32,
    cooldown: 0.30,
    magazineSize: 12,
    reloadSeconds: 1.1,
    spread: 0.03,
    range: 2.4,
    description: 'Steady sidearm. Reliable starter damage.',
  ),
  WeaponKind.revolver: WeaponProfile(
    label: 'Revolver',
    rarity: WeaponRarity.common,
    damage: 55,
    cooldown: 0.48,
    magazineSize: 6,
    reloadSeconds: 1.55,
    spread: 0.02,
    range: 2.6,
    description: 'Heavy single shots. Slow, punchy common sidearm.',
  ),
  WeaponKind.smg: WeaponProfile(
    label: 'SMG',
    rarity: WeaponRarity.common,
    damage: 11,
    cooldown: 0.095,
    magazineSize: 32,
    reloadSeconds: 1.35,
    spread: 0.09,
    range: 2.1,
    description: 'Rapid spray. Best up close where spread still connects.',
  ),
  WeaponKind.machinePistol: WeaponProfile(
    label: 'M.Pistol',
    rarity: WeaponRarity.common,
    damage: 9,
    cooldown: 0.08,
    magazineSize: 24,
    reloadSeconds: 1.2,
    spread: 0.12,
    range: 1.9,
    description: 'Compact auto-pistol. Faster than SMG, shorter reach.',
  ),
  WeaponKind.carbine: WeaponProfile(
    label: 'Carbine',
    rarity: WeaponRarity.common,
    damage: 28,
    cooldown: 0.26,
    magazineSize: 18,
    reloadSeconds: 1.35,
    spread: 0.035,
    range: 2.7,
    description: 'Light rifle. Clean mid-range common pick.',
  ),
  WeaponKind.nailgun: WeaponProfile(
    label: 'Nailgun',
    rarity: WeaponRarity.common,
    damage: 8,
    cooldown: 0.07,
    magazineSize: 40,
    reloadSeconds: 1.5,
    spread: 0.1,
    range: 2.0,
    description: 'Industrial nail hose. Weak nails, huge volume.',
  ),
  WeaponKind.pepperbox: WeaponProfile(
    label: 'Pepperbox',
    rarity: WeaponRarity.common,
    damage: 14,
    cooldown: 0.40,
    magazineSize: 8,
    reloadSeconds: 1.7,
    pellets: 3,
    spread: 0.14,
    range: 1.8,
    description: 'Three-barrel scatter. Short-range common burst.',
  ),
  WeaponKind.dualPistols: WeaponProfile(
    label: 'Duals',
    rarity: WeaponRarity.common,
    damage: 17,
    cooldown: 0.15,
    magazineSize: 20,
    reloadSeconds: 1.4,
    spread: 0.06,
    range: 2.2,
    description: 'Twin pistols. Faster cadence than a single sidearm.',
  ),

  // —— Uncommon (~150–175 DPS) ——
  WeaponKind.shotgun: WeaponProfile(
    label: 'Shotgun',
    rarity: WeaponRarity.uncommon,
    damage: 16,
    cooldown: 0.65,
    magazineSize: 6,
    reloadSeconds: 1.9,
    pellets: 6,
    spread: 0.24,
    range: 1.6,
    description: 'Pellet cone. Melts anything in your face.',
  ),
  WeaponKind.assaultRifle: WeaponProfile(
    label: 'Assault',
    rarity: WeaponRarity.uncommon,
    damage: 22,
    cooldown: 0.14,
    magazineSize: 28,
    reloadSeconds: 1.65,
    spread: 0.04,
    range: 3.0,
    description: 'Accurate automatic. Solid mid-range all-rounder.',
  ),
  WeaponKind.burstCarbine: WeaponProfile(
    label: 'Burst',
    rarity: WeaponRarity.uncommon,
    damage: 18,
    cooldown: 0.32,
    magazineSize: 24,
    reloadSeconds: 1.5,
    pellets: 3,
    spread: 0.06,
    range: 2.6,
    description: 'Controlled 3-round bursts. Steady uncommon DPS.',
  ),
  WeaponKind.combatShotgun: WeaponProfile(
    label: 'C.Shotty',
    rarity: WeaponRarity.uncommon,
    damage: 14,
    cooldown: 0.58,
    magazineSize: 8,
    reloadSeconds: 1.85,
    pellets: 7,
    spread: 0.28,
    range: 1.5,
    description: 'Wider blast pattern. Meaner at point-blank.',
  ),
  WeaponKind.battleRifle: WeaponProfile(
    label: 'Battle Rifle',
    rarity: WeaponRarity.uncommon,
    damage: 36,
    cooldown: 0.22,
    magazineSize: 16,
    reloadSeconds: 1.7,
    spread: 0.025,
    range: 3.3,
    description: 'Semi-auto thumper. Accurate uncommon mid-long pick.',
  ),
  WeaponKind.pdw: WeaponProfile(
    label: 'PDW',
    rarity: WeaponRarity.uncommon,
    damage: 14,
    cooldown: 0.085,
    magazineSize: 30,
    reloadSeconds: 1.45,
    spread: 0.07,
    range: 2.3,
    description: 'Personal defense weapon. Tight spray for its class.',
  ),
  WeaponKind.leverAction: WeaponProfile(
    label: 'Lever',
    rarity: WeaponRarity.uncommon,
    damage: 48,
    cooldown: 0.30,
    magazineSize: 8,
    reloadSeconds: 1.8,
    spread: 0.02,
    range: 3.1,
    description: 'Classic lever rifle. Hard hits, steady cadence.',
  ),
  WeaponKind.autoShotgun: WeaponProfile(
    label: 'Auto Shotty',
    rarity: WeaponRarity.uncommon,
    damage: 12,
    cooldown: 0.38,
    magazineSize: 10,
    reloadSeconds: 2.0,
    pellets: 5,
    spread: 0.26,
    range: 1.55,
    description: 'Semi-auto scatter. Faster follow-ups than pump guns.',
  ),

  // —— Rare (~220–255 DPS) ——
  WeaponKind.sniper: WeaponProfile(
    label: 'Sniper',
    rarity: WeaponRarity.rare,
    damage: 145,
    cooldown: 0.62,
    magazineSize: 5,
    reloadSeconds: 2.2,
    spread: 0.004,
    range: 5.4,
    description: 'Long-range precision. Huge damage per click.',
  ),
  WeaponKind.crossbow: WeaponProfile(
    label: 'Crossbow',
    rarity: WeaponRarity.rare,
    damage: 112,
    cooldown: 0.48,
    magazineSize: 5,
    reloadSeconds: 1.9,
    spread: 0.01,
    range: 4.1,
    appliesSlow: true,
    description: 'Power bolts. Strong hits that briefly snare targets.',
  ),
  WeaponKind.flamethrower: WeaponProfile(
    label: 'Flamer',
    rarity: WeaponRarity.rare,
    damage: 26,
    cooldown: 0.16,
    magazineSize: 55,
    reloadSeconds: 2.5,
    pellets: 3,
    spread: 0.3,
    range: 1.25,
    ignites: true,
    description: 'Short-range fire stream. Melts crowds up close.',
  ),
  WeaponKind.iceRifle: WeaponProfile(
    label: 'Ice Rifle',
    rarity: WeaponRarity.rare,
    damage: 32,
    cooldown: 0.13,
    magazineSize: 22,
    reloadSeconds: 1.75,
    spread: 0.03,
    range: 3.2,
    appliesSlow: true,
    description: 'Chilling mid-range rounds. Slows whatever they hit.',
  ),
  WeaponKind.marksmanRifle: WeaponProfile(
    label: 'Marksman',
    rarity: WeaponRarity.rare,
    damage: 55,
    cooldown: 0.22,
    magazineSize: 12,
    reloadSeconds: 1.85,
    spread: 0.012,
    range: 4.5,
    description: 'Precision mid-long rifle. Clean rare damage.',
  ),
  WeaponKind.toxinSprayer: WeaponProfile(
    label: 'Toxin',
    rarity: WeaponRarity.rare,
    damage: 12,
    cooldown: 0.20,
    magazineSize: 40,
    reloadSeconds: 2.1,
    pellets: 4,
    spread: 0.22,
    range: 1.7,
    description: 'Toxic mist cone. Short range, high volume.',
  ),
  WeaponKind.harpoonGun: WeaponProfile(
    label: 'Harpoon',
    rarity: WeaponRarity.rare,
    damage: 98,
    cooldown: 0.42,
    magazineSize: 4,
    reloadSeconds: 2.0,
    spread: 0.015,
    range: 3.8,
    appliesSlow: true,
    description: 'Heavy spears. Hard punches that drag enemies to a crawl.',
  ),
  WeaponKind.pulseRifle: WeaponProfile(
    label: 'Pulse',
    rarity: WeaponRarity.rare,
    damage: 28,
    cooldown: 0.11,
    magazineSize: 26,
    reloadSeconds: 1.7,
    spread: 0.035,
    range: 3.4,
    description: 'Energy automatic. Reliable rare mid-range DPS.',
  ),

  // —— Epic (~300–350 DPS; pierce/blast lower) ——
  WeaponKind.minigun: WeaponProfile(
    label: 'Minigun',
    rarity: WeaponRarity.epic,
    damage: 16,
    cooldown: 0.05,
    magazineSize: 100,
    reloadSeconds: 3.1,
    spread: 0.11,
    range: 2.8,
    description: 'Bullet hose. Huge mag, wide spray, long reload.',
  ),
  WeaponKind.railgun: WeaponProfile(
    label: 'Railgun',
    rarity: WeaponRarity.epic,
    damage: 185,
    cooldown: 0.70,
    magazineSize: 4,
    reloadSeconds: 2.6,
    spread: 0.0,
    range: 5.6,
    pierces: true,
    description: 'Piercing rail shot. Tears through every zombie in line.',
  ),
  WeaponKind.plasmaCannon: WeaponProfile(
    label: 'Plasma',
    rarity: WeaponRarity.epic,
    damage: 42,
    cooldown: 0.26,
    magazineSize: 10,
    reloadSeconds: 2.0,
    pellets: 2,
    spread: 0.05,
    range: 3.5,
    description: 'Twin plasma bolts. Chunky epic mid-range fire.',
  ),
  WeaponKind.grenadeLauncher: WeaponProfile(
    label: 'Grenades',
    rarity: WeaponRarity.epic,
    damage: 95,
    cooldown: 0.48,
    magazineSize: 5,
    reloadSeconds: 2.3,
    spread: 0.05,
    range: 3.1,
    explosionRadius: 0.62,
    description: 'Lobbed explosives. Detonates on impact with splash.',
  ),
  WeaponKind.rocketPod: WeaponProfile(
    label: 'Rockets',
    rarity: WeaponRarity.epic,
    damage: 110,
    cooldown: 0.55,
    magazineSize: 4,
    reloadSeconds: 2.5,
    spread: 0.04,
    range: 3.6,
    explosionRadius: 0.7,
    description: 'Micro-rockets. Wider blast than grenades, slower fire.',
  ),
  WeaponKind.gaussRifle: WeaponProfile(
    label: 'Gauss',
    rarity: WeaponRarity.epic,
    damage: 160,
    cooldown: 0.55,
    magazineSize: 6,
    reloadSeconds: 2.2,
    spread: 0.008,
    range: 5.0,
    pierces: true,
    description: 'Magnetic pierce rifle. Line damage with less kick than rail.',
  ),
  WeaponKind.shredder: WeaponProfile(
    label: 'Shredder',
    rarity: WeaponRarity.epic,
    damage: 18,
    cooldown: 0.16,
    magazineSize: 36,
    reloadSeconds: 2.0,
    pellets: 3,
    spread: 0.1,
    range: 2.6,
    description: 'Triple-slice rounds. Tears packs at mid range.',
  ),
  WeaponKind.arcCaster: WeaponProfile(
    label: 'Arc Caster',
    rarity: WeaponRarity.epic,
    damage: 30,
    cooldown: 0.09,
    magazineSize: 35,
    reloadSeconds: 1.95,
    spread: 0.06,
    range: 3.2,
    description: 'Lightning spray. High epic cadence.',
  ),

  // —— Legendary (~430–490 DPS; blast lower) ——
  WeaponKind.laserLance: WeaponProfile(
    label: 'Laser',
    rarity: WeaponRarity.legendary,
    damage: 38,
    cooldown: 0.085,
    magazineSize: 40,
    reloadSeconds: 1.8,
    spread: 0.015,
    range: 4.4,
    description: 'Beam spray. Fast legendary firepower.',
  ),
  WeaponKind.thunderCannon: WeaponProfile(
    label: 'Thunder',
    rarity: WeaponRarity.legendary,
    damage: 48,
    cooldown: 0.42,
    magazineSize: 8,
    reloadSeconds: 2.4,
    pellets: 4,
    spread: 0.14,
    range: 3.2,
    description: 'Storm volley. Clears packs with wide legendary spread.',
  ),
  WeaponKind.solarBeam: WeaponProfile(
    label: 'Solar',
    rarity: WeaponRarity.legendary,
    damage: 52,
    cooldown: 0.11,
    magazineSize: 28,
    reloadSeconds: 2.0,
    spread: 0.02,
    range: 4.6,
    description: 'Concentrated sun lance. Hot legendary mid-long DPS.',
  ),
  WeaponKind.cryoCannon: WeaponProfile(
    label: 'Cryo',
    rarity: WeaponRarity.legendary,
    damage: 40,
    cooldown: 0.18,
    magazineSize: 24,
    reloadSeconds: 2.1,
    pellets: 2,
    spread: 0.05,
    range: 3.6,
    appliesSlow: true,
    description: 'Twin frost bolts. Legendary chill that freezes movement.',
  ),
  WeaponKind.clusterLauncher: WeaponProfile(
    label: 'Cluster',
    rarity: WeaponRarity.legendary,
    damage: 120,
    cooldown: 0.40,
    magazineSize: 5,
    reloadSeconds: 2.45,
    spread: 0.06,
    range: 3.4,
    explosionRadius: 0.78,
    description: 'Cluster bombs. Huge legendary splash on impact.',
  ),
  WeaponKind.phantomBow: WeaponProfile(
    label: 'Phantom Bow',
    rarity: WeaponRarity.legendary,
    damage: 170,
    cooldown: 0.38,
    magazineSize: 7,
    reloadSeconds: 1.9,
    spread: 0.01,
    range: 4.8,
    appliesSlow: true,
    description: 'Spectral arrows. Hard precision shots that linger with frost.',
  ),
  WeaponKind.stormCaller: WeaponProfile(
    label: 'Storm',
    rarity: WeaponRarity.legendary,
    damage: 35,
    cooldown: 0.24,
    magazineSize: 18,
    reloadSeconds: 2.15,
    pellets: 3,
    spread: 0.09,
    range: 3.5,
    description: 'Triple thunderbolts. Legendary pack shredder.',
  ),
  WeaponKind.rpg: WeaponProfile(
    label: 'RPG',
    rarity: WeaponRarity.legendary,
    damage: 320,
    cooldown: 1.4,
    magazineSize: 1,
    reloadSeconds: 2.8,
    spread: 0.02,
    range: 4.2,
    explosionRadius: 1.15,
    ignites: true,
    description:
        'One rocket. Massive blast radius, huge damage, leaves enemies burning.',
  ),

  // —— Mythic (~600–680 DPS; pierce lower) ——
  WeaponKind.voidCannon: WeaponProfile(
    label: 'Void',
    rarity: WeaponRarity.mythic,
    damage: 95,
    cooldown: 0.30,
    magazineSize: 12,
    reloadSeconds: 2.1,
    pellets: 2,
    spread: 0.035,
    range: 4.8,
    description: 'Mythic twin void beams. Elite deletion at range.',
  ),
  WeaponKind.starSplitter: WeaponProfile(
    label: 'Star Split',
    rarity: WeaponRarity.mythic,
    damage: 48,
    cooldown: 0.22,
    magazineSize: 30,
    reloadSeconds: 2.0,
    pellets: 3,
    spread: 0.07,
    range: 4.0,
    description: 'Mythic starburst. Rapid triple-shot pressure.',
  ),
  WeaponKind.singularity: WeaponProfile(
    label: 'Singularity',
    rarity: WeaponRarity.mythic,
    damage: 120,
    cooldown: 0.18,
    magazineSize: 14,
    reloadSeconds: 2.2,
    spread: 0.02,
    range: 4.5,
    description: 'Collapsed-star rounds. Dense mythic single shots.',
  ),
  WeaponKind.dragonBreath: WeaponProfile(
    label: 'Dragon',
    rarity: WeaponRarity.mythic,
    damage: 28,
    cooldown: 0.17,
    magazineSize: 45,
    reloadSeconds: 2.4,
    pellets: 4,
    spread: 0.2,
    range: 2.0,
    description: 'Mythic fire cone. Short range, catastrophic volume.',
  ),
  WeaponKind.prismLance: WeaponProfile(
    label: 'Prism',
    rarity: WeaponRarity.mythic,
    damage: 210,
    cooldown: 0.42,
    magazineSize: 6,
    reloadSeconds: 2.3,
    spread: 0.0,
    range: 5.8,
    pierces: true,
    description: 'Refracted pierce beam. Mythic line wipe.',
  ),
  WeaponKind.oblivionCaster: WeaponProfile(
    label: 'Oblivion',
    rarity: WeaponRarity.mythic,
    damage: 55,
    cooldown: 0.17,
    magazineSize: 22,
    reloadSeconds: 2.05,
    pellets: 2,
    spread: 0.04,
    range: 4.3,
    description: 'Twin oblivion bolts. Smooth mythic DPS.',
  ),
  WeaponKind.blowdart: WeaponProfile(
    label: 'Blowdart',
    rarity: WeaponRarity.mythic,
    damage: 78,
    cooldown: 0.34,
    magazineSize: 14,
    reloadSeconds: 1.65,
    spread: 0.008,
    range: 5.0,
    appliesVirus: true,
    description:
        'Toxic darts. Heavy poison DoT that slows and leaps between nearby zombies.',
  ),

  // —— Ascendant (~850–960 DPS; pierce lower) ——
  WeaponKind.apocalypseCannon: WeaponProfile(
    label: 'Apocalypse',
    rarity: WeaponRarity.ascendant,
    damage: 110,
    cooldown: 0.24,
    magazineSize: 16,
    reloadSeconds: 2.3,
    pellets: 2,
    spread: 0.03,
    range: 5.0,
    description: 'Ascendant twin doom beams. End-of-run firepower.',
  ),
  WeaponKind.eternityRail: WeaponProfile(
    label: 'Eternity',
    rarity: WeaponRarity.ascendant,
    damage: 320,
    cooldown: 0.48,
    magazineSize: 5,
    reloadSeconds: 2.6,
    spread: 0.0,
    range: 6.2,
    pierces: true,
    description: 'Ascendant pierce rail. Deletes entire lanes.',
  ),
  WeaponKind.novaStorm: WeaponProfile(
    label: 'Nova Storm',
    rarity: WeaponRarity.ascendant,
    damage: 85,
    cooldown: 0.28,
    magazineSize: 10,
    reloadSeconds: 2.5,
    pellets: 2,
    spread: 0.08,
    range: 3.8,
    explosionRadius: 0.72,
    description: 'Ascendant nova shells. Twin blasts on every impact.',
  ),
  WeaponKind.worldEnder: WeaponProfile(
    label: 'World Ender',
    rarity: WeaponRarity.ascendant,
    damage: 180,
    cooldown: 0.20,
    magazineSize: 12,
    reloadSeconds: 2.4,
    spread: 0.015,
    range: 5.2,
    description: 'Ascendant annihilation cannon. Pure boss melt.',
  ),
  WeaponKind.genesisBlaster: WeaponProfile(
    label: 'Genesis',
    rarity: WeaponRarity.ascendant,
    damage: 85,
    cooldown: 0.18,
    magazineSize: 24,
    reloadSeconds: 2.2,
    pellets: 2,
    spread: 0.04,
    range: 4.7,
    description: 'Ascendant creation fire. Relentless twin beams.',
  ),
};
