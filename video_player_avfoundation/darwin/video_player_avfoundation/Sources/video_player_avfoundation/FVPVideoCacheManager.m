#import "./include/video_player_avfoundation/FVPVideoCacheManager.h"
#import <AVFoundation/AVFoundation.h>

// Declaration of FVPDownloadTask class
@class FVPDownloadTask;

// Declaration of internal interface for private properties and methods
@interface FVPVideoCacheManager () <AVAssetDownloadDelegate, NSURLSessionDelegate>

// Main download tracking dictionary
@property (nonatomic, strong) NSMutableDictionary<NSString *, FVPDownloadTask *> *activeDownloads;
// Progress tracking
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *progressMap;
// Successfully downloaded files
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *downloadedFiles;
// Download session for AVAsset downloads
@property (nonatomic, strong) AVAssetDownloadURLSession *downloadSession;
// Cache directory URL
@property (nonatomic, strong) NSURL *cacheDirectory;
// Dispatch queues for thread safety
@property (nonatomic, strong) dispatch_queue_t taskQueue;
@property (nonatomic, strong) dispatch_queue_t taskAccessQueue;
// Pending downloads queue for respecting max concurrent downloads limit
@property (nonatomic, strong) NSMutableArray *pendingDownloads;
// HLS file paths
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *hlsFilePaths;
// Stores completion handler for background sessions
@property (nonatomic, copy) void (^backgroundSessionCompletionHandler)(void);

@end

// Download task implementation to track individual downloads
@interface FVPDownloadTask : NSObject

@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *urlId;
@property (nonatomic, strong) AVAssetDownloadTask *task;
@property (atomic) double progress;
@property (nonatomic, strong) NSTimer *progressTimer;
@property (nonatomic, weak) FVPVideoCacheManager *manager;
@property (nonatomic) int64_t bytesReceived;
@property (nonatomic) int64_t bytesExpected;
@property (nonatomic) double lastReportedProgress;

- (instancetype)initWithAsset:(AVURLAsset *)asset 
                    urlString:(NSString *)urlString 
                        urlId:(NSString *)urlId 
                      manager:(FVPVideoCacheManager *)manager;
- (void)cancel;

@end

// Constants
static NSString *const kFVPTasksStorageKey = @"com.fvp.downloadTasks";
static NSString *const kFVPHLSFilePathsKey = @"com.fvp.hlsFilePaths";
static int const kFVPMaxConcurrentDownloads = 3;

@implementation FVPVideoCacheManager

#pragma mark - Singleton and initialization

+ (FVPVideoCacheManager *)shared {
    static FVPVideoCacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FVPVideoCacheManager alloc] init];
    });
    return instance;
}

+ (void)initializeCache {
    // Trigger the shared instance initialization
    [FVPVideoCacheManager shared];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeDownloads = [NSMutableDictionary dictionary];
        _progressMap = [NSMutableDictionary dictionary];
        _downloadedFiles = [NSMutableDictionary dictionary];
        _hlsFilePaths = [NSMutableDictionary dictionary];
        _pendingDownloads = [NSMutableArray array];
        
        // Load HLS file paths from UserDefaults
        NSDictionary *savedHLSPaths = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPHLSFilePathsKey];
        if (savedHLSPaths) {
            [_hlsFilePaths addEntriesFromDictionary:savedHLSPaths];
        }
        
        // Setup thread safety dispatch queues
        _taskQueue = dispatch_queue_create("com.fvp.taskQueue", DISPATCH_QUEUE_SERIAL);
        _taskAccessQueue = dispatch_queue_create("com.fvp.accessQueue", DISPATCH_QUEUE_SERIAL);
        
        // Create cache directory
        _cacheDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                  inDomains:NSUserDomainMask] firstObject];
        _cacheDirectory = [_cacheDirectory URLByAppendingPathComponent:@"AVAssetCache" isDirectory:YES];
        
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:_cacheDirectory
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error]) {
            NSLog(@"Failed to create cache directory: %@", error.localizedDescription);
        }
        
        // Setup AVAssetDownloadURLSession
        [self setupAVAssetDownloader];
        
        // Load existing cache files
        dispatch_async(_taskQueue, ^{
            [self loadCachedFiles];
            [self restorePersistentDownloads];
        });
    }
    return self;
}

