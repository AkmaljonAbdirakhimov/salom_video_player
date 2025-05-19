// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A screen that demonstrates Picture-in-Picture mode with VideoPlayer.
class PictureInPictureExample extends StatefulWidget {
  const PictureInPictureExample({super.key});

  @override
  State<PictureInPictureExample> createState() =>
      _PictureInPictureExampleState();
}

class _PictureInPictureExampleState extends State<PictureInPictureExample> {
  late VideoPlayerController _controller;
  bool _isPipSupported = false;
  bool _isInPipMode = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // Create a network video player
    final viewType =
        Platform.isIOS ? VideoViewType.platformView : VideoViewType.textureView;
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4'),
      videoPlayerOptions: ExtendedVideoPlayerOptions(
        viewType: viewType,
      ),
    );

    await _controller.initialize();

    // Check if PiP is supported on the device
    final bool pipSupported = await _controller.isPictureInPictureSupported();

    if (mounted) {
      setState(() {
        _isPipSupported = pipSupported;
      });
    }

    // Listen for PiP mode changes
    _controller.isInPictureInPictureModeStream.listen((bool isInPipMode) {
      if (mounted) {
        setState(() {
          _isInPipMode = isInPipMode;
        });
      }
    });

    // Start playing the video
    await _controller.play();
  }

  Future<void> _togglePictureInPicture() async {
    if (_isPipSupported) {
      final isInPipMode = await _controller.isInPictureInPictureMode();
      if (!isInPipMode) {
        await _controller.enterPictureInPicture();
      }
    }
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
        title: const Text('Picture-in-Picture Example'),
      ),
      body: _controller.value.isInitialized
          ? Column(
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                      child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_isPipSupported)
                      ElevatedButton(
                        onPressed: _togglePictureInPicture,
                        child: const Icon(Icons.picture_in_picture),
                      ),
                  ],
                ),
                if (_isPipSupported) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isInPipMode
                          ? Colors.green.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isInPipMode
                          ? 'Currently in Picture-in-Picture mode'
                          : 'Not in Picture-in-Picture mode',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Picture-in-Picture is not supported on this device',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Note: On iOS, the app must be minimized to see PiP in action. On Android, PiP appears immediately.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}
