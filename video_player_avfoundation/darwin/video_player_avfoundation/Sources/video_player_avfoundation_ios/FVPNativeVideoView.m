// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "../video_player_avfoundation/include/video_player_avfoundation/FVPNativeVideoView.h"
#import "../video_player_avfoundation/include/video_player_avfoundation/FVPVideoPlayer.h"

#import <AVFoundation/AVFoundation.h>

@interface FVPPlayerView : UIView
@end

@implementation FVPPlayerView
+ (Class)layerClass {
  return [AVPlayerLayer class];
}

- (AVPlayerLayer *)playerLayer {
  return (AVPlayerLayer *)[self layer];
}

- (void)setPlayer:(AVPlayer *)player {
  [(AVPlayerLayer *)[self layer] setPlayer:player];
}
@end

@interface FVPNativeVideoView ()
@property(nonatomic) FVPPlayerView *playerView;
@property(nonatomic, weak) FVPVideoPlayer *videoPlayer;
@end

@implementation FVPNativeVideoView
- (instancetype)initWithPlayer:(AVPlayer *)player {
  if (self = [super init]) {
    _playerView = [[FVPPlayerView alloc] init];
    [_playerView setPlayer:player];
  }
  return self;
}

- (FVPPlayerView *)view {
  return self.playerView;
}

// Set the video player reference and initialize PiP controller with the player layer
- (void)setVideoPlayer:(FVPVideoPlayer *)videoPlayer {
  _videoPlayer = videoPlayer;
  
#if TARGET_OS_IOS
  if (_videoPlayer && [self.playerView playerLayer]) {
    [_videoPlayer setupPictureInPictureWithPlayerLayer:[self.playerView playerLayer]];
  }
#endif
}
@end