- (void)setupAVAssetDownloader {
    // Get the app's bundle ID for session identifier
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.fvp";
    NSString *sessionIdentifier = [NSString stringWithFormat:@"%@.video_cache.background", bundleId];
    
    // Using the background session configuration
    NSURLSessionConfiguration *backgroundConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionIdentifier];
    
    // Increase timeout intervals for better network tolerance
    backgroundConfiguration.timeoutIntervalForRequest = 60;
    backgroundConfiguration.timeoutIntervalForResource = 120;
    
    // Configure for background processing
    backgroundConfiguration.sessionSendsLaunchEvents = YES;
    backgroundConfiguration.discretionary = NO;
    
    self.downloadSession = [AVAssetDownloadURLSession sessionWithConfiguration:backgroundConfiguration
                                                          assetDownloadDelegate:self
                                                                  delegateQueue:[NSOperationQueue mainQueue]];
}

#pragma mark - Cache File Management

- (void)loadCachedFiles {
    // Load files from the cache directory
    NSError *error = nil;
    NSArray<NSURL *> *fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:self.cacheDirectory
                                                               includingPropertiesForKeys:nil
                                                                                  options:0
                                                                                    error:&error];
    if (error) {
        NSLog(@"Failed to load cached files: %@", error.localizedDescription);
        return;
    }
    
    for (NSURL *fileURL in fileURLs) {
        NSString *filename = [fileURL lastPathComponent];
        // Extract URL ID from filename (base64 encoded)
        NSString *urlId = [self getURLIdFromFilename:filename];
        if (urlId) {
            self.downloadedFiles[urlId] = fileURL.path;
        }
    }
    
    // Also load HLS paths from UserDefaults that might not be in the cache directory
    NSDictionary *hlsPaths = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPHLSFilePathsKey];
    if (hlsPaths) {
        for (NSString *urlId in hlsPaths) {
            NSString *path = hlsPaths[urlId];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                self.downloadedFiles[urlId] = path;
            }
        }
    }
}

- (void)restorePersistentDownloads {
    // First check for any pending downloads in the session
    __weak typeof(self) weakSelf = self;
    [self.downloadSession getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
        for (NSURLSessionTask *task in tasks) {
            if ([task isKindOfClass:[AVAssetDownloadTask class]]) {
                AVAssetDownloadTask *downloadTask = (AVAssetDownloadTask *)task;
                [weakSelf restoreTaskFromSession:downloadTask];
            }
        }
        
        // Then check saved tasks that might not be in the session yet
        [weakSelf restoreSavedTasks];
    }];
}

- (void)restoreTaskFromSession:(AVAssetDownloadTask *)task {
    if (task.taskDescription) {
        NSString *urlId = task.taskDescription;
        NSString *urlString = [self getUrlStringFromTaskIdentifier:urlId];
        
        if (urlString) {
            // Create a new download task object
            AVURLAsset *asset = task.URLAsset;
            FVPDownloadTask *downloadTask = [[FVPDownloadTask alloc] initWithAsset:asset
                                                                         urlString:urlString
                                                                             urlId:urlId
                                                                           manager:self];
            downloadTask.task = task;
            
            // Add to our tracking dictionary
            dispatch_sync(self.taskAccessQueue, ^{
                self.activeDownloads[urlId] = downloadTask;
            });
            
            // Report current progress
            if (task.countOfBytesExpectedToReceive > 0) {
                double progress = (double)task.countOfBytesReceived / (double)task.countOfBytesExpectedToReceive;
                downloadTask.progress = progress;
                self.progressMap[urlId] = @(progress);
            }
        }
    }
}

- (void)restoreSavedTasks {
    NSDictionary *savedTasks = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPTasksStorageKey];
    if (!savedTasks) {
        return;
    }
    
    for (NSString *urlId in savedTasks) {
        // Skip if already restored from session
        __block BOOL alreadyActive = NO;
        
        dispatch_sync(self.taskAccessQueue, ^{
            alreadyActive = (self.activeDownloads[urlId] != nil);
        });
        
        if (alreadyActive) {
            continue;
        }
        
        NSDictionary *taskInfo = savedTasks[urlId];
        NSString *urlString = taskInfo[@"urlString"];
        
        if (urlString) {
            // Check if it's already fully cached
            if ([self getCachedVideoPath:urlString]) {
                // It's completed, no need to restore
                continue;
            }
            
            // Add to pending downloads to restart
            [self addPendingDownload:urlString];
        }
    }
    
    // Process any pending downloads that need to be restarted
    [self processPendingDownloads];
}

