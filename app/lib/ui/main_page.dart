import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/controller.dart';
import '../state/draft.dart';
import '../state/models.dart';
import '../theme.dart';
import 'downloads.dart';
import 'link_input.dart';
import 'log_dialog.dart';
import 'player/library_view.dart';
import 'player/mini_player.dart';
import 'player/now_playing.dart';
import 'search_view.dart';
import 'settings_dialog.dart';
import 'source_detail.dart';
import 'sources.dart';
import 'update_dialog.dart';
import 'widgets.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key, required this.c});

  final Controller c;

  void _close() => c.downloadsOpen.value = false;

  void _closePlayer() => c.player.panelOpen.value = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([c.drafts, c.downloadsOpen, c.search, c.section, c.player.panelOpen]),
          builder: (context, _) {
            final empty = c.drafts.value.isEmpty;
            final open = c.downloadsOpen.value;
            final playerOpen = c.player.panelOpen.value;
            final searching = c.search.open;
            final listen = c.section.value == Section.listen;
            return LayoutBuilder(
              builder: (context, box) {
                final phone = box.maxWidth < phoneWidth;
                return PopScope(
                  canPop: !open && !searching && !playerOpen,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    if (playerOpen) {
                      _closePlayer();
                    } else if (open) {
                      _close();
                    } else if (searching) {
                      c.search.close();
                    }
                  },
                  child: Stack(
                    children: [
                      ExcludeFocus(
                        excluding: open || playerOpen,
                        child: Column(
                          children: [
                            _Header(
                              c: c,
                              withInput: (!empty || searching || listen) && !phone,
                              compact: box.maxWidth < 1080,
                              phone: phone,
                            ),
                            if (phone && (!empty || searching || listen))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: LinkInput(c: c),
                              ),
                            Divider(height: 1, color: scheme.outlineVariant),
                            if (Platform.isAndroid) _StorageBanner(c: c),
                            Expanded(
                              child: searching
                                  ? FocusTraversalGroup(child: SearchView(c: c))
                                  : listen
                                  ? LibraryView(c: c, phone: phone)
                                  : empty
                                  ? _Hero(c: c)
                                  : phone
                                  ? _PhoneDrafts(c: c)
                                  : Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: box.maxWidth >= 1100 ? 340 : 280,
                                          child: FocusTraversalGroup(child: SourceList(c: c)),
                                        ),
                                        VerticalDivider(width: 1, color: scheme.outlineVariant),
                                        Expanded(
                                          child: FocusTraversalGroup(child: SourceDetail(c: c)),
                                        ),
                                      ],
                                    ),
                            ),
                            if (!empty && !listen) _ActionBar(c: c, phone: phone),
                            FocusTraversalGroup(child: MiniPlayer(p: c.player, phone: phone, onOpen: c.openPage)),
                            if (phone) _SectionBar(c: c),
                          ],
                        ),
                      ),
                      if (playerOpen)
                        Positioned.fill(
                          child: _Reveal(
                            child: CallbackShortcuts(
                              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _closePlayer},
                              child: FocusScope(autofocus: true, child: NowPlaying(p: c.player, phone: phone, onOpen: c.openPage)),
                            ),
                          ),
                        ),
                      if (open && phone)
                        Positioned.fill(
                          child: FocusScope(autofocus: true, child: DownloadsPanel(c: c)),
                        ),
                      if (open && !phone) ...[
                        Positioned.fill(
                          top: 73,
                          child: GestureDetector(
                            onTap: _close,
                            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
                          ),
                        ),
                        Positioned(
                          top: 80,
                          right: 12,
                          bottom: 12,
                          width: (box.maxWidth - 24).clamp(0, 440).toDouble(),
                          child: CallbackShortcuts(
                            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
                            child: FocusScope(autofocus: true, child: DownloadsPanel(c: c)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = motion(context, const Duration(milliseconds: 280));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: const Cubic(0.2, 0, 0, 1),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.c});

  final Controller c;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 64,
      selectedIndex: c.section.value.index,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) => i == Section.listen.index ? c.listen() : c.section.value = Section.download,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.download_outlined),
          selectedIcon: Icon(Icons.download_rounded),
          label: 'Скачать',
        ),
        NavigationDestination(
          icon: Icon(Icons.headphones_outlined),
          selectedIcon: Icon(Icons.headphones_rounded),
          label: 'Слушать',
        ),
      ],
    );
  }
}

