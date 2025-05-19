# Video Player Offline Caching

The video_player package supports downloading videos for offline playback. This guide explains how to use this functionality.

## Overview

Video Player's caching system allows you to:

1. Download videos for offline playback
2. Monitor download progress
3. Manage downloaded videos (cancel downloads, remove cached videos)
4. Automatically use cached videos when available

All of this happens transparently to your existing `VideoPlayerController.network()` usage - when a video is cached, it will automatically be used instead of streaming from the network.

## Supported Platforms

- iOS
- Android

## Basic Usage

### Check if a video is already downloaded

```dart
import 'package:video_player/video_player.dart';

Future<bool> isVideoDownloaded(String url) async {
  return await VideoCacheManager.instance.isDownloaded(url);
}
```

### Download a video for offline playback

```dart
import 'package:video_player/video_player.dart';

Future<void> downloadVideo(String url) async {
  // Start the download
  await VideoCacheManager.instance.startDownload(url);
  
  // Listen for progress updates
  VideoCacheManager.instance.getDownloadProgressStream(url).listen(
    (progress) {
      print('Download progress: ${progress.progress * 100}%');
      print('Bytes downloaded: ${progress.bytesDownloaded}');
      
      if (progress.progress >= 1.0) {
        print('Download complete!');
      }
    },
    onError: (error) {
      print('Download error: $error');
    },
  );
}
```

### Cancel an active download

```dart
import 'package:video_player/video_player.dart';

Future<void> cancelDownload(String url) async {
  bool cancelled = await VideoCacheManager.instance.cancelDownload(url);
  print('Download cancelled: $cancelled');
}
```

### Remove a downloaded video

```dart
import 'package:video_player/video_player.dart';

Future<void> removeDownloadedVideo(String url) async {
  bool removed = await VideoCacheManager.instance.removeDownload(url);
  print('Video removed from cache: $removed');
}
```

## Complete Example

Here's a complete example showing how to download a video and track its progress:

```dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoCacheDemo extends StatefulWidget {
  const VideoCacheDemo({Key? key}) : super(key: key);

  @override
  State<VideoCacheDemo> createState() => _VideoCacheDemoState();
}

class _VideoCacheDemoState extends State<VideoCacheDemo> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  double _downloadProgress = 0.0;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  
  final String videoUrl = 'https://example.com/sample_video.mp4';
  
  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _checkIfDownloaded();
  }

  Future<void> _initializePlayer() async {
    _controller = VideoPlayerController.network(videoUrl);
    await _controller.initialize();
    
    _controller.addListener(() {
      if (_controller.value.isPlaying != _isPlaying) {
        setState(() {
          _isPlaying = _controller.value.isPlaying;
        });
      }
    });
    
    setState(() {});
  }
  
  Future<void> _checkIfDownloaded() async {
    final bool isDownloaded = await VideoCacheManager.instance.isDownloaded(videoUrl);
    setState(() {
      _isDownloaded = isDownloaded;
    });
  }
  
  Future<void> _downloadVideo() async {
    setState(() {
      _isDownloading = true;
    });
    
    // Start the download
    await VideoCacheManager.instance.startDownload(videoUrl);
    
    // Listen to download progress
    VideoCacheManager.instance.getDownloadProgressStream(videoUrl).listen(
      (progress) {
        setState(() {
          _downloadProgress = progress.progress;
        });
        
        // When download completes
        if (progress.progress >= 1.0) {
          setState(() {
            _isDownloaded = true;
            _isDownloading = false;
          });
        }
      },
      onError: (error) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $error')),
        );
      },
      onDone: () {
        setState(() {
          _isDownloading = false;
        });
      },
    );
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
        title: const Text('Video Caching Example'),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  setState(() {
                    if (_isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${_isDownloaded ? 'Downloaded' : _isDownloading ? 'Downloading...' : 'Not Downloaded'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                
                if (_isDownloading)
                  Column(
                    children: [
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 4),
                      Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                  
                const SizedBox(height: 16),
                
                if (!_isDownloaded && !_isDownloading)
                  ElevatedButton(
                    onPressed: _downloadVideo,
                    child: const Text('Download for offline playback'),
                  ),
                  
                if (_isDownloading)
                  ElevatedButton(
                    onPressed: () async {
                      final bool success = await VideoCacheManager.instance.cancelDownload(videoUrl);
                      if (success) {
                        setState(() {
                          _isDownloading = false;
                        });
                      }
                    },
                    child: const Text('Cancel Download'),
                  ),
                  
                if (_isDownloaded)
                  ElevatedButton(
                    onPressed: () async {
                      final bool success = await VideoCacheManager.instance.removeDownload(videoUrl);
                      if (success) {
                        setState(() {
                          _isDownloaded = false;
                          _downloadProgress = 0.0;
                        });
                      }
                    },
                    child: const Text('Remove Download'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## Technical Details

### Maximum Concurrent Downloads

By default, the caching system limits concurrent downloads to 3. Additional downloads are queued and will start automatically when slots become available.

### Automatic Cache Usage

When a video is available in the cache, it will be used automatically when you create a `VideoPlayerController.network()` with the same URL. This happens transparently, so you don't need to change your code.

### Storage Management

The caching system doesn't impose a size limit on the cache. You'll need to implement your own cache eviction policy based on your app's needs.

### Android-Specific Notes

On Android, the implementation uses ExoPlayer's DownloadManager and SimpleCache for handling downloads and caching.

### iOS-Specific Notes

On iOS, the implementation uses AVAssetDownloadURLSession for handling downloads and manages the cache through AVAssetDownloadStorageManager. 