// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.C;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.drm.DrmSessionManager;
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider;
import java.io.IOException;
import java.util.Map;

/**
 * A video asset that uses the download cache for offline playback.
 */
public class CachedHttpVideoAsset extends VideoAsset {
    private static final String DEFAULT_USER_AGENT = "ExoPlayer";
    private static final String HEADER_USER_AGENT = "User-Agent";
    
    @Nullable private final String downloadId;
    @NonNull private final StreamingFormat streamingFormat;
    @NonNull private final Map<String, String> httpHeaders;

    /**
     * Creates a new video asset with download cache support.
     *
     * @param assetUrl original URL of the video
     * @param downloadId identifier for the cached download
     * @param streamingFormat format hint for the video
     * @param httpHeaders HTTP headers to use when playing from non-cached URL
     */
    CachedHttpVideoAsset(
            @Nullable String assetUrl,
            @Nullable String downloadId,
            @NonNull StreamingFormat streamingFormat,
            @NonNull Map<String, String> httpHeaders) {
        super(assetUrl);
        this.downloadId = downloadId;
        this.streamingFormat = streamingFormat;
        this.httpHeaders = httpHeaders;
    }

    @NonNull
    @Override
    public MediaItem getMediaItem() {
        MediaItem.Builder builder = new MediaItem.Builder().setUri(assetUrl);
        String mimeType = null;
        switch (streamingFormat) {
            case SMOOTH:
                mimeType = MimeTypes.APPLICATION_SS;
                break;
            case DYNAMIC_ADAPTIVE:
                mimeType = MimeTypes.APPLICATION_MPD;
                break;
            case HTTP_LIVE:
                mimeType = MimeTypes.APPLICATION_M3U8;
                break;
        }
        if (mimeType != null) {
            builder.setMimeType(mimeType);
        }
        return builder.build();
    }

    @NonNull
    @Override
    public MediaSource.Factory getMediaSourceFactory(@NonNull Context context) {
        // Get the Video Cache Manager
        VideoCacheManager cacheManager = VideoCacheManager.getInstance(context);
        
        // If this is a cached video, create a special MediaSource
        if (downloadId != null) {
            // Get the mime type for this video based on streaming format
            String mimeType = null;
            @C.ContentType int contentType = C.CONTENT_TYPE_OTHER;
            
            switch (streamingFormat) {
                case SMOOTH:
                    mimeType = MimeTypes.APPLICATION_SS;
                    contentType = C.CONTENT_TYPE_SS;
                    break;
                case DYNAMIC_ADAPTIVE:
                    mimeType = MimeTypes.APPLICATION_MPD;
                    contentType = C.CONTENT_TYPE_DASH;
                    break;
                case HTTP_LIVE:
                    mimeType = MimeTypes.APPLICATION_M3U8;
                    contentType = C.CONTENT_TYPE_HLS;
                    break;
            }
            
            // For cached videos, we create a media source factory that respects the streaming format
            final String finalMimeType = mimeType;
            final int finalContentType = contentType;
            
            return new MediaSource.Factory() {
                @Override
                public MediaSource createMediaSource(MediaItem mediaItem) {
                    // Set mime type on the media item if available
                    if (finalMimeType != null) {
                        mediaItem = mediaItem.buildUpon().setMimeType(finalMimeType).build();
                    }
                    
                    // Return appropriate media source from cache manager
                    return cacheManager.createMediaSource(context, assetUrl);
                }
                
                @Override
                public MediaSource.Factory setDrmSessionManagerProvider(
                        @Nullable DrmSessionManagerProvider provider) {
                    return this;
                }

                @Override
                public int[] getSupportedTypes() {
                    if (finalContentType != C.CONTENT_TYPE_OTHER) {
                        return new int[] { finalContentType };
                    }
                    return new DefaultMediaSourceFactory(context).getSupportedTypes();
                }
                
                public MediaSource.Factory setDrmSessionManager(
                        @Nullable DrmSessionManager drmSessionManager) {
                    return this;
                }
                
                public MediaSource.Factory setLoadErrorHandlingPolicy(
                        @Nullable androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy policy) {
                    return this;
                }
            };
        }
        
        // Otherwise, use the normal HTTP behavior similar to HttpVideoAsset
        String userAgent = DEFAULT_USER_AGENT;
        if (!httpHeaders.isEmpty() && httpHeaders.containsKey(HEADER_USER_AGENT)) {
            userAgent = httpHeaders.get(HEADER_USER_AGENT);
        }
        
        DefaultHttpDataSource.Factory initialFactory = new DefaultHttpDataSource.Factory();
        initialFactory.setUserAgent(userAgent).setAllowCrossProtocolRedirects(true);
        
        if (!httpHeaders.isEmpty()) {
            initialFactory.setDefaultRequestProperties(httpHeaders);
        }
        
        DataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context, initialFactory);
        return new DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory);
    }
} 