class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({required this.c, required this.compact});

  final Controller c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Section>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        ButtonSegment(
          value: Section.download,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: compact ? null : const Text('Скачать'),
          tooltip: compact ? 'Скачать' : null,
        ),
        ButtonSegment(
          value: Section.listen,
          icon: const Icon(Icons.headphones_rounded, size: 18),
          label: compact ? null : const Text('Слушать'),
          tooltip: compact ? 'Слушать' : null,
        ),
      ],
      selected: {c.section.value},
      onSelectionChanged: (s) => s.first == Section.listen ? c.listen() : c.section.value = Section.download,
    );
  }
}

class _PhoneDrafts extends StatefulWidget {
  const _PhoneDrafts({required this.c});

  final Controller c;

  @override
  State<_PhoneDrafts> createState() => _PhoneDraftsState();
}

class _PhoneDraftsState extends State<_PhoneDrafts> {
  var _detail = false;

  Controller get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.selected.addListener(_changed);
  }

  @override
  void dispose() {
    c.selected.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (c.selected.value == null && _detail) setState(() => _detail = false);
  }

  void _back() => setState(() => _detail = false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_detail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !c.downloadsOpen.value && !c.search.open) _back();
      },
      child: _detail
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(tooltip: 'К подборке', icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
                      Text(
                        'Подборка',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FocusTraversalGroup(child: SourceDetail(c: c)),
                ),
              ],
            )
          : FocusTraversalGroup(
              child: SourceList(c: c, onOpen: () => setState(() => _detail = true)),
            ),
    );
  }
}

class _StorageBanner extends StatefulWidget {
  const _StorageBanner({required this.c});

  final Controller c;

  @override
  State<_StorageBanner> createState() => _StorageBannerState();
}

class _StorageBannerState extends State<_StorageBanner> with WidgetsBindingObserver {
  var _granted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final granted = await widget.c.desktop.storageGranted();
    if (mounted && granted != _granted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.status.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.status.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_off_outlined, color: context.status.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Нужен доступ к файлам, чтобы сохранять музыку',
              style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.35),
            ),
          ),
          TextButton(onPressed: widget.c.desktop.requestStorage, child: const Text('Разрешить')),
        ],
      ),
    );
  }
}

Future<void> _logout(BuildContext context, Controller c) async {
  final running = c.running;
  final drafts = c.drafts.value.length;
  if (running > 0 || drafts > 0) {
    final body = [
      if (running > 0) 'Незавершённые загрузки остановятся: $running.',
      if (drafts > 0) 'Подборка очистится: ${linksLabel(drafts)}.',
      'Скачанные файлы останутся на диске.',
    ].join(' ');
    final ok = await confirm(context, title: 'Выйти из аккаунта?', body: body, action: 'Выйти');
    if (!ok) return;
  }
  c.logout();
}

class _PhoneMenu extends StatelessWidget {
  const _PhoneMenu({required this.c});

