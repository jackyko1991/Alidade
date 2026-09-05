import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

/// Dim red preserves night-adapted vision far better than white/amber — the
/// classic "red flashlight" astronomer's trick. Shared by the app theme, the
/// overlay markers, and the toggle swatches so everything switches to
/// exactly the same red at once, not several different reds.
const nightModeColor = Color(0xFFB33A3A);

/// A darker variant of [nightModeColor] for secondary/subtitle text and
/// borders (history rows, settings hints) — real solid pixels blended
/// toward black, not alpha transparency (which would pick up whatever's
/// behind it instead of reliably reading as "the same red, but darker").
/// Kept as an explicit, directly-applied color rather than trusting
/// Material's theme-derived roles (ColorScheme.onSurfaceVariant,
/// ListTileTheme, ...): those didn't reliably cascade to every widget in
/// practice, leaving some secondary text/borders still close to white.
final dimNightModeColor = Color.lerp(const Color(0xFF000000), nightModeColor, 0.6)!;

/// Whether the red-on-black "preserve your night vision" theme is active.
/// A bare [ValueNotifier] (rather than routing through [SolveScreen]'s own
/// state) so the toggle button and [AlidadeApp]'s theme can both react to it
/// without passing a callback down through the widget tree.
class NightMode {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static const _key = 'night_mode_v1';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? false;
  }

  static Future<void> toggle() async {
    enabled.value = !enabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled.value);
  }
}
