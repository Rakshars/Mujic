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
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Search",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: "Playlists",
          ),
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

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode yt = YoutubeExplode();

  List<Video> _results = [];
  bool _isLoading = false;

  Video? _currentVideo;
  bool _isPlaying = false;

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final searchResults = await yt.search.getVideos(query);
      setState(() {
        _results = searchResults.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error searching: $e");
    }
  }

  // 🔊 Fixed playSong for audioplayers 6.x (network streaming)
  Future<void> _playSong(Video video) async {
    try {
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final audio = manifest.audioOnly.withHighestBitrate();

      await _player.stop();

      // ✅ Correct way for network URL in audioplayers 6.x
      await _player.play(UrlSource(audio.url.toString()));

      setState(() {
        _currentVideo = video;
        _isPlaying = true;
      });

      debugPrint("▶️ Playing ${video.title} - ${audio.url}");
    } catch (e) {
      debugPrint("Error playing: $e");
    }
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _player.resume();
      setState(() => _isPlaying = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            // 🔎 Search bar
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
                  onSubmitted: _searchSongs,
                  decoration: InputDecoration(
                    icon: const Icon(Icons.search, color: Colors.white),
                    hintText: "Search YouTube Music...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white70),
                      onPressed: () => _searchSongs(_controller.text),
                    ),
                  ),
                ),
              ),
            ),

            // Results
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            "No results yet 🎵",
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final video = _results[index];

                            return ListTile(
                              onTap: () => _playSong(video),
                              leading: Image.network(
                                video.thumbnails.highResUrl,
                                width: 50,
                                height: 50,
                                errorBuilder: (ctx, _, __) =>
                                    const Icon(Icons.music_note,
                                        color: Colors.white),
                              ),
                              title: Text(
                                video.title,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                video.author,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: _currentVideo?.id == video.id
                                  ? const Icon(Icons.equalizer,
                                      color: Colors.green)
                                  : null,
                            );
                          },
                        ),
            ),

            // 🎶 Mini player
            if (_currentVideo != null)
              Container(
                color: Colors.black.withOpacity(0.7),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Image.network(
                      _currentVideo!.thumbnails.lowResUrl,
                      width: 50,
                      height: 50,
                      errorBuilder: (ctx, _, __) =>
                          const Icon(Icons.music_note, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentVideo!.title,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayPause,
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

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: const Center(
        child: Text(
          "Your Playlists 🎶",
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }
}
