import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remappable gameplay actions (class hotkeys stay on 1–0 / -).
enum GameAction {
  moveUp,
  moveDown,
  moveLeft,
  moveRight,
  fire,
  reload,
  ability,
  weaponPrev,
  weaponNext,
  cycleClass,
  upgradeWeapon,
  upgradeClass,
  upgradeAbility,
  pause,
}

extension GameActionLabel on GameAction {
  String get label => switch (this) {
        GameAction.moveUp => 'Move up',
        GameAction.moveDown => 'Move down',
        GameAction.moveLeft => 'Move left',
        GameAction.moveRight => 'Move right',
        GameAction.fire => 'Fire',
        GameAction.reload => 'Reload',
        GameAction.ability => 'Ability',
        GameAction.weaponPrev => 'Previous weapon',
        GameAction.weaponNext => 'Next weapon',
        GameAction.cycleClass => 'Cycle class',
        GameAction.upgradeWeapon => 'Upgrade gun',
        GameAction.upgradeClass => 'Upgrade class',
        GameAction.upgradeAbility => 'Upgrade ability',
        GameAction.pause => 'Pause',
      };
}

class KeybindSettings {
  KeybindSettings([Map<GameAction, LogicalKeyboardKey>? binds])
      : binds = Map<GameAction, LogicalKeyboardKey>.from(
          binds ?? defaultBinds,
        );

  final Map<GameAction, LogicalKeyboardKey> binds;

  static const Map<GameAction, LogicalKeyboardKey> defaultBinds = {
    GameAction.moveUp: LogicalKeyboardKey.keyW,
    GameAction.moveDown: LogicalKeyboardKey.keyS,
    GameAction.moveLeft: LogicalKeyboardKey.keyA,
    GameAction.moveRight: LogicalKeyboardKey.keyD,
    GameAction.fire: LogicalKeyboardKey.space,
    GameAction.reload: LogicalKeyboardKey.keyR,
    GameAction.ability: LogicalKeyboardKey.keyF,
    GameAction.weaponPrev: LogicalKeyboardKey.keyQ,
    GameAction.weaponNext: LogicalKeyboardKey.keyE,
    GameAction.cycleClass: LogicalKeyboardKey.keyC,
    GameAction.upgradeWeapon: LogicalKeyboardKey.keyU,
    GameAction.upgradeClass: LogicalKeyboardKey.keyT,
    GameAction.upgradeAbility: LogicalKeyboardKey.keyG,
    GameAction.pause: LogicalKeyboardKey.escape,
  };

  LogicalKeyboardKey keyFor(GameAction action) =>
      binds[action] ?? defaultBinds[action]!;

  /// Arrow keys always work for movement in addition to remapped binds.
  static bool _arrowMove(GameAction action, LogicalKeyboardKey key) =>
      switch (action) {
        GameAction.moveUp => key == LogicalKeyboardKey.arrowUp,
        GameAction.moveDown => key == LogicalKeyboardKey.arrowDown,
        GameAction.moveLeft => key == LogicalKeyboardKey.arrowLeft,
        GameAction.moveRight => key == LogicalKeyboardKey.arrowRight,
        _ => false,
      };

  bool isPressed(GameAction action, Set<LogicalKeyboardKey> down) {
    if (down.contains(keyFor(action))) return true;
    return down.any((key) => _arrowMove(action, key));
  }

  bool matches(GameAction action, LogicalKeyboardKey key) {
    if (keyFor(action) == key) return true;
    return _arrowMove(action, key);
  }

  /// Assign [key] to [action], swapping if another action already owns it.
  void rebind(GameAction action, LogicalKeyboardKey key) {
    GameAction? conflict;
    for (final other in GameAction.values) {
      if (other != action && binds[other] == key) {
        conflict = other;
        break;
      }
    }
    final previous = keyFor(action);
    binds[action] = key;
    if (conflict != null) {
      binds[conflict] = previous;
    }
  }

  void reset() {
    binds
      ..clear()
      ..addAll(defaultBinds);
  }

  KeybindSettings copy() => KeybindSettings(binds);

  static String labelForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    final label = key.keyLabel.trim();
    if (label.isNotEmpty) return label.toUpperCase();
    final debug = key.debugName ?? 'Key';
    return debug.replaceAll('Key ', '').replaceAll('Digit ', '');
  }

  static const _prefix = 'survival_binds_';

  static Future<KeybindSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = Map<GameAction, LogicalKeyboardKey>.from(defaultBinds);
    for (final action in GameAction.values) {
      final id = prefs.getInt('$_prefix${action.name}');
      if (id == null) continue;
      final key = LogicalKeyboardKey.findKeyByKeyId(id);
      if (key != null) loaded[action] = key;
    }
    return KeybindSettings(loaded);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final action in GameAction.values) {
      await prefs.setInt('$_prefix${action.name}', keyFor(action).keyId);
    }
  }
}
