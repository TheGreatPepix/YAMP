import 'dart:async';

import 'package:flutter/foundation.dart';

import '../player/engine.dart';
import 'search.dart';

enum Repeat { off, all, one }

enum PlayQuality { lossless, mp3, low }

enum LoadStatus { idle, loading, ok, error }

const sourceWave = 'wave';
const sourceLiked = 'liked';
const sourceHome = 'home';
const sourceChart = 'chart';

String topTracksOf(String artist) => '$artist/tracks';

bool isTopTracks(String source) => source.contains('/artist/') && source.endsWith('/tracks');

String artistOfTop(String source) =>
    isTopTracks(source) ? source.substring(0, source.length - '/tracks'.length) : source;

String _s(Object? v) => v == null ? '' : '$v';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class PlayArtist {
  const PlayArtist({required this.name, required this.source});

  factory PlayArtist.fromJson(Map<String, dynamic> j) => PlayArtist(name: _s(j['name']), source: _s(j['source']));

  final String name, source;
}

List<PlayArtist> _artists(Object? v) => [
  for (final a in (v as List? ?? const []))
    if (a is Map<String, dynamic>) PlayArtist.fromJson(a),
];

class PlayTrack {
  const PlayTrack({
    required this.id,
    this.albumId = '',
    this.title = '',
    this.artist = '',
    this.artists = const [],
    this.album = '',
    this.albumSource = '',
    this.cover = '',
    this.durationMs = 0,
    this.explicit = false,
    this.liked = false,
    this.disliked = false,
    this.unavailable = false,
    this.link = '',
  });

  factory PlayTrack.fromJson(Map<String, dynamic> j) => PlayTrack(
    id: _s(j['id']),
    albumId: _s(j['albumId']),
    title: _s(j['title']),
    artist: _s(j['artist']),
    artists: _artists(j['artists']),
    album: _s(j['album']),
    albumSource: _s(j['albumSource']),
    cover: _s(j['cover']),
    durationMs: _i(j['durationMs']),
    explicit: j['explicit'] == true,
    liked: j['liked'] == true,
    disliked: j['disliked'] == true,
    unavailable: j['unavailable'] == true,
    link: _s(j['link']),
  );

  final String id, albumId, title, artist, album, albumSource, cover, link;
  final List<PlayArtist> artists;
  final int durationMs;
  final bool explicit, liked, disliked, unavailable;

  Duration get duration => Duration(milliseconds: durationMs);
}

class PlaySource {
  const PlaySource({
    required this.kind,
    required this.id,
    this.title = '',
    this.cover = '',
    this.artist = '',
    this.artists = const [],
    this.year = 0,
  });

  factory PlaySource.fromJson(Map<String, dynamic> j) => PlaySource(
    kind: _s(j['kind']),
    id: _s(j['id']),
    title: _s(j['title']),
    cover: _s(j['cover']),
    artist: _s(j['artist']),
    artists: _artists(j['artists']),
    year: _i(j['year']),
  );

  final String kind, id, title, cover, artist;
  final List<PlayArtist> artists;
  final int year;

  bool get browsable => kind != sourceWave && id.isNotEmpty;
}

class SourceAlbum {
  const SourceAlbum({
    required this.source,
    required this.title,
    this.year = 0,
    this.cover = '',
    this.count = 0,
    this.type = 'album',
    this.explicit = false,
  });

  factory SourceAlbum.fromJson(Map<String, dynamic> j) => SourceAlbum(
    source: _s(j['source']),
    title: _s(j['title']),
    year: _i(j['year']),
    cover: _s(j['cover']),
    count: _i(j['count']),
    type: _s(j['type']).isEmpty ? 'album' : _s(j['type']),
    explicit: j['explicit'] == true,
  );

  final String source, title, cover, type;
  final int year, count;
  final bool explicit;
}

class LibraryPlaylist {
  const LibraryPlaylist({required this.source, required this.title, this.owner = '', this.count = 0, this.cover = ''});

  factory LibraryPlaylist.fromJson(Map<String, dynamic> j) => LibraryPlaylist(
    source: _s(j['source']),
    title: _s(j['title']),
    owner: _s(j['owner']),
    count: _i(j['count']),
    cover: _s(j['cover']),
  );

  final String source, title, owner, cover;
  final int count;
}

