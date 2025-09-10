import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode yt = YoutubeExplode();

  final ValueNotifier<Video?> _currentVideoNotifier = ValueNotifier(null);

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isRepeating = false;
  int _currentResultIndex = -1;
  Duration _duration = Duration.zero;
  final Map<String, String> _audioUrls = {};

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  double _volume = 1.0;
  List<Video> _results = [];

  // --- New: liked songs as ValueNotifier for live updates ---
  final ValueNotifier<List<Video>> _likedSongsNotifier =
      ValueNotifier<List<Video>>([]);

  late final List<Widget> _pages;

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

    _player.durationStream.listen((d) {
      if (d != null) setState(() => _duration = d);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (_isPlaying) _isBuffering = false;
      });
      if (_isPlaying) {
        _animController.forward();
      } else {
        _animController.stop();
      }
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.ready && _isBuffering) {
        setState(() => _isBuffering = false);
      }
      if (state == ProcessingState.completed) {
        if (_isRepeating && _currentResultIndex >= 0) {
          _playSong(_results[_currentResultIndex], index: _currentResultIndex);
        } else if (_currentResultIndex + 1 < _results.length) {
          final nextVideo = _results[_currentResultIndex + 1];
          _playSong(nextVideo, index: _currentResultIndex + 1);
        } else {
          setState(() {
            _isPlaying = false;
            _animController.stop();
          });
        }
      }
    });

    _pages = [
      SearchPage(
        yt: yt,
        onPlaySong: _playSong,
        resultsCallback: (r) => setState(() => _results = r),
        fadeAnimation: _fadeAnimation,
        currentVideoNotifier: _currentVideoNotifier,
      ),
      PlaylistPage(
        likedSongsNotifier: _likedSongsNotifier,
        onPlaySong: _playSong,
      ),
    ];
  }

  @override
  void dispose() {
    _player.dispose();
    yt.close();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _playSong(Video video, {int? index}) async {
    setState(() {
      _currentResultIndex = index ?? _results.indexOf(video);
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
      await _player.setUrl(audioUrl);
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _isBuffering = false);
      debugPrint("Error playing: $e");
    }
  }

  void _togglePlayPause(StateSetter? modalSetState) async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    modalSetState?.call(() {});
  }

  void _toggleRepeat(StateSetter? modalSetState) {
    setState(() => _isRepeating = !_isRepeating);
    modalSetState?.call(() {});
  }

  void _toggleLike(Video video, StateSetter? modalSetState) {
    final current = List<Video>.from(_likedSongsNotifier.value);
    if (current.any((v) => v.id.value == video.id.value)) {
      current.removeWhere((v) => v.id.value == video.id.value);
    } else {
      current.add(video);
    }
    _likedSongsNotifier.value = current;
    modalSetState?.call(() {});
  }

  bool _isLiked(Video video) {
    return _likedSongsNotifier.value.any((v) => v.id.value == video.id.value);
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
                        Text(currentVideo.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(currentVideo.author,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 20),
                        StreamBuilder<Duration>(
                          stream: _player.positionStream,
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
                              icon: Icon(
                                _isLiked(currentVideo)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 32,
                                color: _isLiked(currentVideo)
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              onPressed: () =>
                                  _toggleLike(currentVideo, modalSetState),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous,
                                  size: 40, color: Colors.white),
                              onPressed: () {
                                if (_currentResultIndex > 0) {
                                  _playSong(
                                      _results[_currentResultIndex - 1],
                                      index: _currentResultIndex - 1);
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
                                if (_currentResultIndex + 1 <
                                    _results.length) {
                                  _playSong(
                                      _results[_currentResultIndex + 1],
                                      index: _currentResultIndex + 1);
                                }
                              },
                            ),
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
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.volume_down,
                                color: Colors.white, size: 28),
                            Expanded(
                              child: Slider(
                                value: _volume,
                                min: 0,
                                max: 2.0,
                                divisions: 20,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                onChanged: (value) async {
                                  setState(() => _volume = value);
                                  await _player.setVolume(_volume);
                                  modalSetState(() {});
                                },
                              ),
                            ),
                            const Icon(Icons.volume_up,
                                color: Colors.white, size: 28),
                          ],
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<Video?>(
              valueListenable: _currentVideoNotifier,
              builder: (_, currentVideo, __) {
                if (currentVideo == null) return const SizedBox();
                return InkWell(
                  onTap: () => _openFullPlayer(context),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 56),
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
          ),
        ],
      ),
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
  final YoutubeExplode yt;
  final Function(Video, {int? index}) onPlaySong;
  final Function(List<Video>) resultsCallback;
  final Animation<double> fadeAnimation;
  final ValueNotifier<Video?> currentVideoNotifier;

  const SearchPage(
      {super.key,
      required this.yt,
      required this.onPlaySong,
      required this.resultsCallback,
      required this.fadeAnimation,
      required this.currentVideoNotifier});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();

  List<Video> _results = [];
  List<Video> _history = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      widget.resultsCallback([]);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final searchResults = await widget.yt.search.getVideos(query);
      setState(() {
        _results = searchResults.toList();
        _isLoading = false;
      });
      widget.resultsCallback(_results);
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error searching: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final displayList = _controller.text.isEmpty ? _history : _results;

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
                    _debounce = Timer(
                        const Duration(milliseconds: 500),
                        () => _searchSongs(query));
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    icon: const Icon(Icons.search, color: Colors.white),
                    hintText: "Search YouTube Music...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : displayList.isEmpty
                      ? const Center(
                          child: Text("No results yet 🎵",
                              style: TextStyle(color: Colors.white70)))
                      : ValueListenableBuilder<Video?>(
                          valueListenable: widget.currentVideoNotifier,
                          builder: (_, currentVideo, __) {
                            return ListView.builder(
                              itemCount: displayList.length,
                              itemBuilder: (context, index) {
                                final video = displayList[index];
                                final isPlayingSong =
                                    currentVideo?.id.value == video.id.value;
                                return ListTile(
                                  onTap: () {
                                    if (!_history
                                        .any((v) => v.id == video.id)) {
                                      setState(() =>
                                          _history.insert(0, video));
                                    }
                                    widget.onPlaySong(video,
                                        index: _results.indexOf(video));
                                  },
                                  leading: Image.network(
                                    video.thumbnails.highResUrl,
                                    width: 50,
                                    height: 50,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.music_note,
                                            color: Colors.white),
                                  ),
                                  title: Text(video.title,
                                      style: const TextStyle(
                                          color: Colors.white)),
                                  subtitle: Text(video.author,
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  trailing: isPlayingSong
                                      ? FadeTransition(
                                          opacity: widget.fadeAnimation,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : null,
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Playlist Page with live counter ---
class PlaylistPage extends StatefulWidget {
  final ValueNotifier<List<Video>> likedSongsNotifier;
  final Function(Video, {int? index}) onPlaySong;

  const PlaylistPage(
      {super.key, required this.likedSongsNotifier, required this.onPlaySong});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Your Playlists 🎶",
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            Expanded(
              child: ListView(
                children: [
                  ValueListenableBuilder<List<Video>>(
                    valueListenable: widget.likedSongsNotifier,
                    builder: (_, likedSongs, __) {
                      return ListTile(
                        leading: const Icon(Icons.favorite,
                            color: Colors.pinkAccent, size: 32),
                        title: const Text("Liked Songs",
                            style:
                                TextStyle(color: Colors.white, fontSize: 18)),
                        subtitle: Text(
                            "${likedSongs.length} ${likedSongs.length == 1 ? 'song' : 'songs'}",
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14)),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailPage(
                                title: "Liked Songs",
                                songs: likedSongs,
                                onPlaySong: widget.onPlaySong,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistDetailPage extends StatelessWidget {
  final String title;
  final List<Video> songs;
  final Function(Video, {int? index}) onPlaySong;

  const PlaylistDetailPage(
      {super.key,
      required this.title,
      required this.songs,
      required this.onPlaySong});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0D1B2A),
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text("No songs yet",
                  style: TextStyle(color: Colors.white70)))
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final video = songs[index];
                return ListTile(
                  leading: Image.network(video.thumbnails.highResUrl,
                      width: 50,
                      height: 50,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.music_note, color: Colors.white)),
                  title: Text(video.title,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(video.author,
                      style: const TextStyle(color: Colors.white70)),
                  onTap: () => onPlaySong(video),
                );
              },
            ),
    );
  }
}
