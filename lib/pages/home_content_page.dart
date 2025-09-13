import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class HomeContentPage extends StatefulWidget {
  final YoutubeExplode yt;
  final Function(Video, {int? index}) onPlaySong;
  final Animation<double> fadeAnimation;
  final ValueNotifier<Video?> currentVideoNotifier;
  final ValueNotifier<List<Video>> recentlyPlayedNotifier;
  final ValueNotifier<List<Video>> likedSongsNotifier;

  const HomeContentPage({
    super.key,
    required this.yt,
    required this.onPlaySong,
    required this.fadeAnimation,
    required this.currentVideoNotifier,
    required this.recentlyPlayedNotifier,
    required this.likedSongsNotifier,
  });

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage>
    with AutomaticKeepAliveClientMixin {
  
  List<Video> _trendingMusic = [];
  List<Video> _madeForYou = [];
  bool _isLoading = true;
  bool _hasMadeForYouContent = false;
  List<String> _trendingQueries = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeTrendingQueries();
    _loadHomeContent();
    
    // Listen to recently played to generate "Made for You" content
    widget.recentlyPlayedNotifier.addListener(_generateMadeForYouContent);
  }

  void _initializeTrendingQueries() {
    final currentYear = DateTime.now().year;
    _trendingQueries = [
      'trending music $currentYear',
      'viral songs $currentYear',
      'hit songs $currentYear',
      'popular music $currentYear',
      'top charts $currentYear',
      'new releases $currentYear',
      'latest hits $currentYear',
    ];
  }

  @override
  void dispose() {
    widget.recentlyPlayedNotifier.removeListener(_generateMadeForYouContent);
    super.dispose();
  }

  Future<void> _loadHomeContent() async {
    setState(() => _isLoading = true);

    try {
      // Use a random query from the list for variety
      final randomQuery = _trendingQueries[DateTime.now().millisecondsSinceEpoch % _trendingQueries.length];
      final trendingResults = await widget.yt.search.getVideos(randomQuery);
      _trendingMusic = trendingResults.take(10).toList();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error loading home content: $e");
    }
  }

  Future<void> _generateMadeForYouContent() async {
    final recentlyPlayed = widget.recentlyPlayedNotifier.value;
    
    if (recentlyPlayed.isEmpty) {
      setState(() {
        _madeForYou = [];
        _hasMadeForYouContent = false;
      });
      return;
    }

    try {
      // Get unique artists from recently played songs
      final artists = recentlyPlayed
          .map((video) => video.author)
          .toSet()
          .take(3)
          .toList();

      List<Video> suggestions = [];

      // Generate suggestions based on artists
      for (final artist in artists) {
        try {
          final artistResults = await widget.yt.search.getVideos('$artist songs');
          final filteredResults = artistResults
              .where((video) => !recentlyPlayed.any((recent) => recent.id.value == video.id.value))
              .take(3)
              .toList();
          suggestions.addAll(filteredResults);
        } catch (e) {
          debugPrint("Error getting suggestions for $artist: $e");
        }
      }

      // If we have less than 6 suggestions, add some genre-based suggestions
      if (suggestions.length < 6) {
        try {
          final genreResults = await widget.yt.search.getVideos('similar songs');
          final additionalSuggestions = genreResults
              .where((video) => 
                  !suggestions.any((s) => s.id.value == video.id.value) &&
                  !recentlyPlayed.any((recent) => recent.id.value == video.id.value))
              .take(6 - suggestions.length)
              .toList();
          suggestions.addAll(additionalSuggestions);
        } catch (e) {
          debugPrint("Error getting additional suggestions: $e");
        }
      }

      setState(() {
        _madeForYou = suggestions.take(8).toList();
        _hasMadeForYouContent = _madeForYou.isNotEmpty;
      });
    } catch (e) {
      debugPrint("Error generating Made for You content: $e");
    }
  }

  void _removeFromRecentlyPlayed(Video video) {
    final current = List<Video>.from(widget.recentlyPlayedNotifier.value);
    current.removeWhere((v) => v.id.value == video.id.value);
    widget.recentlyPlayedNotifier.value = current;
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                "See all",
                style: TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalVideoList(List<Video> videos, {bool showLargeCards = false, bool showRemoveButton = false}) {
    return Container(
      height: showLargeCards ? 200 : 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];
          return ValueListenableBuilder<Video?>(
            valueListenable: widget.currentVideoNotifier,
            builder: (_, currentVideo, __) {
              final isPlayingSong = currentVideo?.id.value == video.id.value;
              return Container(
                width: showLargeCards ? 140 : 120,
                margin: const EdgeInsets.only(right: 12.0),
                child: InkWell(
                  onTap: () => widget.onPlaySong(video),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: showLargeCards ? 105 : 90,
                              width: double.infinity,
                              color: Colors.grey[800],
                              child: Image.network(
                                video.thumbnails.highResUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.deepPurple.shade400,
                                        Colors.deepPurple.shade700,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.music_note,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showRemoveButton)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: InkWell(
                                onTap: () => _removeFromRecentlyPlayed(video),
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                          if (isPlayingSong)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: FadeTransition(
                                    opacity: widget.fadeAnimation,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: showLargeCards ? 32 : 28,
                        child: Text(
                          video.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 14,
                        child: Text(
                          video.author,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildQuickAccessSection() {
    return ValueListenableBuilder<List<Video>>(
      valueListenable: widget.likedSongsNotifier,
      builder: (_, likedSongs, __) {
        return Column(
          children: [
            _buildSectionHeader("Quick Access"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  // Liked Songs Quick Access
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.pink, Colors.purple],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.favorite, color: Colors.white, size: 28),
                      ),
                      title: const Text("Liked Songs", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: Text("${likedSongs.length} songs", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      trailing: likedSongs.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                            onPressed: () {
                              if (likedSongs.isNotEmpty) {
                                widget.onPlaySong(likedSongs.first);
                              }
                            },
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                          )
                        : null,
                      onTap: likedSongs.isNotEmpty 
                        ? () => widget.onPlaySong(likedSongs.first)
                        : null,
                    ),
                  ),
                  // Recently Played Quick Access
                  ValueListenableBuilder<List<Video>>(
                    valueListenable: widget.recentlyPlayedNotifier,
                    builder: (_, recentlyPlayed, __) {
                      if (recentlyPlayed.isEmpty) return const SizedBox();
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey[800],
                              child: Image.network(
                                recentlyPlayed.first.thumbnails.highResUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.blue, Colors.indigo],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.history, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                          ),
                          title: const Text("Recently Played", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                          subtitle: Text("Last played: ${recentlyPlayed.first.title.length > 30 ? recentlyPlayed.first.title.substring(0, 30) + '...' : recentlyPlayed.first.title}", 
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                            onPressed: () => widget.onPlaySong(recentlyPlayed.first),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                          ),
                          onTap: () => widget.onPlaySong(recentlyPlayed.first),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : RefreshIndicator(
              onRefresh: () async {
                _initializeTrendingQueries();
                await _loadHomeContent();
              },
              color: Colors.white,
              backgroundColor: const Color(0xFF1B2A3C),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App title and greeting
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Good ${_getGreeting()}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "What would you like to listen to?",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Refresh button for trending content
                              IconButton(
                                onPressed: () {
                                  _initializeTrendingQueries();
                                  _loadHomeContent();
                                },
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Quick Access Section
                    _buildQuickAccessSection(),
                    
                    const SizedBox(height: 24),
                    
                    // Recently Played Section (horizontal list)
                    ValueListenableBuilder<List<Video>>(
                      valueListenable: widget.recentlyPlayedNotifier,
                      builder: (_, recentlyPlayed, __) {
                        if (recentlyPlayed.isEmpty) return const SizedBox();
                        return Column(
                          children: [
                            _buildSectionHeader("Recently Played"),
                            _buildHorizontalVideoList(recentlyPlayed.take(10).toList(), showRemoveButton: true),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                    
                    // Made for You Section (only show if user has search history)
                    if (_hasMadeForYouContent && _madeForYou.isNotEmpty) ...[
                      _buildSectionHeader("Made for You"),
                      _buildHorizontalVideoList(_madeForYou),
                      const SizedBox(height: 100), // Extra padding for bottom player
                    ],
                    
                    // Add extra padding at the end if there's no Made for You content
                    if (!_hasMadeForYouContent || _madeForYou.isEmpty)
                      const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "morning";
    } else if (hour < 17) {
      return "afternoon";
    } else {
      return "evening";
    }
  }
}