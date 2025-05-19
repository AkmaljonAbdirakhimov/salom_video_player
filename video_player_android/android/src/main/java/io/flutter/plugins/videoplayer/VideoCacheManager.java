// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;
import android.util.Pair;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.C;
import androidx.media3.common.util.Util;
import androidx.media3.database.DatabaseProvider;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.cache.Cache;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor;
import androidx.media3.datasource.cache.NoOpCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import androidx.media3.exoplayer.offline.Download;
import androidx.media3.exoplayer.offline.DownloadCursor;
import androidx.media3.exoplayer.offline.DownloadIndex;
import androidx.media3.exoplayer.offline.DownloadManager;
import androidx.media3.exoplayer.offline.DownloadRequest;
import androidx.media3.exoplayer.offline.DownloadService;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

/** Manages downloading and caching of video files using ExoPlayer's download capabilities. */
public class VideoCacheManager {
    private static final String TAG = "VideoCacheManager";
    private static final int MAX_CACHE_SIZE = 2 * 1024 * 1024 * 1024; // 2GB
    private static final int MAX_CONCURRENT_DOWNLOADS = 3;

    private static VideoCacheManager instance;
    private final Context context;
    private final Cache downloadCache;
    private final DownloadManager downloadManager;
    private final DatabaseProvider databaseProvider;
    private final Map<String, DownloadTracker> activeDownloads = new ConcurrentHashMap<>();
    private final Map<String, Handler> progressHandlers = new ConcurrentHashMap<>();
    private final Map<String, Runnable> progressRunnables = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Executor executor = Executors.newSingleThreadExecutor();

    /** Get the singleton instance of VideoCacheManager */
    public static synchronized VideoCacheManager getInstance(Context context) {
        if (instance == null) {
            instance = new VideoCacheManager(context.getApplicationContext());
        }
        return instance;
    }

    private VideoCacheManager(Context context) {
        this.context = context;
        
        // Create cache directory
        File cacheDir = new File(context.getFilesDir(), "video_cache");
        if (!cacheDir.exists()) {
            cacheDir.mkdirs();
        }

        // Setup database and cache
        databaseProvider = new StandaloneDatabaseProvider(context);
        
        // Create download cache with no eviction
        downloadCache = new SimpleCache(
                cacheDir,
                new NoOpCacheEvictor(),
                databaseProvider);

        // Create download manager
        DataSource.Factory dataSourceFactory = buildDataSourceFactory(context);
        downloadManager = new DownloadManager(
                context,
                databaseProvider,
                downloadCache,
                dataSourceFactory,
                executor);
        
        // Start the download manager
        downloadManager.resumeDownloads();
        
        // Read existing downloads
        loadExistingDownloads();
    }