- (NSString *)getUrlStringFromTaskIdentifier:(NSString *)identifier {
    // Try to decode base64 identifier
    NSData *data = [[NSData alloc] initWithBase64EncodedString:identifier options:0];
    if (data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSString *)getURLIdFromFilename:(NSString *)filename {
    // Extract URL ID from filename (remove file extension)
    NSString *urlId = [filename stringByDeletingPathExtension];
    // Check if it looks like a base64 string (simplified check)
    if ([urlId length] % 4 == 0 && [urlId rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
        return urlId;
    }
    return nil;
}

#pragma mark - Thread Safety Methods

- (FVPDownloadTask *)getDownloadTaskForUrlId:(NSString *)urlId {
    __block FVPDownloadTask *task = nil;
    dispatch_sync(self.taskAccessQueue, ^{
        task = self.activeDownloads[urlId];
    });
    return task;
}

- (void)setDownloadTask:(FVPDownloadTask *)task forUrlId:(NSString *)urlId {
    dispatch_sync(self.taskAccessQueue, ^{
        self.activeDownloads[urlId] = task;
    });
}

- (void)removeDownloadTaskForUrlId:(NSString *)urlId {
    dispatch_sync(self.taskAccessQueue, ^{
        [self.activeDownloads removeObjectForKey:urlId];
    });
}

- (NSUInteger)downloadTasksCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.taskAccessQueue, ^{
        count = [self.activeDownloads count];
    });
    return count;
}

- (void)addPendingDownload:(NSString *)urlString {
    dispatch_sync(self.taskAccessQueue, ^{
        [self.pendingDownloads addObject:urlString];
    });
}

- (NSString *)getNextPendingDownload {
    __block NSString *nextDownload = nil;
    
    dispatch_sync(self.taskAccessQueue, ^{
        if ([self.pendingDownloads count] > 0) {
            nextDownload = self.pendingDownloads[0];
            [self.pendingDownloads removeObjectAtIndex:0];
        }
    });
    
    return nextDownload;
}

#pragma mark - Public API Methods

- (NSString *)startDownload:(NSString *)urlString {
    if (!urlString || [urlString length] == 0) {
        return @"";
    }
    
    NSString *urlId = [self generateUrlId:urlString];
    
    // Run on the task queue to avoid blocking the main thread
    dispatch_async(self.taskQueue, ^{
        // Check if already cached
        if ([self getCachedVideoPath:urlString]) {
            // Already cached, nothing to do
            return;
        }
        
        // Check if already downloading
        if ([self getDownloadTaskForUrlId:urlId]) {
            // Already downloading, nothing to do
            return;
        }
        
        // Check if we're at max concurrent downloads
        if ([self downloadTasksCount] >= kFVPMaxConcurrentDownloads) {
            // Add to pending queue
            [self addPendingDownload:urlString];
            return;
        }
        
        [self performDownload:urlString];
    });
    
    return urlId;
}

- (void)performDownload:(NSString *)urlString {
    NSString *urlId = [self generateUrlId:urlString];
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"Invalid URL: %@", urlString);
        return;
    }
    
    if (!self.downloadSession) {
        NSLog(@"Download session not available");
        return;
    }
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    FVPDownloadTask *downloadTask = [[FVPDownloadTask alloc] initWithAsset:asset
                                                                 urlString:urlString
                                                                     urlId:urlId
                                                                   manager:self];
    
    // Create options based on iOS version
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:@{
        AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: @0
    }];
    
    // Add presentation size option for iOS 14+
    if (@available(iOS 14.0, *)) {
        [options setObject:[NSValue valueWithCGSize:CGSizeMake(480, 360)]
                    forKey:AVAssetDownloadTaskMinimumRequiredPresentationSizeKey];
    }
    
    // Create the download task on the main thread as required by AVFoundation
    dispatch_async(dispatch_get_main_queue(), ^{
        AVAssetDownloadTask *assetDownloadTask = [self.downloadSession assetDownloadTaskWithURLAsset:asset
                                                                                          assetTitle:urlId
                                                                                    assetArtworkData:nil
                                                                                             options:options];
        
        if (!assetDownloadTask) {
            NSLog(@"Could not create download task for URL: %@", urlString);
            return;
        }
        
        // Set the task description to help with restoring state
        assetDownloadTask.taskDescription = urlId;
        
        downloadTask.task = assetDownloadTask;
        [self setDownloadTask:downloadTask forUrlId:urlId];
        
        NSLog(@"Starting download for: %@", urlString);
        
        // Start the download
        [assetDownloadTask resume];
        
        // Save state
        [self saveDownloadTasks];
    });
}

