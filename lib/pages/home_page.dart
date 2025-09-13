import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:share_plus/share_plus.dart';
import 'search_page.dart';
import 'playlist_page.dart';
import '../utils/format_duration.dart';

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

  // --- Add ValueNotifier for custom playlists to trigger updates ---
  final ValueNotifier<int> _playlistUpdateNotifier = ValueNotifier<int>(0);

  // Add a ValueNotifier to trigger modal updates
  final ValueNotifier<int> _modalUpdateNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();

    // Configure system UI overlay style for white status bar icons
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0D1B2A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Disable system sounds
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
        // Clear buffering when playing starts
        if (_isPlaying) _isBuffering = false;
      });
      
      // Update modal when player state changes
      _modalUpdateNotifier.value = _modalUpdateNotifier.value + 1;
      
      if (_isPlaying) {
        _animController.forward();
      } else {
        _animController.stop();
      }
    });

    _player.processingStateStream.listen((state) {
      if (!mounted) return;
      
      // Clear buffering when audio is ready to play
      if (state == ProcessingState.ready) {
        setState(() => _isBuffering = false);
        _modalUpdateNotifier.value = _modalUpdateNotifier.value + 1;
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
        onPlaySong: (video, {int? index, List<Video>? playlist}) =>
            _playSong(video, index: index, fromPlaylist: playlist ?? _likedSongsNotifier.value),
        fadeAnimation: _fadeAnimation,
        currentVideoNotifier: _currentVideoNotifier,
        customPlaylists: _customPlaylists,
        onPlaylistsChanged: () => setState(() {}),
        playlistUpdateNotifier: _playlistUpdateNotifier,
        onRemoveSongFromPlaylist: _removeSongFromPlaylist,
        onRemoveLikedSong: _removeLikedSong,
      ),
    ];
  }

  @override
  void dispose() {
    _player.dispose();
    yt.close();
    _animController.dispose();
    _playlistUpdateNotifier.dispose();
    _modalUpdateNotifier.dispose();
    super.dispose();
  }

  void _removeSongFromPlaylist(String playlistName, Video video) {
    setState(() {
      _customPlaylists[playlistName]?.removeWhere((v) => v.id.value == video.id.value);
      
      // Update song-playlist mapping
      final songId = video.id.value;
      _songInPlaylists[songId]?.remove(playlistName);
      if (_songInPlaylists[songId]?.isEmpty ?? false) {
        _songInPlaylists.remove(songId);
      }
      
      // Trigger playlist update notification
      _playlistUpdateNotifier.value = _playlistUpdateNotifier.value + 1;
    });
  }

  void _removeLikedSong(Video video) {
    final current = List<Video>.from(_likedSongsNotifier.value);
    current.removeWhere((v) => v.id.value == video.id.value);
    _likedSongsNotifier.value = current;
  }

  Future<void> _playSong(Video video,
      {int? index, required List<Video> fromPlaylist}) async {
    // Immediately update UI state for instant feedback
    setState(() {
      _currentPlaylist = fromPlaylist;
      _currentPlaylistIndex = index ?? fromPlaylist.indexOf(video);
      _isBuffering = true;
    });

    _currentVideoNotifier.value = video;

    // Run audio preparation asynchronously without blocking UI
    _prepareAndPlayAudio(video);
  }

  Future<void> _prepareAndPlayAudio(Video video) async {
    try {
      String? audioUrl = _audioUrls[video.id.value];
      
      if (audioUrl == null) {
        // Fetch audio URL in background
        final manifest = await yt.videos.streamsClient.getManifest(video.id);
        final audio = manifest.audioOnly.withHighestBitrate();
        audioUrl = audio.url.toString();
        _audioUrls[video.id.value] = audioUrl;
      }

      // Setup and play audio
      await _player.stop();
      await _player.setUrl(audioUrl);
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() => _isBuffering = false);
        _modalUpdateNotifier.value = _modalUpdateNotifier.value + 1;
      }
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

  void _shareCurrentSong(Video video) {
    final youtubeUrl = 'https://www.youtube.com/watch?v=${video.id.value}';
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool copied = false;
            return AlertDialog(
              backgroundColor: const Color(0xFF1B2A3C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Share Song",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'by ${video.author}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            youtubeUrl,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () async {
                            try {
                              await Clipboard.setData(ClipboardData(text: youtubeUrl));
                              setState(() {
                                copied = true;
                              });
                              // Show success message and close after delay
                              Timer(const Duration(seconds: 1), () {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Link copied to clipboard!'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              });
                            } catch (e) {
                              // Handle error if clipboard access fails
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to copy link'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.deepPurple.shade200,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              copied ? Icons.check : Icons.copy,
                              color: Colors.deepPurple.shade200,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copied 
                      ? 'Link copied successfully!'
                      : 'Click the copy icon to copy the link',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Close",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddToPlaylistDialog(Video? currentVideo, StateSetter? modalSetState) {
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
                      "No available playlist\nTry creating one",
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
                    splashFactory: NoSplash.splashFactory,
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
                      
                      // Trigger playlist update notification
                      _playlistUpdateNotifier.value = _playlistUpdateNotifier.value + 1;
                    });
                    Navigator.pop(context);
                    // Update modal state immediately after dialog closes
                    modalSetState?.call(() {});
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
                return ValueListenableBuilder<int>(
                  valueListenable: _modalUpdateNotifier,
                  builder: (_, updateTrigger, __) {
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
                                  Container(
                                    height: 250,
                                    width: 250,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Image.network(
                                      currentVideo.thumbnails.maxResUrl,
                                      height: 250,
                                      width: 250,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          height: 250,
                                          width: 250,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.deepPurple.shade400,
                                                Colors.deepPurple.shade700,
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.music_note,
                                                size: 80,
                                                color: Colors.white.withOpacity(0.8),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
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
                                        Text(formatDuration(position),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12)),
                                        Text(formatDuration(_duration),
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
                            
                            // First row of controls - Main playback controls
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
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
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
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
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
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
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Second row of controls - Additional controls
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Add to Playlist
                                IconButton(
                                  icon: Icon(
                                    Icons.add,
                                    size: 30,
                                    color: _songInPlaylists[_currentVideoNotifier.value?.id.value]?.isNotEmpty ?? false
                                      ? Colors.purpleAccent
                                      : Colors.white,
                                  ),
                                  onPressed: () => _showAddToPlaylistDialog(_currentVideoNotifier.value, modalSetState),
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                // Like Button
                                IconButton(
                                  icon: Icon(
                                    _isLiked(currentVideo)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 30,
                                    color: _isLiked(currentVideo)
                                        ? Colors.red
                                        : Colors.white,
                                  ),
                                  onPressed: () =>
                                      _toggleLike(currentVideo, modalSetState),
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                // Repeat Button
                                IconButton(
                                  icon: Icon(Icons.repeat,
                                      size: 30,
                                      color: _isRepeating
                                          ? Colors.blueAccent
                                          : Colors.white),
                                  onPressed: () => _toggleRepeat(modalSetState),
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                // Share Button
                                IconButton(
                                  icon: const Icon(Icons.share,
                                      size: 30, color: Colors.white),
                                  onPressed: () => _shareCurrentSong(currentVideo),
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
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
      },
    );
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
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(
                            bottom: 8, left: 8, right: 8),
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
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                    ),
                                  ),
                          ],
                        ),
                      ),
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
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: "Search"),
          BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play), label: "Playlists"),
        ],
      ),
    );
  }
}