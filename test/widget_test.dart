import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deadfall/main.dart';

void main() {
  testWidgets('App launches the zombie survival arena', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpWidget(const DeadfallApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Pistol'), findsWidgets);
    expect(find.textContaining('WASD moves'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.textContaining('Survivor'), findsWidgets);
  });
}
