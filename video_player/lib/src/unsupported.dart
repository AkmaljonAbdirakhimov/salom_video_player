// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_platform_interface/src/video_cache.dart';

/// A stub implementation used for web (where video caching is not supported).
class AndroidVideoCacheManager implements VideoCacheApi {
  /// Private constructor for singleton pattern.
  AndroidVideoCacheManager._();

  static final AndroidVideoCacheManager _instance =
      AndroidVideoCacheManager._();

  /// Returns the singleton instance of [AndroidVideoCacheManager].
  static AndroidVideoCacheManager get instance => _instance;

  @override
  Future<String> startDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> cancelDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> removeDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<DownloadProgress> getDownloadProgress(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<String?> getCachedVideoPath(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> isDownloaded(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<int> getMaxConcurrentDownloads() {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Stream<DownloadProgress> getDownloadProgressStream(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<DownloadState> getDownloadState(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }
}

/// A stub implementation used for web (where video caching is not supported).
class AVFoundationVideoCacheManager implements VideoCacheApi {
  /// Private constructor for singleton pattern.
  AVFoundationVideoCacheManager._();

  static final AVFoundationVideoCacheManager _instance =
      AVFoundationVideoCacheManager._();

  /// Returns the singleton instance of [AVFoundationVideoCacheManager].
  static AVFoundationVideoCacheManager get instance => _instance;

  @override
  Future<String> startDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> cancelDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> removeDownload(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<DownloadProgress> getDownloadProgress(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<String?> getCachedVideoPath(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<bool> isDownloaded(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<int> getMaxConcurrentDownloads() {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Stream<DownloadProgress> getDownloadProgressStream(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }

  @override
  Future<DownloadState> getDownloadState(String url) {
    throw UnimplementedError(
        'Video caching is not supported on this platform.');
  }
}
