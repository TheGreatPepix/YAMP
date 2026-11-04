import 'package:flutter/material.dart';

import '../../state/models.dart';
import '../../state/player.dart';
import '../../theme.dart';
import '../download_menu.dart';
import '../widgets.dart';
import 'controls.dart';

const _rowExtent = 56.0;
const _wideFrom = 900.0;
const _controlsWidth = 560.0;

class NowPlaying extends StatelessWidget {
  const NowPlaying({
    super.key,
    required this.p,
    required this.phone,
    required this.onOpen,
    this.onDownload,
    this.onCompact,
  });

  final PlayerState p;
  final bool phone;
  final OpenPage onOpen;
  final Download? onDownload;
  final VoidCallback? onCompact;

  void _close() => p.panelOpen.value = false;

  void _openQueue(BuildContext context) {
    final d = motion(context, const Duration(milliseconds: 260));
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть очередь',
      barrierColor: Colors.black54,
      transitionDuration: d,
      pageBuilder: (context, _, _) => _QueueFlyout(
        p: p,
        onOpen: phone
            ? null
            : (source) {
                Navigator.of(context).pop();
                onOpen(source);
              },
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: const Cubic(0.2, 0, 0, 1))),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = !phone && box.maxWidth >= _wideFrom;
            final side = phone ? 16.0 : 24.0;
            if (!wide) {
              final cover = ((box.maxWidth - 2 * side).clamp(0.0, 560.0) * (phone ? 1 : 0.62)).clamp(120.0, 360.0);
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: ListenableBuilder(
                    listenable: p,
                    builder: (context, _) {
                      final t = p.track;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(p: p, onClose: _close, onOpen: onOpen, onQueue: () => _openQueue(context)),
                          if (t == null)
                            const _Waiting()
                          else ...[
                            Center(
                              child: Cover(
                                url: p.art.isNotEmpty ? p.art : t.cover,
                                size: cover,
                                radius: 16,
                                kind: ReleaseKind.track,
                              ),
                            ),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: _Main(
                                    p: p,
                                    track: t,
                                    phone: phone,
                                    onOpen: onOpen,
                                    onDownload: onDownload,
                                    cover: false,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              );
            }
            final queueWidth = (box.maxWidth * 0.3).clamp(320.0, 560.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: _Header(p: p, onClose: _close, onOpen: onOpen, onCompact: onCompact),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 0, side, side),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, area) {
                              final art = (area.maxHeight - 300).clamp(160.0, 720.0).clamp(0.0, area.maxWidth);
                              return Center(
                                child: SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: art.clamp(360.0, 720.0)),
                                    child: ListenableBuilder(
                                      listenable: p,
                                      builder: (context, _) {
                                        final t = p.track;
                                        return t == null
                                            ? const _Waiting()
                                            : _Main(
                                                p: p,
                                                track: t,
                                                phone: false,
                                                art: art,
                                                onOpen: onOpen,
                                                onDownload: onDownload,
                                              );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(width: side),
                        SizedBox(
                          width: queueWidth,
                          child: Material(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: FocusTraversalGroup(
                              child: _QueueScroll(p: p, side: 12, top: 16, onOpen: onOpen),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QueueFlyout extends StatelessWidget {
  const _QueueFlyout({required this.p, this.onOpen});

  final PlayerState p;
  final OpenPage? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width * 0.9).clamp(0.0, 420.0);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            left: false,
            child: Stack(
              children: [
                FocusTraversalGroup(
                  child: _QueueScroll(p: p, side: 12, top: 22, onOpen: onOpen),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Закрыть очередь',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _QueueScroll extends StatefulWidget {
  const _QueueScroll({required this.p, required this.side, this.top = 0, this.onOpen});

  final PlayerState p;
  final double side, top;
  final OpenPage? onOpen;

  @override
  State<_QueueScroll> createState() => _QueueScrollState();
}

class _QueueScrollState extends State<_QueueScroll> {
  final _scroll = ScrollController();
  final _head = GlobalKey();
  late var _pos = widget.p.pos;

  PlayerState get p => widget.p;

  @override
  void initState() {
    super.initState();
    p.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    p.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  double get _headHeight => (_head.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (_headHeight + p.pos * _rowExtent - pos.viewportDimension / 3).clamp(0.0, pos.maxScrollExtent);
    _scroll.jumpTo(target);
  }

  void _changed() {
    final was = _pos;
    _pos = p.pos;
    if (was == _pos) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(was, _pos));
  }

  void _follow(int was, int now) {
    if (!mounted || !_scroll.hasClients) return;
    final head = _headHeight;
    final pos = _scroll.position;
    bool visible(int i) {
      final top = head + i * _rowExtent;
      return top >= pos.pixels && top + _rowExtent <= pos.pixels + pos.viewportDimension;
    }

    if (!visible(was) || visible(now)) return;
    final target = (head + now * _rowExtent - pos.viewportDimension / 3).clamp(0.0, pos.maxScrollExtent);
    final d = motion(context, const Duration(milliseconds: 350));
    if (d == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: d, curve: const Cubic(0.2, 0, 0, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = widget.side;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final queue = p.queue;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, widget.top, side, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  key: _head,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Semantics(
                            header: true,
                            child: const Text('Очередь', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          if (queue.isNotEmpty)
                            Text(
                              '${p.pos + 1} из ${queue.length}',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontFeatures: tabular),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 16),
              sliver: SliverFixedExtentList(
                itemExtent: _rowExtent,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => QueueRow(
                    key: ValueKey('q$i-${queue[i].id}'),
                    track: queue[i],
                    current: i == p.pos,
                    playing: p.playing,
                    onOpen: widget.onOpen,
                    onTap: () => i == p.pos ? p.togglePlay() : p.jump(i),
                  ),
                  childCount: queue.length,
                ),
              ),
            ),
            if (p.wave)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side + 6, 0, side, 24),
                  child: Text('Подбираю следующие треки…', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.p, required this.onClose, required this.onOpen, this.onQueue, this.onCompact});

  final PlayerState p;
  final VoidCallback onClose;
  final OpenPage onOpen;
  final VoidCallback? onQueue;
  final VoidCallback? onCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final from = p.source;
        final source = from?.title ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              IconButton(tooltip: 'Свернуть плеер', icon: const Icon(Icons.expand_more_rounded), onPressed: onClose),
              Expanded(
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Сейчас играет', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    if (source.isNotEmpty)
                      Tooltip(
                        message: from!.browsable ? 'Открыть «$source»' : source,
                        child: LinkText(
                          parts: [LinkPart(source, from.browsable ? from.id : '')],
                          onOpen: onOpen,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (onQueue == null && onCompact != null)
                IconButton(
                  tooltip: 'Мини-плеер',
                  icon: const Icon(Icons.picture_in_picture_alt_rounded),
                  onPressed: onCompact,
                )
              else if (onQueue == null)
                const SizedBox(width: 48)
              else
                IconButton(tooltip: 'Очередь', icon: const Icon(Icons.queue_music_rounded), onPressed: onQueue),
            ],
          ),
        );
      },
    );
  }
}

class _Main extends StatelessWidget {
  const _Main({
    required this.p,
    required this.track,
    required this.phone,
    required this.onOpen,
    this.onDownload,
    this.art,
    this.cover = true,
  });

  final PlayerState p;
  final PlayTrack track;
  final bool phone;
  final OpenPage onOpen;
  final Download? onDownload;
  final double? art;
  final bool cover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = art ?? (box.maxWidth * (phone ? 1 : 0.62)).clamp(120.0, 360.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cover) ...[
              Center(
                child: Cover(
                  url: p.art.isNotEmpty ? p.art : track.cover,
                  size: size,
                  radius: 16,
                  kind: ReleaseKind.track,
                ),
              ),
              const SizedBox(height: 20),
            ],
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _controlsWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: TrackText(track: track, big: true, onOpen: onOpen),
                          ),
                        ),
                        if (p.wave) DislikeButton(p: p, track: track, size: 44),
                        LikeButton(p: p, track: track, size: 44),
                        TrackMenu(track: track, onOpen: onOpen, onDownload: onDownload, size: 44),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SeekBar(p: p),
                    const SizedBox(height: 4),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (p.wave) const SizedBox(width: 44) else ShuffleButton(p: p, size: 44),
                            SkipButton(p: p, forward: false, size: 48),
                            PlayPauseButton(p: p, size: 64),
                            SkipButton(p: p, forward: true, size: 48),
                            RepeatButton(p: p, size: 44),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        QualityMenu(p: p),
                        if (!phone) VolumeControl(p: p, width: 120),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.track,
    required this.onTap,
    this.current = false,
    this.playing = false,
    this.onOpen,
  });

  final PlayTrack track;
  final VoidCallback onTap;
  final bool current, playing;
  final OpenPage? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: current,
      child: Material(
        color: current ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                if (current)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
                    child: Icon(
                      playing ? Icons.equalizer_rounded : Icons.pause_rounded,
                      color: context.status.accent,
                      size: 20,
                      semanticLabel: playing ? 'Играет' : 'На паузе',
                    ),
                  )
                else
                  Cover(url: track.cover, size: 40, radius: 6, kind: ReleaseKind.track),
                const SizedBox(width: 12),
                Expanded(
                  child: TrackText(track: track, accent: current, artistsOnly: true, onOpen: onOpen),
                ),
                const SizedBox(width: 12),
                Text(
                  fmtTime(track.duration),
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
