import 'package:flutter/material.dart';

import '../../state/controller.dart';
import '../../state/player.dart';
import '../../state/search.dart';
import '../search_view.dart';
import 'artist_view.dart';
import 'library_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.c, required this.phone});

  final Controller c;
  final bool phone;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  PlayerState get p => widget.c.player;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) p.loadHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final pad = phone ? 12.0 : 20.0;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final home = p.home;
        final rows = [('Для вас', home.personal), ('Вы недавно слушали', home.history)];
        final later = [('Новые релизы', home.releases), ('Новые плейлисты', home.playlists)];
        Widget row(String title, List<SearchHit> hits) => _Row(c: widget.c, title: title, hits: hits, phone: phone);
        return ListView(
          key: const PageStorageKey<String>('home'),
          padding: EdgeInsets.fromLTRB(pad, phone ? 8 : 16, pad, 24),
          children: [
            if (phone) ...[WaveCard(p: p), const SizedBox(height: 8)],
            if (home.status == LoadStatus.loading || home.status == LoadStatus.idle)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (home.status == LoadStatus.error)
              Problem(message: 'Не удалось загрузить главную. ${home.error}', onRetry: () => p.loadHome(force: true))
            else ...[
              for (final (title, hits) in rows)
                if (hits.isNotEmpty) row(title, hits),
              if (home.chart.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: SectionTitle('Чарт', more: 'Весь чарт', onMore: () => widget.c.openPage(sourceChart)),
                ),
                for (final (i, t) in home.chart.indexed)
                  TrackRow(
                    key: ValueKey('chart:${t.id}'),
                    c: widget.c,
                    track: t,
                    number: i + 1,
                    onPlay: () => p.play(sourceChart, track: t.id),
                  ),
              ],
              for (final (title, hits) in later)
                if (hits.isNotEmpty) row(title, hits),
            ],
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.c, required this.title, required this.hits, required this.phone});

  final Controller c;
  final String title;
  final List<SearchHit> hits;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final size = phone ? 136.0 : 168.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(top: 20, bottom: 4), child: SectionTitle(title)),
        SizedBox(
          height: size + 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hits.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) => SizedBox(
              width: size,
              child: HitCard(c: c, hit: hits[i], size: size),
            ),
          ),
        ),
      ],
    );
  }
}
