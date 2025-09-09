import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YouTube Music Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    SearchPage(),
    PlaylistPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0D1B2A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Search"),
          BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play), label: "Playlists"),
        ],
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode yt = YoutubeExplode();

  List<Video> _results = [];
  bool _isLoading = false;

  final ValueNotifier<Video?> _currentVideoNotifier = ValueNotifier(null);
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isRepeating = false; // ✅ repeat flag

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  Duration _duration = Duration.zero;
  final Map<String, String> _audioUrls = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();

    _animController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _animController.forward();
      }
    });

    _player.onDurationChanged.listen((d) => setState(() => _duration = d));

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;

        if (_isPlaying) {
          _isBuffering = false;
        }
      });

      if (_isPlaying) {
        _animController.forward();
      } else {
        _animController.stop();
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (_isBuffering && pos > Duration.zero) {
        setState(() => _isBuffering = false);
      }
    });

    _player.onPlayerComplete.listen((_) async {
      if (_isRepeating && _currentIndex >= 0) {
        // ✅ repeat same song
        await _playSong(_results[_currentIndex], index: _currentIndex);
      } else if (_currentIndex + 1 < _results.length) {
        // play next
        final nextVideo = _results[_currentIndex + 1];
        _playSong(nextVideo, index: _currentIndex + 1);
      } else {
        setState(() {
          _isPlaying = false;
          _animController.stop();
        });
      }
    });
  }

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final searchResults = await yt.search.getVideos(query);
      setState(() {
        _results = searchResults.toList();
        _isLoading = false;
      });

      for (var video in _results) {
        Future.microtask(() async {
          try {
            final manifest =
                await yt.videos.streamsClient.getManifest(video.id);
            final audio = manifest.audioOnly.withHighestBitrate();
            _audioUrls[video.id.value] = audio.url.toString();
          } catch (_) {}
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error searching: $e");
    }
  }

  Future<void> _playSong(Video video, {int? index}) async {
    setState(() {
      _currentIndex = index ?? _results.indexOf(video);
      _isBuffering = true;
    });
    _currentVideoNotifier.value = video;

    try {
      String? audioUrl = _audioUrls[video.id.value];
      if (audioUrl == null) {
        final manifest = await yt.videos.streamsClient.getManifest(video.id);
        final audio = manifest.audioOnly.withHighestBitrate();
        audioUrl = audio.url.toString();
        _audioUrls[video.id.value] = audioUrl;
      }

      await _player.stop();
      await _player.play(UrlSource(audioUrl));
    } catch (e) {
      if (mounted) setState(() => _isBuffering = false);
      debugPrint("Error playing: $e");
    }
  }

  void _togglePlayPause(StateSetter? modalSetState) async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    modalSetState?.call(() {});
  }

  void _toggleRepeat(StateSetter? modalSetState) {
    setState(() => _isRepeating = !_isRepeating);
    modalSetState?.call(() {});
  }

  void _openFullPlayer(BuildContext context) {
    if (_currentVideoNotifier.value == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1B2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return ValueListenableBuilder<Video?>(
              valueListenable: _currentVideoNotifier,
              builder: (_, currentVideo, __) {
                if (currentVideo == null) return const SizedBox();

                return DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.85,
                  maxChildSize: 0.95,
                  minChildSize: 0.5,
                  builder: (_, controller) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          height: 5,
                          width: 50,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(
                                currentVideo.thumbnails.maxResUrl,
                                height: 250,
                                width: 250,
                                fit: BoxFit.cover,
                              ),
                              if (_isBuffering)
                                const CircularProgressIndicator(
                                    color: Colors.white),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          currentVideo.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentVideo.author,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<Duration>(
                          stream: _player.onPositionChanged,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            return Column(
                              children: [
                                Slider(
                                  value: position.inSeconds
                                      .clamp(0, _duration.inSeconds)
                                      .toDouble(),
                                  min: 0,
                                  max: _duration.inSeconds.toDouble(),
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white24,
                                  onChanged: (value) async {
                                    final pos =
                                        Duration(seconds: value.toInt());
                                    await _player.seek(pos);
                                  },
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    Text(_formatDuration(_duration),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous,
                                  size: 40, color: Colors.white),
                              onPressed: () {
                                if (_currentIndex > 0) {
                                  _playSong(_results[_currentIndex - 1],
                                      index: _currentIndex - 1);
                                }
                              },
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: IconButton(
                                key: ValueKey<bool>(_isPlaying),
                                icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    size: 64,
                                    color: Colors.white),
                                onPressed: () =>
                                    _togglePlayPause(modalSetState),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next,
                                  size: 40, color: Colors.white),
                              onPressed: () {
                                if (_currentIndex + 1 < _results.length) {
                                  _playSong(_results[_currentIndex + 1],
                                      index: _currentIndex + 1);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // ✅ Repeat button
                        IconButton(
                          icon: Icon(Icons.repeat,
                              size: 30,
                              color: _isRepeating
                                  ? Colors.blueAccent
                                  : Colors.white),
                          onPressed: () => _toggleRepeat(modalSetState),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    _player.dispose();
    yt.close();
    _animController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (query) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500),
                        () => _searchSongs(query));
                  },
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.white),
                    hintText: "Search YouTube Music...",
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : _results.isEmpty
                      ? const Center(
                          child: Text("No results yet 🎵",
                              style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final video = _results[index];
                            return ListTile(
                              onTap: () => _playSong(video, index: index),
                              leading: Image.network(video.thumbnails.highResUrl,
                                  width: 50,
                                  height: 50,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.music_note,
                                          color: Colors.white)),
                              title: Text(video.title,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(video.author,
                                  style:
                                      const TextStyle(color: Colors.white70)),
                              trailing: ValueListenableBuilder<Video?>(
                                valueListenable: _currentVideoNotifier,
                                builder: (_, current, __) =>
                                    current?.id == video.id
                                        ? FadeTransition(
                                            opacity: _fadeAnimation,
                                            child: const CircleAvatar(
                                                radius: 6,
                                                backgroundColor: Colors.white),
                                          )
                                        : const SizedBox.shrink(),
                              ),
                            );
                          },
                        ),
            ),
            ValueListenableBuilder<Video?>(
              valueListenable: _currentVideoNotifier,
              builder: (_, currentVideo, __) {
                if (currentVideo == null) return const SizedBox();
                return InkWell(
                  onTap: () => _openFullPlayer(context),
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Image.network(currentVideo.thumbnails.lowResUrl,
                            width: 50,
                            height: 50,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.music_note,
                                    color: Colors.white)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(currentVideo.title,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ),
                        _isBuffering
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: IconButton(
                                  key: ValueKey<bool>(_isPlaying),
                                  icon: Icon(
                                      _isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white),
                                  onPressed: () => _togglePlayPause(null),
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1B2A),
      body: Center(
        child: Text("Your Playlists 🎶",
            style: TextStyle(color: Colors.white, fontSize: 20)),
      ),
    );
  }
}