- (void)processPendingDownloads {
    // Process pending downloads if we have capacity
    while ([self downloadTasksCount] < kFVPMaxConcurrentDownloads) {
        NSString *nextDownload = [self getNextPendingDownload];
        if (!nextDownload) {
            break;
        }
        
        [self performDownload:nextDownload];
    }
}

- (BOOL)cancelDownload:(NSString *)urlString {
    NSString *urlId = [self generateUrlId:urlString];
    __block BOOL cancelled = NO;
    
    // First check if it's in the pending queue
    dispatch_sync(self.taskAccessQueue, ^{
        NSUInteger index = [self.pendingDownloads indexOfObject:urlString];
        if (index != NSNotFound) {
            [self.pendingDownloads removeObjectAtIndex:index];
            cancelled = YES;
        }
    });
    
    if (cancelled) {
        return YES;
    }
    
    // Then check active downloads
    FVPDownloadTask *downloadTask = [self getDownloadTaskForUrlId:urlId];
    if (downloadTask) {
        [downloadTask cancel];
        [self removeDownloadTaskForUrlId:urlId];
        [self saveDownloadTasks];
        
        // Process any pending downloads
        [self processPendingDownloads];
        
        return YES;
    }
    
    return NO;
}

- (BOOL)removeDownload:(NSString *)urlString {
    // First cancel any active downloads
    [self cancelDownload:urlString];
    
    NSString *urlId = [self generateUrlId:urlString];
    
    if ([self isHLS:urlString]) {
        // For HLS files, check the special storage in UserDefaults
        NSMutableDictionary *hlsPaths = [NSMutableDictionary dictionaryWithDictionary:
                                        [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPHLSFilePathsKey] ?: @{}];
        
        NSString *path = hlsPaths[urlId];
        if (path) {
            NSError *error = nil;
            if ([[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
                [hlsPaths removeObjectForKey:urlId];
                [[NSUserDefaults standardUserDefaults] setObject:hlsPaths forKey:kFVPHLSFilePathsKey];
                return YES;
            } else {
                NSLog(@"Error removing cached HLS file: %@ at path %@", error.localizedDescription, path);
                return NO;
            }
        }
    } else {
        // For regular files, just delete from the file system
        NSString *path = [self.downloadedFiles objectForKey:urlId];
        if (path) {
            NSError *error = nil;
            if ([[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
                [self.downloadedFiles removeObjectForKey:urlId];
                return YES;
            } else {
                NSLog(@"Error removing cached file: %@", error.localizedDescription);
                return NO;
            }
        }
    }
    
    return NO;
}

- (double)getDownloadProgress:(NSString *)urlString {
    NSString *urlId = [self generateUrlId:urlString];
    
    // If fully downloaded, return 1.0
    if ([self getCachedVideoPath:urlString]) {
        return 1.0;
    }
    
    // Check active downloads
    FVPDownloadTask *downloadTask = [self getDownloadTaskForUrlId:urlId];
    if (downloadTask) {
        return downloadTask.progress;
    }
    
    // Check progress map for saved progress
    NSNumber *progress = self.progressMap[urlId];
    if (progress) {
        return [progress doubleValue];
    }
    
    return 0.0;
}

- (NSString *)getCachedVideoPath:(NSString *)urlString {
    NSString *urlId = [self generateUrlId:urlString];
    
    // For HLS streams, check the special storage first
    if ([self isHLS:urlString]) {
        NSDictionary *hlsPaths = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPHLSFilePathsKey];
        NSString *path = hlsPaths[urlId];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }
    
    // Then check regular cached files
    NSString *path = self.downloadedFiles[urlId];
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }
    
    return nil;
}

- (int)getMaxConcurrentDownloads {
    return kFVPMaxConcurrentDownloads;
}

- (AVAsset *)getAssetForURL:(NSString *)urlString {
    NSString *path = [self getCachedVideoPath:urlString];
    if (path) {
        return [AVAsset assetWithURL:[NSURL fileURLWithPath:path]];
    }
    return nil;
}

- (BOOL)isVideoCached:(NSString *)urlString {
    return [self getCachedVideoPath:urlString] != nil;
}

/**
 * Gets the current download state of a video.
 * 
 * @param urlString URL of the video
 * @return Integer state: 0 (initial), 1 (downloading), 2 (downloaded), 3 (failed)
 */
- (NSInteger)getDownloadState:(NSString *)urlString {
    // Generate the URL ID
    NSString *urlId = [self generateUrlId:urlString];
    
    // Check if it's downloaded
    if ([self isVideoCached:urlString]) {
        return 2; // downloaded
    }
    
    // Check if it's downloading
    __block BOOL isDownloading = NO;
    dispatch_sync(self.taskAccessQueue, ^{
        isDownloading = (self.activeDownloads[urlId] != nil);
    });
    
    if (isDownloading) {
        return 1; // downloading
    }
    
    // Check if it failed (from our tracking dictionaries)
    __block BOOL hasFailed = NO;
    
    // Check in NSUserDefaults for failed downloads
    NSDictionary *savedTasks = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPTasksStorageKey];
    if (savedTasks && savedTasks[urlId]) {
        NSDictionary *taskInfo = savedTasks[urlId];
        NSNumber *failedStatus = taskInfo[@"failed"];
        if (failedStatus && [failedStatus boolValue]) {
            return 3; // failed
        }
    }
    
    // Default state
    return 0; // initial
}

#pragma mark - Helper Methods

- (NSString *)generateUrlId:(NSString *)urlString {
    // Create a URL ID from the URL string by encoding it to base64
    NSData *data = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0];
}

