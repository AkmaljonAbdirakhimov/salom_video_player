// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#import "FVPAVFactory.h"

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// FVPVideoPlayer manages video playback using AVPlayer.
/// It provides methods for controlling playback, adjusting volume, and handling seeking.
/// This class contains all functionalities needed to manage video playback in platform views and is
/// typically used alongside FVPNativeVideoViewFactory. If you need to display a video using a
/// texture, use FVPTextureBasedVideoPlayer instead.
@interface FVPVideoPlayer : NSObject <FlutterStreamHandler, AVPictureInPictureControllerDelegate>
/// The Flutter event channel used to communicate with the Flutter engine.
@property(nonatomic) FlutterEventChannel *eventChannel;
/// The AVPlayer instance used for video playback.
@property(nonatomic, readonly) AVPlayer *player;
/// The AVPictureInPictureController used for Picture-in-Picture functionality.
@property(nonatomic, nullable, strong) AVPictureInPictureController *pipController;
/// Indicates whether the video player has been disposed.
@property(nonatomic, readonly) BOOL disposed;
/// Indicates whether the video player is set to loop.
@property(nonatomic) BOOL isLooping;
/// The current playback position of the video, in milliseconds.
@property(nonatomic, readonly) int64_t position;

/// Initializes a new instance of FVPVideoPlayer with the given asset, AV factory, and registrar.
- (instancetype)initWithAsset:(NSString *)asset
                    avFactory:(id<FVPAVFactory>)avFactory
                    registrar:(NSObject<FlutterPluginRegistrar> *)registrar;

/// Initializes a new instance of FVPVideoPlayer with the given URL, HTTP headers, AV factory, and
/// registrar.
- (instancetype)initWithURL:(NSURL *)url
                httpHeaders:(nonnull NSDictionary<NSString *, NSString *> *)headers
                  avFactory:(id<FVPAVFactory>)avFactory
                  registrar:(NSObject<FlutterPluginRegistrar> *)registrar;

/// Initializes a new instance of FVPVideoPlayer with the given AVAsset, AV factory, and registrar.
/// This is particularly useful for initializing with cached assets.
- (instancetype)initWithAVAsset:(AVAsset *)asset
                      avFactory:(id<FVPAVFactory>)avFactory
                      registrar:(NSObject<FlutterPluginRegistrar> *)registrar;

/// Initializes a new instance of FVPVideoPlayer with the given player item, AV factory, and registrar.
- (instancetype)initWithPlayerItem:(AVPlayerItem *)item
                         avFactory:(id<FVPAVFactory>)avFactory
                         registrar:(NSObject<FlutterPluginRegistrar> *)registrar;

/// Disposes the video player and releases any resources it holds.
- (void)dispose;

/// Disposes the video player without touching the event channel. This
/// is useful for the case where the Engine is in the process of deconstruction
/// so the channel is going to die or is already dead.
- (void)disposeSansEventChannel;

/// Sets the volume of the video player.
- (void)setVolume:(double)volume;

/// Sets the playback speed of the video player.
- (void)setPlaybackSpeed:(double)speed;

/// Starts playing the video.
- (void)play;

/// Pauses the video.
- (void)pause;

/// Seeks to the specified location in the video and calls the completion handler when done, if one
/// is supplied.
- (void)seekTo:(int64_t)location completionHandler:(void (^_Nullable)(BOOL))completionHandler;

#if TARGET_OS_IOS
/// Enters Picture-in-Picture mode if supported.
/// @return YES if successfully entered PiP mode, NO otherwise.
- (BOOL)enterPictureInPictureMode;

/// Checks if Picture-in-Picture mode is currently active.
/// @return YES if in PiP mode, NO otherwise.
- (BOOL)isInPictureInPictureMode;

/// Checks if Picture-in-Picture is supported on the current device.
/// @return YES if PiP is supported, NO otherwise.
+ (BOOL)isPictureInPictureSupported;

/// Sets up Picture-in-Picture with the AVPlayerLayer provided by the renderer.
/// This should be called when the player layer is available and ready to be used.
- (void)setupPictureInPictureWithPlayerLayer:(AVPlayerLayer *)playerLayer;
#endif

@end

NS_ASSUME_NONNULL_END
