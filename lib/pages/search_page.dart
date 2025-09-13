import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class SearchPage extends StatefulWidget {
  final YoutubeExplode yt;
  final Function(Video, {int? index}) onPlaySong;
  final Function(List<Video>) resultsCallback;
  final Animation<double> fadeAnimation;
  final ValueNotifier<Video?> currentVideoNotifier;

  const SearchPage({
    super.key,
    required this.yt,
    required this.onPlaySong,
    required this.resultsCallback,
    required this.fadeAnimation,
    required this.currentVideoNotifier,
  });

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

  void _removeFromHistory(Video video) {
    setState(() {
      _history.removeWhere((v) => v.id.value == video.id.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final displayList = _controller.text.isEmpty ? _history : _results;
    final isShowingHistory = _controller.text.isEmpty;

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
                    hintText: "Search",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
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
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                                      leading: Image.network(
                                        video.thumbnails.highResUrl,
                                        width: 45,
                                        height: 45,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.music_note,
                                                color: Colors.white, size: 20),
                                      ),
                                      title: Text(video.title,
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 14)),
                                      subtitle: Text(video.author,
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 12)),
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isShowingHistory)
                                            InkWell(
                                              onTap: () => _removeFromHistory(video),
                                              splashColor: Colors.transparent,
                                              highlightColor: Colors.transparent,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          if (isPlayingSong)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                left: isShowingHistory ? 8.0 : 0.0,
                                              ),
                                              child: FadeTransition(
                                                opacity: widget.fadeAnimation,
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
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