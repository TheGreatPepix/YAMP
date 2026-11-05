import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:yamp/core/core.dart';
import 'package:yamp/core/fake_core.dart';
import 'package:yamp/core/fake_remote.dart';
import 'package:yamp/player/engine.dart';
import 'package:yamp/state/controller.dart';
import 'package:yamp/state/remote.dart';
import 'package:yamp/theme.dart';
import 'package:yamp/ui/remote_page.dart';
import 'package:yamp/ui/settings_dialog.dart';

class _ScriptCore implements Core {
  final _events = StreamController<Event>();
  final sent = <Map<String, Object?>>[];

  void push(Event e) => _events.add(e);

  @override
  Stream<Event> get events => _events.stream;

  Map<String, Object?> get lastPosition => sent.lastWhere((c) => c['cmd'] == 'playerPosition');

  @override
  void send(Map<String, Object?> command) => sent.add(command);

  @override
  Future<void> close() => _events.close();
}

Widget _app(Widget home) => MaterialApp(theme: buildTheme(Brightness.dark), home: home);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  test('пульт: позиция идёт сама, чужие события и громкость под пальцем', () {
    var now = DateTime(2026, 11, 5, 12);
    final sent = <Map<String, Object?>>[];
    final r = RemoteState(sent.add, clock: () => now);
    addTearDown(r.dispose);

    r.receive({
      'type': 'remoteDevices',
      'devices': [
        {'id': 'pc', 'name': 'Комп', 'paired': true, 'online': true},
      ],
    });
    r.connect(r.devices.single);
    expect(r.status, LinkStatus.connecting);
    r.togglePlay();
    expect(sent.where((c) => c['cmd'] == 'remoteSend'), isEmpty, reason: 'без связи команды не уходят');

    r.receive({'type': 'remoteLink', 'id': 'pc', 'name': 'Комп', 'status': 'online'});
    r.receive({
      'type': 'remoteEvent',
      'id': 'pc',
      'event': {
        'type': 'player',
        'track': {'id': 'a', 'title': 'A', 'durationMs': 100000},
        'volume': 0.5,
      },
    });
    r.receive({
      'type': 'remoteEvent',
      'id': 'pc',
      'event': {'type': 'playback', 'track': 'a', 'playing': true, 'position': 10, 'volume': 0.5},
    });
    now = now.add(const Duration(seconds: 3));
    expect(r.at, const Duration(seconds: 13));
    now = now.add(const Duration(minutes: 5));
    expect(r.at, const Duration(seconds: 100), reason: 'позиция не уходит за длину трека');

    r.receive({
      'type': 'remoteEvent',
      'id': 'other',
      'event': {
        'type': 'player',
        'track': {'id': 'z'},
      },
    });
    expect(r.track?.id, 'a');

    r.togglePlay();
    expect(r.playing, isFalse);
    expect(sent.last, {
      'cmd': 'remoteSend',
      'command': {'cmd': 'pause'},
    });

    r.setVolume(0.2);
    r.setVolume(0.25);
    r.setVolume(0.3, done: true);
    final volumes = [
      for (final c in sent)
        if ((c['command'] as Map?)?['cmd'] == 'volume') (c['command'] as Map)['volume'],
    ];
    expect(volumes, [0.2, 0.3]);
    r.receive({
      'type': 'remoteEvent',
      'id': 'pc',
      'event': {'type': 'playback', 'track': 'a', 'playing': false, 'position': 20, 'volume': 0.9},
    });
    expect(r.volume, 0.3, reason: 'пока палец на ползунке, старое значение с компьютера не дёргает его');
    now = now.add(const Duration(seconds: 2));
    r.receive({
      'type': 'remoteEvent',
      'id': 'pc',
      'event': {'type': 'playback', 'track': 'a', 'playing': false, 'position': 20, 'volume': 0.3},
    });
    expect(r.at, const Duration(seconds: 20));

    r.receive({
      'type': 'remoteEvent',
      'id': 'pc',
      'event': {
        'type': 'player',
        'track': {'id': 'b', 'durationMs': 90000},
      },
    });
    expect(r.at, Duration.zero, reason: 'новый трек начинается с нуля');

    r.receive({
      'type': 'remoteLink',
      'id': 'pc',
      'status': 'failed',
      'message': 'Компьютер больше не узнаёт этот телефон',
    });
    expect(r.connected, isFalse);
    expect(r.linkMessage, contains('не узнаёт'));
  });

  test('компьютер выполняет команды пульта и сообщает, играет ли он', () async {
    final core = _ScriptCore();
    final engine = SilentEngine();
    final c = Controller(core, engine: engine);
    addTearDown(c.dispose);

    core.push({
      'type': 'player',
      'action': 'play',
      'track': {'id': '1', 'title': 'Ветер', 'durationMs': 300000},
      'url': 'http://127.0.0.1/1',
      'volume': 0.8,
    });
    await Future<void>.delayed(Duration.zero);
    expect(engine.isPlaying, isTrue);
    expect(core.lastPosition, {'cmd': 'playerPosition', 'track': '1', 'position': 0.0, 'playing': true});

    core.push({'type': 'remote', 'action': 'pause'});
    await Future<void>.delayed(Duration.zero);
    expect(engine.isPlaying, isFalse);
    expect(core.lastPosition, {'cmd': 'playerPosition', 'track': '1', 'position': 0.0, 'playing': false, 'on': true});

    core.push({'type': 'remote', 'action': 'seek', 'position': 30.5});
    await Future<void>.delayed(Duration.zero);
    expect(engine.at, const Duration(milliseconds: 30500));
    expect(core.lastPosition, {'cmd': 'playerPosition', 'track': '1', 'position': 30.5, 'playing': false});

    core.push({'type': 'remote', 'action': 'resume'});
    await Future<void>.delayed(Duration.zero);
    expect(engine.isPlaying, isTrue);
    expect(core.lastPosition['playing'], isTrue);

    core.push({'type': 'remote', 'action': 'volume', 'volume': 0.25});
    await Future<void>.delayed(Duration.zero);
    expect(engine.volume, 0.25);
    expect(core.sent.last, {'cmd': 'playerVolume', 'volume': 0.25});
  });

  testWidgets('телефон: связывание по QR и управление компьютером', (tester) async {
    _size(tester, const Size(400, 860));
    final core = FakeCore();
    final c = Controller(core);
    await tester.pumpWidget(_app(RemotePage(c: c, scanner: (_) async => fakePairLink)));
    await _settle(tester);

    expect(find.text('Рядом в сети'), findsOneWidget);
    expect(find.text(FakeRemote.pcName), findsOneWidget);

    await tester.tap(find.text('Сканировать QR-код'));
    await _settle(tester);
    expect(find.text('Ветер'), findsWidgets);
    expect(find.text(FakeRemote.pcName), findsOneWidget);

    await tester.tap(find.byTooltip('Пауза'));
    await _settle(tester);
    expect(core.remote.sent.last, {'cmd': 'pause'});
    expect(find.byTooltip('Слушать'), findsOneWidget);

    await tester.tap(find.byTooltip('Следующий трек'));
    await _settle(tester);
    expect(core.remote.sent.last, {'cmd': 'playerNext', 'track': 'r1'});
    expect(find.text('Перемен'), findsWidgets);

    await tester.tap(find.byTooltip('Мне нравится'));
    await _settle(tester);
    expect(find.byTooltip('Убрать из «Мне нравится»'), findsOneWidget);

    await tester.tap(find.byTooltip('Отключиться'));
    await _settle(tester);
    expect(find.text('Связанные компьютеры'), findsOneWidget);

    await tester.tap(find.text(FakeRemote.pcName));
    await _settle(tester);
    expect(find.byTooltip('Отключиться'), findsOneWidget);

    await tester.tap(find.byTooltip('Отключиться'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Отвязать'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Отвязать'));
    await _settle(tester);
    expect(find.text('Связанные компьютеры'), findsNothing);
    expect(find.text('Рядом в сети'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('экран пульта помещается на узких и низких телефонах', (tester) async {
    final core = FakeCore();
    final c = Controller(core);
    for (final size in const [Size(320, 560), Size(360, 740), Size(412, 915), Size(800, 400)]) {
      _size(tester, size);
      await tester.pumpWidget(_app(RemotePage(c: c, scanner: (_) async => fakePairLink)));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'список компьютеров на $size');
      await tester.tap(find.text('Сканировать QR-код'));
      await _settle(tester);
      expect(find.byTooltip('Отключиться'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'пульт на $size');
      await tester.tap(find.byTooltip('Отключиться'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Отвязать'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Отвязать'));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    }
    c.dispose();
  });

  testWidgets('компьютер: QR-код в настройках и список связанных телефонов', (tester) async {
    _size(tester, const Size(1280, 860));
    final core = FakeCore();
    final c = Controller(core);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showSettingsDialog(context, c), child: const Text('Настройки')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Настройки'));
    await _settle(tester);
    await tester.tap(find.text('Пульт с телефона'));
    await _settle(tester);
    expect(find.text('Пока ни одного. Без связывания компьютер не принимает команды ни от кого.'), findsOneWidget);

    await tester.tap(find.text('Показать QR-код'));
    await _settle(tester);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('действует ещё'), findsOneWidget);

    core.remote.pairPhone('Pixel 9');
    await _settle(tester);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('Подключён сейчас'), findsOneWidget);

    await tester.tap(find.text('Отвязать'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Отвязать'));
    await _settle(tester);
    expect(find.text('Pixel 9'), findsNothing);
    expect(core.remote.phones, isEmpty);

    await tester.tap(find.text('Показать QR-код'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Закрыть'));
    await _settle(tester);
    expect(find.byType(QrImageView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
