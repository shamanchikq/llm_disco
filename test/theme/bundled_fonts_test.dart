import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(AppTheme.useBundledFonts);

  test('every font the theme requests loads from the bundle', () async {
    // With runtime fetching off, a variant that isn't under
    // assets/google_fonts/ makes its load (and so pendingFonts) throw.
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    AppTheme.dark;
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      AppTheme.display(fontWeight: weight);
    }
    AppTheme.mono();

    await expectLater(GoogleFonts.pendingFonts(), completes);
  });

  test('a weight that is not bundled is caught in debug builds', () {
    expect(() => AppTheme.display(fontWeight: FontWeight.w300),
        throwsAssertionError);
    expect(() => AppTheme.mono(fontWeight: FontWeight.w700),
        throwsAssertionError);
  });

  test('the font licences are registered', () async {
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();

    expect(packages, containsAll(['Hanken Grotesk', 'JetBrains Mono']));
  });
}
