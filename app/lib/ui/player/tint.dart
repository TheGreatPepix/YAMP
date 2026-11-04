import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets.dart';

const _ground = Color(0xFF0E0E12);
const _plain = Color(0xFF17171D);

final _dark = buildTheme(Brightness.dark);

final ThemeData playerTheme = () {
  final s = _dark.colorScheme;
  final white = Colors.white;
  return _dark.copyWith(
    colorScheme: s.copyWith(
      primary: white,
      onPrimary: _ground,
      primaryContainer: white.withValues(alpha: 0.14),
      surfaceContainerHigh: white.withValues(alpha: 0.10),
      surfaceContainerHighest: white.withValues(alpha: 0.16),
      surfaceContainerLow: Colors.black.withValues(alpha: 0.28),
      onSurfaceVariant: white.withValues(alpha: 0.72),
      outlineVariant: white.withValues(alpha: 0.10),
    ),
    sliderTheme: _dark.sliderTheme.copyWith(
      activeTrackColor: white,
      thumbColor: white,
      inactiveTrackColor: white.withValues(alpha: 0.22),
    ),
  );
}();

class CoverTint {
  static final _cache = <String, Color>{};
  static final _pending = <String, Future<Color?>>{};

  static Color? cached(String url) => _cache[url];

  static Future<Color?> resolve(String url) {
    if (url.isEmpty) return Future.value(null);
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);
    return _pending[url] ??= ColorScheme.fromImageProvider(
      provider: ResizeImage(NetworkImage(url), width: 112, height: 112),
      brightness: Brightness.dark,
    ).then<Color?>((s) {
      if (_cache.length > 64) _cache.clear();
      final c = Color.lerp(_ground, s.primaryContainer, 0.66)!;
      _cache[url] = c;
      return c;
    }).catchError((Object _) => null).whenComplete(() => _pending.remove(url));
  }
}

const _dim = 0.3;
const _vivid = 1.5;

List<double> _ambientMatrix() {
  final r = (1 - _vivid) * 0.2126, g = (1 - _vivid) * 0.7152, b = (1 - _vivid) * 0.0722;
  return [
    (r + _vivid) * _dim, g * _dim, b * _dim, 0, 0,
    r * _dim, (g + _vivid) * _dim, b * _dim, 0, 0,
    r * _dim, g * _dim, (b + _vivid) * _dim, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

final _ambient = ColorFilter.matrix(_ambientMatrix());

class PlayerBackdrop extends StatefulWidget {
  const PlayerBackdrop({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  State<PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<PlayerBackdrop> {
  late Color _color = CoverTint.cached(widget.url) ?? _plain;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PlayerBackdrop old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    if (url.isEmpty) {
      _color = _plain;
      return;
    }
    CoverTint.resolve(url).then((c) {
      if (!mounted || widget.url != url) return;
      setState(() => _color = c ?? _plain);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final fade = motion(context, const Duration(milliseconds: 700));
    return AnimatedContainer(
      duration: fade,
      curve: Curves.easeOut,
      color: _color,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedSwitcher(
              duration: fade,
              child: url.isEmpty
                  ? const SizedBox.expand()
                  : SizedBox.expand(
                      key: ValueKey(url),
                      child: ClipRect(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.mirror),
                          child: ColorFiltered(
                            colorFilter: _ambient,
                            child: Transform.scale(
                              scale: 1.3,
                              child: Image(
                                image: ResizeImage(NetworkImage(url), width: 48, height: 48),
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x1A000000), Color(0x33000000), Color(0x80000000)],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          Material(type: MaterialType.transparency, child: widget.child),
        ],
      ),
    );
  }
}
