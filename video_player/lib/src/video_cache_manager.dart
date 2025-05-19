// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_platform_interface/src/video_cache.dart';

// Conditionally import platform-specific implementations
// ignore: uri_does_not_exist
import 'package:video_player_android/video_player_android.dart'
    if (dart.library.html) 'unsupported.dart';
// ignore: uri_does_not_exist
import 'package:video_player_avfoundation/video_player_avfoundation.dart'
    if (dart.library.html) 'unsupported.dart';

/// Manages video downloading and caching operations across platforms.
class VideoCacheManager implements VideoCacheApi {
  /// Private constructor for singleton pattern.
  VideoCacheManager._() {
    _initPlatformImplementation();
  }

  static final VideoCacheManager _instance = VideoCacheManager._();

  /// Returns the singleton instance of [VideoCacheManager].
  static VideoCacheManager get instance => _instance;

  // The platform-specific implementation
  VideoCacheApi? _platformImplementation;

  void _initPlatformImplementation() {
    if (kIsWeb) {
      // Web doesn't support caching yet
      _platformImplementation = null;
    } else if (Platform.isAndroid) {
      try {
        _platformImplementation = AndroidVideoCacheManager.instance;
      } catch (e) {
        debugPrint('Failed to initialize Android cache manager: $e');
      }
    } else if (Platform.isIOS) {
      try {
        _platformImplementation = AVFoundationVideoCacheManager.instance;
      } catch (e) {
        debugPrint('Failed to initialize iOS cache manager: $e');
      }
    }
  }

  // Stream controllers for each URL being downloaded
  final Map<String, StreamController<DownloadProgress>> _progressControllers =
      {};

  /// Starts downloading a video for offline playback.
  ///
  /// Returns the unique ID for the download.
  @override
  Future<String> startDownload(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.startDownload(url);
    }
    throw UnimplementedError(
        'startDownload is not implemented for this platform');
  }

  /// Cancels an active download.
  ///
  /// Returns true if the download was successfully canceled.
  @override
  Future<bool> cancelDownload(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.cancelDownload(url);
    }
    throw UnimplementedError(
        'cancelDownload is not implemented for this platform');
  }

  /// Removes a downloaded video from the cache.
  ///
  /// Returns true if the video was successfully removed.
  @override
  Future<bool> removeDownload(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.removeDownload(url);
    }
    throw UnimplementedError(
        'removeDownload is not implemented for this platform');
  }

  /// Gets the current progress of a downloading video.
  ///
  /// Returns a DownloadProgress object containing progress value and bytes downloaded.
  @override
  Future<DownloadProgress> getDownloadProgress(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.getDownloadProgress(url);
    }
    throw UnimplementedError(
        'getDownloadProgress is not implemented for this platform');
  }

  /// Gets the file path of a cached video.
  ///
  /// Returns null if the video is not cached.
  @override
  Future<String?> getCachedVideoPath(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.getCachedVideoPath(url);
    }
    return null;
  }

  /// Checks if a video is downloaded and available for offline playback.
  ///
  /// Returns true if the video is cached and ready for offline playback.
  @override
  Future<bool> isDownloaded(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.isDownloaded(url);
    }
    return false;
  }

  /// Gets the maximum number of concurrent downloads supported.
  ///
  /// Additional downloads will be queued.
  @override
  Future<int> getMaxConcurrentDownloads() async {
    if (_platformImplementation != null) {
      return _platformImplementation!.getMaxConcurrentDownloads();
    }
    return 3; // Default value
  }

  /// Gets the current state of a video download.
  ///
  /// Returns the DownloadState of the video (initial, downloading, downloaded, failed).
  @override
  Future<DownloadState> getDownloadState(String url) async {
    if (_platformImplementation != null) {
      return _platformImplementation!.getDownloadState(url);
    }
    return DownloadState.initial; // Default for unsupported platforms
  }

  /// Gets a stream of download progress updates for a video.
  ///
  /// The stream will emit events as the download progresses and completes when the download finishes or fails.
  @override
  Stream<DownloadProgress> getDownloadProgressStream(String url) {
    if (_platformImplementation != null) {
      // Use the platform implementation's stream if available
      return _platformImplementation!.getDownloadProgressStream(url);
    }

    // For unsupported platforms, return a stream that immediately errors out
    return Stream<DownloadProgress>.error(
        'Downloading is not supported on this platform');
  }

  /// Disposes all resources used by the cache manager.
  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }
}
