import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/android_core.dart';
import 'core/core.dart';
import 'core/fake_core.dart';
import 'desktop.dart';
import 'player/engine.dart';
import 'state/controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final exe = Platform.resolvedExecutable;
  final Core core;
  final demo = args.contains('--demo') || const bool.fromEnvironment('YMD_DEMO');
  if (!demo) MediaKitEngine.init();
  final AudioEngine engine = demo ? SilentEngine(tick: const Duration(milliseconds: 250)) : MediaKitEngine();
  if (demo) {
    core = FakeCore();
  } else if (Platform.isAndroid) {
    core = AndroidCore();
  } else {
    final path = Platform.environment['YMCORE'] ?? ProcessCore.beside(exe);
    core = path == null ? _MissingCore() : await ProcessCore.start(path);
  }
  runApp(YmdApp(controller: Controller(core, desktop: Desktop(args: args), engine: engine)));
}

class _MissingCore implements Core {
  @override
  Stream<Event> get events => Stream.value({
        'type': 'fatal',
        'message': 'ядро ymcore не найдено рядом с программой',
      });

  @override
  void send(Map<String, Object?> command) {}

  @override
  Future<void> close() async {}
}
