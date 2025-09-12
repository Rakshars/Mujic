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
  Duration _duration = Duration.zero;
  final Map<String, String> _audioUrls = {};

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  double _volume = 1.0;

  // --- Playlists ---
  List<Video> _results = [];
  final ValueNotifier<List<Video>> _likedSongsNotifier =
      ValueNotifier<List<Video>>([]);

  // --- Track current playlist (search or liked) ---
  List<Video> _currentPlaylist = [];
  int _currentPlaylistIndex = -1;

  late final List<Widget> _pages;

  // --- Store custom playlists globally in HomePage ---
  final Map<String, List<Video>> _customPlaylists = {};

  // --- Track which playlists the current song is added to ---
  final Map<String, Set<String>> _songInPlaylists = {}; 


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
        if (_isRepeating && _currentPlaylistIndex >= 0) {
          _playSong(_currentPlaylist[_currentPlaylistIndex],
              index: _currentPlaylistIndex,
              fromPlaylist: _currentPlaylist);
        } else if (_currentPlaylistIndex + 1 < _currentPlaylist.length) {
          final nextVideo = _currentPlaylist[_currentPlaylistIndex + 1];
          _playSong(nextVideo,
              index: _currentPlaylistIndex + 1,
              fromPlaylist: _currentPlaylist);
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
        onPlaySong: (video, {int? index}) =>
            _playSong(video, index: index, fromPlaylist: _results),
        resultsCallback: (r) => setState(() => _results = r),
        fadeAnimation: _fadeAnimation,
        currentVideoNotifier: _currentVideoNotifier,
      ),
      PlaylistPage(
        likedSongsNotifier: _likedSongsNotifier,
        onPlaySong: (video, {int? index}) =>
            _playSong(video, index: index, fromPlaylist: _likedSongsNotifier.value),
        fadeAnimation: _fadeAnimation,
        currentVideoNotifier: _currentVideoNotifier,
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

  Future<void> _playSong(Video video,
      {int? index, required List<Video> fromPlaylist}) async {
    setState(() {
      _currentPlaylist = fromPlaylist;
      _currentPlaylistIndex = index ?? fromPlaylist.indexOf(video);
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

  void _showAddToPlaylistDialog(Video? currentVideo) {
  if (currentVideo == null) return;

  final songId = currentVideo.id.value;
  final selectedPlaylists = Set<String>.from(_songInPlaylists[songId] ?? {});

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1B2A3C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Add to Playlist",
              style: TextStyle(color: Colors.white),
            ),
            content: _customPlaylists.isEmpty
                ? const Text(
                    "No playlists available.\nCreate one first!",
                    style: TextStyle(color: Colors.white70),
                  )
                : SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: _customPlaylists.keys.map((playlistName) {
                        final isSelected = selectedPlaylists.contains(playlistName);
                        return CheckboxListTile(
                          title: Text(
                            playlistName,
                            style: const TextStyle(color: Colors.white),
                          ),
                          activeColor: Colors.purpleAccent,
                          checkColor: Colors.white,
                          value: isSelected,
                          onChanged: (checked) {
                            setStateDialog(() {
                              if (checked == true) {
                                selectedPlaylists.add(playlistName);
                              } else {
                                selectedPlaylists.remove(playlistName);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                ),
                onPressed: () {
                  setState(() {
                    // Update song-playlist mapping
                    _songInPlaylists[songId] = selectedPlaylists;

                    // Add song to the selected playlists
                    for (final playlist in _customPlaylists.keys) {
                      if (selectedPlaylists.contains(playlist)) {
                        if (!_customPlaylists[playlist]!
                            .any((v) => v.id.value == songId)) {
                          _customPlaylists[playlist]!.add(currentVideo);
                        }
                      } else {
                        _customPlaylists[playlist]!
                            .removeWhere((v) => v.id.value == songId);
                      }
                    }
                  });
                  Navigator.pop(context);
                },
                child: const Text(
                  "Save",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      );
    },
  );
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
                            // --- PLUS ICON (Add to Playlist) ---
                            IconButton(
                              icon: Icon(
                              Icons.add,
                              size: 32,
                              color: _songInPlaylists[_currentVideoNotifier.value?.id.value]?.isNotEmpty ?? false
                                ? Colors.purpleAccent
                                : Colors.white,
                              ),
                              onPressed: () => _showAddToPlaylistDialog(_currentVideoNotifier.value),
                            ),
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
                                if (_currentPlaylistIndex > 0) {
                                  _playSong(
                                      _currentPlaylist[_currentPlaylistIndex - 1],
                                      index: _currentPlaylistIndex - 1,
                                      fromPlaylist: _currentPlaylist);
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
                                if (_currentPlaylistIndex + 1 <
                                    _currentPlaylist.length) {
                                  _playSong(
                                      _currentPlaylist[_currentPlaylistIndex + 1],
                                      index: _currentPlaylistIndex + 1,
                                      fromPlaylist: _currentPlaylist);
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(
                            bottom: 8, left: 8, right: 8), // moved closer
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                currentVideo.thumbnails.lowResUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.music_note,
                                        color: Colors.white),
                              ),
                            ),
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
                                    duration:
                                        const Duration(milliseconds: 250),
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
                      // --- NEW progress bar below mini player ---
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final progress = (_duration.inMilliseconds == 0)
                              ? 0.0
                              : position.inMilliseconds /
                                  _duration.inMilliseconds;
                          return LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white70),
                            minHeight: 4,
                          );
                        },
                      ),
                    ],
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

// --- SearchPage and PlaylistPage remain unchanged ---
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
                    _debounce =
                        Timer(const Duration(milliseconds: 500), () {
                      _searchSongs(query);
                    });
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
                          child: Text(
                            "No songs",
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final video = displayList[index];
                            return ValueListenableBuilder<Video?>(
                              valueListenable: widget.currentVideoNotifier,
                              builder: (_, currentVideo, __) {
                                final isPlayingSong =
                                    currentVideo?.id.value == video.id.value;
                                return ListTile(
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
                                  onTap: () {
                                    widget.onPlaySong(video, index: index);
                                    setState(() {
                                      if (_history.any((v) =>
                                          v.id.value == video.id.value)) {
                                        _history.removeWhere((v) =>
                                            v.id.value == video.id.value);
                                      }
                                      _history.insert(0, video);
                                    });
                                  },
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

class PlaylistPage extends StatefulWidget {
  final ValueNotifier<List<Video>> likedSongsNotifier;
  final Function(Video, {int? index}) onPlaySong;
  final Animation<double> fadeAnimation;
  final ValueNotifier<Video?> currentVideoNotifier;

  const PlaylistPage({
    super.key,
    required this.likedSongsNotifier,
    required this.onPlaySong,
    required this.fadeAnimation,
    required this.currentVideoNotifier,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool _expanded = false;

  /// Stores custom playlists in the format:
  /// { 'My Playlist': [Video1, Video2, ...] }
  final Map<String, List<Video>> _customPlaylists = {};

  void _showCreatePlaylistDialog() {
    final TextEditingController _playlistController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B2A3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Create Playlist",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: _playlistController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Enter playlist name",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              onPressed: () {
                final name = _playlistController.text.trim();
                if (name.isNotEmpty && !_customPlaylists.containsKey(name)) {
                  setState(() {
                  _customPlaylists[name] = [];
                  });
                }
                Navigator.pop(context);
            },

              child: const Text("Create", style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            /// Top Row with Title + Plus Icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Your Playlists 🎶",
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 28),
                    onPressed: _showCreatePlaylistDialog,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                children: [
                  /// --- Liked Songs ---
                  ValueListenableBuilder<List<Video>>(
                    valueListenable: widget.likedSongsNotifier,
                    builder: (_, likedSongs, __) {
                      return ExpansionTile(
                        initiallyExpanded: _expanded,
                        onExpansionChanged: (value) {
                          setState(() => _expanded = value);
                        },
                        leading: const Icon(Icons.favorite,
                            color: Colors.pinkAccent, size: 32),
                        title: const Text("Liked Songs",
                            style: TextStyle(color: Colors.white, fontSize: 18)),
                        subtitle: Text(
                          "${likedSongs.length} ${likedSongs.length == 1 ? 'song' : 'songs'}",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        children: likedSongs.isEmpty
                            ? [
                                const ListTile(
                                  title: Text("No songs yet",
                                      style: TextStyle(color: Colors.white70)),
                                )
                              ]
                            : [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (likedSongs.isNotEmpty) {
                                        widget.onPlaySong(likedSongs.first, index: 0);
                                      }
                                    },
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text("Play All"),
                                  ),
                                ),
                                ...likedSongs.map((video) {
                                  return ValueListenableBuilder<Video?>(
                                    valueListenable: widget.currentVideoNotifier,
                                    builder: (_, currentVideo, __) {
                                      final isPlayingSong =
                                          currentVideo?.id.value == video.id.value;
                                      return ListTile(
                                        leading: Image.network(
                                          video.thumbnails.highResUrl,
                                          width: 50,
                                          height: 50,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.music_note,
                                                  color: Colors.white),
                                        ),
                                        title: Text(video.title,
                                            style:
                                                const TextStyle(color: Colors.white)),
                                        subtitle: Text(video.author,
                                            style: const TextStyle(
                                                color: Colors.white70)),
                                        onTap: () => widget.onPlaySong(video),
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
                                }).toList(),
                              ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  /// --- Custom Playlists Section ---
                  ..._customPlaylists.entries.map((entry) {
                    final playlistName = entry.key;
                    final videos = entry.value;

                    return ExpansionTile(
                      leading: const Icon(Icons.queue_music,
                          color: Colors.white, size: 28),
                      title: Text(
                        playlistName,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      subtitle: Text(
                        "${videos.length} ${videos.length == 1 ? 'song' : 'songs'}",
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      children: videos.isEmpty
                          ? [
                              const ListTile(
                                title: Text("No songs yet",
                                    style: TextStyle(color: Colors.white70)),
                              )
                            ]
                          : videos.map((video) {
                              return ListTile(
                                leading: Image.network(
                                  video.thumbnails.highResUrl,
                                  width: 50,
                                  height: 50,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.music_note,
                                          color: Colors.white),
                                ),
                                title: Text(video.title,
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text(video.author,
                                    style:
                                        const TextStyle(color: Colors.white70)),
                                onTap: () => widget.onPlaySong(video),
                              );
                            }).toList(),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