  final Controller c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountAvatar(account: c.account, size: 30),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.account.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (c.account.login.isNotEmpty && c.account.login != c.account.displayName)
                    Text(c.account.login, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 10),
              const PlusBadge(),
            ],
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_rounded),
          onPressed: () => showSettingsDialog(context, c),
          child: const Text('Настройки'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.receipt_long_rounded),
          onPressed: () => showLogDialog(context, c),
          child: const Text('Журнал'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.verified_outlined),
          onPressed: c.recheck,
          child: const Text('Проверить подписку'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout_rounded),
          onPressed: () => _logout(context, c),
          child: const Text('Выйти'),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'Меню',
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c, required this.withInput, required this.compact, required this.phone});

  final Controller c;
  final bool withInput, compact, phone;

  @override
  Widget build(BuildContext context) {
    if (phone) {
      return SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            children: [
              const BrandMark(size: 30),
              const SizedBox(width: 10),
              Text('YAMP', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              UpdateButton(c: c),
              DownloadsButton(c: c),
              _PhoneMenu(c: c),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const BrandMark(size: 34),
            if (!compact) ...[
              const SizedBox(width: 10),
              Text('YAMP', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
            SizedBox(width: compact ? 12 : 20),
            ListenableBuilder(listenable: c.section, builder: (context, _) => _SectionSwitch(c: c, compact: compact)),
            SizedBox(width: compact ? 12 : 20),
            Expanded(
              child: withInput
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: LinkInput(c: c),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(width: compact ? 12 : 24),
            UpdateButton(c: c),
            DownloadsButton(c: c),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Журнал',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => showLogDialog(context, c),
            ),
            IconButton(
              tooltip: 'Настройки',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => showSettingsDialog(context, c),
            ),
            const SizedBox(width: 6),
            _AccountPill(c: c, compact: compact),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c});

  final Controller c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget point(String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: context.status.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
      ],
    );
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(phone ? 16 : 24, 24, phone ? 16 : 24, phone ? 24 : 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Что скачаем?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: phone ? 32 : 44, fontWeight: FontWeight.w800, letterSpacing: -1.2),
            ),
            const SizedBox(height: 12),
            Text(
              'Найдите музыку по названию или вставьте ссылки. Название, исполнитель и '
              'обложка определятся сами, а нужное можно отметить галочками.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: phone ? 15 : 16, height: 1.5),
            ),
            SizedBox(height: phone ? 20 : 26),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: LinkInput(c: c, hero: true),
            ),
            SizedBox(height: phone ? 24 : 36),
            Wrap(
              spacing: phone ? 20 : 32,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                point(c.quality == Quality.lossless ? 'FLAC до 24 бит / 192 кГц' : 'MP3 320'),
                point('До ${c.concurrency} треков одновременно'),
                point('Теги и обложки сами'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String linksLabel(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n ссылка';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n ссылки';
  return '$n ссылок';
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.c, required this.phone});

  final Controller c;
  final bool phone;

  Future<void> _browse() => c.chooseDir();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drafts = c.drafts.value;
    return ListenableBuilder(
      listenable: Listenable.merge([c, ...drafts]),
      builder: (context, _) {
        final ready = drafts.where((Draft d) => d.ready).toList();
        final tracks = ready.fold(0, (n, d) => n + d.trackCount);
        final loading = drafts.where((d) => d.loading).length;
        final summary = [
          if (ready.isNotEmpty) '${linksLabel(ready.length)} · ${tracksLabel(tracks)}' else 'Нечего скачивать',
          if (loading > 0) 'загружается $loading',
        ].join(' · ');
        final lossless = c.quality == Quality.lossless;
        final quality = MenuAnchor(
          alignmentOffset: const Offset(0, -4),
          menuChildren: [
            for (final (q, label) in [(Quality.lossless, 'FLAC (без потерь)'), (Quality.mp3, 'MP3 320')])
              MenuItemButton(
                leadingIcon: Icon(c.quality == q ? Icons.check_rounded : null),
                onPressed: () => c.setQuality(q),
                child: Text(label),
              ),
          ],
          builder: (context, menu, _) => Tooltip(
            message: 'Качество',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tag(lossless ? 'FLAC' : 'MP3 320', icon: Icons.graphic_eq_rounded, color: context.status.accent),
                    Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        );
        final download = FilledButton.icon(
          onPressed: ready.isEmpty ? null : c.downloadAll,
          icon: const Icon(Icons.download_rounded),
          label: Text(ready.length > 1 ? 'Скачать всё' : 'Скачать'),
        );
        if (phone) {
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    quality,
                  ],
                ),
                const SizedBox(height: 8),
                download,
              ],
            ),
          );
        }
        return Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Text(summary, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(width: 10),
              quality,
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Tooltip(
                    message: 'Изменить папку\n${c.dir}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _browse,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_rounded, size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                c.dir,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              download,
            ],
          ),
        );
      },
    );
  }
}

class _AccountPill extends StatelessWidget {
  const _AccountPill({required this.c, required this.compact});

  final Controller c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const shape = StadiumBorder();
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            c.account.login.isNotEmpty ? c.account.login : c.account.displayName,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.verified_outlined),
          onPressed: c.recheck,
          child: const Text('Проверить подписку'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout_rounded),
          onPressed: () => _logout(context, c),
          child: const Text('Выйти'),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: compact ? c.account.displayName : 'Аккаунт',
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, 4, compact ? 8 : 12, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountAvatar(account: c.account, size: 30),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        c.account.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const PlusBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
