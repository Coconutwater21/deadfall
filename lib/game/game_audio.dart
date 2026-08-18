import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'weapon_catalog.dart';

/// One-shot cues fired from [SurvivalEngine] gameplay events.
enum AudioCue {
  shoot,
  hurt,
  kill,
  deathMiniBoss,
  deathBoss,
  reload,
  ability,
  explosion,
  wave,
  bossAlert,
  pickup,
  gameOver,
  ui,
}

/// Looping background tracks.
enum GameMusic {
  none,
  menu,
  combat,
  boss,
  /// Wave 10 Citadel / Apocalypse Lord siege theme.
  bossCitadel,
  /// Wave 20 Shadow Ronin apex theme.
  bossRonin,
  /// Wave 30 decade milestone.
  bossW30,
  /// Wave 40 decade milestone.
  bossW40,
  /// Wave 50+ decade milestones (escalating apex bed).
  bossW50,
}

/// Loads and plays Deadfall music + SFX via [audioplayers].
///
/// Audio is best-effort: if the iOS plugin fails to start, gameplay still runs
/// silently instead of taking the whole app down.
class GameAudio {
  GameAudio();

  /// Master bus levels. SFX intentionally sit well above BGM.
  static const _musicVol = 0.14;
  static const _sfxVol = 1.0;
  static const _pausedMusicMult = 0.18;

  AudioPlayer? _music;
  final List<AudioPlayer> _sfxPool = [];
  int _sfxIndex = 0;