class HomeFeed {
  const HomeFeed({
    this.status = LoadStatus.idle,
    this.personal = const [],
    this.history = const [],
    this.releases = const [],
    this.playlists = const [],
    this.chart = const [],
    this.error = '',
  });

  final LoadStatus status;
  final List<SearchHit> personal, history, releases, playlists;
  final List<PlayTrack> chart;
  final String error;
}

List<SearchHit> _hits(Object? v) => [
  for (final h in (v as List? ?? const []))
    if (h is Map<String, dynamic>) SearchHit.fromJson(h),
];

class Library {
  const Library({
    this.status = LoadStatus.idle,
    this.playlists = const [],
    this.likedPlaylists = const [],
    this.likedCount = 0,
    this.error = '',
  });

  final LoadStatus status;
  final List<LibraryPlaylist> playlists, likedPlaylists;
  final int likedCount;
  final String error;
}

class TrackList {
  const TrackList({
    this.status = LoadStatus.loading,
    this.info,
    this.tracks = const [],
    this.albums = const [],
    this.error = '',
  });

  final LoadStatus status;
  final PlaySource? info;
  final List<PlayTrack> tracks;
  final List<SourceAlbum> albums;
  final String error;

  Duration get total => tracks.fold(Duration.zero, (sum, t) => sum + t.duration);
}

List<PlayTrack> _tracks(Object? v) => [
  for (final t in (v as List? ?? const []))
    if (t is Map<String, dynamic>) PlayTrack.fromJson(t),
];

class PlayerState extends ChangeNotifier {
  PlayerState(this._send, this.engine) {
    _subs = [
      engine.position.listen(_onPosition),
      engine.duration.listen((d) {
        if (d > Duration.zero) duration.value = d;
      }),
      engine.playing.listen(_onPlaying),
      engine.buffering.listen((b) {
        if (buffering == b) return;
        buffering = b;
        notifyListeners();
      }),
      engine.completed.listen((_) => _onCompleted()),
      engine.errors.listen(_onError),
    ];
  }

  final void Function(Map<String, Object?>) _send;
  final AudioEngine engine;
  late final List<StreamSubscription<Object?>> _subs;

  PlayTrack? track;
  PlayTrack? next;
  var art = '';
  var url = '';
  var pos = 0;
  var count = 0;
  var repeat = Repeat.off;
  var shuffle = false;
  var wave = false;
  var loading = false;
  var quality = PlayQuality.lossless;
  var volume = 0.8;
  PlaySource? source;
  var format = '';
  var queue = const <PlayTrack>[];

  var playing = false;
  var buffering = false;
  final position = ValueNotifier(Duration.zero);
  final duration = ValueNotifier(Duration.zero);

  final panelOpen = ValueNotifier(false);
  final browse = ValueNotifier(sourceHome);
  final browsing = ValueNotifier(false);
  final _history = <String>[];

  bool get canBack => _history.isNotEmpty;

  void browseTo(String source, {bool fromLibrary = false}) {
    if (fromLibrary) _history.clear();
    if (browse.value != source) {
      if (!fromLibrary) _history.add(browse.value);
      browse.value = source;
    }
    browsing.value = true;
    openList(source);
  }

  void back() {
    if (_history.isEmpty) {
      browsing.value = false;
      return;
    }
    browse.value = _history.removeLast();
    if (browse.value == sourceHome) {
      browsing.value = false;
      return;
    }
    openList(browse.value);
  }

  var library = const Library();
  var home = const HomeFeed();
  final lists = <String, TrackList>{};
  final _marks = <String, (bool, bool)>{};
  var likedCount = 0;

  String? _startedFor;
  String? _failedFor;
  var _openedAt = Duration.zero;
  var _volumeApplied = false;

  bool get hasTrack => track != null;

  bool liked(PlayTrack t) => _marks[t.id]?.$1 ?? t.liked;

  bool disliked(PlayTrack t) => _marks[t.id]?.$2 ?? t.disliked;

  bool isCurrent(PlayTrack t) => track?.id == t.id;

  bool get playingWave => wave && hasTrack;