- (BOOL)isHLS:(NSString *)urlString {
    return [urlString rangeOfString:@".m3u8" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (void)saveDownloadTasks {
    dispatch_sync(self.taskAccessQueue, ^{
        NSMutableDictionary *taskData = [NSMutableDictionary dictionary];
        
        for (NSString *urlId in self.activeDownloads) {
            FVPDownloadTask *downloadTask = self.activeDownloads[urlId];
            taskData[urlId] = @{
                @"urlString": downloadTask.urlString,
                @"progress": @(downloadTask.progress),
                @"bytesReceived": @(downloadTask.task.countOfBytesReceived),
                @"bytesExpected": @(downloadTask.task.countOfBytesExpectedToReceive),
                @"timestamp": @([[NSDate date] timeIntervalSince1970])
            };
        }
        
        [[NSUserDefaults standardUserDefaults] setObject:taskData forKey:kFVPTasksStorageKey];
    });
}

#pragma mark - AVAssetDownloadDelegate

- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didFinishDownloadingToURL:(NSURL *)location {
    // Find the download task in our dictionary using task description
    NSString *urlId = assetDownloadTask.taskDescription;
    if (!urlId) {
        NSLog(@"Could not identify completed download task");
        return;
    }
    
    FVPDownloadTask *downloadTask = [self getDownloadTaskForUrlId:urlId];
    if (!downloadTask) {
        NSLog(@"Could not find matching download task for completed AVAssetDownloadTask");
        return;
    }
    
    NSString *originalUrlString = downloadTask.urlString;
    
    if ([self isHLS:originalUrlString]) {
        // For HLS, store the system-provided path
        NSMutableDictionary *hlsPaths = [NSMutableDictionary dictionaryWithDictionary:
                                        [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPHLSFilePathsKey] ?: @{}];
        
        hlsPaths[urlId] = location.path;
        [[NSUserDefaults standardUserDefaults] setObject:hlsPaths forKey:kFVPHLSFilePathsKey];
        
        NSLog(@"HLS download finished. Stored path: %@ for URL: %@", location.path, originalUrlString);
        
        // Update progress to complete
        downloadTask.progress = 1.0;
        self.progressMap[urlId] = @(1.0);
        
    } else {
        // For non-HLS files (e.g., MP4), move to our custom cache directory
        NSError *error = nil;
        
        // Use a consistent file extension, or derive from original URL if possible
        NSString *fileExtension = [NSURL URLWithString:originalUrlString].pathExtension;
        if (!fileExtension || fileExtension.length == 0) {
            fileExtension = location.pathExtension;
        }
        
        if (!fileExtension || fileExtension.length == 0) {
            fileExtension = @"mp4"; // Default
        }
        
        NSURL *destinationUrl = [self.cacheDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", urlId, fileExtension]];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:destinationUrl.path]) {
            [[NSFileManager defaultManager] removeItemAtURL:destinationUrl error:nil];
        }
        
        if ([[NSFileManager defaultManager] moveItemAtURL:location toURL:destinationUrl error:&error]) {
            NSLog(@"Non-HLS download finished. Moved to: %@ for URL: %@", destinationUrl.path, originalUrlString);
            
            self.downloadedFiles[urlId] = destinationUrl.path;
            downloadTask.progress = 1.0;
            self.progressMap[urlId] = @(1.0);
            
        } else {
            NSLog(@"Error moving non-HLS downloaded file: %@ for URL: %@", error.localizedDescription, originalUrlString);
            self.progressMap[urlId] = @(-1.0); // Indicate error
            [self removeDownloadTaskForUrlId:urlId];
            [self saveDownloadTasks];
            [self processPendingDownloads];
            return;
        }
    }
    
    // Common completion logic for both HLS and non-HLS
    [downloadTask cancel];
    [self removeDownloadTaskForUrlId:urlId];
    [self saveDownloadTasks];
    [self processPendingDownloads];
}

- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didLoadTimeRange:(CMTimeRange)timeRange totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad {
    // Calculate the accurate download progress based on loaded time ranges
    double percentComplete = 0.0;
    
    // Safely convert CMTime to seconds
    double expectedDuration = CMTimeGetSeconds(timeRangeExpectedToLoad.duration);
    
    // Iterate through the loaded time ranges
    for (NSValue *value in loadedTimeRanges) {
        CMTimeRange loadedTimeRange = [value CMTimeRangeValue];
        double loadedDuration = CMTimeGetSeconds(loadedTimeRange.duration);
        
        if (expectedDuration > 0) {
            percentComplete += loadedDuration / expectedDuration;
        }
    }
    
    // Make sure progress is between 0 and 1
    percentComplete = MIN(1.0, MAX(0.0, percentComplete));
    
    // Find the associated download task
    NSString *urlId = assetDownloadTask.taskDescription;
    FVPDownloadTask *downloadTask = [self getDownloadTaskForUrlId:urlId];
    
    if (!downloadTask) {
        return;
    }
    
    // Only update if the new progress is higher than the current progress
    if (percentComplete > downloadTask.progress) {
        downloadTask.progress = percentComplete;
        self.progressMap[urlId] = @(percentComplete);
    }
}

#pragma mark - URLSessionDelegate 

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"Download task completed with error: %@", error.localizedDescription);
        
        // Find the affected download task using task description
        if ([task isKindOfClass:[AVAssetDownloadTask class]]) {
            AVAssetDownloadTask *downloadTask = (AVAssetDownloadTask *)task;
            NSString *urlId = downloadTask.taskDescription;
            
            if (urlId) {
                FVPDownloadTask *fvpTask = [self getDownloadTaskForUrlId:urlId];
                
                if (fvpTask) {
                    // Mark as failed
                    self.progressMap[urlId] = @(-1.0);
                    
                    // Check if the error is a network error that might be temporary
                    if ([error.domain isEqualToString:NSURLErrorDomain] && 
                        (error.code == NSURLErrorNetworkConnectionLost || 
                         error.code == NSURLErrorNotConnectedToInternet ||
                         error.code == NSURLErrorTimedOut)) {
                        
                        // For temporary errors, attempt to resume if possible
                        NSData *resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
                        if (resumeData) {
                            // Try to resume the download after a short delay
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                // Check if the task was canceled in the meantime
                                if (![self getDownloadTaskForUrlId:urlId]) {
                                    return;
                                }
                                
                                // Try to create a new download task with resume data
                                // Note: AVAssetDownloadTask doesn't directly support resuming with data
                                // In a real implementation, you'd need more sophisticated handling here
                                [self performDownload:fvpTask.urlString];
                            });
                            return;
                        }
                    }
                    
                    [fvpTask cancel];
                    [self removeDownloadTaskForUrlId:urlId];
                    [self saveDownloadTasks];
                    [self processPendingDownloads];
                }
            }
        }
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    NSLog(@"Background URLSession finished events");
    
    // Process any pending downloads
    dispatch_async(self.taskQueue, ^{
        [self processPendingDownloads];
    });
    
    // Call the completion handler to let the system know we're done
    if (self.backgroundSessionCompletionHandler) {
        void (^completionHandler)(void) = self.backgroundSessionCompletionHandler;
        self.backgroundSessionCompletionHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    }
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    if (error) {
        NSLog(@"Session became invalid with error: %@", error.localizedDescription);
    }
    
    // Recreate the session
    [self setupAVAssetDownloader];
}

