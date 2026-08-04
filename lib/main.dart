import 'package:flutter/material.dart';

import 'ui/survival_game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeadfallApp());
}

class DeadfallApp extends StatelessWidget {
  const DeadfallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deadfall: Zombie Survival',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A5B5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SurvivalGameScreen(),
    );
  }
}