  void receive(Map<String, dynamic> ev) {
    switch (ev['type']) {
      case 'player':
        _onPlayer(ev);
      case 'queue':
        queue = _tracks(ev['tracks']);
        pos = _i(ev['pos']);
      case 'playerFormat':
        if (ev['track'] != track?.id) return;
        format = _s(ev['format']);
      case 'mark':
        _marks[_s(ev['track'])] = (ev['liked'] == true, ev['disliked'] == true);
        likedCount = _i(ev['likedCount']);
        if (lists.containsKey(sourceLiked)) _send({'cmd': 'open', 'source': sourceLiked});
      case 'home':
        final error = _s(ev['error']);
        home = error.isNotEmpty
            ? HomeFeed(status: LoadStatus.error, error: error)
            : HomeFeed(
                status: LoadStatus.ok,
                personal: _hits(ev['personal']),
                history: _hits(ev['history']),
                releases: _hits(ev['releases']),
                playlists: _hits(ev['playlists']),
                chart: _tracks(ev['chart']),
              );
      case 'library':
        final error = _s(ev['error']);
        likedCount = _i(ev['likedCount']);
        library = error.isNotEmpty
            ? Library(status: LoadStatus.error, error: error)
            : Library(
                status: LoadStatus.ok,
                likedCount: likedCount,
                playlists: [
                  for (final p in (ev['playlists'] as List? ?? const []))
                    if (p is Map<String, dynamic>) LibraryPlaylist.fromJson(p),
                ],
                likedPlaylists: [
                  for (final p in (ev['likedPlaylists'] as List? ?? const []))
                    if (p is Map<String, dynamic>) LibraryPlaylist.fromJson(p),
                ],
              );
      case 'tracks':
        final source = _s(ev['source']);
        final error = _s(ev['error']);
        final info = ev['info'];
        lists[source] = error.isNotEmpty
            ? TrackList(status: LoadStatus.error, error: error)
            : TrackList(
                status: LoadStatus.ok,
                info: info is Map<String, dynamic> ? PlaySource.fromJson(info) : null,
                tracks: _tracks(ev['tracks']),
                albums: [
                  for (final a in (ev['albums'] as List? ?? const []))
                    if (a is Map<String, dynamic>) SourceAlbum.fromJson(a),
                ],
              );
      default:
        return;
    }
    notifyListeners();
  }

  void _onPlayer(Map<String, dynamic> ev) {
    final t = ev['track'];
    final n = ev['next'];
    final previous = track?.id;
    track = t is Map<String, dynamic> ? PlayTrack.fromJson(t) : null;
    next = n is Map<String, dynamic> ? PlayTrack.fromJson(n) : null;
    art = _s(ev['art']);
    url = _s(ev['url']);
    pos = _i(ev['pos']);
    count = _i(ev['count']);
    repeat = Repeat.values.asNameMap()[_s(ev['repeat'])] ?? Repeat.off;
    shuffle = ev['shuffle'] == true;
    wave = ev['wave'] == true;
    loading = ev['loading'] == true;
    quality = PlayQuality.values.asNameMap()[_s(ev['quality'])] ?? PlayQuality.lossless;
    volume = (ev['volume'] as num?)?.toDouble() ?? volume;
    final s = ev['source'];
    source = s is Map<String, dynamic> ? PlaySource.fromJson(s) : null;
    if (track?.id != previous) format = '';
    if (!_volumeApplied) {
      _volumeApplied = true;
      engine.setVolume(volume);
    }

    final current = track;
    switch (ev['action']) {
      case 'play' when current != null:
        _startedFor = null;
        _failedFor = null;
        _openedAt = Duration.zero;
        position.value = Duration.zero;
        duration.value = current.duration;
        engine.open(url, hint: current.duration);
      case 'resume' when current != null:
        _failedFor = null;
        _openedAt = position.value;
        engine.open(url, start: position.value, play: playing, hint: current.duration);
      case 'stop':
        _startedFor = null;
        position.value = Duration.zero;
        duration.value = Duration.zero;
        engine.stop();
      case 'end':
        engine.pause();
    }
  }

  void _onPlaying(bool v) {
    if (playing != v) {
      playing = v;
      notifyListeners();
    }
  }

  void _onPosition(Duration p) {
    position.value = p;
    final id = track?.id;
    if (id == null || _startedFor == id) return;
    if (p > _openedAt && p < _openedAt + const Duration(seconds: 3)) {
      _startedFor = id;
      _send({'cmd': 'playerStarted', 'track': id});
    }
  }

  double get _seconds => position.value.inMilliseconds / 1000;

  void _onCompleted() {
    final id = track?.id;
    if (id == null) return;
    final played = duration.value > Duration.zero ? duration.value : position.value;
    _startedFor = null;
    _send({'cmd': 'playerEnded', 'track': id, 'position': played.inMilliseconds / 1000});
  }