// Method to handle setting the background session completion handler
- (void)setBackgroundSessionCompletionHandler:(void (^)(void))completionHandler {
    self.backgroundSessionCompletionHandler = completionHandler;
}

- (int64_t)getBytesDownloaded:(NSString *)urlString {
    NSString *urlId = [self generateUrlId:urlString];
    
    // For completed downloads, return the content length
    NSString *path = [self getCachedVideoPath:urlString];
    if (path) {
        NSError *error = nil;
        NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        if (!error && attributes) {
            NSNumber *fileSize = attributes[NSFileSize];
            return [fileSize longLongValue];
        }
    }
    
    // Check active downloads
    FVPDownloadTask *downloadTask = self.activeDownloads[urlId];
    if (downloadTask) {
        return downloadTask.bytesReceived;
    }
    
    // If available in saved state
    NSDictionary *tasks = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kFVPTasksStorageKey];
    NSDictionary *taskData = tasks[urlId];
    if (taskData) {
        NSNumber *bytesReceived = taskData[@"bytesReceived"];
        if (bytesReceived) {
            return [bytesReceived longLongValue];
        }
    }
    
    return 0;
}

@end

#pragma mark - FVPDownloadTask Implementation

@implementation FVPDownloadTask

- (instancetype)initWithAsset:(AVURLAsset *)asset 
                    urlString:(NSString *)urlString 
                        urlId:(NSString *)urlId 
                      manager:(FVPVideoCacheManager *)manager {
    self = [super init];
    if (self) {
        _asset = asset;
        _urlString = urlString;
        _urlId = urlId;
        _manager = manager;
        _progress = 0.0;
        _lastReportedProgress = 0.0;
        
        // Start a timer to check download progress more frequently
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                 repeats:YES
                                                                   block:^(NSTimer * _Nonnull timer) {
                [self updateProgress];
            }];
        });
    }
    return self;
}