    /**
     * Starts downloading a video for offline playback.
     *
     * @param url URL of the video to download
     * @return A unique ID for the download (base64 encoded URL)
     */
    public String startDownload(String url) {
        if (url == null || url.isEmpty()) {
            return "";
        }
        
        String urlId = generateUrlId(url);
        
        // Ensure any previous download is properly cleaned up
        try {
            // Check if there's an existing download in a non-completed state
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = null;
            try {
                download = downloadIndex.getDownload(urlId);
            } catch (IOException e) {
                // Ignore - just means no download exists
            }
            
            if (download != null && download.state != Download.STATE_COMPLETED) {
                // Remove the existing download before starting a new one
                downloadManager.removeDownload(urlId);
                
                // Remove from active downloads and stop progress updates
                activeDownloads.remove(urlId);
                stopProgressUpdates(urlId);
                
                // Small delay to ensure ExoPlayer has processed the removal
                try {
                    Thread.sleep(100);
                } catch (InterruptedException e) {
                    // Ignore
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Error clearing previous download: " + e.getMessage());
            // Continue with the download attempt anyway
        }
        
        // Check if already cached and completed
        if (isDownloaded(url)) {
            Log.d(TAG, "Video already downloaded: " + url);
            return urlId;
        }
        
        // Check if already downloading
        if (activeDownloads.containsKey(urlId)) {
            Log.d(TAG, "Download already in progress: " + url);
            return urlId;
        }
        
        try {
            // Create media item
            Uri uri = Uri.parse(url);
            MediaItem mediaItem = MediaItem.fromUri(uri);
            
            // Set MIME type if possible to help with progress reporting
            String mimeType = null;
            if (url.toLowerCase().endsWith(".mp4")) {
                mimeType = "video/mp4";
            } else if (url.toLowerCase().endsWith(".m3u8")) {
                mimeType = "application/x-mpegURL";
            } else if (url.toLowerCase().endsWith(".mpd")) {
                mimeType = "application/dash+xml";
            }
            
            // Create download request with proper metadata
            DownloadRequest.Builder requestBuilder = new DownloadRequest.Builder(urlId, uri)
                    .setData(url.getBytes(StandardCharsets.UTF_8));
            
            // Add mime type if available
            if (mimeType != null) {
                requestBuilder.setMimeType(mimeType);
            }
            
            DownloadRequest downloadRequest = requestBuilder.build();
            
            // Add to download manager
            downloadManager.addDownload(downloadRequest);
            
            // Create and store a download tracker
            DownloadTracker tracker = new DownloadTracker(url, urlId);
            activeDownloads.put(urlId, tracker);
            
            // Start tracking progress
            startProgressUpdates(urlId);
            
            Log.d(TAG, "Started download for: " + url + " with ID: " + urlId);
            return urlId;
        } catch (Exception e) {
            Log.e(TAG, "Error starting download: " + e.getMessage(), e);
            return "";
        }
    }

    /**
     * Cancels an active download.
     *
     * @param url URL of the video download to cancel
     * @return true if successfully canceled, false otherwise
     */
    public boolean cancelDownload(String url) {
        String urlId = generateUrlId(url);
        
        // Stop progress updates
        stopProgressUpdates(urlId);
        
        // Remove from active downloads
        DownloadTracker tracker = activeDownloads.remove(urlId);
        if (tracker == null) {
            return false;
        }
        
        // Remove from download manager
        downloadManager.removeDownload(urlId);
        
        Log.d(TAG, "Canceled download for: " + url);
        return true;
    }

    /**
     * Removes a downloaded video from the cache.
     *
     * @param url URL of the video to remove
     * @return true if successfully removed, false otherwise
     */
    public boolean removeDownload(String url) {
        // First cancel any active download
        cancelDownload(url);
        
        String urlId = generateUrlId(url);
        
        try {
            // Check if file exists before
            boolean existsBefore = isDownloaded(url);
            
            if (!existsBefore) {
                // File doesn't exist, nothing to remove
                return false;
            }
            
            // Remove from download manager and cache
            downloadManager.removeDownload(urlId);
            
            // Ensure the download is completely removed from tracking
            activeDownloads.remove(urlId);
            stopProgressUpdates(urlId);
            
            // Clear any cache entries for this URL to prevent stale data
            try {
                // The setDownloadStopReason method is not available in newer ExoPlayer/Media3 versions
                // Force download manager to remove any references to this download
                downloadManager.removeDownload(urlId);
                
                // Additional cleanup by explicitly clearing from cache
                if (downloadCache.isCached(urlId, 0, Long.MAX_VALUE)) {
                    downloadCache.removeResource(urlId);
                }
            } catch (Exception e) {
                // Ignore - entry might be already removed
            }
            
            Log.d(TAG, "Removed download for: " + url);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error removing download: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * Gets the current progress of a downloading video.
     *
     * @param url URL of the video
     * @return A value between 0.0 and 1.0 where 1.0 indicates the download is complete
     */
    public double getDownloadProgress(String url) {
        String urlId = generateUrlId(url);
        
        // If fully downloaded, return 1.0
        if (isDownloaded(url)) {
            return 1.0;
        }
        
        // Get from active downloads
        DownloadTracker tracker = activeDownloads.get(urlId);
        if (tracker != null) {
            return tracker.getProgress();
        }
        
        // Check download index for status
        try {
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = downloadIndex.getDownload(urlId);
            if (download != null) {
                if (download.state == Download.STATE_COMPLETED) {
                    return 1.0;
                } else if (download.state == Download.STATE_DOWNLOADING) {
                    return download.getPercentDownloaded() / 100.0;
                }
            }
        } catch (IOException e) {
            Log.e(TAG, "Error getting download progress: " + e.getMessage(), e);
        }
        
        return 0.0;
    }

    /**
     * Gets the file path of a cached video.
     *
     * @param url URL of the video
     * @return File path of the cached video, or null if not cached
     */
    @Nullable
    public String getCachedVideoPath(String url) {
        String urlId = generateUrlId(url);
        
        // Check if video is fully downloaded
        try {
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = downloadIndex.getDownload(urlId);
            
            if (download != null && download.state == Download.STATE_COMPLETED) {
                // For ExoPlayer, we don't have direct file path access
                // Instead, we return a placeholder path that will be recognized
                // by the video player when it's used to build a MediaSource
                return "exoplayer://download/" + urlId;
            }
        } catch (IOException e) {
            Log.e(TAG, "Error checking download status: " + e.getMessage(), e);
        }
        
        return null;
    }

    /**
     * Checks if a video is downloaded and available for offline playback.
     *
     * @param url URL of the video
     * @return true if the video is cached and ready for offline playback
     */
    public boolean isDownloaded(String url) {
        return getCachedVideoPath(url) != null;
    }

    /**
     * Gets the maximum number of concurrent downloads supported.
     *
     * @return Number of concurrent downloads allowed
     */
    public int getMaxConcurrentDownloads() {
        return MAX_CONCURRENT_DOWNLOADS;
    }

    /**
     * Gets the current download state of a video.
     *
     * @param url URL of the video
     * @return Download state (initial, downloading, downloaded, failed)
     */
    public int getDownloadState(String url) {
        String urlId = generateUrlId(url);
        
        // Check if actively downloading
        if (activeDownloads.containsKey(urlId)) {
            return 1; // downloading
        }
        
        // Check if already downloaded
        if (isDownloaded(url)) {
            return 2; // downloaded
        }
        
        // Check if download failed
        try {
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = downloadIndex.getDownload(urlId);
            
            if (download != null && download.state == Download.STATE_FAILED) {
                return 3; // failed
            }
        } catch (IOException e) {
            // Ignore - treat as initial state
        }
        
        // Default state
        return 0; // initial
    }

    /**
     * Creates a MediaSource for the given URL, using the download cache if available.
     *
     * @param context Android context
     * @param url URL to create MediaSource for
     * @return MediaSource that will use the cached version if available
     */
    public MediaSource createMediaSource(Context context, String url) {
        Uri uri = Uri.parse(url);
        
        // Build data source factory that uses the download cache
        CacheDataSource.Factory cacheDataSourceFactory = buildCacheDataSourceFactory(context);
        
        // Create a MediaSource using the cached data source and DefaultMediaSourceFactory
        // which will automatically detect the correct type of MediaSource based on the URI/extension
        return new DefaultMediaSourceFactory(context)
                .setDataSourceFactory(cacheDataSourceFactory)
                .createMediaSource(MediaItem.fromUri(uri));
    }

    // Helper method to start progress updates for a download
    private void startProgressUpdates(String urlId) {
        stopProgressUpdates(urlId);
        
        Handler handler = new Handler(Looper.getMainLooper());
        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                updateProgress(urlId);
                handler.postDelayed(this, 500); // Update every 500ms
            }
        };
        
        progressHandlers.put(urlId, handler);
        progressRunnables.put(urlId, runnable);
        handler.post(runnable);
    }

    // Helper method to stop progress updates for a download
    private void stopProgressUpdates(String urlId) {
        Handler handler = progressHandlers.get(urlId);
        Runnable runnable = progressRunnables.get(urlId);
        
        if (handler != null && runnable != null) {
            handler.removeCallbacks(runnable);
        }
        
        progressHandlers.remove(urlId);
        progressRunnables.remove(urlId);
    }

    // Helper method to update progress for a download
    private void updateProgress(String urlId) {
        try {
            // Check if we already removed this download from tracking - avoid processing again
            if (!progressHandlers.containsKey(urlId) && !activeDownloads.containsKey(urlId)) {
                return;
            }
            
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = downloadIndex.getDownload(urlId);
            
            if (download != null) {
                DownloadTracker tracker = activeDownloads.get(urlId);
                
                if (tracker != null) {
                    double percentDownloaded = download.getPercentDownloaded();
                    long bytesDownloaded = download.getBytesDownloaded();
                    long contentLength = download.contentLength;
                    int state = download.state;
                    
                    // Calculate progress manually if percentDownloaded is not available
                    if (percentDownloaded == C.PERCENTAGE_UNSET && contentLength > 0 && bytesDownloaded > 0) {
                        percentDownloaded = (bytesDownloaded * 100.0) / contentLength;
                    }
                    
                    // Log download progress details (only for active/downloading states)
                    if (state == Download.STATE_DOWNLOADING) {
                        Log.d(TAG, "Download progress for " + urlId + ": " + 
                              percentDownloaded + "%, bytes: " + bytesDownloaded + 
                              ", total: " + contentLength + ", state: " + stateToString(state));
                    }
                    
                    tracker.update(percentDownloaded / 100.0, bytesDownloaded);
                    
                    // If download completed or failed, stop tracking
                    if (download.state == Download.STATE_COMPLETED || 
                        download.state == Download.STATE_FAILED) {
                        
                        if (download.state == Download.STATE_COMPLETED) {
                            // Mark as fully downloaded
                            tracker.update(1.0, bytesDownloaded);
                            Log.d(TAG, "Download completed for: " + urlId);
                        } else if (download.state == Download.STATE_FAILED) {
                            Log.e(TAG, "Download failed for: " + urlId);
                        }
                        
                        // Clean up everything related to this download to avoid repeated logging
                        stopProgressUpdates(urlId);
                        activeDownloads.remove(urlId);
                    }
                } else {
                    Log.d(TAG, "No tracker found for download: " + urlId);
                    stopProgressUpdates(urlId);
                }
            } else {
                // Download entry not found, stop tracking
                Log.d(TAG, "No download found for ID: " + urlId);
                stopProgressUpdates(urlId);
                activeDownloads.remove(urlId);
            }
        } catch (IOException e) {
            Log.e(TAG, "Error updating download progress: " + e.getMessage(), e);
            // On error, also stop tracking to avoid repeated failures
            stopProgressUpdates(urlId);
            activeDownloads.remove(urlId);
        }
    }
    
    // Helper method to convert download state to string for debugging
    private String stateToString(int state) {
        switch (state) {
            case Download.STATE_QUEUED: return "QUEUED";
            case Download.STATE_STOPPED: return "STOPPED";
            case Download.STATE_DOWNLOADING: return "DOWNLOADING";
            case Download.STATE_COMPLETED: return "COMPLETED";
            case Download.STATE_FAILED: return "FAILED";
            case Download.STATE_REMOVING: return "REMOVING";
            case Download.STATE_RESTARTING: return "RESTARTING";
            default: return "UNKNOWN";
        }
    }

    // Helper method to generate a download ID from a URL
    private String generateUrlId(String url) {
        return Base64.encodeToString(url.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    // Helper method to load existing downloads
    private void loadExistingDownloads() {
        executor.execute(() -> {
            try {
                DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
                DownloadCursor downloadCursor = downloadIndex.getDownloads();
                
                try {
                    while (downloadCursor.moveToNext()) {
                        Download download = downloadCursor.getDownload();
                        String urlId = download.request.id;
                        
                        // Try to recover the URL from the download data
                        String url = null;
                        if (download.request.data != null) {
                            url = new String(download.request.data, StandardCharsets.UTF_8);
                        }
                        
                        // If URL could not be recovered, skip this download
                        if (url == null) {
                            continue;
                        }
                        
                        // Create a tracker for active downloads
                        if (download.state == Download.STATE_DOWNLOADING) {
                            DownloadTracker tracker = new DownloadTracker(url, urlId);
                            tracker.update(download.getPercentDownloaded() / 100.0, download.getBytesDownloaded());
                            activeDownloads.put(urlId, tracker);
                            
                            // Start tracking progress
                            startProgressUpdates(urlId);
                        }
                    }
                } finally {
                    downloadCursor.close();
                }
            } catch (IOException e) {
                Log.e(TAG, "Error loading existing downloads: " + e.getMessage(), e);
            }
        });
    }

    // Build a CacheDataSource.Factory that uses the download cache
    private CacheDataSource.Factory buildCacheDataSourceFactory(Context context) {
        DataSource.Factory upstreamFactory = buildDataSourceFactory(context);
        
        return new CacheDataSource.Factory()
                .setCache(downloadCache)
                .setUpstreamDataSourceFactory(upstreamFactory)
                .setCacheWriteDataSinkFactory(null) // Disable writing to cache during playback
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR);
    }

    // Build a DataSource.Factory for use by ExoPlayer
    private DataSource.Factory buildDataSourceFactory(Context context) {
        DefaultBandwidthMeter bandwidthMeter = new DefaultBandwidthMeter.Builder(context).build();
        DefaultHttpDataSource.Factory httpFactory = new DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setUserAgent(Util.getUserAgent(context, "VideoPlayerPlugin"));
        
        return new DefaultDataSource.Factory(context, httpFactory);
    }

    /**
     * Class to track a download's progress
     */
    private static class DownloadTracker {
        private final String url;
        private final String urlId;
        private double progress;
        private long bytesDownloaded;

        DownloadTracker(String url, String urlId) {
            this.url = url;
            this.urlId = urlId;
            this.progress = 0.0;
            this.bytesDownloaded = 0;
        }

        void update(double progress, long bytesDownloaded) {
            this.progress = progress;
            this.bytesDownloaded = bytesDownloaded;
        }

        double getProgress() {
            return progress;
        }

        long getBytesDownloaded() {
            return bytesDownloaded;
        }
    }

    /**
     * Gets the number of bytes downloaded for a video.
     *
     * @param url URL of the video
     * @return Number of bytes downloaded or 0 if not downloading
     */
    public long getBytesDownloaded(String url) {
        String urlId = generateUrlId(url);
        
        // Get from active downloads
        DownloadTracker tracker = activeDownloads.get(urlId);
        if (tracker != null) {
            return tracker.getBytesDownloaded();
        }
        
        // Check download index for status
        try {
            DownloadIndex downloadIndex = downloadManager.getDownloadIndex();
            Download download = downloadIndex.getDownload(urlId);
            if (download != null) {
                if (download.state == Download.STATE_COMPLETED) {
                    return download.contentLength > 0 ? download.contentLength : download.getBytesDownloaded();
                } else if (download.state == Download.STATE_DOWNLOADING) {
                    return download.getBytesDownloaded();
                }
            }
        } catch (IOException e) {
            Log.e(TAG, "Error getting bytes downloaded: " + e.getMessage(), e);
        }
        
        return 0;
    }
} 