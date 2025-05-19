// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_platform_interface/src/video_cache.dart'
    as platform_interface;

import 'messages.g.dart' as messages;

/// Android implementation of the video cache manager.
class AndroidVideoCacheManager implements VideoCacheApi {
  /// Private constructor for singleton pattern.
  AndroidVideoCacheManager._();

  static final AndroidVideoCacheManager _instance =
      AndroidVideoCacheManager._();

  /// Returns the singleton instance of [AndroidVideoCacheManager].
  static AndroidVideoCacheManager get instance => _instance;

  final messages.AndroidVideoPlayerApi _api = messages.AndroidVideoPlayerApi();

  // Stream controllers for each URL being downloaded
  final Map<String, StreamController<platform_interface.DownloadProgress>>
      _progressControllers = {};

  /// Starts downloading a video for offline playback.
  ///
  /// Returns the unique ID for the download.
  @override
  Future<String> startDownload(String url) async {
    // Reset any existing progress controllers for this URL
    if (_progressControllers.containsKey(url)) {
      // Stop progress updates for the existing download
      _stopProgressUpdates(url);

      // Get a fresh controller (the previous one might still have listeners)
      final oldController = _progressControllers[url]!;

      // Create a new controller to replace the old one
      final newController =
          StreamController<platform_interface.DownloadProgress>.broadcast(
        onListen: () {
          _startProgressUpdates(url);
        },
        onCancel: () {
          _stopProgressUpdates(url);
        },
      );

      // Replace the controller in the map
      _progressControllers[url] = newController;

      // Close the old controller after all listeners have been notified
      // of the download completion
      scheduleMicrotask(() {
        if (!oldController.isClosed) {
          oldController.close();
        }
      });
    }

    final String result = await _api.startDownload(url);
    return result;
  }

  /// Cancels an active download.
  ///
  /// Returns true if the download was successfully canceled.
  @override
  Future<bool> cancelDownload(String url) async {
    final bool result = await _api.cancelDownload(url);
    return result;
  }

  /// Removes a downloaded video from the cache.
  ///
  /// Returns true if the video was successfully removed.
  @override
  Future<bool> removeDownload(String url) async {
    final bool result = await _api.removeDownload(url);
    return result;
  }

  /// Gets the current progress of a downloading video.
  ///
  /// Returns a DownloadProgress object with progress value and bytes downloaded.
  @override
  Future<platform_interface.DownloadProgress> getDownloadProgress(
      String url) async {
    final messages.DownloadProgress progress =
        await _api.getDownloadProgress(url);
    return platform_interface.DownloadProgress(
      url: progress.url,
      progress: progress.progress,
      bytesDownloaded: progress.bytesDownloaded,
    );
  }

  /// Gets the file path of a cached video.
  ///
  /// Returns null if the video is not cached.
  @override
  Future<String?> getCachedVideoPath(String url) async {
    return _api.getCachedVideoPath(url);
  }

  /// Checks if a video is downloaded and available for offline playback.
  ///
  /// Returns true if the video is cached and ready for offline playback.
  @override
  Future<bool> isDownloaded(String url) async {
    final String? path = await getCachedVideoPath(url);
    return path != null;
  }

  /// Gets the maximum number of concurrent downloads supported.
  ///
  /// Additional downloads will be queued.
  @override
  Future<int> getMaxConcurrentDownloads() async {
    final int result = await _api.getMaxConcurrentDownloads();
    return result;
  }

  /// Gets the current state of a video download.
  ///
  /// Returns the DownloadState of the video (initial, downloading, downloaded, failed).
  @override
  Future<platform_interface.DownloadState> getDownloadState(String url) async {
    final messages.DownloadState state = await _api.getDownloadState(url);

    // Convert the pigeon enum to the platform interface enum
    return switch (state) {
      messages.DownloadState.initial =>
        platform_interface.DownloadState.initial,
      messages.DownloadState.downloading =>
        platform_interface.DownloadState.downloading,
      messages.DownloadState.downloaded =>
        platform_interface.DownloadState.downloaded,
      messages.DownloadState.failed => platform_interface.DownloadState.failed,
    };
  }

  /// Gets a stream of download progress updates for a video.
  ///
  /// The stream will emit events as the download progresses and completes when the download finishes or fails.
  @override
  Stream<platform_interface.DownloadProgress> getDownloadProgressStream(
      String url) {
    // Always check the download state first before creating/returning a stream
    return Stream.fromFuture(getDownloadState(url)).asyncExpand((state) {
      // If the URL isn't being downloaded, return an empty stream
      if (state != platform_interface.DownloadState.downloading) {
        return Stream.empty();
      }

      // Create a new controller if needed
      if (!_progressControllers.containsKey(url)) {
        final controller =
            StreamController<platform_interface.DownloadProgress>.broadcast(
          onListen: () {
            _startProgressUpdates(url);
          },
          onCancel: () {
            _stopProgressUpdates(url);
          },
        );
        _progressControllers[url] = controller;
      }

      return _progressControllers[url]!.stream;
    });
  }

  // Start progress polling for the given URL
  void _startProgressUpdates(String url) {
    // Check if we already have a timer running
    _progressTimers[url]?.cancel();

    // Initial progress check
    _checkAndEmitProgress(url);

    // Create a timer that checks progress every 500ms
    _progressTimers[url] =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _checkAndEmitProgress(url);
    });
  }

  // Check progress and emit an event if needed
  Future<void> _checkAndEmitProgress(String url) async {
    try {
      final progressData = await _api.getDownloadProgress(url);
      final controller = _progressControllers[url];

      if (controller != null && !controller.isClosed) {
        // Check if the download is still active
        final state = await _api.getDownloadState(url);
        if (state != messages.DownloadState.downloading &&
            progressData.progress < 1.0) {
          // Download was stopped or interrupted - close the stream
          _stopProgressUpdates(url);
          return;
        }

        controller.add(platform_interface.DownloadProgress(
          url: url,
          progress: progressData.progress,
          bytesDownloaded: progressData.bytesDownloaded,
        ));

        // If download is complete or failed, clean up
        if (progressData.progress >= 1.0 || progressData.progress < 0) {
          _stopProgressUpdates(url);

          // Wait a brief moment for the UI to update before closing
          // the controller to avoid losing the final progress update
          await Future.delayed(const Duration(milliseconds: 500));
          if (!controller.isClosed) {
            controller.close();
          }
        }
      }
    } catch (e) {
      print('Error checking download progress: $e');
      _stopProgressUpdates(url);
    }
  }

  // Stop progress polling for the given URL
  void _stopProgressUpdates(String url) {
    _progressTimers[url]?.cancel();
    _progressTimers.remove(url);
  }

  final Map<String, Timer> _progressTimers = {};

  /// Disposes all resources used by the cache manager.
  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();

    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    _progressTimers.clear();
  }
}