- (void)updateProgress {
    if (!self.task) {
        return;
    }
    
    // Update bytes received/expected from the task
    self.bytesReceived = self.task.countOfBytesReceived;
    self.bytesExpected = self.task.countOfBytesExpectedToReceive;
    
    // Calculate progress based on bytes
    if (self.bytesExpected > 0) {
        double currentProgress = (double)self.bytesReceived / (double)self.bytesExpected;
        
        // Only update if the progress has increased
        if (currentProgress > self.progress) {
            // Apply smoothing - don't jump too far ahead
            double smoothedProgress = MIN(self.progress + 0.03, currentProgress);
            
            // Only send updates if progress has increased by at least 1% from last reported
            if (smoothedProgress >= self.lastReportedProgress + 0.01 || smoothedProgress >= 0.99) {
                self.progress = smoothedProgress;
                self.lastReportedProgress = smoothedProgress;
                
                NSLog(@"Download progress for %@: %.2f%%", self.urlString, smoothedProgress * 100);
            } else {
                // Just update the internal progress without notifying
                self.progress = smoothedProgress;
            }
        }
    }
}

- (void)cancel {
    // Safely cancel the task if it exists and is active
    if (self.task) {
        if (self.task.state == NSURLSessionTaskStateRunning || self.task.state == NSURLSessionTaskStateSuspended) {
            [self.task cancel];
        }
    }
    
    // Clean up progress timer on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressTimer invalidate];
        self.progressTimer = nil;
    });
}

- (void)dealloc {
    if (self.progressTimer) {
        if ([NSThread isMainThread]) {
            [self.progressTimer invalidate];
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.progressTimer invalidate];
            });
        }
        self.progressTimer = nil;
    }
}

@end 