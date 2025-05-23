// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.app.Activity;
import android.app.PictureInPictureParams;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Environment;
import android.util.Log;
import android.util.LongSparseArray;
import android.util.Rational;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugins.videoplayer.Messages.AndroidVideoPlayerApi;
import io.flutter.plugins.videoplayer.Messages.CreateMessage;
import io.flutter.plugins.videoplayer.Messages.DownloadProgress;
import io.flutter.plugins.videoplayer.Messages.DownloadState;
import io.flutter.plugins.videoplayer.Messages.PlatformVideoViewType;
import io.flutter.plugins.videoplayer.platformview.PlatformVideoViewFactory;
import io.flutter.plugins.videoplayer.platformview.PlatformViewVideoPlayer;
import io.flutter.plugins.videoplayer.texture.TextureVideoPlayer;
import io.flutter.view.TextureRegistry;
import android.app.Application;
import android.app.Application.ActivityLifecycleCallbacks;
import android.os.Bundle;

/** Android platform implementation of the VideoPlayerPlugin. */
public class VideoPlayerPlugin implements FlutterPlugin, AndroidVideoPlayerApi, ActivityAware {
  private static final String TAG = "VideoPlayerPlugin";
  private final LongSparseArray<VideoPlayer> videoPlayers = new LongSparseArray<>();
  private FlutterState flutterState;
  private final VideoPlayerOptions options = new VideoPlayerOptions();
  private VideoCacheManager cacheManager;
  private Activity activity;
  private boolean pipChangeEventSent = false;
  private boolean wasInPipMode = false;
  private ActivityPluginBinding activityBinding;

  // TODO(stuartmorgan): Decouple identifiers for platform views and texture views.
  /**
   * The next non-texture player ID, initialized to a high number to avoid collisions with texture
   * IDs (which are generated separately).
   */
  private Long nextPlatformViewPlayerId = Long.MAX_VALUE;

  /** Register this with the v2 embedding for the plugin to respond to lifecycle callbacks. */
  public VideoPlayerPlugin() {}

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    final FlutterInjector injector = FlutterInjector.instance();
    this.flutterState =
        new FlutterState(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            injector.flutterLoader()::getLookupKeyForAsset,
            injector.flutterLoader()::getLookupKeyForAsset,
            binding.getTextureRegistry());
    flutterState.startListening(this, binding.getBinaryMessenger());

