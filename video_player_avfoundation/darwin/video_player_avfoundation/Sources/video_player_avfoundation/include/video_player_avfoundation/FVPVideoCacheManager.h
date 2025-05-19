#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FVPVideoCacheManager : NSObject

@property (class, readonly, strong, nonatomic) FVPVideoCacheManager *shared;

- (NSString *)startDownload:(NSString *)url;
- (BOOL)cancelDownload:(NSString *)url;
- (BOOL)removeDownload:(NSString *)url;
- (double)getDownloadProgress:(NSString *)url;
- (int64_t)getBytesDownloaded:(NSString *)urlString;
- (nullable NSString *)getCachedVideoPath:(NSString *)url;
- (int)getMaxConcurrentDownloads;
- (nullable AVAsset *)getAssetForURL:(NSString *)urlString;
- (BOOL)isVideoCached:(NSString *)url;
- (NSInteger)getDownloadState:(NSString *)urlString;

+ (void)initializeCache;

/**
 * Gets the download progress for a URL.
 * @param urlString The URL to check progress for
 * @return Progress from 0.0 to 1.0
 */
- (double)getDownloadProgress:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END 