  void _onError(String message) {
    final id = track?.id;
    if (id == null || _startedFor == id || _failedFor == id) return;
    _failedFor = id;
    _send({'cmd': 'playerError', 'track': id, 'message': message});
  }

  void Function(String message)? onBlocked;

  String get unavailable {
    final e = engine;
    return e is UnavailableEngine ? e.reason : '';
  }

  bool _blocked() {
    final reason = unavailable;
    if (reason.isEmpty) return false;
    onBlocked?.call(reason);
    return true;
  }

  void togglePlay() {
    if (_blocked()) return;
    if (track == null) {
      play(sourceWave);
      return;
    }
    playing ? engine.pause() : engine.play();
  }

  void resume() {
    if (track != null && !playing) engine.play();
  }

  void pause() {
    if (playing) engine.pause();
  }

  void nextTrack() {
    final id = track?.id;
    if (id == null) return;
    _send({'cmd': 'playerNext', 'track': id, 'position': _seconds});
  }

  void previousTrack() {
    final id = track?.id;
    if (id == null) return;
    _send({'cmd': 'playerPrev', 'track': id, 'position': _seconds});
  }

  void seek(Duration to) {
    position.value = to;
    engine.seek(to);
  }

  void seekBy(Duration delta) {
    final max = duration.value;
    var to = position.value + delta;
    if (to < Duration.zero) to = Duration.zero;
    if (max > Duration.zero && to > max) to = max;
    seek(to);
  }

  void previewVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    engine.setVolume(volume);
    notifyListeners();
  }

  void commitVolume() => _send({'cmd': 'playerVolume', 'volume': volume});

  double _beforeMute = 0.8;

  void toggleMute() {
    if (volume > 0) {
      _beforeMute = volume;
      previewVolume(0);
    } else {
      previewVolume(_beforeMute > 0 ? _beforeMute : 0.8);
    }
    commitVolume();
  }

  void cycleRepeat() {
    final options = wave ? const [Repeat.off, Repeat.one] : Repeat.values;
    final i = options.indexOf(repeat);
    _send({'cmd': 'playerRepeat', 'repeat': options[(i + 1) % options.length].name});
  }

  void toggleShuffle() => _send({'cmd': 'playerShuffle', 'on': !shuffle});

  void setQuality(PlayQuality q) => _send({'cmd': 'playerQuality', 'quality': q.name});

  void play(String source, {String? track, int index = 0}) {
    if (_blocked()) return;
    _send({'cmd': 'play', 'source': source, 'track': ?track, 'index': index});
  }

  void playShuffled(String source) {
    if (_blocked()) return;
    if (!shuffle) _send({'cmd': 'playerShuffle', 'on': true});
    _send({'cmd': 'play', 'source': source, 'index': -1});
  }

  void jump(int index) => _send({'cmd': 'playerJump', 'pos': index, 'position': _seconds});

  void like(PlayTrack t, bool on) => _send({'cmd': 'like', 'track': t.id, 'on': on});

  void dislike(PlayTrack t, bool on) => _send({'cmd': 'dislike', 'track': t.id, 'on': on, 'position': _seconds});

  void loadLibrary({bool force = false}) {
    if (!force && (library.status == LoadStatus.ok || library.status == LoadStatus.loading)) return;
    library = Library(status: LoadStatus.loading, likedCount: likedCount);
    _send({'cmd': 'library'});
    notifyListeners();
  }

  void loadHome({bool force = false}) {
    if (!force && (home.status == LoadStatus.ok || home.status == LoadStatus.loading)) return;
    home = const HomeFeed(status: LoadStatus.loading);
    _send({'cmd': 'home'});
    notifyListeners();
  }

  void openList(String source, {bool force = false}) {
    if (source == sourceHome) {
      loadHome(force: force);
      return;
    }
    final known = lists[source];
    if (!force && known != null && known.status != LoadStatus.error) return;
    lists[source] = const TrackList();
    _send({'cmd': 'open', 'source': source});
    notifyListeners();
  }

  void requestQueue() => _send({'cmd': 'queue'});

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    position.dispose();
    duration.dispose();
    panelOpen.dispose();
    browse.dispose();
    browsing.dispose();
    engine.dispose();
    super.dispose();
  }
}