    // Initialize the cache manager
    cacheManager = VideoCacheManager.getInstance(binding.getApplicationContext());

    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
            "plugins.flutter.dev/video_player_android",
            new PlatformVideoViewFactory(videoPlayers::get));
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (flutterState == null) {
      Log.wtf(TAG, "Detached from the engine before registering to it.");
    }
    flutterState.stopListening(binding.getBinaryMessenger());
    flutterState = null;
    onDestroy();
  }

  private void disposeAllPlayers() {
    for (int i = 0; i < videoPlayers.size(); i++) {
      videoPlayers.valueAt(i).dispose();
    }
    videoPlayers.clear();
  }

  public void onDestroy() {
    // The whole FlutterView is being destroyed. Here we release resources acquired for all
    // instances
    // of VideoPlayer. Once https://github.com/flutter/flutter/issues/19358 is resolved this may
    // be replaced with just asserting that videoPlayers.isEmpty().
    // https://github.com/flutter/flutter/issues/20989 tracks this.
    disposeAllPlayers();
  }

  @Override
  public void initialize() {
    disposeAllPlayers();
  }

  // ActivityAware implementation
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding.getActivity();
    activityBinding = binding;
    registerPipModeMonitor();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    unregisterPipModeMonitor();
    activity = null;
    activityBinding = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    activity = binding.getActivity();
    activityBinding = binding;
    registerPipModeMonitor();
  }

  @Override
  public void onDetachedFromActivity() {
    unregisterPipModeMonitor();
    activity = null;
    activityBinding = null;
  }

  private ActivityLifecycleCallbacks pipStateMonitor = null;

  private void registerPipModeMonitor() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity == null) {
      return;
    }

    if (pipStateMonitor == null) {
      pipStateMonitor = new ActivityLifecycleCallbacks() {
        @Override
        public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle savedInstanceState) {}

        @Override
        public void onActivityStarted(@NonNull Activity activity) {}

        @Override
        public void onActivityResumed(@NonNull Activity activity) {
          checkPipStateChange();
        }

        @Override
        public void onActivityPaused(@NonNull Activity activity) {}

        @Override
        public void onActivityStopped(@NonNull Activity activity) {}

        @Override
        public void onActivitySaveInstanceState(@NonNull Activity activity, @NonNull Bundle outState) {}

        @Override
        public void onActivityDestroyed(@NonNull Activity activity) {}
      };

      ((Application) activity.getApplicationContext()).registerActivityLifecycleCallbacks(pipStateMonitor);
    }
  }

  private void unregisterPipModeMonitor() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity == null || pipStateMonitor == null) {
      return;
    }

    ((Application) activity.getApplicationContext()).unregisterActivityLifecycleCallbacks(pipStateMonitor);
    pipStateMonitor = null;
  }

  private void checkPipStateChange() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity == null) {
      return;
    }

    boolean isCurrentlyInPipMode = activity.isInPictureInPictureMode();
    
    // If we were in PiP mode and now we're not, notify all players
    if (wasInPipMode && !isCurrentlyInPipMode) {
      Log.d(TAG, "Exited PiP mode");
      for (int i = 0; i < videoPlayers.size(); i++) {
        VideoPlayer player = videoPlayers.valueAt(i);
        player.sendPipExitedEvent();
      }
    }
    
    wasInPipMode = isCurrentlyInPipMode;
  }

  @Override
  public Boolean isPictureInPictureSupported() {
    if (activity == null) {
      return false;
    }
    
    // Check PiP support for Android 8.0 (API level 26) and higher
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      return activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
    }
    
    return false;
  }

  @Override
  public Boolean enterPictureInPictureMode(@NonNull Long playerId) {
    if (activity == null) {
      Log.w(TAG, "Cannot enter PiP mode: Activity is null");
      return false;
    }
    
    // Only supported on Android 8.0 (API level 26) and higher
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      Log.w(TAG, "Cannot enter PiP mode: Feature requires Android 8.0 or higher");
      return false;
    }
    
    // Check if activity is in a valid state to enter PiP
    if (activity.isFinishing() || activity.isDestroyed()) {
      Log.w(TAG, "Cannot enter PiP mode: Activity is finishing or destroyed");
      return false;
    }
    
    // Get the video player
    VideoPlayer player = getPlayer(playerId);
    if (player == null) {
      Log.w(TAG, "Cannot enter PiP mode: Player not found for ID: " + playerId);
      return false;
    }
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      try {
        // Get the video dimensions
        int videoWidth = player.getVideoSize().width;
        int videoHeight = player.getVideoSize().height;
        
        // Only attempt to enter PiP if we have valid video dimensions
        if (videoWidth <= 0 || videoHeight <= 0) {
          Log.w(TAG, "Cannot enter PiP mode: Invalid video dimensions: " + videoWidth + "x" + videoHeight);
          return false;
        }
        
        // Check if we're already in PiP mode
        if (activity.isInPictureInPictureMode()) {
          Log.d(TAG, "Already in PiP mode, not re-entering");
          return true;
        }
        
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder();
        
        // Calculate the aspect ratio
        float aspectRatio = (float) videoWidth / videoHeight;
        
        // Clamp aspect ratio to allowed Android range - simple approach
        final float MIN_ASPECT_RATIO = 0.418410f;
        final float MAX_ASPECT_RATIO = 2.390000f;
        
        // Simple clamping using Math.min and Math.max
        float clampedAspectRatio = Math.max(MIN_ASPECT_RATIO, Math.min(aspectRatio, MAX_ASPECT_RATIO));
        if (clampedAspectRatio != aspectRatio) {
          Log.d(TAG, "Adjusted PiP aspect ratio from " + aspectRatio + " to " + clampedAspectRatio);
        }
        
        // Use a consistent denominator for the Rational
        int denominator = 1000;
        int numerator = Math.round(clampedAspectRatio * denominator);
        
        // Create the aspect ratio for PiP
        Rational pipAspectRatio = new Rational(numerator, denominator);
        builder.setAspectRatio(pipAspectRatio);
        
        // For Android 12 (API 31+), we can set additional properties
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          // Disable auto PiP when user navigates away while video is playing
          // Only enter PiP mode explicitly when requested
          builder.setAutoEnterEnabled(false)
                .setSeamlessResizeEnabled(true);
        }
        
        // Use try-catch specifically for the PiP entry to better handle lifecycle exceptions
        try {
          // Enter PiP mode with the configured parameters
          PictureInPictureParams params = builder.build();
          activity.enterPictureInPictureMode(params);
          
          // Update our state tracking
          wasInPipMode = true;
          
          // Manually trigger PiP entered event
          player.sendPipEnteredEvent();
          return true;
        } catch (IllegalStateException e) {
          // This occurs if the activity is not in a valid state for PiP
          Log.e(TAG, "Activity not in valid state for PiP: " + e.getMessage());
          return false;
        } catch (Exception e) {
          Log.e(TAG, "Error entering PiP mode", e);
          return false;
        }
      } catch (Exception e) {
        Log.e(TAG, "Error preparing for PiP mode", e);
      }
    }
    
    return false;
  }

  @Override
  public Boolean isInPictureInPictureMode(@NonNull Long playerId) {
    if (activity == null) {
      return false;
    }
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      boolean isInPipMode = activity.isInPictureInPictureMode();
      return isInPipMode;
    }
    
    return false;
  }

  @Override
  public @NonNull Long create(@NonNull CreateMessage arg) {
    final VideoAsset videoAsset;
    if (arg.getAsset() != null) {
      String assetLookupKey;
      if (arg.getPackageName() != null) {
        assetLookupKey =
            flutterState.keyForAssetAndPackageName.get(arg.getAsset(), arg.getPackageName());
      } else {
        assetLookupKey = flutterState.keyForAsset.get(arg.getAsset());
      }
      videoAsset = VideoAsset.fromAssetUrl("asset:///" + assetLookupKey);
    } else if (arg.getUri().startsWith("rtsp://")) {
      videoAsset = VideoAsset.fromRtspUrl(arg.getUri());
    } else {
      VideoAsset.StreamingFormat streamingFormat = VideoAsset.StreamingFormat.UNKNOWN;
      String formatHint = arg.getFormatHint();
      if (formatHint != null) {
        switch (formatHint) {
          case "ss":
            streamingFormat = VideoAsset.StreamingFormat.SMOOTH;
            break;
          case "dash":
            streamingFormat = VideoAsset.StreamingFormat.DYNAMIC_ADAPTIVE;
            break;
          case "hls":
            streamingFormat = VideoAsset.StreamingFormat.HTTP_LIVE;
            break;
        }
      }
      
      // Check if the video is cached
      String url = arg.getUri();
      String cachedPath = getCachedVideoPath(url);
      
      if (cachedPath != null && cachedPath.startsWith("exoplayer://download/")) {
        // Extract download ID from path
        String downloadId = cachedPath.replace("exoplayer://download/", "");
        
        // Create a cached video asset
        videoAsset = VideoAsset.fromCachedRemoteUrl(
            url, 
            downloadId,
            streamingFormat, 
            arg.getHttpHeaders());
        
        Log.d(TAG, "Using cached video for URL: " + url);
      } else {
        // Create a regular HTTP video asset
        videoAsset = VideoAsset.fromRemoteUrl(url, streamingFormat, arg.getHttpHeaders());
      }
    }

    long id;
    VideoPlayer videoPlayer;
    if (arg.getViewType() == Messages.PlatformVideoViewType.PLATFORM_VIEW) {
      id = nextPlatformViewPlayerId--;
      videoPlayer =
          PlatformViewVideoPlayer.create(
              flutterState.applicationContext,
              VideoPlayerEventCallbacks.bindTo(createEventChannel(id)),
              videoAsset,
              options);
    } else {
      TextureRegistry.SurfaceProducer handle = flutterState.textureRegistry.createSurfaceProducer();
      id = handle.id();
      videoPlayer =
          TextureVideoPlayer.create(
              flutterState.applicationContext,
              VideoPlayerEventCallbacks.bindTo(createEventChannel(id)),
              handle,
              videoAsset,
              options);
    }

    videoPlayers.put(id, videoPlayer);
    return id;
  }

  @NonNull
  private EventChannel createEventChannel(long id) {
    return new EventChannel(
        flutterState.binaryMessenger, "flutter.io/videoPlayer/videoEvents" + id);
  }

  @NonNull
  private VideoPlayer getPlayer(long playerId) {
    VideoPlayer player = videoPlayers.get(playerId);

    // Avoid a very ugly un-debuggable NPE that results in returning a null player.
    if (player == null) {
      String message = "No player found with playerId <" + playerId + ">";
      if (videoPlayers.size() == 0) {
        message += " and no active players created by the plugin.";
      }
      throw new IllegalStateException(message);
    }

    return player;
  }

  @Override
  public void dispose(@NonNull Long playerId) {
    VideoPlayer player = getPlayer(playerId);
    player.dispose();
    videoPlayers.remove(playerId);
  }

  @Override
  public void setLooping(@NonNull Long playerId, @NonNull Boolean looping) {
    VideoPlayer player = getPlayer(playerId);
    player.setLooping(looping);
  }

  @Override
  public void setVolume(@NonNull Long playerId, @NonNull Double volume) {
    VideoPlayer player = getPlayer(playerId);
    player.setVolume(volume);
  }

  @Override
  public void setPlaybackSpeed(@NonNull Long playerId, @NonNull Double speed) {
    VideoPlayer player = getPlayer(playerId);
    player.setPlaybackSpeed(speed);
  }

  @Override
  public void play(@NonNull Long playerId) {
    VideoPlayer player = getPlayer(playerId);
    player.play();
  }

  @Override
  public @NonNull Long position(@NonNull Long playerId) {
    VideoPlayer player = getPlayer(playerId);
    long position = player.getPosition();
    player.sendBufferingUpdate();
    return position;
  }

  @Override
  public void seekTo(@NonNull Long playerId, @NonNull Long position) {
    VideoPlayer player = getPlayer(playerId);
    player.seekTo(position.intValue());
  }

  @Override
  public void pause(@NonNull Long playerId) {
    VideoPlayer player = getPlayer(playerId);
    player.pause();
  }

  @Override
  public void setMixWithOthers(@NonNull Boolean mixWithOthers) {
    options.mixWithOthers = mixWithOthers;
  }
  
  // Video caching API implementation
  
  @Override
  public @NonNull String startDownload(@NonNull String url) {
    if (cacheManager == null) {
      return "";
    }
    return cacheManager.startDownload(url);
  }

  @Override
  public @NonNull Boolean cancelDownload(@NonNull String url) {
    if (cacheManager == null) {
      return false;
    }
    return cacheManager.cancelDownload(url);
  }

  @Override
  public @NonNull Boolean removeDownload(@NonNull String url) {
    if (cacheManager == null) {
      return false;
    }
    return cacheManager.removeDownload(url);
  }

  @Override
  public @NonNull DownloadProgress getDownloadProgress(@NonNull String url) {
    try {
      double progress = cacheManager.getDownloadProgress(url);
      long bytesDownloaded = cacheManager.getBytesDownloaded(url);
      
      DownloadProgress result = new DownloadProgress.Builder()
          .setUrl(url)
          .setProgress(progress)
          .setBytesDownloaded(bytesDownloaded)
          .build();
      
      return result;
    } catch (Exception e) {
      Log.e(TAG, "Error retrieving download progress: " + e);
      
      // Return a minimal progress object on error
      DownloadProgress result = new DownloadProgress.Builder()
          .setUrl(url)
          .setProgress(0.0)
          .setBytesDownloaded(0L)
          .build();
      return result;
    }
  }

  @Override
  public @Nullable String getCachedVideoPath(@NonNull String url) {
    if (cacheManager == null) {
      return null;
    }
    return cacheManager.getCachedVideoPath(url);
  }

  @Override
  public @NonNull Long getMaxConcurrentDownloads() {
    if (cacheManager == null) {
      return 3L; // Default value
    }
    return (long) cacheManager.getMaxConcurrentDownloads();
  }

  @Override
  public @NonNull DownloadState getDownloadState(@NonNull String url) {
    int state = cacheManager.getDownloadState(url);
    
    // Convert the integer state from VideoCacheManager to DownloadState enum
    switch (state) {
      case 0:
        return DownloadState.INITIAL;
      case 1:
        return DownloadState.DOWNLOADING;
      case 2:
        return DownloadState.DOWNLOADED;
      case 3:
        return DownloadState.FAILED;
      default:
        return DownloadState.INITIAL;
    }
  }

  private interface KeyForAssetFn {
    String get(String asset);
  }

  private interface KeyForAssetAndPackageName {
    String get(String asset, String packageName);
  }

  private static final class FlutterState {
    final Context applicationContext;
    final BinaryMessenger binaryMessenger;
    final KeyForAssetFn keyForAsset;
    final KeyForAssetAndPackageName keyForAssetAndPackageName;
    final TextureRegistry textureRegistry;

    FlutterState(
        Context applicationContext,
        BinaryMessenger messenger,
        KeyForAssetFn keyForAsset,
        KeyForAssetAndPackageName keyForAssetAndPackageName,
        TextureRegistry textureRegistry) {
      this.applicationContext = applicationContext;
      this.binaryMessenger = messenger;
      this.keyForAsset = keyForAsset;
      this.keyForAssetAndPackageName = keyForAssetAndPackageName;
      this.textureRegistry = textureRegistry;
    }

    void startListening(VideoPlayerPlugin methodCallHandler, BinaryMessenger messenger) {
      AndroidVideoPlayerApi.setUp(messenger, methodCallHandler);
    }

    void stopListening(BinaryMessenger messenger) {
      AndroidVideoPlayerApi.setUp(messenger, null);
    }
  }

  // Add this helper method to calculate greatest common divisor (GCD)
  private int gcd(int a, int b) {
    return b == 0 ? a : gcd(b, a % b);
  }
}
