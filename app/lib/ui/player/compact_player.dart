import 'package:flutter/material.dart';

import '../../state/controller.dart';
import '../../state/models.dart';
import '../../theme.dart';
import '../widgets.dart';
import 'controls.dart';

class CompactPlayer extends StatelessWidget {
  const CompactPlayer({super.key, required this.c});

  final Controller c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = c.player;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: Border.all(color: scheme.outlineVariant),
      child: ListenableBuilder(
        listenable: Listenable.merge([p, c.pinned]),
        builder: (context, _) {
          final t = p.track;
          final pinned = c.pinned.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => c.desktop.drag(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                  child: Row(
                    children: [
                      if (t != null)
                        Cover(url: t.cover, size: 52, radius: 8, kind: ReleaseKind.track)
                      else
                        const SizedBox.square(dimension: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: t == null
                            ? Text('Ничего не играет', style: TextStyle(color: scheme.onSurfaceVariant))
                            : Semantics(liveRegion: true, child: TrackText(track: t)),
                      ),
                      IconButton(
                        tooltip: pinned ? 'Открепить от верха' : 'Поверх всех окон',
                        isSelected: pinned,
                        onPressed: c.togglePin,
                        icon: const Icon(Icons.push_pin_outlined),
                        selectedIcon: Icon(Icons.push_pin_rounded, color: context.status.accent),
                      ),
                      IconButton(
                        tooltip: 'Развернуть окно',
                        onPressed: () => c.setCompact(false),
                        icon: const Icon(Icons.open_in_full_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (t != null) LikeButton(p: p, track: t, size: 36) else const SizedBox(width: 36),
                  SkipButton(p: p, forward: false),
                  const SizedBox(width: 4),
                  PlayPauseButton(p: p, size: 40),
                  const SizedBox(width: 4),
                  SkipButton(p: p, forward: true),
                  if (p.wave) const SizedBox(width: 36) else RepeatButton(p: p, size: 36),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: SeekBar(p: p, compact: true),
              ),
            ],
          );
        },
      ),
    );
  }
}
