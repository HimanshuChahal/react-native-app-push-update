#import "RNAppPushUpdate.h"
#import <React/RCTBridge.h>
#import <React/RCTRootView.h>

@interface RNAppPushUpdate ()

@property (nonatomic, strong) RCTBridge *bridge;
@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, strong) NSString *baseUrl;
@property (nonatomic, strong) NSString *productKey;

@end

@implementation RNAppPushUpdate

- (NSString *)getJSBundleFileWithWindow:(UIWindow *)window launchOptions:(NSDictionary *)launchOptions {
    NSString *bundlePath = nil;
    NSString *topic = @"";

    NSURL *bundleUrl = [[NSBundle bundleForClass:[self class]] URLForResource:@"RNAppPushUpdate" withExtension:@"bundle"];
    if (bundleUrl) {
        NSBundle *bundle = [NSBundle bundleWithURL:bundleUrl];
        NSString *path = [bundle pathForResource:@"RNAppPushUpdateInfo" ofType:@"plist"];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            self.baseUrl = dict[@"rn_app_push_update_base_url"] ?: @"";
            self.productKey = dict[@"rn_app_push_update_key"];
            topic = dict[@"rn_app_push_update_fcm_update_topic"] ?: @"";
        }
    }

    NSString *bundleDirectory = [[self getLibraryDirectory] stringByAppendingPathComponent:@"Application Support"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager fileExistsAtPath:bundleDirectory]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:bundleDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"RNAppPushUpdate ❌ Error creating directory: %@", error.localizedDescription);
        }
    }

    NSString *bundleFile = [bundleDirectory stringByAppendingPathComponent:@"index.ios.bundle"];
    if ([fileManager fileExistsAtPath:bundleFile]) {
        NSLog(@"RNAppPushUpdate ✅ Found the latest bundle");
        bundlePath = bundleFile;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self checkForUpdate];
    });

    self.initialized = YES;

    if (bundlePath) {
        NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];
        self.bridge = [[RCTBridge alloc] initWithBundleURL:bundleURL moduleProvider:nil launchOptions:launchOptions];

        NSString *moduleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"";
        RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:self.bridge moduleName:moduleName initialProperties:nil];

        UIViewController *rootVC = [UIViewController new];
        rootVC.view = rootView;
        window.rootViewController = rootVC;
        [window makeKeyAndVisible];
    }

    return bundlePath;
}

- (void)checkForUpdate {
    NSString *key = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"rn_app_push_update_key"] ?: self.productKey ?: @"";
    if ([key isEqualToString:@"no_key"] || [key length] == 0) {
        NSLog(@"RNAppPushUpdate ❌ No key provided in Info.plist. Please refer to the documentation.");
        return;
    }

    NSString *versionCode = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
    NSString *urlStr = [NSString stringWithFormat:@"%@product/versions?key=%@&version_code=%@", self.baseUrl, key, versionCode];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        NSLog(@"RNAppPushUpdate ❌ Invalid URL");
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"RNAppPushUpdate ❌ Error in fetching product versions: %@", error.localizedDescription);
            return;
        }
        if (!data) {
            NSLog(@"RNAppPushUpdate ❌ No data received");
            return;
        }
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSLog(@"RNAppPushUpdate ❌ JSON parse error: %@", jsonError.localizedDescription);
            return;
        }
        BOOL isVersionAccepted = [json[@"is_version_accepted"] boolValue];
        NSString *downloadUrl = json[@"download_url"];
        NSInteger bundleId = [json[@"accepted_bundle_id"] integerValue];
        if (isVersionAccepted && downloadUrl.length > 0) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSInteger downloadedBundleId = [defaults integerForKey:@"rn_app_push_update_shared_prefs_bundle_id"];
            if (downloadedBundleId != bundleId) {
                [self downloadBundleFromServerWithUrl:downloadUrl bundleId:bundleId];
            } else {
                NSLog(@"RNAppPushUpdate ✅ Latest bundle already downloaded");
            }
        } else {
            NSLog(@"RNAppPushUpdate ⚠️ No download URL or version not accepted");
        }
    }];
    [task resume];
}

- (void)downloadBundleFromServerWithUrl:(NSString *)urlStr bundleId:(NSInteger)bundleId {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url || ![urlStr rangeOfString:@"://" options:NSRegularExpressionSearch].length) {
        NSLog(@"RNAppPushUpdate ❌ Invalid download URL");
        return;
    }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"RNAppPushUpdate ❌ Error downloading bundle: %@", error.localizedDescription);
            return;
        }
        if (!data) {
            NSLog(@"RNAppPushUpdate ❌ Empty bundle data");
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"RNAppPushUpdate ❌ Invalid HTTP response code");
            return;
        }
        NSString *bundleDirectory = [[self getLibraryDirectory] stringByAppendingPathComponent:@"Application Support"];
        NSString *destinationPath = [bundleDirectory stringByAppendingPathComponent:@"index.ios.bundle"];

        NSError *writeError;
        [data writeToFile:destinationPath options:NSDataWritingAtomic error:&writeError];
        if (writeError) {
            NSLog(@"RNAppPushUpdate ❌ Error saving bundle: %@", writeError.localizedDescription);
            return;
        }

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setInteger:bundleId forKey:@"rn_app_push_update_shared_prefs_bundle_id"];

        NSLog(@"RNAppPushUpdate ✅ Bundle downloaded to %@", destinationPath);
    }];
    [task resume];
}

- (NSString *)getLibraryDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

@end
