import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
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

  List<dynamic> _results = [];
  bool _isLoading = false;
  String? _currentSong;

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse("https://saavn.dev/api/search/songs?query=$query");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _results = data["data"]["results"] ?? [];
          _isLoading = false;
        });

        debugPrint("Search results: $_results");
      } else {
        setState(() => _isLoading = false);
        debugPrint("Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Exception: $e");
    }
  }

  Future<void> _playSong(dynamic item) async {
    try {
      final songId = item["id"];
      if (songId == null) return;

      final url = Uri.parse("https://saavn.dev/api/songs/$songId");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songData =
            (data["data"] as List).isNotEmpty ? data["data"][0] : null;

        if (songData == null) return;

        String? urlToPlay;

        // 1️⃣ Try full download URLs (sometimes missing)
        final List<dynamic>? urls = songData["downloadUrl"];
        if (urls != null && urls.isNotEmpty) {
          final validUrls = urls
              .where((u) => u != null && u["link"] != null)
              .map((u) => u["link"] as String)
              .toList();
          if (validUrls.isNotEmpty) {
            urlToPlay = validUrls.last; // usually highest quality
          }
        }

        // 2️⃣ Fallback: preview URL (always available, 30 sec)
        if (urlToPlay == null &&
            songData["more_info"] != null &&
            songData["more_info"]["preview_url"] != null) {
          urlToPlay = songData["more_info"]["preview_url"];
        }

        if (urlToPlay == null) {
          debugPrint("⚠️ No playable URL found for ${songData["name"]}");
          return;
        }

        await _player.stop();
        await _player.play(UrlSource(urlToPlay));

        setState(() {
          _currentSong = songData["name"];
        });

        debugPrint("▶️ Playing: $urlToPlay");
      } else {
        debugPrint("Error fetching song details: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error playing song: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A), // Midnight Blue
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔎 Search bar
              Container(
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
                    hintText: "Search JioSaavn songs...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white70),
                      onPressed: () => _searchSongs(_controller.text),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

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
                              final item = _results[index];

                              final title = item["name"] ?? "Unknown Title";
                              final artist =
                                  item["primaryArtists"] ?? "Unknown Artist";

                              String? image;
                              if (item["image"] != null &&
                                  item["image"] is List &&
                                  item["image"].isNotEmpty) {
                                image = item["image"].last["link"];
                              }

                              return ListTile(
                                onTap: () => _playSong(item),
                                leading: image != null
                                    ? Image.network(
                                        image,
                                        width: 50,
                                        height: 50,
                                        errorBuilder: (ctx, _, __) =>
                                            const Icon(Icons.music_note,
                                                color: Colors.white),
                                      )
                                    : const Icon(Icons.music_note,
                                        color: Colors.white),
                                title: Text(
                                  title,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  artist,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                trailing: _currentSong == title
                                    ? const Icon(Icons.equalizer,
                                        color: Colors.green)
                                    : null,
                              );
                            },
                          ),
              )
            ],
          ),
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
