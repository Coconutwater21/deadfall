import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../game/survival_engine.dart';
import '../game/ui_layout_settings.dart';
import '../game/keybind_settings.dart';

class SurvivalGameScreen extends StatefulWidget {
  const SurvivalGameScreen({super.key});

  @override
  State<SurvivalGameScreen> createState() => _SurvivalGameScreenState();
}

class _SurvivalGameScreenState extends State<SurvivalGameScreen>
    with SingleTickerProviderStateMixin {
  late final SurvivalEngine engine;
  late final GameAudio _audio;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  Offset _joystick = Offset.zero;
  Duration? _lastTick;
  bool _showIntro = true;
  bool _showSettings = false;
  UiLayoutSettings _ui = UiLayoutSettings();
  KeybindSettings _binds = KeybindSettings();
  GameAction? _rebindingAction;
  final ScrollController _weaponBarScroll = ScrollController();
  final ScrollController _classBarScroll = ScrollController();
  WeaponKind? _weaponBarScrollTarget;
  final Map<WeaponKind, GlobalKey> _weaponTileKeys = {};
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    engine = SurvivalEngine();
    engine.paused = true;
    _audio = GameAudio();
    engine.onAudioCue = (cue, {weapon}) {
      // Fire-and-forget; never let SFX errors tear down the isolate.
      _audio.play(cue, weapon: weapon);
    };
    _ticker = createTicker(_tick)..start();
    engine.loadHighScores();
    _loadUiSettings();
    // Defer audio until after the first frame so the Flutter engine / plugins
    // are fully up (avoids white-screen kills on physical iOS devices).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _audio.init().then((_) {
        if (!mounted) return;
        _syncAudioSettings();
        _syncMusic();
      }).catchError((Object e, StackTrace st) {
        debugPrint('Audio startup failed: $e\n$st');
      });
    });
    // Web: keep right-click for ability instead of the browser menu.
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  Future<void> _loadUiSettings() async {
    final loaded = await UiLayoutSettings.load();
    final binds = await KeybindSettings.load();
    if (!mounted) return;
    setState(() {
      _ui = loaded;
      _binds = binds;
      engine.autoEquipNewWeapons = loaded.autoEquipNewWeapons;
    });
    _syncAudioSettings();
    _syncMusic();
  }

  void _syncAudioSettings() {
    _audio.setMuted(_ui.muted);
    _audio.setMusicEnabled(_ui.musicEnabled);
    _audio.setMusicVolume(_ui.musicVolume);
    _audio.setSfxVolume(_ui.sfxVolume);
  }

  void _syncMusic() {
    final duck = engine.paused || _showIntro || _showSettings;
    _audio.setPausedDuck(duck && !engine.gameOver);

    final GameMusic track;
    if (engine.gameOver || _showIntro) {
      track = GameMusic.menu;
    } else {
      final elite = engine.eliteMusicTrack;
      if (elite != GameMusic.none) {
        track = elite;
      } else if (engine.wave > 0 || engine.waveActive) {
        track = GameMusic.combat;
      } else {
        track = GameMusic.menu;
      }
    }
    _audio.setMusic(track);
  }

  Future<void> _persistUiSettings() async {
    await _ui.save();
    await _binds.save();
  }

  void _syncGameplaySettings() {
    engine.autoEquipNewWeapons = _ui.autoEquipNewWeapons;
  }

  bool get _compact {
    final size = MediaQuery.sizeOf(context);
    return UiLayoutSettings.isCompact(size);
  }

  double get _hudScale =>
      _ui.uiScale * UiLayoutSettings.densityFor(MediaQuery.sizeOf(context));

  double get _ctrlScale =>
      _ui.controlsScale *
      (UiLayoutSettings.isCompact(MediaQuery.sizeOf(context)) ? 0.78 : 1.0);

  // Positions come straight from saved settings so phones can customize freely.
  double get _hudTop => _ui.hudTop;

  double get _classBarTop => _ui.classBarTop;

  double get _weaponBarBottom => _ui.weaponBarBottom;

  double get _controlsBottom => _ui.controlsBottom;

  double get _controlsSideInset => _ui.controlsSideInset;

  void _openSettings() {
    setState(() {
      _showSettings = true;
      _rebindingAction = null;
    });
  }

  void _closeSettings() {
    setState(() {
      _showSettings = false;
      _rebindingAction = null;
    });
    _syncGameplaySettings();
    _persistUiSettings();
    _focusNode.requestFocus();
  }

  void _resetUiSettings() {
    setState(() {
      _ui.resetFor(MediaQuery.sizeOf(context));
      _binds.reset();
      _rebindingAction = null;
      _syncGameplaySettings();
      _syncAudioSettings();
    });
    _persistUiSettings();
  }

  void _startRebind(GameAction action) {
    setState(() => _rebindingAction = action);
    _focusNode.requestFocus();
  }

  void _applyRebind(LogicalKeyboardKey key) {
    final action = _rebindingAction;
    if (action == null) return;
    // Ignore modifier-only keys.
    if (key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return;
    }
    setState(() {
      _binds.rebind(action, key);
      _rebindingAction = null;
    });
    _binds.save();
  }

  void _tick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick!).inMicroseconds / 1000000;
    _lastTick = elapsed;
    engine.update(dt);
    _syncMusic();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _ticker.dispose();
    _focusNode.dispose();
    _nameFocus.dispose();
    _nameController.dispose();
    _weaponBarScroll.dispose();
    _classBarScroll.dispose();
    engine.onAudioCue = null;
    engine.dispose();
    _audio.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // Let the leaderboard name field receive typing.
    if (engine.awaitingNameEntry || _nameFocus.hasFocus) {
      return KeyEventResult.ignored;
    }

    // Capture the next key while remapping in settings.
    if (_rebindingAction != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent)) {
      _applyRebind(event.logicalKey);
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _keys.add(key);
      if (_binds.matches(GameAction.fire, key)) {
        engine.aimAtNearest();
        engine.setFiring(true);
      }
      // Weapon swap / class hotkeys only on key down (not repeat).
      if (event is KeyDownEvent) {
        if (_binds.matches(GameAction.weaponPrev, key)) {
          engine.cycleWeapon(-1);
        }
        if (_binds.matches(GameAction.weaponNext, key)) {
          engine.cycleWeapon(1);
        }
        if (_binds.matches(GameAction.reload, key)) engine.reload();
        if (_binds.matches(GameAction.ability, key)) engine.activateAbility();
        if (_binds.matches(GameAction.upgradeWeapon, key)) {
          engine.tryUpgradeEquippedWeapon();
        }
        if (_binds.matches(GameAction.upgradeClass, key)) {
          engine.tryUpgradeEquippedClass();
        }
        if (_binds.matches(GameAction.upgradeAbility, key)) {
          engine.tryUpgradeEquippedAbility();
        }
        if (key == LogicalKeyboardKey.digit1 ||
            key == LogicalKeyboardKey.numpad1) {
          engine.selectClassByHotkey(0);
        }
        if (key == LogicalKeyboardKey.digit2 ||
            key == LogicalKeyboardKey.numpad2) {
          engine.selectClassByHotkey(1);
        }
        if (key == LogicalKeyboardKey.digit3 ||
            key == LogicalKeyboardKey.numpad3) {
          engine.selectClassByHotkey(2);
        }
        if (key == LogicalKeyboardKey.digit4 ||
            key == LogicalKeyboardKey.numpad4) {
          engine.selectClassByHotkey(3);
        }
        if (key == LogicalKeyboardKey.digit5 ||
            key == LogicalKeyboardKey.numpad5) {
          engine.selectClassByHotkey(4);
        }
        if (key == LogicalKeyboardKey.digit6 ||
            key == LogicalKeyboardKey.numpad6) {
          engine.selectClassByHotkey(5);
        }
        if (key == LogicalKeyboardKey.digit7 ||
            key == LogicalKeyboardKey.numpad7) {
          engine.selectClassByHotkey(6);
        }
        if (key == LogicalKeyboardKey.digit8 ||
            key == LogicalKeyboardKey.numpad8) {
          engine.selectClassByHotkey(7);
        }
        if (key == LogicalKeyboardKey.digit9 ||
            key == LogicalKeyboardKey.numpad9) {
          engine.selectClassByHotkey(8);
        }
        if (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0) {
          engine.selectClassByHotkey(9);
        }
        if (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract) {
          engine.selectClassByHotkey(10);
        }
        if (_binds.matches(GameAction.cycleClass, key)) {
          final unlocked = PlayerClass.values
              .where(engine.unlockedClasses.contains)
              .toList();
          if (unlocked.isNotEmpty) {
            final index = unlocked.indexOf(engine.playerClass);
            final next = unlocked[(index + 1) % unlocked.length];
            engine.selectClass(next);
          }
        }
      }
      if (_binds.matches(GameAction.pause, key)) {
        if (_showSettings) {
          if (_rebindingAction != null) {
            setState(() => _rebindingAction = null);
          } else {
            _closeSettings();
          }
        } else {
          engine.togglePause();
          if (!engine.paused) _showSettings = false;
        }
      }
    } else if (event is KeyUpEvent) {
      _keys.remove(key);
      if (_binds.matches(GameAction.fire, key)) engine.setFiring(false);
    }
    _updateMovement();
    return KeyEventResult.handled;
  }

  void _updateMovement() {
    var dx = _joystick.dx;
    var dy = _joystick.dy;
    if (_binds.isPressed(GameAction.moveLeft, _keys)) dx--;
    if (_binds.isPressed(GameAction.moveRight, _keys)) dx++;
    if (_binds.isPressed(GameAction.moveUp, _keys)) dy--;
    if (_binds.isPressed(GameAction.moveDown, _keys)) dy++;
    engine.setMovement(Offset(dx, dy));
  }

  void _setJoystick(Offset direction) {
    _joystick = direction;
    _updateMovement();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final naming = engine.awaitingNameEntry;
        return Focus(
          focusNode: _focusNode,
          autofocus: !naming,
          canRequestFocus: !naming,
          skipTraversal: naming,
          onKeyEvent: _handleKey,
          child: ScrollConfiguration(
            behavior: const _MouseDragScrollBehavior(),
            child: Scaffold(
            backgroundColor: const Color(0xFF05090D),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final projection = ArenaProjection(
                    size,
                    engine.player,
                    zoom: UiLayoutSettings.isCompact(size) ? 1.45 : 1,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          onHover: (event) => engine.setAim(
                              projection.toWorld(event.localPosition)),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) {
                              if (!(engine.gameOver &&
                                  engine.awaitingNameEntry)) {
                                _focusNode.requestFocus();
                              }
                              engine.setAim(
                                  projection.toWorld(event.localPosition));
                              if (engine.gameOver) return;
                              if ((event.buttons & kSecondaryMouseButton) !=
                                  0) {
                                engine.activateAbility();
                                return;
                              }
                              engine.setFiring(true);
                            },
                            onPointerMove: (event) => engine.setAim(
                                projection.toWorld(event.localPosition)),
                            onPointerUp: (_) => engine.setFiring(false),
                            onPointerCancel: (_) => engine.setFiring(false),
                            child: CustomPaint(
                              painter: SurvivalPainter(engine, projection),
                            ),
                          ),
                        ),
                      ),
                      _buildHud(),
                      _buildClassBar(),
                      _buildWeaponBar(),
                      _buildMobileControls(),
                      if (engine.waveBannerTimer > 0) _buildWaveBanner(),
                      if (engine.notificationTimer > 0) _buildNotification(),
                      if (engine.damageFlash > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.redAccent
                                      .withValues(alpha: 0.7),
                                  width: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (engine.badEndingCutscene && !engine.gameOver)
                        _buildBadEndingCutscene()
                      else if (_showIntro && !engine.gameOver)
                        _buildIntro()
                      else if (engine.paused && _showSettings)
                        _buildSettingsOverlay()
                      else if (engine.paused)
                        _buildPauseOverlay(),
                      if (engine.gameOver) _buildGameOver(),
                    ],
                  );
                },
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildHud() {
    final healthRatio =
        (engine.health / engine.maxHealth).clamp(0.0, 1.0).toDouble();
    final overhealed = engine.health > engine.maxHealth;
    final healthColor = overhealed
        ? const Color(0xFF80DEEA)
        : healthRatio > 0.5
            ? const Color(0xFF77E28A)
            : healthRatio > 0.25
                ? Colors.orangeAccent
                : Colors.redAccent;
    final ammoColor = engine.isReloading
        ? Colors.amberAccent
        : engine.ammoInMag == 0
            ? Colors.redAccent
            : engine.weapon.color;
    final elites = _activeElites;
    return Positioned(
      left: _compact ? 8 : 14,
      right: _compact ? 8 : 14,
      top: _hudTop,
      child: Transform.scale(
        alignment: Alignment.topCenter,
        scale: _hudScale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite,
                        color: Colors.redAccent, size: 21),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        overhealed
                            ? '${engine.health}/${engine.maxHealth}  OVERHEAL  ${engine.playerClass.label}'
                            : '${engine.health}/${engine.maxHealth}  ${engine.playerClass.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: overhealed
                              ? const Color(0xFF80DEEA)
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Container(
                  height: 16,
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0A1018),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: healthColor.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      children: [
                        Container(color: const Color(0xFF1A222C)),
                        FractionallySizedBox(
                          widthFactor: healthRatio,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color.lerp(healthColor, Colors.white, 0.25)!,
                                  healthColor,
                                  Color.lerp(healthColor, Colors.black, 0.25)!,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: healthColor.withValues(alpha: 0.7),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (engine.playerClass == PlayerClass.reaper) ...[
                  const SizedBox(height: 6),
                  _buildSoulBar(),
                ],
              ],
            ),
          ),
          Flexible(
            flex: 5,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (engine.soulScytheActive)
                    _hudPill(
                      Icons.content_cut,
                      engine.soulScytheSwinging
                          ? 'SWING'
                          : 'SCYTHE ${engine.soulScytheSecondsLeft.toStringAsFixed(1)}s',
                      const Color(0xFFB388FF),
                    )
                  else
                    _hudPill(
                      Icons.sports_martial_arts,
                      engine.isReloading
                          ? 'REL ${engine.reloadSecondsLeft.toStringAsFixed(1)}s'
                          : '${engine.ammoInMag}/${engine.magazineSize}',
                      ammoColor,
                    ),
                  const SizedBox(width: 8),
                  _hudPill(
                    Icons.auto_awesome,
                    engine.soulScytheActive
                        ? 'Soul Scythe'
                        : engine.weaponLevel(engine.weapon) > 0
                            ? '${engine.weapon.label} +${engine.weaponLevel(engine.weapon)}'
                            : engine.weapon.label,
                    engine.soulScytheActive
                        ? const Color(0xFFB388FF)
                        : engine.weapon.rarity.color,
                  ),
                  if (engine.isSlowedByGoo) ...[
                    const SizedBox(width: 8),
                    _hudPill(
                      Icons.water_drop,
                      'GOO SLOW',
                      const Color(0xFF76FF03),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _hudPill(
                      Icons.attach_money, '${engine.money}', Colors.amberAccent),
                  const SizedBox(width: 8),
                  _hudPill(
                      Icons.gps_fixed, '${engine.kills}', Colors.orangeAccent),
                  const SizedBox(width: 8),
                  _hudPill(
                    Icons.vpn_key,
                    '${engine.miniKeys}/${engine.bossKeys}',
                    const Color(0xFFFFD54F),
                  ),
                  const SizedBox(width: 8),
                  _hudPill(
                    Icons.flash_on,
                    engine.abilityUnlocked
                        ? (engine.abilityCooldownLeft > 0
                            ? 'F/RMB ${engine.abilityCooldownLeft.toStringAsFixed(0)}s'
                            : 'F/RMB')
                        : 'F/RMB',
                    engine.abilityReady
                        ? Colors.lightGreenAccent
                        : engine.isShielded
                            ? Colors.lightBlueAccent
                            : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  _hudPill(
                    Icons.warning_amber_rounded,
                    engine.waveActive
                        ? 'W${engine.wave} · ${engine.enemiesRemaining}'
                        : 'N${engine.nextWaveTimer.ceil()}',
                    const Color(0xFF9BE7FF),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      if (_showSettings) {
                        _closeSettings();
                      }
                      engine.togglePause();
                      if (!engine.paused) {
                        setState(() => _showSettings = false);
                      }
                    },
                    icon: const Icon(Icons.pause, size: 20),
                    tooltip: 'Pause',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
            if (elites.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...elites.asMap().entries.map((entry) {
                final i = entry.key;
                final elite = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i < elites.length - 1 ? 6 : 0,
                  ),
                  child: _buildEliteHealthBar(
                    elite,
                    compact: elites.length > 1,
                    indexLabel: elites.length > 1
                        ? '${i + 1}/${elites.length}'
                        : null,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSoulBar() {
    final ratio = engine.soulCharge.clamp(0.0, 1.0);
    const accent = Color(0xFFB388FF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          engine.soulScytheActive
              ? 'SOUL BAR  ·  SCYTHE ACTIVE'
              : 'SOUL BAR',
          style: TextStyle(
            color: accent.withValues(alpha: 0.95),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 12,
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xCC0A1018),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(color: const Color(0xFF1A1524)),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(accent, Colors.white, 0.35)!,
                          accent,
                          const Color(0xFF7E57C2),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// All living bosses / mini-bosses, bosses first, then lowest HP%.
  List<Zombie> get _activeElites {
    final elites = engine.zombies
        .where((z) => z.kind.isBoss || z.kind.isMiniBoss)
        .toList();
    elites.sort((a, b) {
      final bossCmp =
          (b.kind.isBoss ? 1 : 0).compareTo(a.kind.isBoss ? 1 : 0);
      if (bossCmp != 0) return bossCmp;
      final aRatio = a.maxHealth <= 0 ? 1.0 : a.health / a.maxHealth;
      final bRatio = b.maxHealth <= 0 ? 1.0 : b.health / b.maxHealth;
      return aRatio.compareTo(bRatio);
    });
    return elites;
  }

  Widget _buildEliteHealthBar(
    Zombie elite, {
    bool compact = false,
    String? indexLabel,
  }) {
    final ratio =
        (elite.health / elite.maxHealth).clamp(0.0, 1.0).toDouble();
    final accent = elite.kind.color;
    final tier = elite.kind.isBoss ? 'BOSS' : 'MINI-BOSS';
    final title = indexLabel == null
        ? '$tier · ${elite.kind.label.toUpperCase()}'
        : '$tier $indexLabel · ${elite.kind.label.toUpperCase()}';
    final hpText =
        '${elite.health.ceil()}/${elite.maxHealth.ceil()}';
    final barHeight = compact ? 14.0 : 18.0;
    final titleSize = compact ? 11.0 : 13.0;
    final hpSize = compact ? 10.0 : 11.0;
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 36 : 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? 1.0 : 1.4,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            Container(
              height: barHeight,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xDD0A1018),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: accent.withValues(alpha: 0.75),
                  width: compact ? 1.2 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: compact ? 8 : 12,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(color: const Color(0xFF1A222C)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(accent, Colors.white, 0.35)!,
                                accent,
                                Color.lerp(accent, Colors.black, 0.3)!,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      hpText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: hpSize,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xD9111820),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassBar() {
    final compact = _compact;
    final classesByPrice = PlayerClass.values.toList()
      ..sort((a, b) {
        final byMoney = a.moneyCost.compareTo(b.moneyCost);
        if (byMoney != 0) return byMoney;
        final byKills = a.killCost.compareTo(b.killCost);
        if (byKills != 0) return byKills;
        return a.label.compareTo(b.label);
      });
    return Positioned(
      left: compact ? 6 : 12,
      right: compact ? 6 : 12,
      top: _classBarTop,
      child: Transform.scale(
        alignment: Alignment.topCenter,
        scale: _hudScale,
        // heightFactor keeps this shrink-wrapped so scale doesn't shift it.
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: Container(
          constraints: BoxConstraints(maxWidth: compact ? 640 : 920),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 8,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC111820),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: _wheelScrollable(
            controller: _classBarScroll,
            axis: Axis.horizontal,
            child: SingleChildScrollView(
            controller: _classBarScroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    'CLASS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...classesByPrice.map((kind) {
                  final unlocked = engine.unlockedClasses.contains(kind);
                  final selected = engine.playerClass == kind;
                  final canBuy = engine.canUnlockClass(kind);
                  final hotkey = kind.index == 9
                      ? '0'
                      : kind.index == 10
                          ? '-'
                          : '${kind.index + 1}';
                  return Padding(
                    padding: EdgeInsets.only(right: compact ? 4 : 6),
                    child: InkWell(
                      onTap: () {
                        if (unlocked) {
                          engine.selectClass(kind);
                        } else {
                          engine.unlockClass(kind);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 7 : 10,
                            vertical: compact ? 4 : 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? kind.color.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? kind.color
                                : canBuy
                                    ? Colors.amberAccent
                                    : Colors.white24,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Opacity(
                          opacity: unlocked || canBuy ? 1 : 0.45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    hotkey,
                                    style: TextStyle(
                                      color: kind.color.withValues(alpha: 0.85),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    unlocked
                                        ? Icons.person
                                        : canBuy
                                            ? Icons.lock_open
                                            : Icons.lock,
                                    size: 14,
                                    color: kind.color,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    kind.label,
                                    style: TextStyle(
                                      color: kind.color,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                unlocked
                                    ? 'L${engine.classLevel(kind)} · ${engine.playerClass == kind ? engine.maxHealth : (kind.maxHealth * SurvivalUpgrades.classHealthMult(engine.classLevel(kind))).round()} HP · ${(kind.moveSpeed * SurvivalUpgrades.classSpeedMult(engine.classLevel(kind))).toStringAsFixed(2)} spd'
                                    : '\$${kind.moneyCost} + ${kind.killCost} kills',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                              if (!compact) ...[
                                SizedBox(
                                  width: 168,
                                  child: Text(
                                    kind.description,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 9,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: SizedBox(
                                    width: 168,
                                    child: Text(
                                      '${kind.abilityName}: ${kind.abilityDescription}',
                                      style: TextStyle(
                                        color: Colors.lightGreenAccent
                                            .withValues(alpha: unlocked ? 0.85 : 0.55),
                                        fontSize: 9,
                                        height: 1.25,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: SizedBox(
                                    width: 168,
                                    child: Text(
                                      'Class L5: ${SurvivalUpgrades.classMasteryName(kind)} — ${SurvivalUpgrades.classMasteryBlurb(kind)}',
                                      style: TextStyle(
                                        color: const Color(0xFFFFD54F)
                                            .withValues(alpha: unlocked ? 0.9 : 0.55),
                                        fontSize: 8.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: SizedBox(
                                    width: 168,
                                    child: Text(
                                      'Ability L5: ${SurvivalUpgrades.abilityMasteryName(kind)} — ${SurvivalUpgrades.abilityMasteryBlurb(kind)}',
                                      style: TextStyle(
                                        color: Colors.lightGreenAccent
                                            .withValues(alpha: unlocked ? 0.8 : 0.5),
                                        fontSize: 8.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (unlocked) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: InkWell(
                                    onTap: () {
                                      if (engine.unlockedAbilities
                                          .contains(kind)) {
                                        if (engine.playerClass == kind) {
                                          engine.activateAbility();
                                        } else {
                                          engine.selectClass(kind);
                                        }
                                      } else {
                                        engine.unlockAbility(kind);
                                      }
                                    },
                                    child: Text(
                                      engine.unlockedAbilities.contains(kind)
                                          ? (SurvivalUpgrades.isMastered(
                                                  engine.abilityLevel(kind))
                                              ? 'F · ${kind.abilityName} MAX · ${SurvivalUpgrades.abilityMasteryBlurb(kind)}'
                                              : 'F · ${kind.abilityName} L${engine.abilityLevel(kind)}')
                                          : 'Unlock ${kind.abilityName}: \$${kind.abilityMoneyCost} + ${kind.abilityKillCost}k',
                                      style: TextStyle(
                                        color: engine.unlockedAbilities
                                                .contains(kind)
                                            ? Colors.lightGreenAccent
                                            : engine.canUnlockAbility(kind)
                                                ? Colors.amberAccent
                                                : Colors.white38,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _upgradeChip(
                                      label: engine.classLevel(kind) >=
                                              SurvivalUpgrades.maxLevel
                                          ? 'MAX · ${SurvivalUpgrades.classMasteryName(kind)}'
                                          : 'CLASS +\$${SurvivalUpgrades.classMoneyCost(kind, engine.classLevel(kind))}/${SurvivalUpgrades.classKillCost(kind, engine.classLevel(kind))}k',
                                      enabled: engine.canUpgradeClass(kind),
                                      onTap: () => engine.upgradeClass(kind),
                                    ),
                                    if (engine.unlockedAbilities.contains(kind))
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: _upgradeChip(
                                          label: engine.abilityLevel(kind) >=
                                                  SurvivalUpgrades.maxLevel
                                              ? 'MAX · ${SurvivalUpgrades.abilityMasteryName(kind)}'
                                              : 'ABL +\$${SurvivalUpgrades.abilityMoneyCost(kind, engine.abilityLevel(kind))}/${SurvivalUpgrades.abilityKillCost(kind, engine.abilityLevel(kind))}k',
                                          enabled:
                                              engine.canUpgradeAbility(kind),
                                          onTap: () =>
                                              engine.upgradeAbility(kind),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _upgradeChip({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: enabled
              ? Colors.amberAccent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? Colors.amberAccent : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.amberAccent : Colors.white38,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  /// Maps mouse-wheel / trackpad scroll onto [controller] so horizontal bars
  /// respond to the usual vertical wheel gesture.
  Widget _wheelScrollable({
    required ScrollController controller,
    required Axis axis,
    required Widget child,
  }) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) return;
        if (!controller.hasClients) return;
        final pos = controller.position;
        final raw = axis == Axis.horizontal
            ? (signal.scrollDelta.dx.abs() > signal.scrollDelta.dy.abs()
                ? signal.scrollDelta.dx
                : signal.scrollDelta.dy)
            : signal.scrollDelta.dy;
        final next = (pos.pixels + raw)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((next - pos.pixels).abs() > 0.01) {
          controller.jumpTo(next);
        }
      },
      child: child,
    );
  }

  Widget _weaponUpgradePips(int level, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(SurvivalUpgrades.maxLevel, (i) {
        final filled = i < level;
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: filled ? color : Colors.white24,
              width: 1,
            ),
            boxShadow: filled
                ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 3)]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildEquippedUpgradeRow() {
    final gun = engine.weapon;
    final gunLevel = engine.weaponLevel(gun);
    final gunMax = gunLevel >= SurvivalUpgrades.maxLevel;
    final gunReady = engine.canUpgradeWeapon(gun);
    final gunCost = gunMax
        ? 'MAX'
        : '+\$${SurvivalUpgrades.weaponMoneyCost(gun, gunLevel)}/'
            '${SurvivalUpgrades.weaponKillCost(gun, gunLevel)}k';

    final cls = engine.playerClass;
    final classLevel = engine.classLevel(cls);
    final classMax = classLevel >= SurvivalUpgrades.maxLevel;
    final classReady = engine.canUpgradeClass(cls);
    final classCost = classMax
        ? 'MAX'
        : '+\$${SurvivalUpgrades.classMoneyCost(cls, classLevel)}/'
            '${SurvivalUpgrades.classKillCost(cls, classLevel)}k';

    final ablUnlocked = engine.unlockedAbilities.contains(cls);
    final ablLevel = engine.abilityLevel(cls);
    final ablMax = ablUnlocked && ablLevel >= SurvivalUpgrades.maxLevel;
    final ablReady = ablUnlocked
        ? engine.canUpgradeAbility(cls)
        : engine.canUnlockAbility(cls);
    final ablCost = !ablUnlocked
        ? 'UNLOCK \$${cls.abilityMoneyCost}/${cls.abilityKillCost}k'
        : ablMax
            ? 'MAX'
            : '+\$${SurvivalUpgrades.abilityMoneyCost(cls, ablLevel)}/'
                '${SurvivalUpgrades.abilityKillCost(cls, ablLevel)}k';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          _equippedUpgradeChip(
            keyHint: _bindLabel(GameAction.upgradeWeapon),
            title: 'GUN',
            detail: gunCost,
            color: gun.rarity.color,
            enabled: gunReady,
            onTap: engine.tryUpgradeEquippedWeapon,
          ),
          _equippedUpgradeChip(
            keyHint: _bindLabel(GameAction.upgradeClass),
            title: 'CLASS',
            detail: classCost,
            color: cls.color,
            enabled: classReady,
            onTap: engine.tryUpgradeEquippedClass,
          ),
          _equippedUpgradeChip(
            keyHint: _bindLabel(GameAction.upgradeAbility),
            title: 'ABL',
            detail: ablCost,
            color: Colors.lightGreenAccent,
            enabled: ablReady,
            onTap: engine.tryUpgradeEquippedAbility,
          ),
        ],
      ),
    );
  }

  Widget _equippedUpgradeChip({
    required String keyHint,
    required String title,
    required String detail,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? color.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? color : Colors.white24,
              width: enabled ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                keyHint,
                style: TextStyle(
                  color: enabled ? color : Colors.white38,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                detail,
                style: TextStyle(
                  color: enabled
                      ? Colors.amberAccent
                      : Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeaponBar() {
    final unlocked = engine.unlockedSorted;
    final compact = _compact;
    _scheduleWeaponBarScroll(engine.weapon);
    return Positioned(
      left: compact ? 6 : 12,
      right: compact ? 6 : 12,
      bottom: _weaponBarBottom,
      child: Transform.scale(
        alignment: Alignment.bottomCenter,
        scale: _hudScale,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: Container(
          constraints: BoxConstraints(maxWidth: compact ? 640 : 920),
          padding: EdgeInsets.all(compact ? 4 : 6),
          decoration: BoxDecoration(
            color: const Color(0xE3111820),
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            border: Border.all(color: Colors.white24),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEquippedUpgradeRow(),
              if (!compact)
                Padding(
                padding: const EdgeInsets.only(bottom: 4, top: 2),
                child: Column(
                  children: [
                    Text(
                      '${engine.weapon.rarity.label} ${engine.weapon.label}'
                      '${engine.weaponLevel(engine.weapon) > 0 ? '  +${engine.weaponLevel(engine.weapon)}' : ''}'
                      '  ·  ${(engine.effectiveWeaponDamage / math.max(0.05, engine.effectiveWeaponCooldown)).round()} DPS'
                      '  ·  ${engine.weapon.description}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            engine.weapon.rarity.color.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Special: ${engine.weapon.specialAbility}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.amberAccent.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SurvivalUpgrades.isMastered(
                              engine.weaponLevel(engine.weapon))
                          ? 'Mastery: ${SurvivalUpgrades.weaponMasteryName(engine.weapon)} — ${SurvivalUpgrades.weaponMasteryBlurb(engine.weapon)}'
                          : 'L5 Mastery: ${SurvivalUpgrades.weaponMasteryName(engine.weapon)} — ${SurvivalUpgrades.weaponMasteryBlurb(engine.weapon)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFFFD54F).withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (engine.abilityUnlocked) ...[
                      const SizedBox(height: 2),
                      Text(
                        SurvivalUpgrades.isMastered(
                                engine.abilityLevel(engine.playerClass))
                            ? '${engine.playerClass.abilityName}: ${engine.playerClass.abilityDescription} · Mastery: ${SurvivalUpgrades.abilityMasteryBlurb(engine.playerClass)}'
                            : '${engine.playerClass.abilityName}: ${engine.playerClass.abilityDescription}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              Colors.lightGreenAccent.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _wheelScrollable(
                controller: _weaponBarScroll,
                axis: Axis.horizontal,
                child: SingleChildScrollView(
                controller: _weaponBarScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...unlocked.map((kind) {
                      final selected = engine.weapon == kind;
                      final level = engine.weaponLevel(kind);
                      final dps = (kind.damage *
                              SurvivalUpgrades.weaponDamageMult(level) /
                              math.max(
                                  0.05,
                                  kind.cooldown *
                                      SurvivalUpgrades.weaponCooldownMult(
                                          level)))
                          .round();
                      final moneyCost =
                          SurvivalUpgrades.weaponMoneyCost(kind, level);
                      final killCost =
                          SurvivalUpgrades.weaponKillCost(kind, level);
                      final tileKey = _weaponTileKeys.putIfAbsent(
                        kind,
                        GlobalKey.new,
                      );
                      return Padding(
                        key: tileKey,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: compact ? 88 : 124,
                          padding: EdgeInsets.symmetric(
                              vertical: compact ? 4 : 7, horizontal: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? kind.color.withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? kind.color
                                  : kind.rarity.color.withValues(alpha: 0.35),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => engine.equip(kind),
                                borderRadius: BorderRadius.circular(8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          _weaponIcon(kind),
                                          color: kind.color,
                                          size: compact ? 18 : 22,
                                        ),
                                        if (level > 0)
                                          Positioned(
                                            right: -10,
                                            top: -6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.amberAccent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '+$level',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    _weaponUpgradePips(level, kind.rarity.color),
                                    const SizedBox(height: 3),
                                    Text(
                                      kind.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${kind.rarity.label} · $dps DPS',
                                      style: TextStyle(
                                        color: kind.rarity.color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      engine.weaponDropOddsLabel(kind),
                                      style: TextStyle(
                                        color: Colors.lightBlueAccent
                                            .withValues(alpha: 0.95),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        kind.description,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                          fontSize: 8.5,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        kind.specialAbility,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.amberAccent
                                              .withValues(alpha: 0.8),
                                          fontSize: 8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${SurvivalUpgrades.weaponMasteryName(kind)}: ${SurvivalUpgrades.weaponMasteryBlurb(kind)}',
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFFD54F)
                                              .withValues(alpha: 0.85),
                                          fontSize: 8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        SurvivalUpgrades.weaponMasteryName(kind),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFFD54F)
                                              .withValues(alpha: 0.85),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              _upgradeChip(
                                label: level >= SurvivalUpgrades.maxLevel
                                    ? 'MAX · ${SurvivalUpgrades.weaponMasteryName(kind)}'
                                    : 'UPGRADE \$$moneyCost · ${killCost}k',
                                enabled: engine.canUpgradeWeapon(kind),
                                onTap: () => engine.upgradeWeapon(kind),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ...WeaponKind.values
                        .where((k) => !engine.unlockedWeapons.contains(k))
                        .map(
                          (kind) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Container(
                              width: compact ? 78 : 112,
                              padding: EdgeInsets.symmetric(
                                  vertical: compact ? 4 : 7, horizontal: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      kind.rarity.color.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Opacity(
                                opacity: 0.45,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock,
                                        color: kind.rarity.color,
                                        size: compact ? 16 : 20),
                                    const SizedBox(height: 2),
                                    Text(
                                      kind.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${kind.rarity.label} · ${kind.dpsRounded} DPS',
                                      style: TextStyle(
                                        color: kind.rarity.color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      engine.weaponDropOddsLabel(kind),
                                      style: TextStyle(
                                        color: Colors.lightBlueAccent
                                            .withValues(alpha: 0.95),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        kind.description,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              Colors.white.withValues(alpha: 0.5),
                                          fontSize: 8.5,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        kind.specialAbility,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.amberAccent
                                              .withValues(alpha: 0.55),
                                          fontSize: 8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${SurvivalUpgrades.weaponMasteryName(kind)}: ${SurvivalUpgrades.weaponMasteryBlurb(kind)}',
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFFD54F)
                                              .withValues(alpha: 0.7),
                                          fontSize: 8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        SurvivalUpgrades.weaponMasteryName(kind),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFFD54F)
                                              .withValues(alpha: 0.7),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _scheduleWeaponBarScroll(WeaponKind weapon) {
    if (_weaponBarScrollTarget == weapon) return;
    _weaponBarScrollTarget = weapon;
    // Wait two frames so the weapon tile has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _weaponBarScrollTarget != weapon) return;
        _scrollWeaponBarToEquipped(weapon);
      });
    });
  }

  void _scrollWeaponBarToEquipped(WeaponKind weapon) {
    final ctx = _weaponTileKeys[weapon]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!_weaponBarScroll.hasClients) return;
    final ordered = engine.unlockedSorted;
    final index = ordered.indexOf(weapon);
    if (index < 0) return;
    const itemExtent = 128.0;
    final viewport = _weaponBarScroll.position.viewportDimension;
    final target = index * itemExtent + itemExtent / 2 - viewport / 2;
    _weaponBarScroll.animateTo(
      target.clamp(0.0, _weaponBarScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  IconData _weaponIcon(WeaponKind kind) => switch (kind.symbol) {
        WeaponSymbol.sidearm => Icons.ads_click,
        WeaponSymbol.revolver => Icons.adjust,
        WeaponSymbol.smg => Icons.graphic_eq,
        WeaponSymbol.machinePistol => Icons.touch_app,
        WeaponSymbol.rifle => Icons.my_location,
        WeaponSymbol.shotgun => Icons.flash_on,
        WeaponSymbol.burst => Icons.more_horiz,
        WeaponSymbol.marksman => Icons.center_focus_strong,
        WeaponSymbol.crossbow => Icons.arrow_forward,
        WeaponSymbol.flamer => Icons.local_fire_department,
        WeaponSymbol.cryo => Icons.ac_unit,
        WeaponSymbol.toxin => Icons.science,
        WeaponSymbol.minigun => Icons.blur_circular,
        WeaponSymbol.rail => Icons.bolt,
        WeaponSymbol.plasma => Icons.bubble_chart,
        WeaponSymbol.launcher => Icons.sports_baseball,
        WeaponSymbol.beam => Icons.wb_sunny,
        WeaponSymbol.thunder => Icons.thunderstorm,
        WeaponSymbol.voidCore => Icons.nightlight_round,
        WeaponSymbol.star => Icons.auto_awesome,
      };

  Widget _buildMobileControls() {
    final compact = _compact;
    final stick = compact ? 92.0 : 118.0;
    final sideBtn = compact ? 42.0 : 52.0;
    final fireBtn = compact ? 56.0 : 68.0;
    final gap = compact ? 7.0 : 10.0;
    return Positioned(
      left: _controlsSideInset,
      right: _controlsSideInset,
      bottom: _controlsBottom,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.scale(
            alignment: Alignment.bottomLeft,
            scale: _ctrlScale,
            child: _VirtualJoystick(
              size: stick,
              onChanged: _setJoystick,
            ),
          ),
          const Spacer(),
          Transform.scale(
            alignment: Alignment.bottomRight,
            scale: _ctrlScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HoldButton(
                  icon: Icons.flash_on,
                  size: sideBtn,
                  color: engine.abilityReady
                      ? Colors.lightGreenAccent
                      : Colors.cyanAccent,
                  onHold: (held) {
                    if (held) engine.activateAbility();
                  },
                ),
                SizedBox(height: gap),
                _HoldButton(
                  icon: Icons.replay,
                  size: sideBtn,
                  color: Colors.amberAccent,
                  onHold: (held) {
                    if (held) engine.reload();
                  },
                ),
                SizedBox(height: gap),
                _HoldButton(
                  icon: Icons.gps_fixed,
                  size: fireBtn,
                  color: Colors.redAccent,
                  onHold: (held) {
                    if (held) engine.aimAtNearest();
                    engine.setFiring(held);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadEndingCutscene() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        alignment: Alignment.center,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0C10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFFF5252).withValues(alpha: 0.8),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD50000).withValues(alpha: 0.32),
                blurRadius: 40,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'THE BAD ENDING',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFF8A80),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Only the Necromancer and his thralls remain.\n'
                'Two seconds of quiet…\n'
                'then the ritual completes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'He ascends into a true boss — every boss and '
                'mini-boss answers his call, and the spawning never stops.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFAB91).withValues(alpha: 0.95),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  setState(() {
                    engine.resolveBadEnding();
                  });
                  _focusNode.requestFocus();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'FACE THE BAD ENDING',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    final compact = _compact;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        alignment: Alignment.center,
        child: Container(
          width: compact ? 420 : 520,
          constraints: BoxConstraints(
            maxWidth: compact ? 460 : 560,
            maxHeight: compact ? 520 : 640,
          ),
          margin: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 28,
            compact ? 16 : 26,
            compact ? 16 : 28,
            compact ? 14 : 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF111820),
            borderRadius: BorderRadius.circular(compact ? 16 : 22),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.65),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withValues(alpha: 0.18),
                blurRadius: 36,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.sports_esports,
                      color: Colors.cyanAccent, size: compact ? 24 : 32),
                  SizedBox(width: compact ? 8 : 12),
                  Text(
                    'HOW TO PLAY',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: compact ? 20 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _introLine(
                        Icons.keyboard,
                        'Move',
                        '${_bindLabel(GameAction.moveLeft)}'
                        '${_bindLabel(GameAction.moveUp)}'
                        '${_bindLabel(GameAction.moveDown)}'
                        '${_bindLabel(GameAction.moveRight)} '
                        'or arrows · touch joystick',
                      ),
                      _introLine(
                        Icons.ads_click,
                        'Aim & shoot',
                        'Mouse aim · left click / ${_bindLabel(GameAction.fire)} · hold fire on mobile',
                      ),
                      _introLine(
                        Icons.flash_on,
                        'Ability',
                        '${_bindLabel(GameAction.ability)} or right-click · unlock per class, then press again to cast',
                      ),
                      _introLine(
                        Icons.replay,
                        'Reload',
                        '${_bindLabel(GameAction.reload)} · yellow reload button on mobile',
                      ),
                      _introLine(
                        Icons.swap_horiz,
                        'Weapons',
                        '${_bindLabel(GameAction.weaponPrev)} / ${_bindLabel(GameAction.weaponNext)} cycle · tap a gun in the bar',
                      ),
                      _introLine(
                        Icons.upgrade,
                        'Quick upgrade',
                        '${_bindLabel(GameAction.upgradeWeapon)} gun · '
                        '${_bindLabel(GameAction.upgradeClass)} class · '
                        '${_bindLabel(GameAction.upgradeAbility)} ability — chips above the gun bar also work',
                      ),
                      _introLine(
                        Icons.groups,
                        'Classes',
                        'Hotkeys 1–9 / 0 / - · ${_bindLabel(GameAction.cycleClass)} cycles unlocked · '
                        'Reaper Soul Bar fills from damage and drains over time — full bars heal a flat amount by Reaper level (can overheal); Soul Scythe is a big melee cleave',
                      ),
                      _introLine(
                        Icons.settings,
                        'Settings',
                        '${_bindLabel(GameAction.pause)} pause · remappable keybinds, UI scale, and auto-equip live in Settings',
                      ),
                      _introLine(
                        Icons.favorite,
                        'Boss bars',
                        'Every living mini-boss and boss shows its own HP bar under the HUD',
                      ),
                      _introLine(
                        Icons.vpn_key,
                        'Loot',
                        'Keys from mini-bosses & bosses · chests in houses · crates drop cash, HP, and guns',
                      ),
                      _introLine(
                        Icons.warning_amber,
                        'Waves',
                        'Mini-bosses every 5 · Blazeburst from wave 15 · Citadel / bosses every 10 · Shadow Ronin every 20',
                      ),
                      _introLine(
                        Icons.emoji_events,
                        'Leaderboard',
                        'Top 50 runs get ranks (Apex, Warlord, Champion…) · enter a name when you qualify',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Close this when you\'re ready — the run starts immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _showIntro = false;
                    engine.paused = false;
                  });
                  _focusNode.requestFocus();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'GOT IT',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _bindLabel(GameAction action) =>
      KeybindSettings.labelForKey(_binds.keyFor(action));

  Widget _introLine(IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.cyanAccent.withValues(alpha: 0.9), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveBanner() {
    return Positioned(
      left: 0,
      right: 0,
      top: 120,
      child: IgnorePointer(
        child: Column(
          children: [
            Text(
              'WAVE ${engine.wave}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: [Shadow(color: Colors.redAccent, blurRadius: 18)],
              ),
            ),
            const Text(
              'THE HORDE IS COMING',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotification() {
    return Positioned(
      left: 0,
      right: 0,
      top: 86,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Colors.amberAccent.withValues(alpha: 0.65)),
          ),
          child: Text(
            engine.notification,
            style: const TextStyle(
              color: Colors.amberAccent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: const Color(0xFF111820),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.65),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withValues(alpha: 0.15),
                blurRadius: 40,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.pause_circle_filled,
                color: Colors.cyanAccent,
                size: 58,
              ),
              const SizedBox(height: 13),
              const Text(
                'PAUSED',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Take a breath. The horde will wait.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 23),
              FilledButton(
                onPressed: () {
                  setState(() => _showSettings = false);
                  engine.togglePause();
                  _focusNode.requestFocus();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 15),
                ),
                child: const Text(
                  'RESUME',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text(
                  'SETTINGS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsOverlay() {
    final compact = _compact;
    final density = UiLayoutSettings.densityFor(MediaQuery.sizeOf(context));
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          width: compact ? double.infinity : 420,
          constraints: BoxConstraints(
            maxWidth: compact ? 520 : 420,
            maxHeight: compact ? MediaQuery.sizeOf(context).height * 0.92 : 700,
          ),
          margin: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 0,
            vertical: compact ? 8 : 0,
          ),
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 22,
            compact ? 14 : 20,
            compact ? 14 : 22,
            compact ? 12 : 18,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF111820).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(compact ? 16 : 22),
            border: Border.all(
              color: Colors.amberAccent.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, color: Colors.amberAccent),
                  SizedBox(width: 10),
                  Text(
                    'UI LAYOUT',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  compact
                      ? 'Phone layout — drag sliders to resize and move HUD / sticks. Saves automatically.'
                      : 'Adjust size and position. Changes save automatically.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _settingsSlider(
                        label: 'HUD / menus size',
                        value: _ui.uiScale,
                        min: UiLayoutSettings.uiScaleMin,
                        max: UiLayoutSettings.uiScaleMax,
                        display: density < 1
                            ? '${(_ui.uiScale * 100).round()}% → ${(_hudScale * 100).round()}%'
                            : '${(_ui.uiScale * 100).round()}%',
                        onChanged: (v) => setState(() => _ui.uiScale = v),
                      ),
                      _settingsSlider(
                        label: 'Touch controls size',
                        value: _ui.controlsScale,
                        min: UiLayoutSettings.controlsScaleMin,
                        max: UiLayoutSettings.controlsScaleMax,
                        display: compact
                            ? '${(_ui.controlsScale * 100).round()}% → ${(_ctrlScale * 100).round()}%'
                            : '${(_ui.controlsScale * 100).round()}%',
                        onChanged: (v) =>
                            setState(() => _ui.controlsScale = v),
                      ),
                      _settingsSlider(
                        label: 'Top HUD position',
                        value: _ui.hudTop,
                        min: 0,
                        max: 72,
                        display: '${_ui.hudTop.round()}',
                        onChanged: (v) => setState(() => _ui.hudTop = v),
                      ),
                      _settingsSlider(
                        label: 'Class bar position',
                        value: _ui.classBarTop,
                        min: 20,
                        max: 160,
                        display: '${_ui.classBarTop.round()}',
                        onChanged: (v) => setState(() => _ui.classBarTop = v),
                      ),
                      _settingsSlider(
                        label: 'Weapon bar height',
                        value: _ui.weaponBarBottom,
                        min: 0,
                        max: 80,
                        display: '${_ui.weaponBarBottom.round()}',
                        onChanged: (v) =>
                            setState(() => _ui.weaponBarBottom = v),
                      ),
                      _settingsSlider(
                        label: 'Controls height',
                        value: _ui.controlsBottom,
                        min: 40,
                        max: 280,
                        display: '${_ui.controlsBottom.round()}',
                        onChanged: (v) =>
                            setState(() => _ui.controlsBottom = v),
                      ),
                      _settingsSlider(
                        label: 'Controls side inset',
                        value: _ui.controlsSideInset,
                        min: 4,
                        max: 48,
                        display: '${_ui.controlsSideInset.round()}',
                        onChanged: (v) =>
                            setState(() => _ui.controlsSideInset = v),
                      ),
                      const SizedBox(height: 8),
                      _settingsSlider(
                        label: 'Music volume',
                        value: _ui.musicVolume,
                        min: 0,
                        max: 1,
                        display: '${(_ui.musicVolume * 100).round()}%',
                        onChanged: (v) {
                          setState(() {
                            _ui.musicVolume = v;
                            _ui.musicEnabled = v > 0.001;
                            _syncAudioSettings();
                          });
                        },
                      ),
                      _settingsSlider(
                        label: 'Sound effects volume',
                        value: _ui.sfxVolume,
                        min: 0,
                        max: 1,
                        display: '${(_ui.sfxVolume * 100).round()}%',
                        onChanged: (v) {
                          setState(() {
                            _ui.sfxVolume = v;
                            _syncAudioSettings();
                          });
                        },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Auto-equip new weapons',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _ui.autoEquipNewWeapons
                              ? 'Loot instantly switches your gun'
                              : 'Loot unlocks guns without switching',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        value: _ui.autoEquipNewWeapons,
                        activeColor: Colors.amberAccent,
                        onChanged: (v) {
                          setState(() {
                            _ui.autoEquipNewWeapons = v;
                            _syncGameplaySettings();
                          });
                          _persistUiSettings();
                        },
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'KEYBINDS',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tap a bind, then press a key. Conflicts swap. '
                          'Arrows always move. Class slots stay on 1–0 / -.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...GameAction.values.map(_buildKeybindRow),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetUiSettings,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      child: const Text('RESET'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _closeSettings,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text(
                        'BACK',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeybindRow(GameAction action) {
    final listening = _rebindingAction == action;
    final keyLabel = KeybindSettings.labelForKey(_binds.keyFor(action));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: listening
            ? Colors.amberAccent.withValues(alpha: 0.16)
            : const Color(0xFF1A2430),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (listening) {
              setState(() => _rebindingAction = null);
            } else {
              _startRebind(action);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    action.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: listening
                          ? Colors.amberAccent.withValues(alpha: 0.25)
                          : Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: listening
                            ? Colors.amberAccent
                            : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      listening ? 'PRESS KEY…' : keyLabel,
                      style: TextStyle(
                        color: listening
                            ? Colors.amberAccent
                            : Colors.white70,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: listening ? 0.6 : 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.amberAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.amberAccent,
              overlayColor: Colors.amberAccent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                onChanged(v);
                _persistUiSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    final needsName = engine.awaitingNameEntry;
    if (needsName) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !engine.awaitingNameEntry) return;
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        }
        if (!_nameFocus.hasFocus) {
          _nameFocus.requestFocus();
        }
      });
    }
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        alignment: Alignment.center,
        child: Container(
          width: 420,
          constraints: const BoxConstraints(maxHeight: 680),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111820),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.65), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dangerous, color: Colors.redAccent, size: 48),
              const SizedBox(height: 8),
              const Text(
                'OVERRUN',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Wave ${engine.wave}  •  ${engine.totalKills} kills  •  \$${engine.totalMoneyEarned} earned',
                style: const TextStyle(color: Colors.white70),
              ),
              if (needsName) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final pending = engine.pendingScore;
                    final place = pending == null
                        ? 1
                        : LeaderboardRanks.placeForScore(
                            pending.score,
                            engine.highScores,
                          );
                    final rank = LeaderboardRanks.titleForPlace(place);
                    final podium = LeaderboardRanks.isPodium(place);
                    return Column(
                      children: [
                        Text(
                          podium ? 'PODIUM FINISH' : 'NEW HIGH SCORE',
                          style: TextStyle(
                            color: _rankColor(place),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '#$place $rank · ${LeaderboardRanks.blurbForPlace(place)}',
                          style: TextStyle(
                            color: _rankColor(place).withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Focus(
                  onKeyEvent: (_, __) => KeyEventResult.ignored,
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    autofocus: true,
                    maxLength: HighScoreStore.maxNameLength,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    keyboardType: TextInputType.name,
                    enableSuggestions: false,
                    autocorrect: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: Colors.amberAccent,
                    decoration: InputDecoration(
                      counterStyle: const TextStyle(color: Colors.white38),
                      hintText: 'Enter your name',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A2430),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.amberAccent,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submitScoreName(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _nameController.clear();
                          _submitScoreName();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('SKIP'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _submitScoreName,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'SAVE SCORE',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'HIGH SCORES',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: engine.highScores.isEmpty
                    ? const Text('No scores yet',
                        style: TextStyle(color: Colors.white54))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: engine.highScores.length,
                        separatorBuilder: (_, __) => const Divider(height: 10),
                        itemBuilder: (context, index) {
                          final entry = engine.highScores[index];
                          final place = index + 1;
                          final rankTitle =
                              LeaderboardRanks.titleForPlace(place);
                          final rankColor = _rankColor(place);
                          final podium = LeaderboardRanks.isPodium(place);
                          final highRank = LeaderboardRanks.isHighRank(place);
                          final isYours = engine.isOwnLeaderboardEntry(entry);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isYours
                                  ? Colors.amberAccent.withValues(alpha: 0.18)
                                  : podium
                                      ? rankColor.withValues(alpha: 0.1)
                                      : highRank
                                          ? rankColor.withValues(alpha: 0.06)
                                          : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isYours
                                  ? Border.all(
                                      color: Colors.amberAccent
                                          .withValues(alpha: 0.85),
                                      width: 1.5,
                                    )
                                  : podium
                                      ? Border.all(
                                          color:
                                              rankColor.withValues(alpha: 0.45),
                                        )
                                      : highRank
                                          ? Border.all(
                                              color: rankColor.withValues(
                                                  alpha: 0.28),
                                            )
                                          : null,
                            ),
                            child: Row(
                              children: [
                                _rankBadge(
                                  place: place,
                                  color: isYours ? Colors.amberAccent : rankColor,
                                  podium: podium,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              entry.playerName,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isYours
                                                    ? Colors.amberAccent
                                                    : Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            rankTitle.toUpperCase(),
                                            style: TextStyle(
                                              color: isYours
                                                  ? Colors.amberAccent
                                                  : rankColor,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 10,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'W${entry.wave}  ${entry.kills} kills  \$${entry.money}  ${entry.className}',
                                        style: TextStyle(
                                          color: isYours
                                              ? Colors.amberAccent
                                                  .withValues(alpha: 0.85)
                                              : Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isYours)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Text(
                                      'YOU',
                                      style: TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                Text(
                                  '${entry.score}',
                                  style: TextStyle(
                                    color: isYours
                                        ? Colors.amberAccent
                                        : podium
                                            ? rankColor
                                            : Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: needsName
                    ? null
                    : () {
                        _nameController.clear();
                        engine.start();
                        engine.paused = true;
                        setState(() {
                          _showIntro = true;
                          _showSettings = false;
                        });
                        _focusNode.requestFocus();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      Colors.redAccent.withValues(alpha: 0.25),
                  disabledForegroundColor: Colors.white38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                  ),
                child: Text(
                  needsName ? 'SAVE YOUR NAME FIRST' : 'TRY AGAIN',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _rankColor(int place) => switch (place) {
        1 => const Color(0xFFFFD54F), // gold
        2 => const Color(0xFFCFD8DC), // silver
        3 => const Color(0xFFFFAB91), // bronze
        4 || 5 => const Color(0xFFE040FB),
        6 || 7 || 8 => const Color(0xFF7C4DFF),
        9 || 10 => const Color(0xFFCE93D8),
        _ when place <= 15 => const Color(0xFF80CBC4),
        _ when place <= 20 => const Color(0xFF81D4FA),
        _ when place <= 30 => const Color(0xFFA5D6A7),
        _ when place <= 40 => const Color(0xFFFFCC80),
        _ => const Color(0xFF90A4AE),
      };

  Widget _rankBadge({
    required int place,
    required Color color,
    required bool podium,
  }) {
    final icon = switch (place) {
      1 => Icons.emoji_events,
      2 => Icons.military_tech,
      3 => Icons.workspace_premium,
      _ => null,
    };
    return SizedBox(
      width: podium ? 40 : 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, color: color, size: podium ? 18 : 16)
          else
            Text(
              '#$place',
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          if (podium)
            Text(
              '#$place',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submitScoreName() async {
    if (!engine.awaitingNameEntry) return;
    await engine.submitHighScoreName(_nameController.text);
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }
}

class _VirtualJoystick extends StatefulWidget {
  const _VirtualJoystick({
    required this.onChanged,
    this.size = 118,
  });

  final ValueChanged<Offset> onChanged;
  final double size;

  @override
  State<_VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<_VirtualJoystick> {
  Offset _knob = Offset.zero;

  double get _radius => widget.size * 0.5;
  double get _knobTravel => _radius * 0.58;
  double get _knobSize => widget.size * 0.38;

  void _updateFromLocal(Offset local) {
    final center = Offset(_radius, _radius);
    var delta = local - center;
    final max = _knobTravel;
    if (delta.distance > max) {
      delta = delta / delta.distance * max;
    }
    setState(() => _knob = delta);
    // Deadzone so tiny taps don't drift the player.
    final norm = delta.distance < max * 0.12
        ? Offset.zero
        : Offset(delta.dx / max, delta.dy / max);
    widget.onChanged(norm);
  }

  void _release() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final center = Offset(_radius, _radius);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _updateFromLocal(e.localPosition),
        onPointerMove: (e) => _updateFromLocal(e.localPosition),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: CustomPaint(
          painter: _JoystickPainter(
            knobOffset: _knob,
            knobSize: _knobSize,
            center: center,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knobOffset,
    required this.knobSize,
    required this.center,
  });

  final Offset knobOffset;
  final double knobSize;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final baseR = size.shortestSide * 0.5;
    // Base pad
    canvas.drawCircle(
      center,
      baseR,
      Paint()..color = const Color(0x99111820),
    );
    canvas.drawCircle(
      center,
      baseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.cyanAccent.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      center,
      baseR * 0.72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white24,
    );
    // Crosshair guides
    final guide = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1.2;
    canvas.drawLine(
      center + Offset(0, -baseR * 0.55),
      center + Offset(0, baseR * 0.55),
      guide,
    );
    canvas.drawLine(
      center + Offset(-baseR * 0.55, 0),
      center + Offset(baseR * 0.55, 0),
      guide,
    );

    final knobCenter = center + knobOffset;
    canvas.drawCircle(
      knobCenter,
      knobSize * 0.5 + 3,
      Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      knobCenter,
      knobSize * 0.5,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF4DD0E1), Color(0xFF1565C0)],
        ).createShader(
          Rect.fromCircle(center: knobCenter, radius: knobSize * 0.5),
        ),
    );
    canvas.drawCircle(
      knobCenter,
      knobSize * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.knobOffset != knobOffset;
  }
}

class _HoldButton extends StatelessWidget {
  const _HoldButton({
    required this.icon,
    required this.onHold,
    this.size = 43,
    this.color = Colors.white70,
  });

  final IconData icon;
  final ValueChanged<bool> onHold;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onHold(true),
      onPointerUp: (_) => onHold(false),
      onPointerCancel: (_) => onHold(false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x99111820),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.6)),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Icon(icon, color: color, size: size * 0.53),
      ),
    );
  }
}

class ArenaProjection {
  ArenaProjection(
    this.size,
    this.camera, {
    double zoom = 1,
  })  : scale = math.min(size.width, size.height) /
            (SurvivalEngine.arenaHalf * 0.55 / zoom.clamp(0.5, 2.5)),
        center = Offset(size.width / 2, size.height * 0.49);

  final Size size;
  final Offset camera;
  final double scale;
  final Offset center;

  Offset project(Offset world, [double height = 0]) {
    final relative = world - camera;
    return Offset(
      center.dx + (relative.dx - relative.dy) * scale * 0.55,
      center.dy +
          (relative.dx + relative.dy) * scale * 0.28 -
          height * scale * 0.55,
    );
  }

  Offset toWorld(Offset screen) {
    final a = (screen.dx - center.dx) / (scale * 0.55);
    final b = (screen.dy - center.dy) / (scale * 0.28);
    return camera + Offset((a + b) / 2, (b - a) / 2);
  }
}

class SurvivalPainter extends CustomPainter {
  SurvivalPainter(this.engine, this.projection) : super(repaint: engine);

  final SurvivalEngine engine;
  final ArenaProjection projection;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintArena(canvas);
    // Floors first so plazas/walls can layer over them correctly.
    _paintHouseFloors(canvas);
    _paintCorpses(canvas);
    _paintPoison(canvas);
    _paintStickyGoo(canvas);
    _paintFirePits(canvas);
    _paintLaserCannons(canvas);
    _paintSkyHazards(canvas, size);
    _paintEnemyTelegraphs(canvas);
    // Props, house walls/roofs, and actors share one depth sort.
    _paintDepthSortedWorld(canvas);
    _paintEnemyBolts(canvas);
    _paintTracers(canvas);
    _paintDamageFloaters(canvas);
    _paintBlastFlashes(canvas);
    _paintZombiePointers(canvas, size);
    _paintCrosshair(canvas);
  }

  static double _isoDepth(Offset world) => world.dx + world.dy;

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1528), Color(0xFF3A2A38), Color(0xFF1C1410)],
          stops: [0, 0.52, 1],
        ).createShader(Offset.zero & size),
    );
    final horizon = projection.center.dy - projection.scale * 0.37;
    // Warm dusk glow behind the rooftops.
    canvas.drawCircle(
      Offset(size.width * 0.5, horizon + 20),
      size.width * 0.42,
      Paint()
        ..color = const Color(0x33FF8A50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
    final sil = Paint()..color = const Color(0xFF120E14);
    for (var i = 0; i < 16; i++) {
      final slot = size.width / 15;
      final x = i * slot - 6;
      final baseH = 22.0 + ((i * 41) % 58);
      final body = Rect.fromLTWH(x, horizon - baseH, slot * 0.92, baseH);
      canvas.drawRect(body, sil);
      // Pitched roof triangle.
      final roof = Path()
        ..moveTo(body.left - 3, body.top)
        ..lineTo(body.center.dx, body.top - 12 - (i % 3) * 4)
        ..lineTo(body.right + 3, body.top)
        ..close();
      canvas.drawPath(roof, sil);
      // Church spire on a couple of slots.
      if (i == 4 || i == 11) {
        canvas.drawRect(
          Rect.fromLTWH(body.center.dx - 3, body.top - 36, 6, 36),
          sil,
        );
        canvas.drawPath(
          Path()
            ..moveTo(body.center.dx - 7, body.top - 36)
            ..lineTo(body.center.dx, body.top - 52)
            ..lineTo(body.center.dx + 7, body.top - 36)
            ..close(),
          sil,
        );
      }
      final windowPaint = Paint()
        ..color = i.isEven
            ? const Color(0x66FFB74D)
            : const Color(0x44FFCC80);
      for (double y = body.top + 8; y < body.bottom - 6; y += 11) {
        canvas.drawRect(Rect.fromLTWH(body.left + 6, y, 3.5, 4.5), windowPaint);
        canvas.drawRect(Rect.fromLTWH(body.right - 10, y, 3.5, 4.5), windowPaint);
      }
    }
    // Soft moon.
    canvas.drawCircle(
      Offset(size.width * 0.78, horizon - 118),
      28,
      Paint()
        ..color = const Color(0xFFD7CCC8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _paintArena(Canvas canvas) {
    const half = SurvivalEngine.arenaHalf;
    final corners = [
      projection.project(const Offset(-half, -half)),
      projection.project(const Offset(half, -half)),
      projection.project(const Offset(half, half)),
      projection.project(const Offset(-half, half)),
    ];
    final floor = Path()..addPolygon(corners, true);
    canvas.drawPath(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A322C), Color(0xFF241E1A), Color(0xFF1A1612)],
        ).createShader(floor.getBounds()),
    );

    // Cobble diamonds across the plaza.
    final cobble = Paint()
      ..color = const Color(0x224E453C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    const cobbleSteps = 20;
    for (var i = -cobbleSteps; i <= cobbleSteps; i++) {
      final value = half * i / cobbleSteps;
      canvas.drawLine(
        projection.project(Offset(value, -half)),
        projection.project(Offset(value, half)),
        cobble,
      );
      canvas.drawLine(
        projection.project(Offset(-half, value)),
        projection.project(Offset(half, value)),
        cobble,
      );
    }
    // Offset second grid for brick/cobble feel.
    final cobble2 = Paint()
      ..color = const Color(0x185D5346)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var i = -cobbleSteps; i <= cobbleSteps; i++) {
      final value = half * (i + 0.5) / cobbleSteps;
      canvas.drawLine(
        projection.project(Offset(value, -half)),
        projection.project(Offset(value, half)),
        cobble2,
      );
    }

    // Main cross streets through Old Town square.
    final road = Paint()
      ..color = const Color(0x55463C34)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final roadEdge = Paint()
      ..color = const Color(0x668D7B68)
      ..strokeWidth = 1.4;
    final roadCenter = Paint()
      ..color = const Color(0x33E0C9A6)
      ..strokeWidth = 1.2;
    for (final axis in [
      [const Offset(-half + 0.4, 0), const Offset(half - 0.4, 0)],
      [const Offset(0, -half + 0.4), const Offset(0, half - 0.4)],
    ]) {
      final a = projection.project(axis[0]);
      final b = projection.project(axis[1]);
      canvas.drawLine(a, b, road);
      canvas.drawLine(a, b, roadEdge);
      canvas.drawLine(a, b, roadCenter);
    }

    // Soft plaza stains / worn stones.
    final stain = Paint()..color = const Color(0x225D4037);
    for (final spot in const [
      Offset(-1.6, -0.8),
      Offset(2.1, 1.2),
      Offset(-2.4, 2.0),
      Offset(1.3, -2.2),
      Offset(0.4, 0.6),
      Offset(-0.7, 1.5),
    ]) {
      final c = projection.project(spot);
      canvas.drawOval(
        Rect.fromCenter(
          center: c,
          width: projection.scale * 0.55,
          height: projection.scale * 0.28,
        ),
        stain,
      );
    }

    // Market plazas around houses.
    for (final house in engine.houses) {
      final plaza = house.outer.inflate(0.35);
      final pts = [
        Offset(plaza.left, plaza.top),
        Offset(plaza.right, plaza.top),
        Offset(plaza.right, plaza.bottom),
        Offset(plaza.left, plaza.bottom),
      ].map(projection.project).toList();
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy)
        ..lineTo(pts[3].dx, pts[3].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0x334A4038));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x558D6E63),
      );
    }

    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF6D5A4A),
    );

    // Warm lantern-lit edge dashes.
    final hazard = Paint()
      ..color = const Color(0x55FFB74D)
      ..strokeWidth = 3;
    const steps = 16;
    for (var i = -steps + 1; i < steps; i += 2) {
      final a = half * i / steps;
      final b = half * (i + 1) / steps;
      canvas.drawLine(
        projection.project(Offset(a, -half)),
        projection.project(Offset(b, -half)),
        hazard,
      );
      canvas.drawLine(
        projection.project(Offset(a, half)),
        projection.project(Offset(b, half)),
        hazard,
      );
      canvas.drawLine(
        projection.project(Offset(-half, a)),
        projection.project(Offset(-half, b)),
        hazard,
      );
      canvas.drawLine(
        projection.project(Offset(half, a)),
        projection.project(Offset(half, b)),
        hazard,
      );
    }
  }

  void _paintDepthSortedWorld(Canvas canvas) {
    final items = <({double depth, int tie, void Function() paint})>[];
    var tie = 0;

    void add(double depth, void Function() paint) {
      items.add((depth: depth, tie: tie++, paint: paint));
    }

    for (final prop in engine.props) {
      final captured = prop;
      add(_isoDepth(captured.position), () => _paintProp(canvas, captured));
    }

    // Sort houses back→front so shared edges don't flicker.
    final houses = List<House>.from(engine.houses)
      ..sort((a, b) => _isoDepth(a.center).compareTo(_isoDepth(b.center)));
    for (final house in houses) {
      final rim = [
        Offset(house.outer.left, house.outer.top),
        Offset(house.outer.right, house.outer.top),
        Offset(house.outer.right, house.outer.bottom),
        Offset(house.outer.left, house.outer.bottom),
      ];
      final wallColor = switch (house.facade % 3) {
        0 => const Color(0xFF6D4C41),
        1 => const Color(0xFFBCAAA4),
        _ => const Color(0xFF8D5A4A),
      };
      final trimColor = switch (house.facade % 3) {
        0 => const Color(0xFF3E2723),
        1 => const Color(0xFF5D4037),
        _ => const Color(0xFF4E342E),
      };

      // Walls far→near by face midpoint.
      final faces = <({int side, double depth})>[];
      for (var i = 0; i < 4; i++) {
        final mid = Offset.lerp(rim[i], rim[(i + 1) % 4], 0.5)!;
        faces.add((side: i, depth: _isoDepth(mid)));
      }
      faces.sort((a, b) => a.depth.compareTo(b.depth));
      for (final face in faces) {
        final side = face.side;
        final depth = face.depth;
        if (side == house.doorSide) {
          add(depth, () {
            _paintHouseDoorWall(canvas, house, rim, wallColor, trimColor);
            _paintHouseDoorFrame(canvas, house, rim, trimColor);
          });
        } else {
          add(
            depth,
            () => _paintHouseWallFace(
              canvas,
              house,
              rim,
              side,
              wallColor,
              trimColor,
            ),
          );
        }
      }

      // Roof sits at the front eaves so units behind/inside draw under it.
      final roofDepth = [
        _isoDepth(rim[0]),
        _isoDepth(rim[1]),
        _isoDepth(rim[2]),
        _isoDepth(rim[3]),
      ].reduce(math.max);
      add(roofDepth + 0.02, () => _paintHouseRoof(canvas, house, rim));
    }

    for (final crate in engine.crates) {
      final captured = crate;
      add(
        _isoDepth(captured.position),
        () => _paintCrate(canvas, captured),
      );
    }
    for (final chest in engine.chests) {
      final captured = chest;
      add(
        _isoDepth(captured.position),
        () => _paintChest(canvas, captured),
      );
    }
    for (final key in engine.keyDrops) {
      final captured = key;
      add(
        _isoDepth(captured.position),
        () => _paintKeyDrop(canvas, captured),
      );
    }
    for (final zombie in engine.zombies) {
      final captured = zombie;
      add(
        _isoDepth(captured.position),
        () => _paintZombie(canvas, captured),
      );
    }
    for (final ally in engine.gunAllies) {
      final captured = ally;
      add(
        _isoDepth(captured.position),
        () => _paintGunAlly(canvas, captured),
      );
    }
    add(_isoDepth(engine.player), () => _paintPlayer(canvas));

    items.sort((a, b) {
      final c = a.depth.compareTo(b.depth);
      return c != 0 ? c : a.tie.compareTo(b.tie);
    });
    for (final item in items) {
      item.paint();
    }
  }

  void _paintProp(Canvas canvas, SolidProp prop) {
    _paintShadow(canvas, prop.position, prop.radius * 1.6);
    final p = projection.project(prop.position);
    final r = prop.radius * projection.scale;
    switch (prop.kind) {
      case PropKind.rock:
        canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 2.2, height: r * 1.3),
          Paint()..color = const Color(0xFF5D554C),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: p + Offset(0, -r * 0.35),
            width: r * 1.6,
            height: r * 1.1,
          ),
          Paint()..color = const Color(0xFF8D8174),
        );
      case PropKind.crateStack:
        final box = Rect.fromCenter(
          center: p + Offset(0, -r * 0.4),
          width: r * 1.7,
          height: r * 1.4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()..color = const Color(0xFF8D6E63),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF4E342E),
        );
        canvas.drawLine(
          box.topCenter,
          box.bottomCenter,
          Paint()
            ..color = const Color(0xFF5D4037)
            ..strokeWidth = 1.5,
        );
      case PropKind.rubble:
        canvas.drawCircle(
            p, r * 0.7, Paint()..color = const Color(0xFF6D4C41));
        canvas.drawCircle(
          p + Offset(r * 0.45, -r * 0.2),
          r * 0.45,
          Paint()..color = const Color(0xFF795548),
        );
      case PropKind.pillar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: p + Offset(0, -r * 1.1),
              width: r * 1.1,
              height: r * 2.6,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0xFF8D8578),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: p + Offset(0, -r * 2.2),
              width: r * 1.35,
              height: r * 0.35,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = const Color(0xFFBCAAA4),
        );
      case PropKind.barrel:
        final body = Rect.fromCenter(
          center: p + Offset(0, -r * 0.55),
          width: r * 1.55,
          height: r * 1.85,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(r * 0.35)),
          Paint()..color = const Color(0xFF6D4C41),
        );
        canvas.drawLine(
          Offset(body.left + 2, body.center.dy - r * 0.25),
          Offset(body.right - 2, body.center.dy - r * 0.25),
          Paint()
            ..color = const Color(0xFFB0BEC5)
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(body.left + 2, body.center.dy + r * 0.3),
          Offset(body.right - 2, body.center.dy + r * 0.3),
          Paint()
            ..color = const Color(0xFFB0BEC5)
            ..strokeWidth = 2,
        );
      case PropKind.lampPost:
        final base = p + Offset(0, -r * 0.2);
        final top = p + Offset(0, -r * 3.1);
        canvas.drawLine(
          base,
          top,
          Paint()
            ..color = const Color(0xFF37474F)
            ..strokeWidth = math.max(2.5, r * 0.28)
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          top,
          r * 0.55,
          Paint()
            ..color = const Color(0x66FFB74D)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
            top, r * 0.32, Paint()..color = const Color(0xFFFFE082));
        canvas.drawCircle(
          top,
          r * 0.16,
          Paint()..color = const Color(0xFFFFF8E1),
        );
      case PropKind.well:
        final rim = Rect.fromCenter(
          center: p + Offset(0, -r * 0.15),
          width: r * 2.2,
          height: r * 1.15,
        );
        canvas.drawOval(rim, Paint()..color = const Color(0xFF5D4037));
        canvas.drawOval(
          rim.deflate(r * 0.28),
          Paint()..color = const Color(0xFF263238),
        );
        canvas.drawLine(
          p + Offset(-r * 0.85, -r * 0.9),
          p + Offset(-r * 0.85, -r * 2.0),
          Paint()
            ..color = const Color(0xFF8D6E63)
            ..strokeWidth = 2.4,
        );
        canvas.drawLine(
          p + Offset(r * 0.85, -r * 0.9),
          p + Offset(r * 0.85, -r * 2.0),
          Paint()
            ..color = const Color(0xFF8D6E63)
            ..strokeWidth = 2.4,
        );
        canvas.drawLine(
          p + Offset(-r * 0.95, -r * 2.0),
          p + Offset(r * 0.95, -r * 2.0),
          Paint()
            ..color = const Color(0xFFA1887F)
            ..strokeWidth = 3,
        );
      case PropKind.cart:
        final bed = Rect.fromCenter(
          center: p + Offset(0, -r * 0.55),
          width: r * 2.4,
          height: r * 1.15,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bed, const Radius.circular(3)),
          Paint()..color = const Color(0xFF795548),
        );
        canvas.drawCircle(
          p + Offset(-r * 0.7, r * 0.15),
          r * 0.38,
          Paint()..color = const Color(0xFF37474F),
        );
        canvas.drawCircle(
          p + Offset(r * 0.7, r * 0.15),
          r * 0.38,
          Paint()..color = const Color(0xFF37474F),
        );
        canvas.drawLine(
          bed.topLeft + const Offset(4, 2),
          bed.topLeft + Offset(-r * 0.4, -r * 0.9),
          Paint()
            ..color = const Color(0xFF5D4037)
            ..strokeWidth = 2.2,
        );
    }
  }

  void _paintHouseFloors(Canvas canvas) {
    final houses = List<House>.from(engine.houses)
      ..sort((a, b) => _isoDepth(a.center).compareTo(_isoDepth(b.center)));
    for (final house in houses) {
      final outer = house.outer;
      final floorCorners = [
        Offset(outer.left, outer.top),
        Offset(outer.right, outer.top),
        Offset(outer.right, outer.bottom),
        Offset(outer.left, outer.bottom),
      ].map(projection.project).toList();
      final floor = Path()
        ..moveTo(floorCorners[0].dx, floorCorners[0].dy)
        ..lineTo(floorCorners[1].dx, floorCorners[1].dy)
        ..lineTo(floorCorners[2].dx, floorCorners[2].dy)
        ..lineTo(floorCorners[3].dx, floorCorners[3].dy)
        ..close();
      canvas.drawPath(floor, Paint()..color = const Color(0xFF3E2723));
      final board = Paint()
        ..color = const Color(0x335D4037)
        ..strokeWidth = 1;
      for (var t = 0.15; t < 0.95; t += 0.14) {
        final a = Offset(outer.left, outer.top + outer.height * t);
        final b = Offset(outer.right, outer.top + outer.height * t);
        canvas.drawLine(projection.project(a), projection.project(b), board);
      }
    }
  }

  void _paintHouseWallFace(
    Canvas canvas,
    House house,
    List<Offset> rim,
    int side,
    Color wallColor,
    Color trimColor, {
    Offset? from,
    Offset? to,
  }) {
    final aWorld = from ?? rim[side];
    final bWorld = to ?? rim[(side + 1) % 4];
    final a = projection.project(aWorld, 0.02);
    final b = projection.project(bWorld, 0.02);
    final aTop = projection.project(aWorld, 0.3);
    final bTop = projection.project(bWorld, 0.3);
    final wall = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(bTop.dx, bTop.dy)
      ..lineTo(aTop.dx, aTop.dy)
      ..close();
    canvas.drawPath(wall, Paint()..color = wallColor);
    canvas.drawPath(
      wall,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = trimColor,
    );

    final span = (bWorld - aWorld).distance;
    if (span < House.doorWidth * 0.55) return;

    final mid = Offset.lerp(aWorld, bWorld, 0.5)!;
    final winLow = projection.project(mid, 0.1);
    final winHigh = projection.project(mid, 0.22);
    final win = Rect.fromPoints(
      winLow + const Offset(-5, -2),
      winHigh + const Offset(5, 2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(1.5)),
      Paint()..color = const Color(0xAAFFCC80),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(1.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = trimColor,
    );
    if (house.facade % 3 == 0) {
      canvas.drawLine(
        aTop,
        b,
        Paint()
          ..color = trimColor.withValues(alpha: 0.55)
          ..strokeWidth = 1.6,
      );
    }
  }

  void _paintHouseDoorWall(
    Canvas canvas,
    House house,
    List<Offset> rim,
    Color wallColor,
    Color trimColor,
  ) {
    final side = house.doorSide;
    final a = rim[side];
    final b = rim[(side + 1) % 4];
    final along = b - a;
    final len = along.distance;
    if (len < 0.001) return;
    final dir = along / len;
    final mid = Offset.lerp(a, b, 0.5)!;
    final gap = House.doorWidth / 2;
    final left = mid - dir * gap;
    final right = mid + dir * gap;
    // Wall stubs on either side of the doorway (no more missing façade).
    _paintHouseWallFace(
      canvas,
      house,
      rim,
      side,
      wallColor,
      trimColor,
      from: a,
      to: left,
    );
    _paintHouseWallFace(
      canvas,
      house,
      rim,
      side,
      wallColor,
      trimColor,
      from: right,
      to: b,
    );
  }

  void _paintHouseRoof(Canvas canvas, House house, List<Offset> rim) {
    final roofBase =
        rim.map((o) => projection.project(o, 0.32)).toList(growable: false);
    final ridgeA = projection.project(
      Offset((rim[0].dx + rim[1].dx) / 2, (rim[0].dy + rim[1].dy) / 2),
      0.48,
    );
    final ridgeB = projection.project(
      Offset((rim[2].dx + rim[3].dx) / 2, (rim[2].dy + rim[3].dy) / 2),
      0.48,
    );

    // See-through roof while the player is inside so chests/player stay visible.
    final inside = house.inner.inflate(0.06).contains(engine.player);
    final roofAlpha = inside ? 0.18 : 1.0;
    final leftFill = const Color(0xFF5D4037).withValues(alpha: roofAlpha);
    final rightFill = const Color(0xFF4E342E).withValues(alpha: roofAlpha);
    final ridgeColor = const Color(0xFF3E2723).withValues(alpha: roofAlpha);

    // Draw farther roof plane first.
    final leftCentroid = Offset(
      (roofBase[0].dx + roofBase[3].dx + ridgeA.dx + ridgeB.dx) / 4,
      (roofBase[0].dy + roofBase[3].dy + ridgeA.dy + ridgeB.dy) / 4,
    );
    final rightCentroid = Offset(
      (roofBase[1].dx + roofBase[2].dx + ridgeA.dx + ridgeB.dx) / 4,
      (roofBase[1].dy + roofBase[2].dy + ridgeA.dy + ridgeB.dy) / 4,
    );
    final roofLeft = Path()
      ..moveTo(roofBase[0].dx, roofBase[0].dy)
      ..lineTo(roofBase[3].dx, roofBase[3].dy)
      ..lineTo(ridgeB.dx, ridgeB.dy)
      ..lineTo(ridgeA.dx, ridgeA.dy)
      ..close();
    final roofRight = Path()
      ..moveTo(roofBase[1].dx, roofBase[1].dy)
      ..lineTo(roofBase[2].dx, roofBase[2].dy)
      ..lineTo(ridgeB.dx, ridgeB.dy)
      ..lineTo(ridgeA.dx, ridgeA.dy)
      ..close();
    final leftFirst = leftCentroid.dy <= rightCentroid.dy;
    if (leftFirst) {
      canvas.drawPath(roofLeft, Paint()..color = leftFill);
      canvas.drawPath(roofRight, Paint()..color = rightFill);
    } else {
      canvas.drawPath(roofRight, Paint()..color = rightFill);
      canvas.drawPath(roofLeft, Paint()..color = leftFill);
    }
    canvas.drawLine(
      ridgeA,
      ridgeB,
      Paint()
        ..color = ridgeColor
        ..strokeWidth = 2,
    );

    if (inside) return; // Hide chimney while indoors so it doesn't block the view.

    final chimneyBase = Offset(
      house.center.dx + house.width * 0.28,
      house.center.dy - house.depth * 0.18,
    );
    final cLow = projection.project(chimneyBase, 0.34);
    final cHigh = projection.project(chimneyBase, 0.55);
    canvas.drawLine(
      cLow,
      cHigh,
      Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.square,
    );
    canvas.drawCircle(
      cHigh + const Offset(0, -2),
      3.5,
      Paint()..color = const Color(0xFF8D6E63),
    );
  }

  void _paintHouseDoorFrame(
    Canvas canvas,
    House house,
    List<Offset> rim,
    Color trimColor,
  ) {
    final side = house.doorSide;
    final a = rim[side];
    final b = rim[(side + 1) % 4];
    final along = b - a;
    final len = along.distance;
    if (len < 0.001) return;
    final dir = along / len;
    final gap = House.doorWidth / 2;
    final mid = Offset.lerp(a, b, 0.5)!;
    final left = mid - dir * gap;
    final right = mid + dir * gap;
    final posts = [left, right];
    for (final post in posts) {
      final low = projection.project(post, 0.02);
      final high = projection.project(post, 0.24);
      canvas.drawLine(
        low,
        high,
        Paint()
          ..color = trimColor
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
    }
    final lintelL = projection.project(left, 0.24);
    final lintelR = projection.project(right, 0.24);
    canvas.drawLine(
      lintelL,
      lintelR,
      Paint()
        ..color = trimColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    final glow = projection.project(mid, 0.1);
    canvas.drawCircle(
      glow,
      7,
      Paint()
        ..color = const Color(0x44FFCC80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _paintChest(Canvas canvas, TreasureChest chest) {
    _paintShadow(canvas, chest.position, 0.12);
    final p = projection.project(chest.position, chest.opened ? 0.02 : 0.06);
    final w = projection.scale * 0.12;
    final box = Rect.fromCenter(center: p, width: w, height: w * 0.75);
    final color =
        chest.opened ? const Color(0xFF8D6E63) : chest.requiredKey.color;
    if (chest.isRespawning && chest.respawnTimer < 8) {
      final pulse = 0.35 + 0.35 * math.sin(chest.respawnTimer * 6);
      canvas.drawCircle(
        p,
        w * 0.85,
        Paint()
          ..color = chest.requiredKey.color.withValues(alpha: pulse * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.45)!],
        ).createShader(box),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black87,
    );
    if (!chest.opened) {
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.black87);
      canvas.drawCircle(p, 2, Paint()..color = Colors.amberAccent);
    }
  }

  void _paintKeyDrop(Canvas canvas, WorldKeyDrop drop) {
    final p = projection.project(drop.position, 0.08);
    canvas.drawCircle(
      p,
      7,
      Paint()
        ..color = drop.kind.color.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
  }

  void _paintShadow(Canvas canvas, Offset position, double radius) {
    final center = projection.project(position);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 3),
        width: radius * projection.scale * 1.55,
        height: radius * projection.scale * 0.48,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _paintEnemyTelegraphs(Canvas canvas) {
    for (final zombie in engine.zombies) {
      if (!zombie.isWindingUp) continue;
      final progress = zombie.windUpProgress;
      final pulse = 0.55 + 0.45 * math.sin(progress * math.pi * 6);
      final warnAt = zombie.telegraphWorld ?? zombie.position;
      final ground = projection.project(warnAt);

      if (zombie.telegraphRadius > 0) {
        final warnW = zombie.telegraphRadius * projection.scale * 2.2;
        final warnH = zombie.telegraphRadius * projection.scale * 0.9;
        final rect = Rect.fromCenter(
          center: ground,
          width: warnW * (0.85 + pulse * 0.2),
          height: warnH * (0.85 + pulse * 0.2),
        );
        final color = switch (zombie.pendingAttack) {
          EnemyAttackKind.exploder => const Color(0xFFFF6D00),
          EnemyAttackKind.globling => const Color(0xFF76FF03),
          EnemyAttackKind.melee => const Color(0xFFFF1744),
          _ => zombie.kind.color,
        };
        canvas.drawOval(
          rect,
          Paint()..color = color.withValues(alpha: 0.18 + pulse * 0.16),
        );
        canvas.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..color = color.withValues(alpha: 0.55 + pulse * 0.35),
        );

        // Warning bang for big AoE / explosions
        if (zombie.telegraphRadius >= 0.35 ||
            zombie.pendingAttack == EnemyAttackKind.exploder ||
            zombie.pendingAttack == EnemyAttackKind.globling) {
          final tri = Path()
            ..moveTo(ground.dx, ground.dy - 12)
            ..lineTo(ground.dx - 9, ground.dy + 7)
            ..lineTo(ground.dx + 9, ground.dy + 7)
            ..close();
          canvas.drawPath(
            tri,
            Paint()..color = const Color(0xFFFFEB3B).withValues(alpha: 0.9),
          );
          canvas.drawPath(
            tri,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..color = const Color(0xFFB71C1C),
          );
          final bang = TextPainter(
            text: const TextSpan(
              text: '!',
              style: TextStyle(
                color: Color(0xFFB71C1C),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          bang.paint(
            canvas,
            Offset(ground.dx - bang.width / 2, ground.dy - bang.height * 0.55),
          );
        }
      }

      // Bolt / barrage charge line toward the player
      final isRangedCharge = zombie.pendingAttack == EnemyAttackKind.ability &&
          zombie.telegraphRadius <= 0.01 &&
          (zombie.kind == ZombieKind.spitter ||
              zombie.kind == ZombieKind.frostbite ||
              zombie.kind == ZombieKind.knifeThrower ||
              zombie.kind == ZombieKind.knifeFanatic ||
              zombie.kind == ZombieKind.sharpshooter ||
              zombie.kind == ZombieKind.scatterGunner ||
              zombie.kind == ZombieKind.emberCaster ||
              zombie.kind == ZombieKind.iceLancer ||
              zombie.kind == ZombieKind.hexWitch ||
              zombie.kind == ZombieKind.railSniper ||
              zombie.kind == ZombieKind.harpooner ||
              zombie.kind == ZombieKind.boltSlinger ||
              zombie.kind == ZombieKind.toxinDart ||
              zombie.kind == ZombieKind.zapper ||
              zombie.kind == ZombieKind.missileer ||
              zombie.kind == ZombieKind.voidSovereign ||
              zombie.kind == ZombieKind.siegeBehemoth ||
              zombie.kind == ZombieKind.dreadlord ||
              zombie.kind == ZombieKind.citadelTower ||
              zombie.kind == ZombieKind.apocalypseLord);
      if (isRangedCharge) {
        final from = projection.project(zombie.position, 0.2);
        final facing = zombie.attackFacing;
        final aimWorld = zombie.position + facing * (0.55 + progress * 0.7);
        final to = projection.project(aimWorld, 0.12);
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = zombie.kind.color.withValues(alpha: 0.35 + progress * 0.45)
            ..strokeWidth = 2 + progress * 3
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          from,
          4 + progress * 6,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35 + progress * 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
  }

  double _hammerLeapHeight(Zombie zombie) {
    if (zombie.kind != ZombieKind.hammerMauler) return 0;
    if (!zombie.isWindingUp ||
        zombie.pendingAttack != EnemyAttackKind.ability) {
      return 0;
    }
    // Arc up during the telegraph, then land as the smash commits.
    return math.sin(zombie.windUpProgress * math.pi) * 1.35;
  }

  void _paintHammer(
    Canvas canvas,
    Zombie zombie,
    Offset bodyCenter,
    Offset faceDir,
    double bodyWidth,
    double bodyHeight,
    double swing,
    double wind,
  ) {
    final dir = faceDir.distance < 0.001
        ? const Offset(1, 0)
        : faceDir / faceDir.distance;
    final perp = Offset(-dir.dy, dir.dx);
    final rear = wind > 0.05 && zombie.attackAnim < 0.2;
    final smashLeap = zombie.pendingAttack == EnemyAttackKind.ability && wind > 0;
    final raise = smashLeap
        ? (-0.9 - wind * 1.4)
        : (rear ? (-0.55 - wind * 1.1) : (0.35 + swing * 1.35));
    final grip = bodyCenter +
        dir * (bodyWidth * 0.55) +
        perp * (bodyWidth * 0.15) +
        Offset(0, -bodyHeight * 0.05);
    final headPos = grip +
        dir * (bodyWidth * raise) +
        Offset(0, -bodyHeight * (rear || smashLeap ? 0.55 + wind * 0.35 : 0.12));

    final haft = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = math.max(4.0, bodyWidth * 0.22)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(grip, headPos, haft);

    final headW = bodyWidth * (1.15 + swing * 0.35);
    final headH = bodyWidth * 0.55;
    final headRect = Rect.fromCenter(center: headPos, width: headW, height: headH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, Radius.circular(bodyWidth * 0.12)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFE0B2), Color(0xFF8D6E63), Color(0xFF4E342E)],
        ).createShader(headRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, Radius.circular(bodyWidth * 0.12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF3E2723),
    );
  }

  void _paintZombie(Canvas canvas, Zombie zombie) {
    if (zombie.kind == ZombieKind.citadelTower) {
      _paintCitadelTower(canvas, zombie);
      return;
    }

    final radius = zombie.radius;
    // Haste Mage: enormous cyan haste ring on the ground.
    if (zombie.kind == ZombieKind.hasteMage) {
      final ground = projection.project(zombie.position);
      const auraR = 2.95;
      final w = auraR * projection.scale * 2.2;
      final h = auraR * projection.scale * 0.9;
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..color = const Color(0x2800E5FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..color = const Color(0xAA00E5FF),
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w * 0.72, height: h * 0.72),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0x6600BCD4),
      );
    }
    if (zombie.kind == ZombieKind.blazeburst) {
      final ground = projection.project(zombie.position);
      final pulse = zombie.isWindingUp
          ? 0.85 + zombie.windUpProgress * 0.45
          : 1.0;
      final w = zombie.radius * projection.scale * 5.2 * pulse;
      final h = w * 0.42;
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..color = const Color(0x44FF6D00)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w * 0.7, height: h * 0.7),
        Paint()
          ..color = const Color(0x33FFAB40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    if (zombie.isGhost) {
      final ground = projection.project(zombie.position);
      final w = math.max(22.0, zombie.radius * projection.scale * 3.6);
      final h = w * 0.42;
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..color = const Color(0x55E1F5FE)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    if (zombie.isAscendedNecromancer) {
      final ground = projection.project(zombie.position);
      final w = math.max(48.0, zombie.radius * projection.scale * 6.5);
      final h = w * 0.48;
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..color = const Color(0x667C4DFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w * 0.7, height: h * 0.7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xCCE040FB),
      );
    }
    if (zombie.isBlocking) {
      final ground = projection.project(zombie.position);
      final w = math.max(28.0, zombie.radius * projection.scale * 4.2);
      final h = w * 0.42;
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..color = const Color(0x5590CAF9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xCCE3F2FD),
      );
    }
    _paintShadow(canvas, zombie.position, radius * 2);
    final leapHeight = _hammerLeapHeight(zombie);
    final foot = projection.project(zombie.position, leapHeight);
    final tall = zombie.kind == ZombieKind.brute ||
        zombie.kind == ZombieKind.bloater ||
        zombie.kind == ZombieKind.necromancer ||
        zombie.kind == ZombieKind.hiveMother ||
        zombie.kind == ZombieKind.shieldBearer ||
        zombie.kind == ZombieKind.boneGolem ||
        zombie.kind == ZombieKind.hammerMauler ||
        zombie.kind.isMiniBoss ||
        zombie.kind.isBoss;
    final bodyHeight = projection.scale * radius * (tall ? 2.75 : 2.45);
    final bodyWidth = projection.scale * radius * 1.35;
    final hit = zombie.hitFlash > 0;
    var tint = zombie.isBurning
        ? const Color(0xFFFF7043)
        : zombie.isInfected
            ? const Color(0xFF9CCC65)
            : zombie.isSlowed
                ? const Color(0xFF81D4FA)
                : zombie.kind.color;
    if (zombie.isGhost) {
      tint = Color.lerp(tint, const Color(0xFFE1F5FE), 0.55)!
          .withValues(alpha: 0.55);
    }
    final shade = zombie.kind.darkColor;
    final wind = zombie.isWindingUp ? zombie.windUpProgress : 0.0;
    final windScale = zombie.pendingAttack == EnemyAttackKind.exploder ||
            zombie.pendingAttack == EnemyAttackKind.globling
        ? 1 + wind * 0.35
        : zombie.kind == ZombieKind.hammerMauler &&
                zombie.pendingAttack == EnemyAttackKind.ability
            ? 1 + wind * 0.2
            : 1 + wind * 0.08;

    final facing = zombie.attackFacing;
    final screenFacing = Offset(
      (facing.dx - facing.dy) * projection.scale * 0.55,
      (facing.dx + facing.dy) * projection.scale * 0.28,
    );
    final faceDir = screenFacing.distance == 0
        ? Offset.zero
        : screenFacing / screenFacing.distance;
    // Wind-up pulls back; recovery lunge uses attackAnim.
    final lunge = faceDir *
        ((zombie.attackAnim * bodyWidth * 0.85) - (wind * bodyWidth * 0.55));
    final swing = math.max(zombie.attackAnim, wind * 0.85);

    final legs = Paint()
      ..color = shade
      ..strokeWidth = math.max(3, bodyWidth * 0.2)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        foot + Offset(-bodyWidth * 0.22, 0) + lunge * 0.2,
        foot + Offset(-bodyWidth * 0.12, -bodyHeight * 0.42) + lunge * 0.45,
        legs);
    canvas.drawLine(
        foot + Offset(bodyWidth * 0.22, 0) + lunge * 0.2,
        foot + Offset(bodyWidth * 0.12, -bodyHeight * 0.42) + lunge * 0.45,
        legs);

    final bodyCenter = foot + Offset(0, -bodyHeight * 0.58) + lunge * 0.7;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: bodyCenter,
        width: bodyWidth *
            windScale *
            (zombie.kind == ZombieKind.bloater
                ? 1.35
                : zombie.kind == ZombieKind.globling
                    ? 1.3
                    : zombie.kind == ZombieKind.stalker
                        ? 0.85
                        : 1),
        height: bodyHeight *
            0.75 *
            windScale *
            (zombie.kind == ZombieKind.globling ? 0.85 : 1),
      ),
      Radius.circular(bodyWidth * (zombie.kind == ZombieKind.globling ? 0.55 : 0.38)),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: hit
              ? [Colors.white, Colors.redAccent]
              : wind > 0.05
                  ? [
                      Color.lerp(tint, Colors.white, wind * 0.45)!,
                      shade,
                    ]
                  : [tint, shade],
        ).createShader(body.outerRect),
    );

    if (swing > 0.05) {
      final armPaint = Paint()
        ..color = tint.withValues(alpha: 0.9)
        ..strokeWidth = math.max(3, bodyWidth * 0.18)
        ..strokeCap = StrokeCap.round;
      final rear = wind > 0.05 && zombie.attackAnim < 0.2;
      final shoulder =
          bodyCenter + Offset(-bodyWidth * 0.35, -bodyHeight * 0.05);
      final claw = shoulder +
          faceDir *
              (bodyWidth *
                  (rear ? (-0.35 - wind * 0.55) : (0.9 + swing * 1.1))) +
          Offset(0, -bodyHeight * (rear ? 0.35 * wind : 0.1 * (1 - swing)));
      canvas.drawLine(shoulder, claw, armPaint);
      canvas.drawCircle(claw, bodyWidth * 0.12, armPaint);
      final shoulder2 =
          bodyCenter + Offset(bodyWidth * 0.3, -bodyHeight * 0.02);
      final claw2 = shoulder2 +
          faceDir *
              (bodyWidth *
                  (rear ? (-0.2 - wind * 0.35) : (0.55 + swing * 0.7))) +
          Offset(swing * 4, swing * 6);
      canvas.drawLine(shoulder2, claw2, armPaint);
    }

    final head = foot + Offset(0, -bodyHeight * 1.05) + lunge * 0.85;
    canvas.drawCircle(
      head,
      bodyWidth * 0.39 * windScale,
      Paint()
        ..color = hit ? Colors.white : Color.lerp(tint, Colors.white, 0.2)!,
    );
    canvas.drawCircle(head + Offset(-bodyWidth * 0.15, -1),
        math.max(1.4, bodyWidth * 0.06), Paint()..color = Colors.redAccent);
    canvas.drawCircle(head + Offset(bodyWidth * 0.15, -1),
        math.max(1.4, bodyWidth * 0.06), Paint()..color = Colors.redAccent);

    if (zombie.kind == ZombieKind.hammerMauler) {
      _paintHammer(canvas, zombie, bodyCenter, faceDir, bodyWidth, bodyHeight,
          swing, wind);
    }

    // Ability cue marks (shapes — no icon font dependency).
    final cueCenter = head + Offset(0, -bodyWidth * 0.72);
    final cuePaint = Paint()..color = tint.withValues(alpha: 0.95);
    switch (zombie.kind) {
      case ZombieKind.spitter:
        canvas.drawCircle(cueCenter, 3.5, cuePaint);
      case ZombieKind.skyCaller:
        canvas.drawPath(
          Path()
            ..moveTo(cueCenter.dx, cueCenter.dy + 5)
            ..lineTo(cueCenter.dx - 5, cueCenter.dy - 3)
            ..lineTo(cueCenter.dx + 5, cueCenter.dy - 3)
            ..close(),
          cuePaint,
        );
      case ZombieKind.necromancer:
        canvas.drawCircle(
            cueCenter,
            4.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = tint);
        canvas.drawCircle(cueCenter, 1.8, cuePaint);
      case ZombieKind.exploder:
        canvas.drawCircle(cueCenter, 4, cuePaint);
        canvas.drawCircle(cueCenter, 2, Paint()..color = Colors.white70);
      case ZombieKind.globling:
        canvas.drawOval(
          Rect.fromCenter(center: cueCenter, width: 9, height: 7),
          cuePaint,
        );
        canvas.drawCircle(
          cueCenter + const Offset(0, -1),
          1.6,
          Paint()..color = Colors.white70,
        );
      case ZombieKind.shadowRonin:
        final blade = Paint()
          ..color = const Color(0xFFE0E0E0)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          cueCenter + const Offset(-6, 4),
          cueCenter + const Offset(7, -5),
          blade,
        );
        canvas.drawCircle(
          cueCenter + const Offset(-6, 4),
          2,
          Paint()..color = const Color(0xFFB71C1C),
        );
      case ZombieKind.screamer:
        canvas.drawCircle(cueCenter, 3, cuePaint);
        canvas.drawCircle(
          cueCenter,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = tint.withValues(alpha: 0.7),
        );
      case ZombieKind.hasteMage:
        // Staff with glowing crystal tip.
        final staffPaint = Paint()
          ..color = const Color(0xFFB0BEC5)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          cueCenter + const Offset(2, 9),
          cueCenter + const Offset(-1, -5),
          staffPaint,
        );
        canvas.drawCircle(
          cueCenter + const Offset(-1, -6),
          4.2,
          Paint()
            ..color = tint.withValues(alpha: 0.9)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(cueCenter + const Offset(-1, -6), 3.2, cuePaint);
        canvas.drawCircle(
          cueCenter + const Offset(-1, -6),
          1.4,
          Paint()..color = Colors.white70,
        );
      case ZombieKind.laserOverseer:
        // Twin laser diodes on a dish.
        final dish = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = tint;
        canvas.drawCircle(cueCenter, 5.5, dish);
        canvas.drawCircle(
          cueCenter + const Offset(-2.2, -1),
          2.2,
          Paint()..color = const Color(0xFFFF00E5),
        );
        canvas.drawCircle(
          cueCenter + const Offset(2.2, -1),
          2.2,
          Paint()..color = const Color(0xFF00E5FF),
        );
      case ZombieKind.blazeburst:
        // Cluster of fire orbs.
        canvas.drawCircle(
          cueCenter,
          6.2,
          Paint()
            ..color = const Color(0x66FF6D00)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        for (final o in [
          const Offset(0, -3.2),
          const Offset(-3.0, 1.6),
          const Offset(3.0, 1.6),
        ]) {
          canvas.drawCircle(
            cueCenter + o,
            2.4,
            Paint()..color = const Color(0xFFFF9100),
          );
          canvas.drawCircle(
            cueCenter + o + const Offset(-0.6, -0.6),
            0.9,
            Paint()..color = Colors.white70,
          );
        }
      case ZombieKind.knifeThrower:
      case ZombieKind.knifeFanatic:
        final blades = zombie.kind == ZombieKind.knifeFanatic ? 3 : 1;
        for (var i = 0; i < blades; i++) {
          final y = (i - (blades - 1) / 2) * 3.2;
          canvas.drawLine(
            cueCenter + Offset(-5, y + 2),
            cueCenter + Offset(6, y - 2),
            Paint()
              ..color = tint
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round,
          );
        }
      case ZombieKind.sharpshooter:
      case ZombieKind.railSniper:
        canvas.drawLine(
          cueCenter + const Offset(-6, 0),
          cueCenter + const Offset(6, 0),
          Paint()
            ..color = tint
            ..strokeWidth = 2.2,
        );
        canvas.drawCircle(cueCenter + const Offset(6, 0), 2.2, cuePaint);
      case ZombieKind.missileer:
        // Missile silhouette over head.
        final tip = cueCenter + const Offset(5, -3);
        final body = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(cueCenter.dx - 5, cueCenter.dy - 1)
          ..lineTo(cueCenter.dx - 5, cueCenter.dy + 3)
          ..lineTo(tip.dx, tip.dy + 2)
          ..close();
        canvas.drawPath(body, Paint()..color = const Color(0xFFFF8F00));
        canvas.drawCircle(
          cueCenter + const Offset(-6, 1),
          2.2,
          Paint()..color = const Color(0xFFFFEE58),
        );
      case ZombieKind.scatterGunner:
        for (final dx in [-4.0, 0.0, 4.0]) {
          canvas.drawCircle(cueCenter + Offset(dx, 0), 2.0, cuePaint);
        }
      case ZombieKind.emberCaster:
      case ZombieKind.iceLancer:
      case ZombieKind.hexWitch:
      case ZombieKind.zapper:
        canvas.drawCircle(cueCenter, 4.2, cuePaint);
        canvas.drawCircle(
          cueCenter,
          2.0,
          Paint()..color = Colors.white70,
        );
      case ZombieKind.harpooner:
      case ZombieKind.boltSlinger:
      case ZombieKind.toxinDart:
        canvas.drawLine(
          cueCenter + const Offset(-3, 3),
          cueCenter + const Offset(4, -3),
          Paint()
            ..color = tint
            ..strokeWidth = 2,
        );
      case ZombieKind.voidSovereign:
        canvas.drawCircle(
          cueCenter,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xFFEA80FC),
        );
        canvas.drawCircle(cueCenter, 2.5, cuePaint);
        canvas.drawLine(
          cueCenter + const Offset(-5, 0),
          cueCenter + const Offset(5, 0),
          Paint()
            ..color = Colors.white70
            ..strokeWidth = 1.6,
        );
      case ZombieKind.hammerMauler:
        // Tiny hammer glyph above head.
        canvas.drawLine(
          cueCenter + const Offset(-1, 5),
          cueCenter + const Offset(-1, -2),
          Paint()
            ..color = const Color(0xFFBCAAA4)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: cueCenter + const Offset(-1, -4),
              width: 10,
              height: 5,
            ),
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xFFFFB74D),
        );
      case ZombieKind.stalker:
        canvas.drawOval(
          Rect.fromCenter(center: cueCenter, width: 10, height: 5),
          Paint()..color = tint.withValues(alpha: 0.5),
        );
      case ZombieKind.runner:
        canvas.drawLine(
          cueCenter + const Offset(-4, 2),
          cueCenter + const Offset(4, -2),
          Paint()
            ..color = tint
            ..strokeWidth = 2,
        );
      default:
        break;
    }

    final healthWidth = math.max(24.0, bodyWidth * 1.45);
    final healthRect = Rect.fromLTWH(
      head.dx - healthWidth / 2,
      head.dy - bodyWidth * 0.65,
      healthWidth,
      4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(healthRect, const Radius.circular(2)),
      Paint()..color = Colors.black87,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          healthRect.left,
          healthRect.top,
          healthWidth * (zombie.health / zombie.maxHealth).clamp(0, 1),
          4,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = tint,
    );
  }

  void _paintCitadelTower(Canvas canvas, Zombie zombie) {
    _paintShadow(canvas, zombie.position, zombie.radius * 2.4);
    final base = projection.project(zombie.position);
    final scale = projection.scale;
    final hit = zombie.hitFlash > 0;
    final w = zombie.radius * scale * 1.8;
    final h = zombie.radius * scale * 4.2;
    final tower = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: base + Offset(0, -h * 0.42),
        width: w,
        height: h,
      ),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(
      tower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: hit
              ? [Colors.white, Colors.redAccent]
              : const [Color(0xFFFF5252), Color(0xFF4A0000)],
        ).createShader(tower.outerRect),
    );
    // Cross embrasures hinting X / + fire patterns.
    final tip = base + Offset(0, -h * 0.88);
    final charging = zombie.isWindingUp;
    final cross = Paint()
      ..color = charging
          ? Color.lerp(
              Colors.white70,
              const Color(0xFFFF5252),
              zombie.windUpProgress,
            )!
          : Colors.white70
      ..strokeWidth = charging ? 2.5 + zombie.windUpProgress * 2 : 2.5
      ..strokeCap = StrokeCap.round;
    if (charging) {
      canvas.drawCircle(
        tip,
        10 + zombie.windUpProgress * 14,
        Paint()
          ..color = const Color(0x66FF1744)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    if (zombie.isBlocking) {
      canvas.drawCircle(
        base + Offset(0, -h * 0.35),
        w * 0.85,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xCCE3F2FD),
      );
      canvas.drawCircle(
        base + Offset(0, -h * 0.35),
        w * 0.85,
        Paint()
          ..color = const Color(0x4490CAF9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawLine(tip + const Offset(-10, 0), tip + const Offset(10, 0), cross);
    canvas.drawLine(tip + const Offset(0, -10), tip + const Offset(0, 10), cross);
    canvas.drawLine(tip + const Offset(-7, -7), tip + const Offset(7, 7), cross);
    canvas.drawLine(tip + const Offset(-7, 7), tip + const Offset(7, -7), cross);

    final healthWidth = math.max(40.0, w * 1.4);
    final healthRect = Rect.fromLTWH(
      tip.dx - healthWidth / 2,
      tip.dy - 18,
      healthWidth,
      5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(healthRect, const Radius.circular(2)),
      Paint()..color = Colors.black87,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          healthRect.left,
          healthRect.top,
          healthWidth * (zombie.health / zombie.maxHealth).clamp(0, 1),
          5,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = zombie.kind.color,
    );
  }

  void _paintCorpses(Canvas canvas) {
    for (final corpse in engine.corpses) {
      final p = projection.project(corpse.position);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: 18, height: 8),
        Paint()..color = const Color(0x553E2723),
      );
    }
  }

  void _paintPoison(Canvas canvas) {
    for (final cloud in engine.poisonClouds) {
      final p = projection.project(cloud.position);
      final pulse = 0.9 + 0.1 * math.sin(cloud.life * 5);
      final r = cloud.radius * projection.scale * 0.95 * pulse;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 2.4, height: r * 1.05),
        Paint()
          ..color = const Color(0x8856B32A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 1.9, height: r * 0.8),
        Paint()..color = const Color(0xAA76FF03).withValues(alpha: 0.45),
      );
      for (var i = 0; i < 3; i++) {
        final ang = cloud.life * 2.2 + i * 2.1;
        final bubble = p +
            Offset(math.cos(ang) * r * 0.35, math.sin(ang) * r * 0.18 - 2);
        canvas.drawCircle(
          bubble,
          2.5 + (i % 2),
          Paint()..color = const Color(0xCCB2FF59),
        );
      }
    }
  }

  void _paintStickyGoo(Canvas canvas) {
    for (final goo in engine.stickyGoos) {
      final p = projection.project(goo.position);
      final r = goo.radius * projection.scale * 0.9;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 2.2, height: r * 0.9),
        Paint()
          ..color = const Color(0x668BC34A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  void _paintFirePits(Canvas canvas) {
    for (final pit in engine.firePits) {
      final p = projection.project(pit.position);
      final pulse = 0.85 + 0.15 * math.sin(pit.life * 10);
      final r = pit.radius * projection.scale * 0.95 * pulse;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 2.3, height: r * 0.95),
        Paint()
          ..color = const Color(0x664E342E)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 1.9, height: r * 0.75),
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF176).withValues(alpha: 0.95),
              const Color(0xFFFF6F00).withValues(alpha: 0.85),
              const Color(0x00BF360C),
            ],
          ).createShader(
            Rect.fromCenter(center: p, width: r * 1.9, height: r * 0.75),
          ),
      );
      // Ember flickers
      for (var i = 0; i < 4; i++) {
        final ang = pit.life * 6 + i * 1.7;
        final ember = p + Offset(math.cos(ang) * r * 0.35, -8.0 - i * 3.0);
        canvas.drawCircle(
          ember,
          2.2,
          Paint()..color = const Color(0xFFFFCA28).withValues(alpha: 0.8),
        );
      }
    }
  }

  void _paintLaserCannons(Canvas canvas) {
    for (final cannon in engine.laserCannons) {
      final from = projection.project(cannon.position, 0.18);
      final to = projection.project(cannon.beamEnd, 0.05);
      final target = projection.project(cannon.target, 0.02);
      final charging = cannon.phase == LaserCannonPhase.charging;
      final firing = cannon.phase == LaserCannonPhase.firing;
      final relocating = cannon.phase == LaserCannonPhase.relocating;

      if (charging || firing) {
        final chargeT = charging
            ? (1 - cannon.phaseTimer / LaserCannon.chargeDuration)
                .clamp(0.0, 1.0)
            : 1.0;
        final pulse = firing
            ? 0.85 + 0.15 * math.sin(cannon.phaseTimer * 18)
            : 0.55 + 0.45 * math.sin(cannon.phaseTimer * 10);

        // World→screen beam thickness scales with the huge hit width.
        final beamPx =
            LaserCannon.beamHalfWidth * projection.scale * 1.15;

        if (charging) {
          // Big red danger telegraph along the full beam path.
          final warnAlpha = 0.22 + 0.38 * chargeT * pulse;
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF1744).withValues(alpha: warnAlpha)
              ..strokeWidth = beamPx * (1.1 + 0.35 * chargeT)
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          );
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF5252).withValues(alpha: 0.35 + 0.45 * chargeT)
              ..strokeWidth = math.max(4.0, beamPx * 0.35 * chargeT)
              ..strokeCap = StrokeCap.round,
          );
          // Dashed-feel core by drawing a thinner bright red spine.
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF8A80).withValues(alpha: 0.55 + 0.4 * chargeT)
              ..strokeWidth = 2.5 + 3.5 * chargeT
              ..strokeCap = StrokeCap.round,
          );

          // Red impact marker at the locked random spot.
          final markR = projection.scale *
              (0.22 + 0.18 * chargeT) *
              (0.9 + 0.15 * pulse);
          canvas.drawCircle(
            target,
            markR * 1.6,
            Paint()
              ..color = const Color(0x66FF1744)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
          );
          canvas.drawCircle(
            target,
            markR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = const Color(0xFFFF1744).withValues(alpha: 0.75 + 0.25 * pulse),
          );
          canvas.drawCircle(
            target,
            markR * 0.35,
            Paint()..color = const Color(0xFFFF8A80).withValues(alpha: 0.9),
          );
          // Crosshair ticks on the indicator.
          final tick = markR * 0.85;
          final tickPaint = Paint()
            ..color = const Color(0xFFFF5252)
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            target + Offset(-tick, 0),
            target + Offset(-tick * 0.35, 0),
            tickPaint,
          );
          canvas.drawLine(
            target + Offset(tick * 0.35, 0),
            target + Offset(tick, 0),
            tickPaint,
          );
          canvas.drawLine(
            target + Offset(0, -tick),
            target + Offset(0, -tick * 0.35),
            tickPaint,
          );
          canvas.drawLine(
            target + Offset(0, tick * 0.35),
            target + Offset(0, tick),
            tickPaint,
          );
        }

        if (firing) {
          final coreW = beamPx * 0.95 * pulse;
          final glowW = beamPx * 1.85 * pulse;
          // Outer red/magenta blast
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF1744).withValues(alpha: 0.45)
              ..strokeWidth = glowW
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
          );
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF5252).withValues(alpha: 0.85)
              ..strokeWidth = coreW
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = const Color(0xFFFF8A80).withValues(alpha: 0.95)
              ..strokeWidth = coreW * 0.55
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.95)
              ..strokeWidth = math.max(4.0, coreW * 0.22)
              ..strokeCap = StrokeCap.round,
          );
        }
      }

      // Turret base
      final basePulse = relocating
          ? 0.6 + 0.4 * math.sin(cannon.phaseTimer * 20)
          : 1.0;
      final baseR = 11.0 * basePulse;
      canvas.drawCircle(
        from,
        baseR * 1.35,
        Paint()
          ..color = const Color(0xAA1A0033)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        from,
        baseR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              firing ? const Color(0xFFFFFFFF) : const Color(0xFFFF1744),
              const Color(0xFF4A148C),
            ],
          ).createShader(Rect.fromCircle(center: from, radius: baseR)),
      );
      canvas.drawCircle(
        from,
        baseR * 0.55,
        Paint()..color = charging
            ? const Color(0xFFFF5252)
            : const Color(0xFF00E5FF),
      );
      final barrelDir = to - from;
      if (barrelDir.distanceSquared > 1e-4) {
        final barrelEnd = from + barrelDir / barrelDir.distance * (baseR + 10);
        canvas.drawLine(
          from,
          barrelEnd,
          Paint()
            ..color = const Color(0xFFE0E0E0)
            ..strokeWidth = 4.5
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          barrelEnd,
          3.2,
          Paint()..color = firing
              ? Colors.white
              : charging
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFF00E5),
        );
      }
    }
  }

  Offset _meteorScreenCorner(Size size, int corner) {
    const pad = 40.0;
    return switch (corner) {
      0 => const Offset(-pad, -pad),
      1 => Offset(size.width + pad, -pad),
      2 => Offset(-pad, size.height + pad),
      _ => Offset(size.width + pad, size.height + pad),
    };
  }

  void _paintSkyHazards(Canvas canvas, Size size) {
    for (final hazard in engine.skyHazards) {
      if (hazard.detonated) continue;
      final ground = projection.project(hazard.target);
      final progress = hazard.fallProgress;
      final eased = math.pow(progress, 1.35).toDouble();
      final falling = hazard.screenCorner != null
          ? Offset.lerp(
              _meteorScreenCorner(size, hazard.screenCorner!),
              ground,
              eased,
            )!
          : projection.project(hazard.airWorld, hazard.height * 1.15);

      if (hazard.summonsZombie) {
        canvas.drawCircle(
          ground,
          10,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0x88AB47BC),
        );
        canvas.drawLine(falling, ground, Paint()..color = Colors.white24);
        canvas.drawCircle(falling, 8, Paint()..color = const Color(0xFFCE93D8));
        continue;
      }

      final pulse = 0.55 + 0.45 * math.sin(progress * math.pi * 8);
      final warnW = hazard.blastRadius * projection.scale * 2.6;
      final warnH = hazard.blastRadius * projection.scale * 1.05;
      final warnRect = Rect.fromCenter(
        center: ground,
        width: warnW * (0.92 + pulse * 0.12),
        height: warnH * (0.92 + pulse * 0.12),
      );

      // Big red impact zone
      canvas.drawOval(
        warnRect,
        Paint()..color = Color.fromRGBO(220, 20, 20, 0.22 + pulse * 0.18),
      );
      canvas.drawOval(
        warnRect.inflate(6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = Color.fromRGBO(255, 40, 40, 0.55 + pulse * 0.35),
      );
      canvas.drawOval(
        warnRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xEEFFCDD2),
      );

      // Warning triangle + bang
      final triH = 22.0 + pulse * 4;
      final triW = 20.0 + pulse * 3;
      final tri = Path()
        ..moveTo(ground.dx, ground.dy - triH * 0.55)
        ..lineTo(ground.dx - triW * 0.55, ground.dy + triH * 0.45)
        ..lineTo(ground.dx + triW * 0.55, ground.dy + triH * 0.45)
        ..close();
      canvas.drawPath(
        tri,
        Paint()..color = const Color(0xFFFFEB3B).withValues(alpha: 0.95),
      );
      canvas.drawPath(
        tri,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0xFFB71C1C),
      );
      final bang = TextPainter(
        text: const TextSpan(
          text: '!',
          style: TextStyle(
            color: Color(0xFFB71C1C),
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bang.paint(
        canvas,
        Offset(ground.dx - bang.width / 2, ground.dy - bang.height * 0.55),
      );

      // Long fiery trail from corner dive
      final trail = Path()
        ..moveTo(falling.dx, falling.dy)
        ..lineTo(ground.dx, ground.dy);
      canvas.drawPath(
        trail,
        Paint()
          ..color = const Color(0xAAFF6F00)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        trail,
        Paint()
          ..color = const Color(0xCCFFE082)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      // Big meteor body
      final meteorR = 14.0 + progress * 4;
      canvas.drawCircle(
        falling,
        meteorR + 6,
        Paint()
          ..color = const Color(0x66FF3D00)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        falling,
        meteorR,
        Paint()
          ..shader = const RadialGradient(
            colors: [
              Color(0xFFFFF59D),
              Color(0xFFFF6F00),
              Color(0xFFBF360C),
            ],
          ).createShader(Rect.fromCircle(center: falling, radius: meteorR)),
      );
      canvas.drawCircle(
        falling + Offset(-meteorR * 0.25, -meteorR * 0.25),
        meteorR * 0.28,
        Paint()..color = const Color(0xDDFFFFFF),
      );
    }
  }

  void _paintEnemyBolts(Canvas canvas) {
    for (final bolt in engine.enemyBolts) {
      final p = projection.project(bolt.position, 0.1);
      if (bolt.style == EnemyBoltStyle.citadel ||
          bolt.style == EnemyBoltStyle.apocalypse) {
        _paintBossComet(canvas, bolt, p);
        continue;
      }
      if (bolt.style == EnemyBoltStyle.knife) {
        _paintKnifeBolt(canvas, bolt, p);
        continue;
      }
      if (bolt.style == EnemyBoltStyle.fireball) {
        _paintFireballBolt(canvas, bolt, p);
        continue;
      }
      if (bolt.style == EnemyBoltStyle.missile) {
        _paintMissileBolt(canvas, bolt, p);
        continue;
      }
      final size = math.max(7.0, bolt.radius * projection.scale * 2.4);
      canvas.drawCircle(
        p,
        size + 4,
        Paint()
          ..color = bolt.color.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        p,
        size,
        Paint()
          ..color = bolt.color.withValues(alpha: 0.95)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        p,
        size * 0.42,
        Paint()..color = const Color(0xEEFFFFFF),
      );
    }
  }

  void _paintMissileBolt(Canvas canvas, EnemyBolt bolt, Offset p) {
    final speed = bolt.velocity.distance;
    final dir = speed < 1e-5
        ? const Offset(1, 0)
        : Offset(bolt.velocity.dx / speed, bolt.velocity.dy / speed);
    // Convert world velocity into a roughly isometric screen direction.
    final screenDir = Offset(
      (dir.dx - dir.dy) * 0.55,
      (dir.dx + dir.dy) * 0.28,
    );
    final face = screenDir.distance < 1e-5
        ? const Offset(1, 0)
        : screenDir / screenDir.distance;
    final length = math.max(9.0, bolt.radius * projection.scale * 3.6);
    final width = math.max(2.8, bolt.radius * projection.scale * 1.15);
    final tip = p + face * length * 0.45;
    final tail = p - face * length * 0.55;
    final perp = Offset(-face.dy, face.dx);

    // Exhaust trail
    canvas.drawCircle(
      tail - face * 2.5,
      width * 1.15,
      Paint()
        ..color = const Color(0x66FF6D00)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      tail - face * 1.2,
      width * 0.55,
      Paint()..color = const Color(0xAAFFEE58),
    );

    final body = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (p + perp * width * 0.55 - face * length * 0.15).dx,
        (p + perp * width * 0.55 - face * length * 0.15).dy,
      )
      ..lineTo(tail.dx + perp.dx * width * 0.35, tail.dy + perp.dy * width * 0.35)
      ..lineTo(tail.dx - perp.dx * width * 0.35, tail.dy - perp.dy * width * 0.35)
      ..lineTo(
        (p - perp * width * 0.55 - face * length * 0.15).dx,
        (p - perp * width * 0.55 - face * length * 0.15).dy,
      )
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-face.dx, -face.dy),
          end: Alignment(face.dx, face.dy),
          colors: [
            const Color(0xFFFFE082),
            bolt.color,
            const Color(0xFFE65100),
          ],
        ).createShader(Rect.fromPoints(tip, tail)),
    );
    canvas.drawCircle(tip, width * 0.3, Paint()..color = Colors.white);
  }

  void _paintFireballBolt(Canvas canvas, EnemyBolt bolt, Offset p) {
    final size = math.max(8.0, bolt.radius * projection.scale * 3.2);
    final genGlow = bolt.splitRemaining >= 2
        ? 1.25
        : bolt.splitRemaining == 1
            ? 1.05
            : 0.85;
    canvas.drawCircle(
      p,
      size * 1.8 * genGlow,
      Paint()
        ..color = const Color(0xFFFF6D00).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      p,
      size * 1.15,
      Paint()
        ..color = bolt.color.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      p,
      size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF8E1),
            bolt.color,
            const Color(0xFFBF360C),
          ],
        ).createShader(Rect.fromCircle(center: p, radius: size)),
    );
    canvas.drawCircle(
      p + Offset(-size * 0.15, -size * 0.18),
      size * 0.28,
      Paint()..color = const Color(0xDDFFFFFF),
    );
  }

  void _paintKnifeBolt(Canvas canvas, EnemyBolt bolt, Offset p) {
    final speed = bolt.velocity.distance;
    final dir = speed > 0.001
        ? Offset(
            (bolt.velocity.dx - bolt.velocity.dy) * 0.55,
            (bolt.velocity.dx + bolt.velocity.dy) * 0.28,
          )
        : const Offset(1, 0);
    final screenDir = dir.distanceSquared < 1e-6
        ? const Offset(1, 0)
        : dir / dir.distance;
    final len = math.max(14.0, bolt.radius * projection.scale * 18);
    final tip = p + screenDir * (len * 0.55);
    final tail = p - screenDir * (len * 0.45);
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = bolt.color.withValues(alpha: 0.35)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = bolt.color
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 2.4, Paint()..color = Colors.white);
  }

  void _paintBossComet(Canvas canvas, EnemyBolt bolt, Offset p) {
    final apocalypse = bolt.style == EnemyBoltStyle.apocalypse;
    final speed = bolt.velocity.distance;
    final dir = speed > 0.001
        ? bolt.velocity / speed
        : const Offset(1, 0);
    // Map world velocity into screen-ish streak direction.
    final screenDir = Offset(
      (dir.dx - dir.dy) * 0.85,
      (dir.dx + dir.dy) * 0.45,
    );
    final streak = screenDir.distance == 0
        ? const Offset(1, 0)
        : screenDir / screenDir.distance;

    final core = math.max(4.5, bolt.radius * projection.scale * 2.1);
    final hot = apocalypse
        ? const Color(0xFFFF5252)
        : const Color(0xFFFF9100);
    final deep = apocalypse
        ? const Color(0xFFD50000)
        : const Color(0xFFFF3D00);
    final accent = apocalypse
        ? const Color(0xFFE040FB)
        : const Color(0xFFFFEA00);

    // Ember trail.
    for (var i = 4; i >= 1; i--) {
      final t = i / 4.0;
      final trail = p - streak * (core * (1.2 + i * 1.35));
      canvas.drawCircle(
        trail,
        core * (0.85 - t * 0.35),
        Paint()
          ..color = deep.withValues(alpha: 0.12 + (1 - t) * 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // Soft bloom
    canvas.drawCircle(
      p,
      core * 2.4,
      Paint()
        ..color = deep.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Elongated comet body
    final tip = p + streak * core * 1.15;
    final tail = p - streak * core * 2.4;
    final perp = Offset(-streak.dy, streak.dx);
    final body = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (p + perp * core * 0.55).dx,
        (p + perp * core * 0.55).dy,
      )
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(
        (p - perp * core * 0.55).dx,
        (p - perp * core * 0.55).dy,
      )
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            deep.withValues(alpha: 0.15),
            hot.withValues(alpha: 0.95),
            const Color(0xFFFFFFF0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromPoints(tail, tip)),
    );

    // Energy ring
    canvas.drawCircle(
      p,
      core * 1.15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withValues(alpha: 0.85),
    );
    // Cross spark for citadel / diamond spark for apocalypse
    final sparkWhite = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final sparkAccent = Paint()
      ..color = accent.withValues(alpha: 0.8)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    if (apocalypse) {
      canvas.drawLine(
        p + Offset(-core * 0.55, 0),
        p + Offset(core * 0.55, 0),
        sparkWhite,
      );
      canvas.drawLine(
        p + Offset(0, -core * 0.55),
        p + Offset(0, core * 0.55),
        sparkWhite,
      );
      canvas.drawLine(
        p + Offset(-core * 0.38, -core * 0.38),
        p + Offset(core * 0.38, core * 0.38),
        sparkAccent,
      );
    } else {
      canvas.drawLine(
        p + streak * core * 0.7,
        p - streak * core * 0.35,
        sparkWhite,
      );
      canvas.drawLine(
        p + perp * core * 0.45,
        p - perp * core * 0.45,
        sparkWhite,
      );
    }

    canvas.drawCircle(p, core * 0.38, Paint()..color = Colors.white);
    canvas.drawCircle(
      p + Offset(-core * 0.12, -core * 0.12),
      core * 0.12,
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }

  void _paintGunAlly(Canvas canvas, GunAlly ally) {
    _paintShadow(canvas, ally.position, 0.1);
    final foot = projection.project(ally.position);
    final bodyH = projection.scale * 0.12;
    final bodyW = projection.scale * 0.07;
    final tint = ally.hitFlash > 0
        ? Color.lerp(const Color(0xFFFFD54F), Colors.white, 0.7)!
        : const Color(0xFFFFD54F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: foot + Offset(0, -bodyH * 0.55),
          width: bodyW,
          height: bodyH,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = tint,
    );
    canvas.drawCircle(
      foot + Offset(0, -bodyH * 1.05),
      bodyW * 0.38,
      Paint()..color = Color.lerp(tint, Colors.white, 0.35)!,
    );
    // Tiny rifle
    final aim = ally.aim;
    final screenAim = Offset(
      (aim.dx - aim.dy) * projection.scale * 0.55,
      (aim.dx + aim.dy) * projection.scale * 0.28,
    );
    if (screenAim.distanceSquared > 1e-4) {
      final dir = screenAim / screenAim.distance;
      canvas.drawLine(
        foot + Offset(0, -bodyH * 0.55),
        foot + Offset(0, -bodyH * 0.55) + dir * (bodyW * 1.8),
        Paint()
          ..color = const Color(0xFFE0E0E0)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
    // HP pip
    final hp = (ally.health / ally.maxHealth).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 10, foot.dy - bodyH * 1.45, 20, 3),
      Paint()..color = Colors.black45,
    );
    canvas.drawRect(
      Rect.fromLTWH(foot.dx - 10, foot.dy - bodyH * 1.45, 20 * hp, 3),
      Paint()
        ..color = hp > 0.35
            ? const Color(0xFF76FF03)
            : const Color(0xFFFF5252),
    );
  }

  void _paintPlayer(Canvas canvas) {
    final kind = engine.playerClass;
    final accent = kind.color;
    final deep = Color.lerp(accent, const Color(0xFF0A1014), 0.62)!;
    final mid = Color.lerp(accent, const Color(0xFF1A2430), 0.35)!;

    // Bulk / lean silhouette by class fantasy.
    final bulk = switch (kind) {
      PlayerClass.juggernaut => 1.45,
      PlayerClass.tank => 1.28,
      PlayerClass.demolitions => 1.18,
      PlayerClass.commander => 1.12,
      PlayerClass.assault => 1.08,
      PlayerClass.reaper => 1.06,
      PlayerClass.survivor => 1.0,
      PlayerClass.ranger => 0.98,
      PlayerClass.berserker => 0.96,
      PlayerClass.scout => 0.88,
      PlayerClass.ghost => 0.9,
    };
    final tall = switch (kind) {
      PlayerClass.juggernaut || PlayerClass.tank => 1.12,
      PlayerClass.ghost || PlayerClass.scout => 1.08,
      PlayerClass.commander => 1.06,
      _ => 1.0,
    };

    const radius = 0.06;
    _paintShadow(canvas, engine.player, radius * 2 * bulk);
    final foot = projection.project(engine.player);
    final bodyHeight = projection.scale * radius * 2.45 * tall;
    final bodyWidth = projection.scale * radius * 1.35 * bulk;

    if (engine.isShielded) {
      canvas.drawOval(
        Rect.fromCenter(
          center: foot + Offset(0, -bodyHeight * 0.55),
          width: bodyWidth * 2.4,
          height: bodyHeight * 1.6,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.lightBlueAccent.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    final facing = engine.aimDirection;
    final screenFacing = Offset(
      (facing.dx - facing.dy) * projection.scale * 0.55,
      (facing.dx + facing.dy) * projection.scale * 0.28,
    );
    final direction = screenFacing.distance == 0
        ? const Offset(0, -1)
        : screenFacing / screenFacing.distance;

    final legColor = Color.lerp(deep, const Color(0xFF1C2831), 0.35)!;
    final legPaint = Paint()
      ..color = legColor
      ..strokeWidth = bodyWidth * (kind == PlayerClass.juggernaut ? 0.28 : 0.22)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      foot + Offset(-bodyWidth * 0.22, 0),
      foot + Offset(-bodyWidth * 0.1, -bodyHeight * 0.45),
      legPaint,
    );
    canvas.drawLine(
      foot + Offset(bodyWidth * 0.22, 0),
      foot + Offset(bodyWidth * 0.1, -bodyHeight * 0.45),
      legPaint,
    );

    // Ghost cloak / ranger cape behind torso.
    if (kind == PlayerClass.ghost || kind == PlayerClass.ranger) {
      final cape = Path()
        ..moveTo(foot.dx - bodyWidth * 0.55, foot.dy - bodyHeight * 0.55)
        ..lineTo(foot.dx + bodyWidth * 0.55, foot.dy - bodyHeight * 0.55)
        ..lineTo(foot.dx + bodyWidth * 0.7, foot.dy - bodyHeight * 0.05)
        ..lineTo(foot.dx, foot.dy + bodyHeight * 0.08)
        ..lineTo(foot.dx - bodyWidth * 0.7, foot.dy - bodyHeight * 0.05)
        ..close();
      canvas.drawPath(
        cape,
        Paint()
          ..color = kind == PlayerClass.ghost
              ? accent.withValues(alpha: 0.35)
              : deep.withValues(alpha: 0.75),
      );
    }

    final torsoCenter = foot + Offset(0, -bodyHeight * 0.62);
    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: torsoCenter,
        width: bodyWidth *
            (kind == PlayerClass.berserker
                ? 0.92
                : kind == PlayerClass.juggernaut
                    ? 1.12
                    : 1),
        height: bodyHeight * (kind == PlayerClass.juggernaut ? 0.86 : 0.78),
      ),
      Radius.circular(bodyWidth * (kind == PlayerClass.juggernaut ? 0.22 : 0.3)),
    );
    final torsoAlpha = kind == PlayerClass.ghost ? 0.72 : 1.0;
    canvas.drawRRect(
      torso,
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: torsoAlpha),
            deep.withValues(alpha: torsoAlpha),
          ],
        ).createShader(torso.outerRect),
    );

    // Class kit details on the torso.
    switch (kind) {
      case PlayerClass.reaper:
        // Soul mark on the chest.
        canvas.drawCircle(
          torsoCenter + Offset(0, -bodyHeight * 0.02),
          bodyWidth * 0.16,
          Paint()..color = const Color(0xFFE1BEE7),
        );
        canvas.drawCircle(
          torsoCenter + Offset(0, -bodyHeight * 0.02),
          bodyWidth * 0.08,
          Paint()..color = const Color(0xFF7E57C2),
        );
      case PlayerClass.tank:
      case PlayerClass.juggernaut:
        // Shoulder plates.
        for (final side in [-1.0, 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: torsoCenter +
                    Offset(side * bodyWidth * 0.55, -bodyHeight * 0.18),
                width: bodyWidth * 0.42,
                height: bodyWidth * 0.28,
              ),
              Radius.circular(bodyWidth * 0.08),
            ),
            Paint()..color = Color.lerp(accent, Colors.white, 0.25)!,
          );
        }
        if (kind == PlayerClass.tank) {
          // Small buckler on off-hand side.
          canvas.drawCircle(
            torsoCenter + Offset(-direction.dy, direction.dx) * bodyWidth * 0.85,
            bodyWidth * 0.28,
            Paint()..color = const Color(0xFFB0BEC5),
          );
        }
      case PlayerClass.assault:
        // Chest plate straps.
        canvas.drawLine(
          torsoCenter + Offset(-bodyWidth * 0.28, -bodyHeight * 0.2),
          torsoCenter + Offset(bodyWidth * 0.28, bodyHeight * 0.18),
          Paint()
            ..color = deep
            ..strokeWidth = 2.2,
        );
        canvas.drawLine(
          torsoCenter + Offset(bodyWidth * 0.28, -bodyHeight * 0.2),
          torsoCenter + Offset(-bodyWidth * 0.28, bodyHeight * 0.18),
          Paint()
            ..color = deep
            ..strokeWidth = 2.2,
        );
      case PlayerClass.demolitions:
        // Bandolier dots.
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
            torsoCenter +
                Offset(-bodyWidth * 0.22 + i * bodyWidth * 0.14, -bodyHeight * 0.12 + i * 3.2),
            bodyWidth * 0.09,
            Paint()..color = const Color(0xFFFFE082),
          );
        }
      case PlayerClass.commander:
        // Epaulets + sash.
        for (final side in [-1.0, 1.0]) {
          canvas.drawCircle(
            torsoCenter + Offset(side * bodyWidth * 0.42, -bodyHeight * 0.22),
            bodyWidth * 0.14,
            Paint()..color = const Color(0xFFFFF59D),
          );
        }
        canvas.drawLine(
          torsoCenter + Offset(-bodyWidth * 0.35, -bodyHeight * 0.05),
          torsoCenter + Offset(bodyWidth * 0.35, bodyHeight * 0.2),
          Paint()
            ..color = const Color(0xFFE53935)
            ..strokeWidth = 3,
        );
      case PlayerClass.berserker:
        // Torn wrap marks.
        canvas.drawLine(
          torsoCenter + Offset(-bodyWidth * 0.35, -bodyHeight * 0.15),
          torsoCenter + Offset(bodyWidth * 0.2, bodyHeight * 0.1),
          Paint()
            ..color = const Color(0xFF4A148C)
            ..strokeWidth = 2.4,
        );
      case PlayerClass.scout:
        // Slim harness.
        canvas.drawLine(
          torsoCenter + Offset(-bodyWidth * 0.2, -bodyHeight * 0.25),
          torsoCenter + Offset(-bodyWidth * 0.2, bodyHeight * 0.2),
          Paint()
            ..color = deep
            ..strokeWidth = 2,
        );
      case PlayerClass.ranger:
        // Quiver hint on back.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: torsoCenter - direction * bodyWidth * 0.55,
              width: bodyWidth * 0.22,
              height: bodyHeight * 0.45,
            ),
            Radius.circular(bodyWidth * 0.08),
          ),
          Paint()..color = const Color(0xFF5D4037),
        );
      case PlayerClass.survivor:
      case PlayerClass.ghost:
        break;
    }

    final head = foot + Offset(0, -bodyHeight * 1.08);
    final skin = kind == PlayerClass.ghost
        ? const Color(0xFFCFD8DC)
        : const Color(0xFFD7B08B);
    canvas.drawCircle(
      head,
      bodyWidth * (kind == PlayerClass.juggernaut ? 0.34 : 0.38),
      Paint()..color = skin.withValues(alpha: kind == PlayerClass.ghost ? 0.75 : 1),
    );

    // Headgear per class.
    switch (kind) {
      case PlayerClass.assault:
      case PlayerClass.tank:
      case PlayerClass.juggernaut:
        // Helmet.
        canvas.drawArc(
          Rect.fromCircle(
            center: head,
            radius: bodyWidth * (kind == PlayerClass.juggernaut ? 0.4 : 0.42),
          ),
          math.pi,
          math.pi,
          true,
          Paint()..color = mid,
        );
        if (kind == PlayerClass.juggernaut) {
          canvas.drawRect(
            Rect.fromCenter(
              center: head + Offset(0, -bodyWidth * 0.08),
              width: bodyWidth * 0.55,
              height: bodyWidth * 0.12,
            ),
            Paint()..color = const Color(0xFFFFE082),
          );
        }
      case PlayerClass.scout:
      case PlayerClass.ranger:
      case PlayerClass.ghost:
        // Hood.
        final hood = Path()
          ..moveTo(head.dx - bodyWidth * 0.42, head.dy)
          ..quadraticBezierTo(
            head.dx,
            head.dy - bodyWidth * 0.72,
            head.dx + bodyWidth * 0.42,
            head.dy,
          )
          ..close();
        canvas.drawPath(
          hood,
          Paint()
            ..color = kind == PlayerClass.ghost
                ? accent.withValues(alpha: 0.55)
                : deep,
        );
      case PlayerClass.reaper:
        // Hooded cowl.
        final hood = Path()
          ..moveTo(head.dx - bodyWidth * 0.42, head.dy)
          ..quadraticBezierTo(
            head.dx,
            head.dy - bodyWidth * 0.78,
            head.dx + bodyWidth * 0.42,
            head.dy,
          )
          ..close();
        canvas.drawPath(
          hood,
          Paint()..color = deep,
        );
        canvas.drawCircle(
          head + Offset(0, bodyWidth * 0.02),
          bodyWidth * 0.12,
          Paint()..color = const Color(0xFFE1BEE7).withValues(alpha: 0.7),
        );
      case PlayerClass.demolitions:
        // Goggles.
        canvas.drawArc(
          Rect.fromCircle(center: head, radius: bodyWidth * 0.4),
          math.pi,
          math.pi,
          true,
          Paint()..color = deep,
        );
        canvas.drawCircle(
          head + Offset(-bodyWidth * 0.14, -bodyWidth * 0.02),
          bodyWidth * 0.12,
          Paint()..color = const Color(0xFF80DEEA),
        );
        canvas.drawCircle(
          head + Offset(bodyWidth * 0.14, -bodyWidth * 0.02),
          bodyWidth * 0.12,
          Paint()..color = const Color(0xFF80DEEA),
        );
      case PlayerClass.berserker:
        // Wild hair spikes.
        for (final dx in [-0.28, -0.08, 0.12, 0.32]) {
          canvas.drawLine(
            head + Offset(bodyWidth * dx, -bodyWidth * 0.1),
            head + Offset(bodyWidth * dx * 1.2, -bodyWidth * 0.55),
            Paint()
              ..color = const Color(0xFF4A148C)
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          );
        }
      case PlayerClass.commander:
        // Peaked cap.
        canvas.drawArc(
          Rect.fromCircle(center: head, radius: bodyWidth * 0.4),
          math.pi,
          math.pi,
          true,
          Paint()..color = deep,
        );
        canvas.drawLine(
          head + Offset(-bodyWidth * 0.42, -bodyWidth * 0.05),
          head + Offset(bodyWidth * 0.42, -bodyWidth * 0.05),
          Paint()
            ..color = const Color(0xFFFFF59D)
            ..strokeWidth = 2.5,
        );
      case PlayerClass.survivor:
        canvas.drawArc(
          Rect.fromCircle(center: head, radius: bodyWidth * 0.4),
          math.pi,
          math.pi,
          true,
          Paint()..color = const Color(0xFF19242B),
        );
    }

    // World-space health bar above the player.
    final overhealed = engine.health > engine.maxHealth;
    final hpRatio =
        (engine.health / engine.maxHealth).clamp(0.0, 1.0).toDouble();
    final hpColor = overhealed
        ? const Color(0xFF80DEEA)
        : hpRatio > 0.5
            ? const Color(0xFF77E28A)
            : hpRatio > 0.25
                ? const Color(0xFFFFB74D)
                : const Color(0xFFFF5252);
    final barW = math.max(36.0, bodyWidth * 3.2);
    final barH = 5.0;
    final barTopLeft = Offset(head.dx - barW / 2, head.dy - bodyWidth * 1.45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barW, barH),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xCC000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barW * hpRatio, barH),
        const Radius.circular(3),
      ),
      Paint()..color = hpColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barW, barH),
        const Radius.circular(3),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );

    final gunStart = foot + Offset(0, -bodyHeight * 0.68);
    final gunLen = bodyWidth *
        switch (kind) {
          PlayerClass.ranger => 1.55,
          PlayerClass.assault || PlayerClass.commander => 1.35,
          PlayerClass.scout => 1.1,
          PlayerClass.berserker => 1.0,
          PlayerClass.reaper => engine.soulScytheActive ? 2.15 : 1.2,
          _ => 1.2,
        };
    if (engine.soulScytheActive) {
      _paintSoulScythe(
        canvas,
        gunStart,
        direction,
        gunLen * 1.95,
        bodyWidth,
        engine.soulScytheSwingAngle,
      );
    } else {
      _paintEquippedWeapon(
        canvas,
        gunStart,
        direction,
        gunLen,
        bodyWidth,
        engine.weapon,
      );
    }
  }

  void _paintSoulScythe(
    Canvas canvas,
    Offset grip,
    Offset aimDirection,
    double length,
    double bodyWidth,
    double swingAngle,
  ) {
    final aim = aimDirection.distance < 0.001
        ? const Offset(1, 0)
        : aimDirection / aimDirection.distance;
    final cosA = math.cos(swingAngle);
    final sinA = math.sin(swingAngle);
    final shaftDir = Offset(
      aim.dx * cosA - aim.dy * sinA,
      aim.dx * sinA + aim.dy * cosA,
    );
    final bladeSide = Offset(-shaftDir.dy, shaftDir.dx);
    final pulse = 0.55 + 0.45 * math.sin(engine.gameTime * 6.5);
    final swingHard = swingAngle.abs().clamp(0.0, 1.2) / 1.2;

    final butt = grip - shaftDir * length * 0.42;
    final head = grip + shaftDir * length * 1.05;
    final lowerGrip = Offset.lerp(butt, head, 0.22)!;
    final midGrip = Offset.lerp(butt, head, 0.48)!;
    final upperBand = Offset.lerp(butt, head, 0.82)!;

    // Soft soul aura behind the whole weapon.
    canvas.drawCircle(
      head + bladeSide * bodyWidth * 0.35 - shaftDir * length * 0.28,
      bodyWidth * (1.35 + swingHard * 0.45),
      Paint()
        ..color = Color(0xFFB388FF).withValues(alpha: 0.12 + pulse * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Ebony snath with a faint purple underglow — long slim pole.
    final poleGlow = Paint()
      ..color = const Color(0x667E57C2)
      ..strokeWidth = math.max(4.0, bodyWidth * 0.24)
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(butt, head, poleGlow);

    final polePaint = Paint()
      ..shader = LinearGradient(
        colors: const [
          Color(0xFF1A1224),
          Color(0xFF3A2A4A),
          Color(0xFF120C18),
          Color(0xFF2A1F38),
        ],
        stops: const [0, 0.35, 0.7, 1],
      ).createShader(Rect.fromPoints(butt, head))
      ..strokeWidth = math.max(2.6, bodyWidth * 0.15)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(butt, head, polePaint);

    // Wood grain / rune scratches along the shaft.
    for (var i = 0; i < 5; i++) {
      final t = 0.12 + i * 0.16;
      final a = Offset.lerp(butt, head, t)!;
      final b = Offset.lerp(butt, head, t + 0.07)!;
      canvas.drawLine(
        a + bladeSide * bodyWidth * 0.04,
        b + bladeSide * bodyWidth * 0.04,
        Paint()
          ..color = const Color(0x44E1BEE7)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }

    // Leather wraps.
    void wrapBand(Offset center, {double flare = 1}) {
      canvas.drawLine(
        center - shaftDir * bodyWidth * 0.08,
        center + shaftDir * bodyWidth * 0.08,
        Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = math.max(4.2, bodyWidth * 0.28 * flare)
          ..strokeCap = StrokeCap.butt,
      );
      canvas.drawLine(
        center - shaftDir * bodyWidth * 0.05,
        center + shaftDir * bodyWidth * 0.05,
        Paint()
          ..color = const Color(0xFF8D6E63)
          ..strokeWidth = math.max(2.2, bodyWidth * 0.14 * flare)
          ..strokeCap = StrokeCap.butt,
      );
      // Stitching.
      for (final side in [-1.0, 1.0]) {
        canvas.drawLine(
          center + bladeSide * bodyWidth * 0.1 * side - shaftDir * bodyWidth * 0.05,
          center + bladeSide * bodyWidth * 0.1 * side + shaftDir * bodyWidth * 0.05,
          Paint()
            ..color = const Color(0xFFD7CCC8)
            ..strokeWidth = 0.9,
        );
      }
    }

    wrapBand(lowerGrip, flare: 1.15);
    wrapBand(midGrip);

    // Ornate metal rings.
    void metalRing(Offset center, {required Color metal, double size = 1}) {
      canvas.drawCircle(
        center,
        bodyWidth * 0.16 * size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(metal, Colors.white, 0.45)!,
              metal,
              Color.lerp(metal, Colors.black, 0.45)!,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: bodyWidth * 0.18 * size),
          ),
      );
      canvas.drawCircle(
        center,
        bodyWidth * 0.16 * size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = Colors.white54,
      );
    }

    metalRing(Offset.lerp(butt, head, 0.18)!, metal: const Color(0xFFB0BEC5));
    metalRing(upperBand, metal: const Color(0xFFCE93D8), size: 1.15);

    // Pommel: cracked soul crystal.
    final pommel = butt - shaftDir * bodyWidth * 0.05;
    canvas.drawCircle(
      pommel,
      bodyWidth * 0.28,
      Paint()
        ..color = const Color(0x88B388FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      pommel,
      bodyWidth * 0.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(const Color(0xFFF3E5F5), Colors.white, pulse)!,
            const Color(0xFF7E57C2),
            const Color(0xFF311B92),
          ],
        ).createShader(
          Rect.fromCircle(center: pommel, radius: bodyWidth * 0.22),
        ),
    );
    canvas.drawLine(
      pommel + bladeSide * bodyWidth * 0.08,
      pommel - bladeSide * bodyWidth * 0.1 - shaftDir * bodyWidth * 0.06,
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      pommel - bladeSide * bodyWidth * 0.06,
      pommel + shaftDir * bodyWidth * 0.08,
      Paint()
        ..color = const Color(0xAAE1BEE7)
        ..strokeWidth = 1,
    );

    // Secondary grip horn (classic scythe nib).
    final hornRoot = midGrip - shaftDir * length * 0.02;
    final hornTip = hornRoot + bladeSide * bodyWidth * 0.55 - shaftDir * bodyWidth * 0.15;
    canvas.drawLine(
      hornRoot,
      hornTip,
      Paint()
        ..color = const Color(0xFF4E342E)
        ..strokeWidth = math.max(2.6, bodyWidth * 0.14)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      hornTip,
      bodyWidth * 0.08,
      Paint()..color = const Color(0xFF8D6E63),
    );

    // Socket / skull collar at the head.
    final collar = head - shaftDir * length * 0.06;
    canvas.drawCircle(
      collar,
      bodyWidth * 0.26,
      Paint()
        ..color = const Color(0x557E57C2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: collar,
          width: bodyWidth * 0.55,
          height: bodyWidth * 0.42,
        ),
        Radius.circular(bodyWidth * 0.1),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFCFD8DC), Color(0xFF607D8B), Color(0xFF37474F)],
        ).createShader(
          Rect.fromCenter(
            center: collar,
            width: bodyWidth * 0.55,
            height: bodyWidth * 0.42,
          ),
        ),
    );
    // Tiny fang rivets.
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        collar + bladeSide * bodyWidth * 0.16 * side,
        bodyWidth * 0.045,
        Paint()..color = const Color(0xFFFFF59D),
      );
    }
    // Socket gem in the collar.
    canvas.drawCircle(
      collar,
      bodyWidth * 0.1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Color(0xFFE040FB).withValues(alpha: 0.9),
            const Color(0xFF4A148C),
          ],
        ).createShader(
          Rect.fromCircle(center: collar, radius: bodyWidth * 0.12),
        ),
    );

    // Blade geometry — thin hooked crescent like a real farming scythe.
    final tang = head - shaftDir * length * 0.01;
    final throat =
        head + bladeSide * bodyWidth * 0.1 - shaftDir * length * 0.01;
    final belly = head +
        bladeSide * bodyWidth * (0.95 + swingHard * 0.06) -
        shaftDir * length * 0.48;
    final tip = head +
        bladeSide * bodyWidth * 0.58 -
        shaftDir * length * 1.12;
    final spineMid = head +
        bladeSide * bodyWidth * 0.32 -
        shaftDir * length * 0.62;
    final spineNear = head +
        bladeSide * bodyWidth * 0.14 -
        shaftDir * length * 0.24;

    final blade = Path()
      ..moveTo(tang.dx, tang.dy)
      ..lineTo(throat.dx, throat.dy)
      ..quadraticBezierTo(belly.dx, belly.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(spineMid.dx, spineMid.dy, spineNear.dx, spineNear.dy)
      ..lineTo(tang.dx, tang.dy)
      ..close();

    final bladeBounds = Rect.fromPoints(tip, throat).inflate(bodyWidth * 0.35);

    // Outer void glow.
    canvas.drawPath(
      blade,
      Paint()
        ..color = Color(0xFFEA80FC).withValues(alpha: 0.22 + pulse * 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Main blade fill — polished violet steel.
    canvas.drawPath(
      blade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF8F5FF),
            Color.lerp(const Color(0xFFB388FF), Colors.white, pulse * 0.25)!,
            const Color(0xFF7C4DFF),
            const Color(0xFF311B92),
            const Color(0xFF1A0A2E),
          ],
          stops: const [0, 0.22, 0.48, 0.78, 1],
        ).createShader(bladeBounds),
    );

    // Darker spine band / thin back of the blade.
    final spineBand = Path()
      ..moveTo(tang.dx, tang.dy)
      ..lineTo(
        (tang + bladeSide * bodyWidth * 0.06).dx,
        (tang + bladeSide * bodyWidth * 0.06).dy,
      )
      ..quadraticBezierTo(
        (spineMid + bladeSide * bodyWidth * 0.04).dx,
        (spineMid + bladeSide * bodyWidth * 0.04).dy,
        (tip + shaftDir * length * 0.03 + bladeSide * bodyWidth * 0.03).dx,
        (tip + shaftDir * length * 0.03 + bladeSide * bodyWidth * 0.03).dy,
      )
      ..quadraticBezierTo(spineMid.dx, spineMid.dy, spineNear.dx, spineNear.dy)
      ..close();
    canvas.drawPath(
      spineBand,
      Paint()..color = const Color(0xCC1A1030),
    );

    // Fuller groove.
    canvas.drawPath(
      Path()
        ..moveTo(
          (throat + bladeSide * bodyWidth * 0.08 - shaftDir * length * 0.04).dx,
          (throat + bladeSide * bodyWidth * 0.08 - shaftDir * length * 0.04).dy,
        )
        ..quadraticBezierTo(
          (belly - bladeSide * bodyWidth * 0.12 - shaftDir * length * 0.04).dx,
          (belly - bladeSide * bodyWidth * 0.12 - shaftDir * length * 0.04).dy,
          (tip + shaftDir * length * 0.1 + bladeSide * bodyWidth * 0.04).dx,
          (tip + shaftDir * length * 0.1 + bladeSide * bodyWidth * 0.04).dy,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, bodyWidth * 0.055)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xAA4A148C),
    );

    // Engraved soul runes along the spine.
    for (var i = 0; i < 4; i++) {
      final t = 0.18 + i * 0.18;
      final rune = Offset.lerp(spineNear, tip, t)!;
      final next = Offset.lerp(spineNear, tip, (t + 0.08).clamp(0.0, 1.0))!;
      final runeDir = next - rune;
      final runeLen = runeDir.distance;
      if (runeLen < 0.5) continue;
      final rd = runeDir / runeLen;
      final rp = Offset(-rd.dy, rd.dx);
      final glow = 0.45 + 0.55 * math.sin(engine.gameTime * 8 + i * 1.7);
      canvas.drawLine(
        rune - rd * bodyWidth * 0.05 + rp * bodyWidth * 0.04,
        rune + rd * bodyWidth * 0.08 - rp * bodyWidth * 0.05,
        Paint()
          ..color = Color(0xFFE1BEE7).withValues(alpha: 0.35 + glow * 0.55)
          ..strokeWidth = 1.35
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        rune,
        bodyWidth * 0.035,
        Paint()
          ..color = Color(0xFFF3E5F5).withValues(alpha: 0.5 + glow * 0.5),
      );
    }

    // Serrated soul notches on the back edge.
    for (var i = 0; i < 3; i++) {
      final t = 0.25 + i * 0.2;
      final n = Offset.lerp(spineNear, tip, t)!;
      canvas.drawLine(
        n,
        n - bladeSide * bodyWidth * 0.08 - shaftDir * bodyWidth * 0.03,
        Paint()
          ..color = const Color(0xFFD1C4E9)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }

    // Razor cutting edge.
    canvas.drawPath(
      Path()
        ..moveTo(throat.dx, throat.dy)
        ..quadraticBezierTo(belly.dx, belly.dy, tip.dx, tip.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, bodyWidth * 0.07)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawPath(
      Path()
        ..moveTo(throat.dx, throat.dy)
        ..quadraticBezierTo(belly.dx, belly.dy, tip.dx, tip.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, bodyWidth * 0.11)
        ..strokeCap = StrokeCap.round
        ..color = Color(0xFFEA80FC).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Blade outline.
    canvas.drawPath(
      blade,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = const Color(0xFFEDE7F6),
    );

    // Hanging soul chain / charms from the collar.
    var charm = collar + bladeSide * bodyWidth * 0.22 + shaftDir * bodyWidth * 0.12;
    for (var i = 0; i < 3; i++) {
      final next = charm +
          bladeSide * bodyWidth * 0.12 +
          shaftDir * bodyWidth * (0.16 + i * 0.02) +
          Offset(0, bodyWidth * 0.08 * math.sin(engine.gameTime * 5 + i));
      canvas.drawLine(
        charm,
        next,
        Paint()
          ..color = const Color(0xFFB0BEC5)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        next,
        bodyWidth * (0.05 + i * 0.01),
        Paint()
          ..color = i == 2
              ? Color(0xFFE040FB).withValues(alpha: 0.85)
              : const Color(0xFFCE93D8),
      );
      charm = next;
    }

    // Floating soul wisps near the blade tip.
    for (var i = 0; i < 4; i++) {
      final drift = engine.gameTime * (1.8 + i * 0.4) + i * 1.3;
      final wisp = tip -
          shaftDir * bodyWidth * (0.3 + i * 0.35) +
          bladeSide * bodyWidth * (0.2 * math.sin(drift)) -
          shaftDir * bodyWidth * (0.15 * math.cos(drift * 0.7));
      canvas.drawCircle(
        wisp,
        bodyWidth * (0.06 + 0.03 * math.sin(drift * 2)),
        Paint()
          ..color = Color(0xFFE1BEE7).withValues(alpha: 0.35 + pulse * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Motion smear / afterimage crescents while swinging.
    if (swingHard > 0.2 || engine.soulScytheSwinging) {
      for (var i = 1; i <= 3; i++) {
        final lag = swingAngle.sign * i * 0.12;
        final c = math.cos(swingAngle - lag);
        final s = math.sin(swingAngle - lag);
        final lagDir = Offset(
          aim.dx * c - aim.dy * s,
          aim.dx * s + aim.dy * c,
        );
        final lagSide = Offset(-lagDir.dy, lagDir.dx);
        final lagTip = grip +
            lagDir * length * 0.98 +
            lagSide * bodyWidth * 1.1 -
            lagDir * length * 1.0;
        canvas.drawLine(
          grip + lagDir * length * 0.55,
          lagTip,
          Paint()
            ..color = Color(0xFFB388FF).withValues(alpha: 0.18 / i)
            ..strokeWidth = math.max(2.0, bodyWidth * 0.12)
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  void _paintEquippedWeapon(
    Canvas canvas,
    Offset grip,
    Offset direction,
    double length,
    double bodyWidth,
    WeaponKind weapon,
  ) {
    final dir = direction.distance < 0.001
        ? const Offset(1, 0)
        : direction / direction.distance;
    final perp = Offset(-dir.dy, dir.dx);
    final tip = grip + dir * length;
    final body = weapon.bodyColor;
    final accent = weapon.color;
    final style = weapon.bodyStyle;
    final thick = math.max(
      2.4,
      bodyWidth *
          switch (style) {
            WeaponBodyStyle.minigun => 0.32,
            WeaponBodyStyle.launcher || WeaponBodyStyle.shotgun => 0.28,
            WeaponBodyStyle.sniper || WeaponBodyStyle.rifle => 0.2,
            WeaponBodyStyle.smg => 0.18,
            WeaponBodyStyle.pistol => 0.16,
            WeaponBodyStyle.bow => 0.14,
            WeaponBodyStyle.flamer => 0.26,
            WeaponBodyStyle.beam => 0.17,
            WeaponBodyStyle.exotic => 0.24,
          },
    );

    // Stock / rear.
    if (style == WeaponBodyStyle.rifle ||
        style == WeaponBodyStyle.sniper ||
        style == WeaponBodyStyle.shotgun ||
        style == WeaponBodyStyle.launcher) {
      final stock = grip - dir * (length * 0.28);
      canvas.drawLine(
        grip,
        stock + perp * bodyWidth * 0.12,
        Paint()
          ..color = const Color(0xFF4E342E)
          ..strokeWidth = thick * 0.85
          ..strokeCap = StrokeCap.round,
      );
    }

    // Main receiver / barrel.
    canvas.drawLine(
      grip,
      tip,
      Paint()
        ..color = body
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round,
    );
    // Rarity glow trim along the top.
    canvas.drawLine(
      grip + perp * (thick * 0.22),
      tip + perp * (thick * 0.22),
      Paint()
        ..color = accent.withValues(alpha: 0.85)
        ..strokeWidth = math.max(1.2, thick * 0.28)
        ..strokeCap = StrokeCap.round,
    );

    switch (style) {
      case WeaponBodyStyle.pistol:
        canvas.drawCircle(tip, thick * 0.55, Paint()..color = accent);
        // Mag well.
        canvas.drawLine(
          grip + dir * length * 0.2,
          grip + dir * length * 0.2 + Offset(0, thick * 0.9),
          Paint()
            ..color = const Color(0xFF37474F)
            ..strokeWidth = thick * 0.55
            ..strokeCap = StrokeCap.round,
        );
      case WeaponBodyStyle.smg:
        for (var i = 1; i <= 3; i++) {
          final p = grip + dir * (length * i / 4);
          canvas.drawCircle(p, thick * 0.28, Paint()..color = accent);
        }
        canvas.drawCircle(tip, thick * 0.45, Paint()..color = Colors.white70);
      case WeaponBodyStyle.rifle:
        // Handguard ridges.
        for (var i = 1; i <= 4; i++) {
          final p = grip + dir * (length * (0.25 + i * 0.12));
          canvas.drawLine(
            p - perp * thick * 0.35,
            p + perp * thick * 0.35,
            Paint()
              ..color = const Color(0xFF3E2723)
              ..strokeWidth = 1.4,
          );
        }
        canvas.drawCircle(tip, thick * 0.4, Paint()..color = accent);
      case WeaponBodyStyle.shotgun:
        // Dual barrels.
        canvas.drawLine(
          grip + perp * thick * 0.35,
          tip + perp * thick * 0.35,
          Paint()
            ..color = body
            ..strokeWidth = thick * 0.7
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          grip - perp * thick * 0.35,
          tip - perp * thick * 0.35,
          Paint()
            ..color = body
            ..strokeWidth = thick * 0.7
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(tip, thick * 0.5, Paint()..color = accent);
      case WeaponBodyStyle.sniper:
        // Scope.
        final scope = grip + dir * length * 0.45 + perp * thick * 0.55;
        canvas.drawCircle(scope, thick * 0.55, Paint()..color = accent);
        canvas.drawCircle(scope, thick * 0.28, Paint()..color = Colors.white70);
        canvas.drawLine(
          tip - dir * length * 0.15,
          tip,
          Paint()
            ..color = const Color(0xFF90A4AE)
            ..strokeWidth = thick * 0.45,
        );
        canvas.drawCircle(tip, thick * 0.35, Paint()..color = Colors.white);
      case WeaponBodyStyle.bow:
        final limb = length * 0.55;
        canvas.drawArc(
          Rect.fromCenter(center: grip + dir * length * 0.15, width: limb, height: limb * 1.1),
          -1.2,
          2.4,
          false,
          Paint()
            ..color = body
            ..style = PaintingStyle.stroke
            ..strokeWidth = thick * 0.7,
        );
        canvas.drawLine(
          grip,
          tip,
          Paint()
            ..color = accent
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(tip, 2.4, Paint()..color = Colors.white);
      case WeaponBodyStyle.flamer:
        final tank = grip - dir * length * 0.15 + Offset(0, thick * 0.4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: tank, width: thick * 1.6, height: thick * 1.8),
            Radius.circular(thick * 0.3),
          ),
          Paint()..color = const Color(0xFF455A64),
        );
        canvas.drawCircle(
          tip,
          thick * 0.7,
          Paint()
            ..color = accent.withValues(alpha: 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(tip, thick * 0.35, Paint()..color = const Color(0xFFFFE082));
      case WeaponBodyStyle.launcher:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(grip - perp * thick * 0.55, tip + perp * thick * 0.55),
            Radius.circular(thick * 0.4),
          ),
          Paint()..color = body,
        );
        canvas.drawCircle(tip, thick * 0.65, Paint()..color = accent);
        canvas.drawCircle(tip, thick * 0.3, Paint()..color = const Color(0xFFFFF59D));
      case WeaponBodyStyle.minigun:
        for (final side in [-0.55, 0.0, 0.55]) {
          canvas.drawLine(
            grip + perp * thick * side,
            tip + perp * thick * side * 0.6,
            Paint()
              ..color = body
              ..strokeWidth = thick * 0.45
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(tip, thick * 0.55, Paint()..color = accent);
      case WeaponBodyStyle.beam:
        canvas.drawLine(
          grip,
          tip,
          Paint()
            ..color = accent.withValues(alpha: 0.55)
            ..strokeWidth = thick * 1.1
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          tip,
          thick * 0.55,
          Paint()
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      case WeaponBodyStyle.exotic:
        canvas.drawCircle(
          grip + dir * length * 0.4,
          thick * 0.7,
          Paint()
            ..color = accent.withValues(alpha: 0.7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        for (final t in [0.25, 0.5, 0.75]) {
          canvas.drawCircle(
            grip + dir * length * t,
            thick * 0.28,
            Paint()..color = Colors.white70,
          );
        }
        canvas.drawCircle(tip, thick * 0.5, Paint()..color = accent);
    }
  }

  void _paintCrate(Canvas canvas, SupplyCrate crate) {
    _paintShadow(canvas, crate.position, 0.12);
    final ground = projection.project(crate.position);
    final center = projection.project(crate.position, crate.height * 0.56);
    final width = projection.scale * 0.1;
    final height = width * 0.68;
    final box = Rect.fromCenter(center: center, width: width, height: height);
    final rarityColor = crate.displayRarity.color;
    final rarityDark = Color.lerp(rarityColor, Colors.black, 0.45)!;
    final rarityLight = Color.lerp(rarityColor, Colors.white, 0.35)!;

    // Soft rarity beacon so drops read from farther away.
    canvas.drawCircle(
      ground,
      width * (crate.height > 0.12 ? 1.35 : 1.05),
      Paint()
        ..color = rarityColor.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    if (crate.height > 0.12) {
      final chuteCenter = center - Offset(0, width * 1.08);
      final chute = Rect.fromCenter(
        center: chuteCenter,
        width: width * 1.8,
        height: width * 0.75,
      );
      canvas.drawArc(
        chute,
        math.pi,
        math.pi,
        true,
        Paint()
          ..shader = LinearGradient(
            colors: [rarityLight, rarityColor, rarityDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(chute),
      );
      canvas.drawArc(
        chute,
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = rarityLight.withValues(alpha: 0.9),
      );
      final ropes = Paint()
        ..color = rarityLight.withValues(alpha: 0.75)
        ..strokeWidth = 1.2;
      canvas.drawLine(
          chuteCenter + Offset(-width * 0.88, 0), box.topLeft, ropes);
      canvas.drawLine(
          chuteCenter + Offset(width * 0.88, 0), box.topRight, ropes);
      canvas.drawLine(
        ground,
        center,
        Paint()..color = rarityColor.withValues(alpha: 0.28),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = rarityColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: [rarityLight, rarityColor, rarityDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(box),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = rarityDark,
    );
    final strap = Paint()
      ..color = rarityDark.withValues(alpha: 0.85)
      ..strokeWidth = 2.4;
    canvas.drawLine(box.topLeft, box.bottomRight, strap);
    canvas.drawLine(box.topRight, box.bottomLeft, strap);
  }

  void _paintTracers(Canvas canvas) {
    for (final tracer in engine.tracers) {
      final from = projection.project(tracer.from, 0.08);
      final to = projection.project(tracer.to, 0.05);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = tracer.color.withValues(alpha: 0.85)
          ..strokeWidth = tracer.strokeWidth
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      final dmg = tracer.damage;
      if (dmg == null) continue;
      final tip = Offset.lerp(from, to, 0.82)!;
      final label = TextPainter(
        text: TextSpan(
          text: '$dmg',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            shadows: [
              Shadow(color: tracer.color, blurRadius: 6),
              const Shadow(color: Colors.black87, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        tip - Offset(label.width / 2, label.height + 2),
      );
    }
  }

  void _paintDamageFloaters(Canvas canvas) {
    for (final floater in engine.damageFloaters) {
      final t = (floater.life / floater.maxLife).clamp(0.0, 1.0);
      final p = projection.project(floater.position, 0.22 + (1 - t) * 0.35);
      final text = floater.blocked ? 'BLOCK' : '${floater.amount}';
      final size = floater.blocked ? 11.0 : (12.0 + (floater.amount >= 80 ? 2 : 0));
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: floater.blocked
                ? const Color(0xFF90CAF9).withValues(alpha: 0.35 + t * 0.65)
                : Color.lerp(
                    Colors.white,
                    floater.color,
                    0.35,
                  )!.withValues(alpha: 0.25 + t * 0.75),
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        p - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  void _paintBlastFlashes(Canvas canvas) {
    for (final blast in engine.blastFlashes) {
      final p = projection.project(blast.position);
      final t = (blast.life / 0.28).clamp(0.0, 1.0);
      final r = blast.radius * projection.scale * (1.15 - t * 0.25);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 2.4, height: r),
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.85 * t),
              blast.color.withValues(alpha: 0.75 * t),
              blast.color.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCenter(center: p, width: r * 2.4, height: r),
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(center: p, width: r * 1.2, height: r * 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.7 * t),
      );
    }
  }

  void _paintZombiePointers(Canvas canvas, Size size) {
    if (engine.zombies.isEmpty || engine.zombies.length > 5) return;

    const margin = 34.0;
    final bounds = Rect.fromLTWH(
      margin,
      margin,
      size.width - margin * 2,
      size.height - margin * 2,
    );
    final from = projection.project(engine.player, 0.12);

    for (final zombie in engine.zombies) {
      final to = projection.project(zombie.position, 0.1);
      var delta = to - from;
      // Prefer short wrap direction on the isometric plane by using world delta.
      final worldDelta = _screenDeltaToward(zombie.position);
      if (worldDelta.distanceSquared > 1e-6) {
        delta = worldDelta;
      }
      if (delta.distanceSquared < 36) continue;
      final dir = delta / delta.distance;

      final onScreen = bounds.contains(to);
      // Skip if the zombie is clearly in view and close.
      if (onScreen && (to - from).distance < 110) continue;

      final tip = onScreen
          ? from + dir * math.min(78.0, (to - from).distance * 0.42)
          : _rayToRectEdge(from, dir, bounds);
      _drawHunterArrow(canvas, tip, dir, zombie.kind.color);
    }
  }

  /// Approximate screen-space direction from the player to [world], including wrap.
  Offset _screenDeltaToward(Offset world) {
    final dx = world.dx - engine.player.dx;
    final dy = world.dy - engine.player.dy;
    final span = SurvivalEngine.arenaHalf * 2;
    var wx = dx;
    var wy = dy;
    if (wx > SurvivalEngine.arenaHalf) wx -= span;
    if (wx < -SurvivalEngine.arenaHalf) wx += span;
    if (wy > SurvivalEngine.arenaHalf) wy -= span;
    if (wy < -SurvivalEngine.arenaHalf) wy += span;
    return Offset(
      (wx - wy) * projection.scale * 0.55,
      (wx + wy) * projection.scale * 0.28,
    );
  }

  Offset _rayToRectEdge(Offset origin, Offset dir, Rect bounds) {
    var t = double.infinity;
    if (dir.dx > 1e-6) {
      t = math.min(t, (bounds.right - origin.dx) / dir.dx);
    } else if (dir.dx < -1e-6) {
      t = math.min(t, (bounds.left - origin.dx) / dir.dx);
    }
    if (dir.dy > 1e-6) {
      t = math.min(t, (bounds.bottom - origin.dy) / dir.dy);
    } else if (dir.dy < -1e-6) {
      t = math.min(t, (bounds.top - origin.dy) / dir.dy);
    }
    if (!t.isFinite || t < 0) {
      return Offset(
        origin.dx.clamp(bounds.left, bounds.right),
        origin.dy.clamp(bounds.top, bounds.bottom),
      );
    }
    final hit = origin + dir * t;
    return Offset(
      hit.dx.clamp(bounds.left, bounds.right),
      hit.dy.clamp(bounds.top, bounds.bottom),
    );
  }

  void _drawHunterArrow(Canvas canvas, Offset tip, Offset dir, Color color) {
    final perp = Offset(-dir.dy, dir.dx);
    final base = tip - dir * 16;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + perp * 7).dx, (base + perp * 7).dy)
      ..lineTo((base - dir * 4).dx, (base - dir * 4).dy)
      ..lineTo((base - perp * 7).dx, (base - perp * 7).dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  void _paintCrosshair(Canvas canvas) {
    final preview = engine.aimPreview;
    final from = projection.project(engine.player, 0.12);
    final impact = projection.project(preview.impact, 0.06);
    final color = engine.weapon.color;
    final hitColor =
        preview.hitEnemy ? const Color(0xFFFF8A80) : color;

    // Aim laser to impact.
    canvas.drawLine(
      from,
      impact,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawLine(
      from,
      impact,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Spread fan for wide guns.
    final spread = engine.weapon.spread;
    if (spread > 0.04) {
      final dir = engine.aimDirection.distance > 0.001
          ? engine.aimDirection / engine.aimDirection.distance
          : const Offset(0, -1);
      for (final sign in [-1.0, 1.0]) {
        final ang = spread * 0.85 * sign;
        final cosA = math.cos(ang);
        final sinA = math.sin(ang);
        final spreadDir = Offset(
          dir.dx * cosA - dir.dy * sinA,
          dir.dx * sinA + dir.dy * cosA,
        );
        final edge = projection.project(
          engine.player + spreadDir * preview.along,
          0.04,
        );
        canvas.drawLine(
          from,
          edge,
          Paint()
            ..color = color.withValues(alpha: 0.2)
            ..strokeWidth = 1.1,
        );
      }
    }

    // Blast radius preview for launchers.
    if (preview.blastRadius > 0.01) {
      final w = preview.blastRadius * projection.scale * 2.2;
      final h = preview.blastRadius * projection.scale * 0.9;
      canvas.drawOval(
        Rect.fromCenter(center: impact, width: w, height: h),
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawOval(
        Rect.fromCenter(center: impact, width: w, height: h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = color.withValues(alpha: 0.55),
      );
    }

    // Impact reticle.
    final r = preview.hitEnemy ? 11.0 : 8.0;
    canvas.drawCircle(
      impact,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = hitColor.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      impact,
      2.4,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawLine(
      impact - Offset(r + 6, 0),
      impact - Offset(r * 0.45, 0),
      Paint()
        ..color = hitColor
        ..strokeWidth = 1.6,
    );
    canvas.drawLine(
      impact + Offset(r * 0.45, 0),
      impact + Offset(r + 6, 0),
      Paint()
        ..color = hitColor
        ..strokeWidth = 1.6,
    );
    canvas.drawLine(
      impact - Offset(0, r + 6),
      impact - Offset(0, r * 0.45),
      Paint()
        ..color = hitColor
        ..strokeWidth = 1.6,
    );
    canvas.drawLine(
      impact + Offset(0, r * 0.45),
      impact + Offset(0, r + 6),
      Paint()
        ..color = hitColor
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant SurvivalPainter oldDelegate) => true;
}

/// Allows click-drag scrolling with a mouse / trackpad (needed on Flutter web).
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  const _MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
