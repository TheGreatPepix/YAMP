import 'dart:async';

import 'package:media_kit/media_kit.dart';

abstract class AudioEngine {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<void> get completed;
  Stream<String> get errors;

  Future<void> open(String url, {Duration start = Duration.zero, bool play = true, Duration hint = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitEngine implements AudioEngine {
  MediaKitEngine() : _player = Player(configuration: const PlayerConfiguration(title: 'YAMD'));

  final Player _player;

  static void init() => MediaKit.ensureInitialized();

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Stream<void> get completed => _player.stream.completed.where((done) => done);

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(String url, {Duration start = Duration.zero, bool play = true, Duration hint = Duration.zero}) =>
      _player.open(Media(url, start: start > Duration.zero ? start : null), play: play);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> setVolume(double volume) => _player.setVolume((volume * 100).clamp(0, 100).toDouble());

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class SilentEngine implements AudioEngine {
  SilentEngine({this.tick});

  final Duration? tick;

  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);

  Timer? _timer;
  var _at = Duration.zero;
  var _length = Duration.zero;
  var _isPlaying = false;
  var volume = 1.0;
  String? url;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<String> get errors => _errors.stream;

  bool get isPlaying => _isPlaying;

  Duration get at => _at;

  void _setPlaying(bool v) {
    _isPlaying = v;
    _playing.add(v);
    _timer?.cancel();
    _timer = null;
    final t = tick;
    if (v && t != null) _timer = Timer.periodic(t, (_) => _advance(t));
  }

  void _advance(Duration by) {
    _at += by;
    if (_length > Duration.zero && _at >= _length) {
      _at = _length;
      _position.add(_at);
      finish();
      return;
    }
    _position.add(_at);
  }

  void finish() {
    _setPlaying(false);
    _completed.add(null);
  }

  void progress(Duration by) => _advance(by);

  void fail(String message) {
    _setPlaying(false);
    _errors.add(message);
  }

  @override
  Future<void> open(
    String url, {
    Duration start = Duration.zero,
    bool play = true,
    Duration hint = Duration.zero,
  }) async {
    this.url = url;
    _at = start;
    _length = hint;
    _duration.add(hint);
    _position.add(start);
    _setPlaying(play);
  }

  @override
  Future<void> play() async {
    if (url != null) _setPlaying(true);
  }

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> seek(Duration to) async {
    _at = to;
    _position.add(to);
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> stop() async {
    url = null;
    _at = Duration.zero;
    _setPlaying(false);
    _position.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
  }
}
