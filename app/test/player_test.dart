import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ymd/app.dart';
import 'package:ymd/core/fake_core.dart';
import 'package:ymd/core/fake_player.dart';
import 'package:ymd/player/engine.dart';
import 'package:ymd/state/controller.dart';
import 'package:ymd/state/player.dart';
import 'package:ymd/ui/player/artist_view.dart';
import 'package:ymd/ui/player/controls.dart';
import 'package:ymd/ui/player/library_view.dart';
import 'package:ymd/ui/player/now_playing.dart';
import 'package:ymd/ui/search_view.dart';

Future<(FakeCore, Controller, SilentEngine)> _open(WidgetTester tester, {Size size = const Size(1280, 860)}) async {
  tester.view.physicalSize = const Size(1280, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final core = FakeCore();
  final engine = SilentEngine();
  final c = Controller(core, engine: engine);
  await tester.pumpWidget(YmdApp(controller: c));
  await tester.pumpAndSettle();
  final manual = find.text('Вставить токен вручную');
  if (manual.evaluate().isNotEmpty) {
    await tester.tap(manual);
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), 'good-token');
  await tester.pump();
  await tester.tap(find.text('Войти'));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
  return (core, c, engine);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Finder _tip(String message) => find.byTooltip(message);

Finder _link(String text) => find.byWidgetPredicate(
  (w) =>
      w is LinkText &&
      w.onOpen != null &&
      w.parts.any((p) => p.source.isNotEmpty) &&
      w.parts.map((p) => p.text).join() == text,
);

Finder _panel(Finder f) => find.descendant(of: find.byType(NowPlaying), matching: f).first;

Future<void> _tapLink(WidgetTester tester, Finder f) => tester.tapAt(tester.getTopLeft(f) + const Offset(8, 8));

void main() {
  testWidgets('слушать: библиотека, волна, лайк, переходы и конец трека', (tester) async {
    final (core, c, engine) = await _open(tester);

    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    expect(c.section.value, Section.listen);
    expect(find.text('Моя волна'), findsOneWidget);
    expect(find.text('Мне нравится'), findsWidgets);
    expect(find.text('Дорога'), findsOneWidget);
    expect(find.text('2 трека'), findsWidgets);

    await tester.tap(find.text('Моя волна'));
    await _settle(tester);
    final first = c.player.track!;
    expect(core.player.started, isEmpty);
    engine.progress(const Duration(milliseconds: 500));
    expect(c.player.wave, isTrue);
    expect(engine.url, contains('fake://track/${first.id}'));
    expect(engine.isPlaying, isTrue);
    expect(core.player.started, [first.id]);
    expect(_tip('Пауза'), findsOneWidget);
    expect(_tip('Не рекомендовать'), findsOneWidget);
    expect(_tip('Перемешать'), findsNothing);

    await tester.tap(_tip('Мне нравится').first);
    await _settle(tester);
    expect(c.player.liked(c.player.track!), isTrue);
    expect(_tip('Убрать из «Мне нравится»'), findsWidgets);

    engine.finish();
    await _settle(tester);
    expect(core.player.ended, [first.id]);
    expect(c.player.track!.id, isNot(first.id));

    final second = c.player.track!.id;
    await tester.tap(_tip('Не рекомендовать'));
    await _settle(tester);
    expect(c.player.track!.id, isNot(second));

    await tester.tap(_tip('Пауза'));
    await _settle(tester);
    expect(engine.isPlaying, isFalse);
    expect(_tip('Слушать'), findsOneWidget);

    await core.close();
  });

  testWidgets('плейлист: запуск трека, повтор, качество, панель плеера и Esc', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);

    await tester.tap(find.text('Дорога'));
    await _settle(tester);
    expect(find.text('ПЛЕЙЛИСТ'), findsOneWidget);
    expect(find.text('8 треков · 36 мин'), findsOneWidget);
    expect(find.text('Недоступен в каталоге'), findsOneWidget);

    await tester.tap(find.text('Кукушка'));
    await _settle(tester);
    expect(c.player.track!.title, 'Кукушка');
    expect(c.player.source!.id, fakePlaylist);
    expect(find.text('Пауза'), findsOneWidget);

    await tester.tap(_tip('Повтор выключен'));
    await _settle(tester);
    expect(c.player.repeat, Repeat.all);
    await tester.tap(_tip('Повтор всех треков'));
    await _settle(tester);
    expect(c.player.repeat, Repeat.one);
    engine.finish();
    await _settle(tester);
    expect(c.player.track!.title, 'Кукушка');

    await tester.tap(_tip('Следующий трек').first);
    await _settle(tester);
    expect(c.player.track!.title, 'Группа крови');

    await tester.tap(find.text('FLAC'));
    await _settle(tester);
    await tester.tap(find.text('Экономия трафика').last);
    await _settle(tester);
    expect(c.player.quality, PlayQuality.low);
    expect(engine.url, endsWith('q=low'));
    expect(find.text('MP3 192'), findsOneWidget);

    await tester.tap(_tip('Открыть плеер и очередь'));
    await _settle(tester);
    expect(find.text('Сейчас играет'), findsOneWidget);
    expect(find.text('Очередь'), findsOneWidget);
    expect(find.text('3 из 7'), findsOneWidget);
    final inPanel = find.descendant(of: find.byType(NowPlaying), matching: find.text('Перемен'));
    await tester.scrollUntilVisible(
      inPanel,
      100,
      scrollable: find.descendant(of: find.byType(NowPlaying), matching: find.byType(Scrollable)).last,
    );
    await tester.tap(inPanel);
    await _settle(tester);
    expect(c.player.track!.title, 'Перемен');
    expect(find.text('6 из 7'), findsOneWidget);
    expect(find.text('Кукушка'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Сейчас играет'), findsNothing);

    await core.close();
  });

  testWidgets('горячие клавиши: пробел, Ctrl+стрелки и медиаклавиши', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    await tester.tap(find.text('Дорога'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Слушать'));
    await _settle(tester);
    expect(c.player.track!.title, 'Звезда по имени Солнце');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.isPlaying, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(engine.isPlaying, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _settle(tester);
    expect(c.player.track!.title, 'Кукушка');

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.isPlaying, isTrue);

    await core.close();
  });

  testWidgets('пустой плейлист предлагает Мою волну', (tester) async {
    final (core, c, _) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    await tester.tap(find.text('Пустой'));
    await _settle(tester);
    expect(find.text('В этом плейлисте пока нет треков'), findsOneWidget);
    await tester.tap(find.text('Включить Мою волну'));
    await _settle(tester);
    expect(c.player.wave, isTrue);
    expect(c.player.hasTrack, isTrue);
    await core.close();
  });

  for (final size in const [Size(360, 760), Size(320, 640)]) {
    testWidgets('телефон ${size.width.round()}: навигация снизу, мини-плеер и полный экран', (tester) async {
      final (core, c, _) = await _open(tester, size: size);

      await tester.tap(find.text('Слушать'));
      await _settle(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Моя волна'));
      await _settle(tester);
      expect(c.player.hasTrack, isTrue);

      await tester.tap(find.bySemanticsLabel(RegExp('^Открыть плеер')).first);
      await _settle(tester);
      expect(find.text('Сейчас играет'), findsOneWidget);
      expect(_tip('Свернуть плеер'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(popped, isTrue);
      expect(find.text('Сейчас играет'), findsNothing);

      await tester.tap(find.text('Мне нравится'));
      await _settle(tester);
      expect(_tip('К библиотеке'), findsOneWidget);
      await tester.tap(_tip('К библиотеке'));
      await _settle(tester);

      await tester.tap(find.text('Скачать'));
      await _settle(tester);
      expect(c.section.value, Section.download);
      expect(find.bySemanticsLabel(RegExp('^Открыть плеер')), findsWidgets);

      await core.close();
    });
  }

  testWidgets('трек из поиска можно сразу послушать', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.enterText(find.byType(TextField), 'кино');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(c.search.open, isTrue);
    await tester.tap(_tip('Слушать').first);
    await _settle(tester);
    expect(c.player.hasTrack, isTrue);
    expect(engine.isPlaying, isTrue);
    expect(c.drafts.value, isEmpty);
    await core.close();
  });

  testWidgets('ошибки: три подряд останавливают плеер, ошибка посреди трека не перескакивает', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    await tester.tap(find.text('Дорога'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Слушать'));
    await _settle(tester);

    final first = c.player.track!.id;
    engine.progress(const Duration(seconds: 1));
    engine.progress(const Duration(seconds: 9));
    engine.fail('decoder glitch');
    await _settle(tester);
    expect(core.player.failed, isEmpty);
    expect(c.player.track!.id, first);

    await tester.tap(_tip('Следующий трек').first);
    await _settle(tester);
    for (var i = 0; i < 3; i++) {
      engine.fail('HTTP 404');
      engine.fail('HTTP 404 again');
      await _settle(tester);
    }
    expect(core.player.failed, hasLength(3));
    expect(find.text('Не удаётся воспроизвести треки'), findsOneWidget);
    engine.fail('HTTP 404');
    await _settle(tester);
    expect(core.player.failed, hasLength(3));
    await core.close();
  });

  testWidgets('поиск в разделе Слушать: трек играет, исполнитель и альбом открываются страницами', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'кино');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Война'));
    await _settle(tester);
    expect(c.drafts.value, isEmpty);
    expect(c.player.hasTrack, isTrue);
    expect(engine.isPlaying, isTrue);

    await tester.tap(find.byType(BestCard));
    await _settle(tester);
    expect(c.search.open, isFalse);
    expect(find.text('ИСПОЛНИТЕЛЬ'), findsOneWidget);
    expect(find.text('Популярные треки'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1988 · Альбом'), 200, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('1988 · Альбом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1988 · Альбом'));
    await _settle(tester);
    expect(find.text('АЛЬБОМ'), findsOneWidget);
    expect(find.textContaining('Кино · 1988'), findsOneWidget);

    await tester.tap(find.text('Перемен'));
    await _settle(tester);
    expect(c.player.track!.title, 'Перемен');
    expect(c.player.source!.kind, 'album');

    await tester.tap(find.text('Назад'));
    await _settle(tester);
    expect(c.player.browse.value, contains('/artist/'));
    expect(find.byType(AlbumCard), findsWidgets);
    await tester.tap(find.text('Дорога'));
    await _settle(tester);
    expect(find.text('Назад'), findsNothing);
    expect(c.drafts.value, isEmpty);
    await core.close();
  });

  testWidgets('из плеера: исполнитель, альбом и источник открываются страницами', (tester) async {
    final (core, c, _) = await _open(tester);
    c.player.play(fakePlaylist);
    await _settle(tester);
    expect(c.player.track!.title, 'Звезда по имени Солнце');
    expect(c.section.value, Section.download);

    c.player.panelOpen.value = true;
    await _settle(tester);
    await _tapLink(tester, _panel(_link('Кино')));
    await _settle(tester);
    expect(c.player.panelOpen.value, isFalse);
    expect(c.section.value, Section.listen);
    expect(c.player.browse.value, fakeArtist('Кино'));
    expect(find.text('ИСПОЛНИТЕЛЬ'), findsOneWidget);
    expect(find.text('Назад'), findsNothing);

    c.player.panelOpen.value = true;
    await _settle(tester);
    await _tapLink(tester, _panel(_link('Звезда по имени Солнце')));
    await _settle(tester);
    expect(c.player.panelOpen.value, isFalse);
    expect(c.player.browse.value, fakeAlbum);
    expect(find.text('АЛЬБОМ'), findsOneWidget);
    expect(find.text('Назад'), findsOneWidget);
    expect(_link('Кино · 1988 · 8 треков · 36 мин'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(TrackRow), matching: _tip('Ещё')).first);
    await _settle(tester);
    expect(find.text('Перейти к альбому'), findsNothing);
    await tester.tap(find.text('Перейти к исполнителю'));
    await _settle(tester);
    expect(c.player.browse.value, fakeArtist('Кино'));

    c.player.panelOpen.value = true;
    await _settle(tester);
    await tester.tap(_panel(_tip('Ещё')));
    await _settle(tester);
    await tester.tap(find.text('Перейти к альбому'));
    await _settle(tester);
    expect(c.player.browse.value, fakeAlbum);

    c.player.panelOpen.value = true;
    await _settle(tester);
    await _tapLink(tester, _panel(_link('Дорога')));
    await _settle(tester);
    expect(c.player.browse.value, fakePlaylist);
    expect(find.text('ПЛЕЙЛИСТ'), findsOneWidget);

    await _tapLink(tester, find.descendant(of: find.byType(TrackRow), matching: _link('Аквариум')).first);
    await _settle(tester);
    expect(c.player.browse.value, fakeArtist('Аквариум'));
    await tester.tap(find.text('Назад'));
    await _settle(tester);
    expect(c.player.browse.value, fakePlaylist);
    await core.close();
  });

  testWidgets('страница исполнителя: сетка популярных, все треки, релизы по разделам', (tester) async {
    final (core, c, _) = await _open(tester);
    final kino = fakeArtist('Кино');
    c.openPage(kino);
    await _settle(tester);
    expect(find.text('ИСПОЛНИТЕЛЬ'), findsOneWidget);
    expect(find.text('3 альбома · 1 сингл · 1 сборник'), findsOneWidget);
    expect(find.byType(TrackRow), findsNWidgets(6));
    expect(_link('Кино'), findsNothing);

    await tester.tap(find.byType(TrackRow).at(1));
    await _settle(tester);
    expect(c.player.source!.id, kino);
    expect(c.player.track!.title, 'Кукушка');

    await tester.tap(find.text('Все треки'));
    await _settle(tester);
    expect(c.player.browse.value, topTracksOf(kino));
    expect(find.text('ПОПУЛЯРНЫЕ ТРЕКИ'), findsOneWidget);
    expect(find.text('Альбомы'), findsNothing);
    await tester.scrollUntilVisible(find.text('Танец на цыпочках'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Танец на цыпочках'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Назад'));
    await _settle(tester);
    expect(c.player.browse.value, kino);

    final scroll = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Сборники'), 200, scrollable: scroll);
    expect(find.text('Синглы и EP'), findsOneWidget);
    final cards = tester.widgetList<AlbumCard>(find.byType(AlbumCard)).map((w) => w.album.title).toList();
    expect(cards, ['Чёрный альбом', 'Звезда по имени Солнце', 'Группа крови', 'Кукушка', 'Последний герой']);
    await tester.tap(find.byType(AlbumCard).first);
    await _settle(tester);
    expect(c.player.browse.value, 'https://music.yandex.ru/album/13');
    await core.close();
  });

  testWidgets('страница исполнителя на телефоне: три популярных трека', (tester) async {
    final (core, c, _) = await _open(tester, size: const Size(380, 800));
    c.openPage(fakeArtist('Кино'));
    await _settle(tester);
    expect(find.byType(TrackRow), findsNWidgets(3));
    expect(find.text('Все треки'), findsOneWidget);
    await core.close();
  });

  testWidgets('очередь в плеере: исполнитель открывается, название переключает трек', (tester) async {
    final (core, c, _) = await _open(tester);
    c.player.play(fakePlaylist);
    await _settle(tester);
    c.player.panelOpen.value = true;
    await _settle(tester);
    final row = find.descendant(of: find.byType(QueueRow), matching: _link('Аквариум'));
    await _tapLink(tester, row);
    await _settle(tester);
    expect(c.player.panelOpen.value, isFalse);
    expect(c.player.browse.value, fakeArtist('Аквариум'));
    expect(find.text('Аквариум'), findsWidgets);
    expect(c.player.track!.title, 'Звезда по имени Солнце');
    await core.close();
  });

  testWidgets('выход из аккаунта останавливает плеер', (tester) async {
    final (core, c, engine) = await _open(tester);
    await tester.tap(find.text('Слушать'));
    await _settle(tester);
    await tester.tap(find.text('Моя волна'));
    await _settle(tester);
    expect(engine.isPlaying, isTrue);
    c.logout();
    await _settle(tester);
    expect(engine.isPlaying, isFalse);
    expect(c.player.hasTrack, isFalse);
    await core.close();
  });

  for (final wave in [false, true]) {
    testWidgets('ничего не вылезает за край от 320 до 1400 px, wave=$wave', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final core = FakeCore();
      final c = Controller(core, engine: SilentEngine());
      await tester.pumpWidget(YmdApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вставить токен вручную'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'good');
      await tester.pump();
      await tester.tap(find.text('Войти'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      c.listen();
      await tester.pumpAndSettle();
      if (wave) {
        c.player.play('wave');
      } else {
        await tester.tap(find.text('Дорога'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Город золотой'));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      for (final open in [false, true]) {
        c.player.panelOpen.value = open;
        for (var w = 320.0; w <= 1400; w += 40) {
          for (final h in [560.0, 760.0]) {
            tester.view.physicalSize = Size(w, h);
            await tester.pumpAndSettle();
          }
        }
      }
      c.player.panelOpen.value = false;
      c.openPage(fakeArtist('Кино'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      for (var w = 320.0; w <= 1400; w += 40) {
        tester.view.physicalSize = Size(w, 760);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
        await tester.pumpAndSettle();
      }
      await core.close();
    });
  }
}
