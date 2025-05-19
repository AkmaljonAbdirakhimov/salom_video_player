// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Represents the state of a video download.
enum DownloadState {
  /// The video is not downloaded or queued for download.
  initial,

  /// The video is currently being downloaded or queued for download.
  downloading,

  /// The video has been successfully downloaded.
  downloaded,

  /// The download failed.
  failed
}

/// Represents the progress of a video download.
class DownloadProgress {
  /// Creates a download progress instance.
  DownloadProgress({
    required this.url,
    required this.progress,
    required this.bytesDownloaded,
  });

  /// The URL of the video being downloaded.
  final String url;

  /// The progress of the download, from 0.0 to 1.0.
  final double progress;

  /// The number of bytes downloaded so far.
  final int bytesDownloaded;
}

/// Interface for video caching functionality.
abstract class VideoCacheApi {
  /// The instance of [VideoCacheApi] to use.
  static VideoCacheApi? _instance;

  /// Returns the instance of [VideoCacheApi].
  static VideoCacheApi get instance {
    if (_instance == null) {
      throw Exception('No implementation of VideoCacheApi was provided');
    }
    return _instance!;
  }

  /// Sets the instance of [VideoCacheApi] to use.
  static set instance(VideoCacheApi instance) {
    _instance = instance;
  }

  /// Starts downloading a video for offline playback.
  ///
  /// Returns the unique ID for the download.
  Future<String> startDownload(String url);

  /// Cancels an active download.
  ///
  /// Returns true if the download was successfully canceled.
  Future<bool> cancelDownload(String url);

  /// Removes a downloaded video from the cache.
  ///
  /// Returns true if the video was successfully removed.
  Future<bool> removeDownload(String url);

  /// Gets the current progress of a downloading video.
  ///
  /// Returns a DownloadProgress object containing progress value between 0.0 and 1.0
  /// and the number of bytes downloaded.
  Future<DownloadProgress> getDownloadProgress(String url);

  /// Gets the file path of a cached video.
  ///
  /// Returns null if the video is not cached.
  Future<String?> getCachedVideoPath(String url);

  /// Checks if a video is downloaded and available for offline playback.
  ///
  /// Returns true if the video is cached and ready for offline playback.
  Future<bool> isDownloaded(String url);

  /// Gets the maximum number of concurrent downloads supported.
  ///
  /// Additional downloads will be queued.
  Future<int> getMaxConcurrentDownloads();

  /// Gets a stream of download progress updates for a video.
  ///
  /// The stream will emit events as the download progresses and completes when the download finishes or fails.
  Stream<DownloadProgress> getDownloadProgressStream(String url);

  /// Gets the current state of a video download.
  ///
  /// Returns the DownloadState of the video (initial, downloading, downloaded, failed).
  Future<DownloadState> getDownloadState(String url);
}