  bool _ready = false;
  bool _failed = false;
  bool _muted = false;
  bool _musicEnabled = true;
  double _musicVolume = 1;
  double _sfxVolume = 1;
  bool _pausedDuck = false;
  GameMusic _current = GameMusic.none;
  DateTime _lastShoot = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHurt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get muted => _muted;
  bool get musicEnabled => _musicEnabled;
  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;
  GameMusic get currentMusic => _current;
  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready || _failed) return;
    try {
      // Avoid fighting other audio on iOS; also configures AVAudioSession.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: const AudioContextAndroid(),
        ),
      );

      final music = AudioPlayer(playerId: 'deadfall_music');
      await music.setReleaseMode(ReleaseMode.loop);
      await music.setVolume(_effectiveMusicVolume);
      _music = music;

      // Pool so overlapping gunshots / kills don't cut each other off.
      for (var i = 0; i < 6; i++) {
        final p = AudioPlayer(playerId: 'deadfall_sfx_$i');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(_effectiveSfxVolume);
        _sfxPool.add(p);
      }
      _ready = true;
    } catch (e, st) {
      _failed = true;
      _ready = false;
      debugPrint('GameAudio init failed (continuing muted): $e\n$st');
    }
  }

  void setMuted(bool value) {
    _muted = value;
    if (!_ready) return;
    _applyVolumes();
    _syncMusicPlayback();
  }

  void setMusicEnabled(bool value) {
    _musicEnabled = value;
    if (!_ready) return;
    _applyVolumes();
    _syncMusicPlayback();
  }

  void setMusicVolume(double value) {
    _musicVolume = value.clamp(0.0, 1.0);
    if (_ready) _applyVolumes();
  }

  void setSfxVolume(double value) {
    _sfxVolume = value.clamp(0.0, 1.0);
    if (_ready) _applyVolumes();
  }

  /// Softens BGM while pause / settings overlays are up.
  void setPausedDuck(bool duck) {
    if (_pausedDuck == duck) return;
    _pausedDuck = duck;
    if (_ready) _applyVolumes();
  }

  double get _effectiveMusicVolume => (!_musicEnabled || _muted)
      ? 0
      : _musicVol * _musicVolume * (_pausedDuck ? _pausedMusicMult : 1);

  double get _effectiveSfxVolume => _muted ? 0 : _sfxVol * _sfxVolume;

  void _applyVolumes() {
    final music = _music;
    if (music == null) return;
    music.setVolume(_effectiveMusicVolume);
    for (final p in _sfxPool) {
      p.setVolume(_effectiveSfxVolume);
    }
  }

  void _syncMusicPlayback() {
    final music = _music;
    if (music == null) return;
    if (_muted || !_musicEnabled || _current == GameMusic.none) {
      music.pause();
    } else if (music.state != PlayerState.playing) {
      music.resume();
    }
  }

  Future<void> setMusic(GameMusic track) async {
    if (_failed) return;
    if (!_ready) await init();
    if (!_ready) return;
    final music = _music;
    if (music == null) return;

    if (track == _current) {
      if (!_muted && _musicEnabled && track != GameMusic.none) {
        // Ensure playback after unmute / resume.
        final state = music.state;
        if (state != PlayerState.playing) {
          await music.resume();
        }
      }
      return;
    }
    _current = track;
    if (track == GameMusic.none) {
      await music.stop();
      return;
    }
    final path = switch (track) {
      GameMusic.menu => 'audio/music/menu_v3.mp3',
      GameMusic.combat => 'audio/music/combat_v3.mp3',
      GameMusic.boss => 'audio/music/boss_v3.mp3',
      GameMusic.bossCitadel => 'audio/music/boss_citadel_v3.mp3',
      GameMusic.bossRonin => 'audio/music/boss_ronin_v3.mp3',
      GameMusic.bossW30 => 'audio/music/boss_w30_v3.mp3',
      GameMusic.bossW40 => 'audio/music/boss_w40_v3.mp3',
      GameMusic.bossW50 => 'audio/music/boss_w50_v3.mp3',
      GameMusic.none => '',
    };
    try {
      await music.stop();
      await music.setReleaseMode(ReleaseMode.loop);
      await music.play(AssetSource(path));
      // Some platforms reset volume on play — re-assert after start.
      await music.setVolume(_effectiveMusicVolume);
      if (_muted || !_musicEnabled) await music.pause();
    } catch (e, st) {
      debugPrint('GameAudio setMusic($track) failed: $e\n$st');
    }
  }

  Future<void> play(AudioCue cue, {WeaponKind? weapon}) async {
    if (_failed) return;
    if (!_ready) await init();
    if (!_ready || _muted || _sfxPool.isEmpty) return;

    // Cap fire rate so full-auto doesn't exhaust the pool.
    if (cue == AudioCue.shoot) {
      final now = DateTime.now();
      // Allow denser fire for minigun-class weapons.
      final minGap = weapon == WeaponKind.minigun ||
              weapon == WeaponKind.smg ||
              weapon == WeaponKind.machinePistol ||
              weapon == WeaponKind.nailgun ||
              weapon == WeaponKind.shredder ||
              weapon == WeaponKind.arcCaster
          ? 40
          : 55;
      if (now.difference(_lastShoot).inMilliseconds < minGap) return;
      _lastShoot = now;
    }
    if (cue == AudioCue.hurt) {
      final now = DateTime.now();
      if (now.difference(_lastHurt).inMilliseconds < 180) return;
      _lastHurt = now;
    }

    final path = switch (cue) {
      AudioCue.shoot when weapon != null =>
        'audio/sfx/weapons/${weapon.name}.mp3',
      AudioCue.shoot => 'audio/sfx/shoot.mp3',
      AudioCue.hurt => 'audio/sfx/hurt.mp3',
      AudioCue.kill => 'audio/sfx/death.mp3',
      AudioCue.deathMiniBoss => 'audio/sfx/death_miniboss.mp3',
      AudioCue.deathBoss => 'audio/sfx/death_boss.mp3',
      AudioCue.reload => 'audio/sfx/reload.mp3',
      AudioCue.ability => 'audio/sfx/ability.mp3',
      AudioCue.explosion => 'audio/sfx/explosion.mp3',
      AudioCue.wave => 'audio/sfx/wave.mp3',
      AudioCue.bossAlert => 'audio/sfx/boss_alert.mp3',
      AudioCue.pickup => 'audio/sfx/pickup.mp3',
      AudioCue.gameOver => 'audio/sfx/game_over.mp3',
      AudioCue.ui => 'audio/sfx/ui.mp3',
    };

    final player = _sfxPool[_sfxIndex % _sfxPool.length];
    _sfxIndex++;
    try {
      await player.stop();
      await player.setVolume(_effectiveSfxVolume);
      await player.play(AssetSource(path));
    } catch (e, st) {
      debugPrint('GameAudio play($cue) failed: $e\n$st');
    }
  }

  Future<void> dispose() async {
    await _music?.dispose();
    _music = null;
    for (final p in _sfxPool) {
      await p.dispose();
    }
    _sfxPool.clear();
    _ready = false;
  }
}
