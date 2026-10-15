import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';

void main() {
  // A component theme that sets a bare TextStyle replaces the inherited one,
  // so its text falls back to the platform font instead of Hanken Grotesk.
  testWidgets('text in themed components uses Hanken Grotesk', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView(
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('elevated')),
            FilledButton(onPressed: () {}, child: const Text('filled')),
            TextButton(onPressed: () {}, child: const Text('text button')),
            OutlinedButton(onPressed: () {}, child: const Text('outlined')),
            ActionChip(label: const Text('chip'), onPressed: () {}),
            const ListTile(
              title: Text('tile title'),
              subtitle: Text('tile subtitle'),
            ),
            const TextField(decoration: InputDecoration(labelText: 'label')),
          ],
        ),
      ),
    ));

    for (final label in [
      'elevated',
      'filled',
      'text button',
      'outlined',
      'chip',
      'tile title',
      'tile subtitle',
      'label',
    ]) {
      final text = tester.widget<RichText>(find.descendant(
          of: find.text(label), matching: find.byType(RichText)));
      expect(text.text.style?.fontFamily, startsWith('HankenGrotesk'),
          reason: '"$label" is not in Hanken Grotesk');
    }
  });
}
