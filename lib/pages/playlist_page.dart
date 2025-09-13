import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistPage extends StatefulWidget {
  final ValueNotifier<List<Video>> likedSongsNotifier;
  final Function(Video, {int? index, List<Video>? playlist}) onPlaySong;
  final Animation<double> fadeAnimation;
  final ValueNotifier<Video?> currentVideoNotifier;
  final Map<String, List<Video>> customPlaylists;
  final VoidCallback onPlaylistsChanged;
  final ValueNotifier<int> playlistUpdateNotifier;
  final Function(String, Video) onRemoveSongFromPlaylist;
  final Function(Video) onRemoveLikedSong;

  const PlaylistPage({
    super.key,
    required this.likedSongsNotifier,
    required this.onPlaySong,
    required this.fadeAnimation,
    required this.currentVideoNotifier,
    required this.customPlaylists,
    required this.onPlaylistsChanged,
    required this.playlistUpdateNotifier,
    required this.onRemoveSongFromPlaylist,
    required this.onRemoveLikedSong,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool _expanded = false;

  void _showCreatePlaylistDialog() {
    final TextEditingController playlistController = TextEditingController();

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
            controller: playlistController,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: () {
                final name = playlistController.text.trim();
                if (name.isNotEmpty && !widget.customPlaylists.containsKey(name)) {
                  setState(() {
                    widget.customPlaylists[name] = [];
                  });
                  widget.onPlaylistsChanged();
                  widget.playlistUpdateNotifier.value = widget.playlistUpdateNotifier.value + 1;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Your Playlists",
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 28),
                    onPressed: _showCreatePlaylistDialog,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: widget.playlistUpdateNotifier,
                builder: (_, updateTrigger, __) {
                  return ListView(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ValueListenableBuilder<List<Video>>(
                          valueListenable: widget.likedSongsNotifier,
                          builder: (_, likedSongs, __) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
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
                                              splashFactory: NoSplash.splashFactory,
                                            ),
                                            onPressed: () {
                                              if (likedSongs.isNotEmpty) {
                                                widget.onPlaySong(likedSongs.first, index: 0, playlist: likedSongs);
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
                                                        style:
                                                            const TextStyle(color: Colors.white, fontSize: 14)),
                                                    subtitle: Text(video.author,
                                                        style: const TextStyle(
                                                            color: Colors.white70, fontSize: 12)),
                                                    onTap: () => widget.onPlaySong(video, playlist: likedSongs),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        InkWell(
                                                          onTap: () => widget.onRemoveLikedSong(video),
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
                                                        if (isPlayingSong) ...[
                                                          const SizedBox(width: 8),
                                                          FadeTransition(
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
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        }).toList(),
                                      ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...widget.customPlaylists.entries.map((entry) {
                        final playlistName = entry.key;
                        final videos = entry.value;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
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
                                  : [
                                      // Add Play All button for custom playlists
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
                                            splashFactory: NoSplash.splashFactory,
                                          ),
                                          onPressed: () {
                                            if (videos.isNotEmpty) {
                                              widget.onPlaySong(videos.first, index: 0, playlist: videos);
                                            }
                                          },
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text("Play All"),
                                        ),
                                      ),
                                      // Add all videos in the playlist
                                      ...videos.map((video) {
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
                                                child: InkWell(
                                                  onTap: () => widget.onPlaySong(video, playlist: videos),
                                                  splashColor: Colors.transparent,
                                                  highlightColor: Colors.transparent,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                    child: Row(
                                                      children: [
                                                        Image.network(
                                                          video.thumbnails.highResUrl,
                                                          width: 45,
                                                          height: 45,
                                                          errorBuilder: (_, __, ___) =>
                                                              const Icon(Icons.music_note,
                                                                  color: Colors.white, size: 20),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              SizedBox(
                                                                width: double.infinity,
                                                                child: Text(
                                                                  video.title,
                                                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  softWrap: false,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 2),
                                                              SizedBox(
                                                                width: double.infinity,
                                                                child: Text(
                                                                  video.author,
                                                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  softWrap: false,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        InkWell(
                                                          onTap: () => widget.onRemoveSongFromPlaylist(playlistName, video),
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
                                                        if (isPlayingSong) ...[
                                                          const SizedBox(width: 8),
                                                          FadeTransition(
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
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
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