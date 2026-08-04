import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HighScoreEntry {
  HighScoreEntry({
    required this.wave,
    required this.kills,
    required this.money,
    required this.className,
    required this.at,
    this.playerName = 'Anonymous',
  });

  final int wave;
  final int kills;
  final int money;
  final String className;
  final DateTime at;
  final String playerName;

  int get score => wave * 1000 + kills * 10 + money;

  Map<String, dynamic> toJson() => {
        'wave': wave,
        'kills': kills,
        'money': money,
        'className': className,
        'at': at.toIso8601String(),
        'playerName': playerName,
      };

  factory HighScoreEntry.fromJson(Map<String, dynamic> json) {
    final rawName = (json['playerName'] as String?)?.trim() ?? '';
    return HighScoreEntry(
      wave: json['wave'] as int? ?? 0,
      kills: json['kills'] as int? ?? 0,
      money: json['money'] as int? ?? 0,
      className: json['className'] as String? ?? 'Survivor',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      playerName: rawName.isEmpty ? 'Anonymous' : rawName,
    );
  }

  HighScoreEntry copyWith({String? playerName}) => HighScoreEntry(
        wave: wave,
        kills: kills,
        money: money,
        className: className,
        at: at,
        playerName: playerName ?? this.playerName,
      );
}

/// Flavor titles for leaderboard placement (1 = best).
abstract final class LeaderboardRanks {
  static String titleForPlace(int place) {
    if (place <= 0) return 'Unknown';
    if (place <= _namedTitles.length) return _namedTitles[place - 1];
    if (place <= 30) return 'Survivor';
    if (place <= 40) return 'Recruit';
    return 'Rookie';
  }

  static const List<String> _namedTitles = [
    'Apex', // 1
    'Warlord', // 2
    'Champion', // 3
    'Vanguard', // 4
    'Dominator', // 5
    'Legend', // 6
    'Mythic', // 7
    'Ascendant', // 8
    'Elite', // 9
    'Ace', // 10
    'Paragon', // 11
    'Reaper', // 12
    'Slayer', // 13
    'Raider', // 14
    'Hunter', // 15
    'Veteran', // 16
    'Hardened', // 17
    'Operative', // 18
    'Scout', // 19
    'Contender', // 20
  ];

  static String blurbForPlace(int place) => switch (place) {
        1 => 'Top of the board',
        2 => 'Nearly untouchable',
        3 => 'Podium finisher',
        4 || 5 => 'Commanding the field',
        6 || 7 || 8 => 'Upper echelon',
        9 || 10 => 'Top-ten terror',
        _ when place <= 15 => 'Deep in the ranks',
        _ when place <= 20 => 'Proven fighter',
        _ when place <= 30 => 'Made a real dent',
        _ when place <= 40 => 'Climbing the board',
        _ => 'First foothold',
      };

  static bool isPodium(int place) => place >= 1 && place <= 3;

  /// Top-ten get a bit more flair in the UI.
  static bool isHighRank(int place) => place >= 1 && place <= 10;

  /// Where [score] would sit if inserted into a sorted [board] (1-based).
  static int placeForScore(int score, List<HighScoreEntry> board) {
    var place = 1;
    for (final entry in board) {
      if (score > entry.score) break;
      place++;
    }
    return place;
  }
}

class HighScoreStore {
  HighScoreStore._();
  static const _key = 'survival_high_scores_v1';
  /// Keep a deep local board so more runs earn a named rank.
  static const maxEntries = 50;
  static const maxNameLength = 16;

  static Future<List<HighScoreEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => HighScoreEntry.fromJson(
              jsonDecode(e) as Map<String, dynamic>,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  /// Whether [entry] would appear on the saved top board.
  static Future<bool> wouldQualify(HighScoreEntry entry) async {
    final list = await load();
    if (list.length < maxEntries) return true;
    return entry.score > list.last.score;
  }

  static String sanitizeName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'Anonymous';
    if (cleaned.length <= maxNameLength) return cleaned;
    return cleaned.substring(0, maxNameLength).trimRight();
  }

  static Future<List<HighScoreEntry>> record(HighScoreEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.add(entry);
    list.sort((a, b) => b.score.compareTo(a.score));
    final trimmed = list.take(maxEntries).toList();
    await prefs.setStringList(
      _key,
      trimmed.map((e) => jsonEncode(e.toJson())).toList(),
    );
    return trimmed;
  }
}
