import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'butler.dart';

// Fotorealistischer Butler als Video. Das Kling-Wasserzeichen sitzt unten rechts
// und wird durch Zuschnitt (Sprechen) bzw. Zoom (Zuhoeren) aus dem Bild geschnitten.
class ButlerVideoAvatar extends StatefulWidget {
  final ButlerState state;
  const ButlerVideoAvatar({super.key, required this.state});
  @override
  State<ButlerVideoAvatar> createState() => _ButlerVideoAvatarState();
}

class _ButlerVideoAvatarState extends State<ButlerVideoAvatar> {
  // Zoom des Zuhoer-Videos (Hochformat), Fixpunkt als Anteil im Bild.
  static const double listenScale = 1.3;
  static const FractionalOffset listenAnchor = FractionalOffset(0.5, 0.2);

  VideoPlayerController? _speak;
  VideoPlayerController? _listen;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<VideoPlayerController> _load(String path) async {
    final c = VideoPlayerController.asset(path,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    await c.initialize();
    await c.setLooping(true);
    await c.setVolume(0);
    await c.setPlaybackSpeed(0.6);
    return c;
  }

  Future<void> _init() async {
    VideoPlayerController? s;
    VideoPlayerController? l;
    try {
      s = await _load('assets/butler_speaking.mp4');
      l = await _load('assets/butler_listening.mp4');
      if (!mounted) {
        s.dispose();
        l.dispose();
        return;
      }
      setState(() {
        _speak = s;
        _listen = l;
      });
      _sync();
    } catch (_) {
      s?.dispose();
      l?.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(ButlerVideoAvatar old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _sync();
  }

  void _sync() {
    final s = _speak;
    final l = _listen;
    if (s == null || l == null) return;
    // Beide Videos laufen dauerhaft durch, nur die Deckkraft wechselt weich.
    if (!s.value.isPlaying) s.play();
    if (!l.value.isPlaying) l.play();
  }

  @override
  void dispose() {
    _speak?.dispose();
    _listen?.dispose();
    super.dispose();
  }

  Widget _cover(VideoPlayerController c) {
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.center,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.92;
    final s = _speak;
    final l = _listen;
    Widget inner;
    if (_failed) {
      inner = Transform.scale(scale: 1.8, child: ButlerAvatar(state: widget.state));
    } else if (s == null || l == null) {
      inner = Image.asset('assets/butler_portrait.jpg', fit: BoxFit.cover);
    } else {
      final speaking = widget.state == ButlerState.speaking;
      inner = Stack(fit: StackFit.expand, children: [
        AnimatedOpacity(
          opacity: speaking ? 0 : 1,
          duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
          child: Transform.scale(
            scale: listenScale,
            alignment: listenAnchor,
            child: _cover(l),
          ),
        ),
        AnimatedOpacity(
          opacity: speaking ? 1 : 0,
          duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
          child: _cover(s),
        ),
        // dunkler Verlauf unten als zusaetzliche Maske
        const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 90,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x0005080F), Color(0xFF05080F)],
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    return Container(
      width: w,
      height: w * 4 / 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0x334DD0E1), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x334DD0E1), blurRadius: 40, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: ColoredBox(color: const Color(0xFF05080F), child: inner),
      ),
    );
  }
}