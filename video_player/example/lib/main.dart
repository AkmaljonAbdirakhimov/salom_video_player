import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'pip_example.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Player Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Player Examples'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Video Download Example'),
            subtitle:
                const Text('Download and cache videos for offline playback'),
            trailing: const Icon(Icons.download),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const VideoDownloadScreen()),
              );
            },
          ),
          ListTile(
            title: const Text('Picture-in-Picture Example'),
            subtitle: const Text('Enable PiP mode for video playback'),
            trailing: const Icon(Icons.picture_in_picture),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PictureInPictureExample()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class VideoDownloadScreen extends StatefulWidget {
  const VideoDownloadScreen({super.key});

  @override
  State<VideoDownloadScreen> createState() => _VideoDownloadScreenState();
}

class _VideoDownloadScreenState extends State<VideoDownloadScreen> {
  // List of sample videos to display
  final List<VideoItem> _videos = [
    VideoItem(
      name: 'Big Buck Bunny',
      url:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
    ),
    VideoItem(
      name: 'Elephant Dream',
      url:
          'https://bitmovin-a.akamaihd.net/content/MI201109210084_1/mpds/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.mpd',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
    ),
    VideoItem(
      name: 'Tears of Steel',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg',
    ),
  ];

  // Cache manager for downloading videos
  final VideoCacheManager _cacheManager = VideoCacheManager.instance;

  @override
  void initState() {
    super.initState();
    _checkDownloadedVideos();
  }

  // Check which videos are already downloaded
  Future<void> _checkDownloadedVideos() async {
    for (final video in _videos) {
      if (!video.isAsset) {
        final downloadState = await _cacheManager.getDownloadState(video.url);
        setState(() {
          video.downloadState = downloadState;
          video.downloadProgress =
              downloadState == DownloadState.downloaded ? 1.0 : 0.0;

          // If it's downloaded, get the size
          if (downloadState == DownloadState.downloaded) {
            _cacheManager.getDownloadProgress(video.url).then((progress) {
              setState(() {
                video.bytesDownloaded = progress.bytesDownloaded;
              });
            });
          }

          // If it's currently downloading, set up the listener to continue showing progress
          if (downloadState == DownloadState.downloading) {
            _setupDownloadProgressListener(video);
          }
        });
      }
    }
  }

  // Start downloading a video
  Future<void> _startDownload(VideoItem video) async {
    if (video.isAsset) {
      return;
    }

    setState(() {
      video.downloadState = DownloadState.downloading;
      video.downloadProgress = 0.0;
      video.bytesDownloaded = 0;
    });

    try {
      // Cancel any existing download progress listeners for this URL
      _cacheManager
          .getDownloadProgressStream(video.url)
          .drain()
          .catchError((_) {});

      // Start the download
      await _cacheManager.startDownload(video.url);

      // Set up a fresh listener for the download progress
      _setupDownloadProgressListener(video);
    } catch (e) {
      setState(() {
        video.downloadState = DownloadState.failed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start download: $e')),
      );
    }
  }

  // Helper method to set up download progress listeners
  void _setupDownloadProgressListener(VideoItem video) {
    // Get a fresh stream for this URL
    _cacheManager.getDownloadProgressStream(video.url).listen(
      (progress) {
        if (mounted) {
          setState(() {
            video.downloadProgress = progress.progress;
            video.bytesDownloaded = progress.bytesDownloaded;
            video.downloadState = progress.progress == 1.0
                ? DownloadState.downloaded
                : DownloadState.downloading;
          });
        }
      },
      onDone: () {
        print('onDone: ${video.url}');
        if (mounted) {
          // Update download state after completion
          _checkDownloadedVideos();
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            video.downloadState = DownloadState.failed;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download error: $e')),
          );
        }
      },
    );
  }

  // Cancel an ongoing download
  Future<void> _cancelDownload(VideoItem video) async {
    if (video.isAsset || !video.isDownloading) {
      return;
    }

    try {
      final success = await _cacheManager.cancelDownload(video.url);
      if (success) {
        setState(() {
          video.downloadState = DownloadState.initial;
          video.downloadProgress = 0.0;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel download: $e')),
      );
    }
  }

  // Remove a downloaded video
  Future<void> _removeDownload(VideoItem video) async {
    if (video.isAsset || !video.isDownloaded) {
      return;
    }

    try {
      final success = await _cacheManager.removeDownload(video.url);
      if (success) {
        setState(() {
          video.downloadState = DownloadState.initial;
          video.downloadProgress = 0.0;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove download: $e')),
      );
    }
  }

  // Play a video
  void _playVideo(VideoItem video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(videoItem: video),
      ),
    );
  }

  // Format bytes to human-readable format
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Get an icon based on download state
  Widget _getDownloadStateIcon(DownloadState state) {
    return switch (state) {
      DownloadState.initial => const Icon(Icons.cloud_outlined),
      DownloadState.downloading =>
        const Icon(Icons.downloading, color: Colors.blue),
      DownloadState.downloaded =>
        const Icon(Icons.download_done, color: Colors.green),
      DownloadState.failed =>
        const Icon(Icons.error_outline, color: Colors.red),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Download Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: _videos.length,
        itemBuilder: (context, index) {
          final video = _videos[index];
          return Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  onTap: () => _playVideo(video),
                  leading: video.thumbnailUrl != null
                      ? Image.network(
                          video.thumbnailUrl!,
                          width: 100,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 100,
                            height: 56,
                            color: Colors.grey,
                            child: const Icon(Icons.video_file),
                          ),
                        )
                      : Container(
                          width: 100,
                          height: 56,
                          color: Colors.grey,
                          child: const Icon(Icons.video_file),
                        ),
                  title: Text(video.name),
                  subtitle:
                      Text(video.isAsset ? 'Asset video' : 'Online video'),
                  trailing: _getDownloadStateIcon(video.downloadState),
                ),
                if (video.isDownloading) ...[
                  LinearProgressIndicator(
                    value: video.downloadProgress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text(
                          '${(video.downloadProgress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_formatBytes(video.bytesDownloaded)} downloaded',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ] else if (video.hasFailedDownload) ...[
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Download failed - tap retry to try again',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else if (video.isDownloaded) ...[
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Downloaded (${_formatBytes(video.bytesDownloaded)})',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Download/Cancel button or Play button for assets
                      if (video.isAsset)
                        ElevatedButton.icon(
                          onPressed: () => _playVideo(video),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else ...[
                        switch (video.downloadState) {
                          DownloadState.initial => ElevatedButton.icon(
                              onPressed: () => _startDownload(video),
                              icon: const Icon(Icons.download),
                              label: const Text('Download'),
                            ),
                          DownloadState.downloading => ElevatedButton.icon(
                              onPressed: () => _cancelDownload(video),
                              icon: const Icon(Icons.cancel),
                              label: const Text('Cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          DownloadState.downloaded => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _playVideo(video),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _removeDownload(video),
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Remove'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          DownloadState.failed => ElevatedButton.icon(
                              onPressed: () => _startDownload(video),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        },
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final VideoItem videoItem;

  const VideoPlayerScreen({
    required this.videoItem,
    super.key,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoController();
  }

  Future<void> _initializeVideoController() async {
    if (widget.videoItem.isAsset) {
      // For asset videos
      _controller = VideoPlayerController.asset(
        widget.videoItem.url.replaceFirst('asset:', ''),
      );
    } else if (widget.videoItem.isDownloaded) {
      // For downloaded videos
      final cacheManager = VideoCacheManager.instance;
      final String? filePath =
          await cacheManager.getCachedVideoPath(widget.videoItem.url);

      if (filePath != null && !filePath.startsWith("exoplayer://")) {
        _controller = VideoPlayerController.file(File(filePath));
      } else {
        _controller =
            VideoPlayerController.networkUrl(Uri.parse(widget.videoItem.url));
      }
    } else {
      // For online videos
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoItem.url));
    }

    _controller.addListener(() {
      setState(() {
        _isBuffering = _controller.value.isBuffering;
      });
    });

    await _controller.initialize();
    setState(() {
      _isInitialized = true;
    });
    _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.videoItem.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    _ControlsOverlay(controller: _controller),
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.all(10.0),
                    ),
                    if (_isBuffering)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black26,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _ControlsOverlay({required this.controller});

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  bool _hideControls = true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _hideControls = !_hideControls;
        });
      },
      child: AnimatedOpacity(
        opacity: _hideControls ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.black26,
          child: Center(
            child: IconButton(
              icon: Icon(
                widget.controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
                size: 50.0,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (widget.controller.value.isPlaying) {
                    widget.controller.pause();
                  } else {
                    widget.controller.play();
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}

// Model class to represent a video item
class VideoItem {
  final String name;
  final String url;
  final String? thumbnailUrl;
  final bool isAsset;

  DownloadState downloadState = DownloadState.initial;
  double downloadProgress = 0.0;
  int bytesDownloaded = 0;

  VideoItem({
    required this.name,
    required this.url,
    this.thumbnailUrl,
    this.isAsset = false,
  });

  bool get isDownloaded => downloadState == DownloadState.downloaded;
  bool get isDownloading => downloadState == DownloadState.downloading;
  bool get hasFailedDownload => downloadState == DownloadState.failed;
}
