#import "RNAppPushUpdate.h"
#import <React/RCTBridge.h>
#import <React/RCTRootView.h>
#import <objc/runtime.h>

@interface RNAppUpdateButtonHandler : NSObject

- (void)onUpdatePressed;

@end

@implementation RNAppUpdateButtonHandler

- (NSString *)getLibraryDirectory {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
  return [paths firstObject];
}

- (void)onUpdatePressed {
  UIWindow *window = nil;

  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (scene.activationState == UISceneActivationStateForegroundActive &&
          [scene isKindOfClass:[UIWindowScene class]]) {
          
          UIWindowScene *windowScene = (UIWindowScene *)scene;
          window = windowScene.windows.firstObject;
          break;
      }
  }
  if (!window) return;

  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *libraryDirPath = [self getLibraryDirectory];
  NSURL *libraryDir = [NSURL fileURLWithPath:libraryDirPath];
  NSURL *bundleDir = [libraryDir URLByAppendingPathComponent:@"Application Support"];
  if (![fileManager fileExistsAtPath:bundleDir.path]) {
    return;
  }

  NSURL *bundleFile = [bundleDir URLByAppendingPathComponent:@"index.ios.bundle"];
  if (![fileManager fileExistsAtPath:bundleFile.path]) {
    return;
  }

  NSString *jsBundlePath = bundleFile.path;
  RCTBridge *bridge = [[RCTBridge alloc] initWithBundleURL:[NSURL fileURLWithPath:jsBundlePath]
                                            moduleProvider:nil
                                             launchOptions:nil];

  NSString *moduleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"";
  RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:bridge moduleName:moduleName initialProperties:nil];

  UIViewController *vc = [UIViewController new];
  vc.view = rootView;
  window.rootViewController = vc;
  [window makeKeyAndVisible];
}

@end

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
  
  if (!self.initialized) {
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
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *downloadedVersionCode = [defaults stringForKey:@"rn_app_push_update_shared_prefs_version_code"] ?: @"-1";
      NSString *versionCode = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
      if (downloadedVersionCode == versionCode) {
        NSLog(@"RNAppPushUpdate ✅ Found the latest bundle");
        bundlePath = bundleFile;
      } else {
        NSLog(@"RNAppPushUpdate: Downloaded bundle is for versionCode: %@, current versionCode: %@. Deleting this bundle.", downloadedVersionCode, versionCode);
        
        NSError *error = nil;
        
        if ([fileManager fileExistsAtPath:bundleFile]) {
          BOOL success = [fileManager removeItemAtPath:bundleFile error:&error];
          if (success) {
            NSLog(@"RNAppPushUpdate: ✅ Bundle file deleted.");
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"rn_app_push_update_shared_prefs_bundle_id"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"rn_app_push_update_shared_prefs_version_code"];
          } else {
            NSLog(@"RNAppPushUpdate: ⚠️ Failed to delete bundle file: %@", error.localizedDescription);
          }
        }
      }
    }
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
                [self downloadBundleFromServerWithUrl:downloadUrl bundleId:bundleId versionCode:versionCode];
            } else {
                NSLog(@"RNAppPushUpdate ✅ Latest bundle already downloaded");
            }
        } else {
            NSLog(@"RNAppPushUpdate ⚠️ No download URL or version not accepted");
        }
    }];
    [task resume];
}

- (void)downloadBundleFromServerWithUrl:(NSString *)urlStr bundleId:(NSInteger)bundleId versionCode: (NSString *)versionCode {
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
        BOOL success = [data writeToFile:destinationPath options:NSDataWritingAtomic error:&writeError];
        if (!success || writeError) {
            NSLog(@"RNAppPushUpdate ❌ Error saving bundle: %@", writeError.localizedDescription);
            return;
        }

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setInteger:bundleId forKey:@"rn_app_push_update_shared_prefs_bundle_id"];
        [defaults setObject:versionCode forKey:@"rn_app_push_update_shared_prefs_version_code"];

        NSLog(@"RNAppPushUpdate ✅ Bundle downloaded to %@", destinationPath);
        [self showUpdateHeader];
    }];
    [task resume];
}

- (NSString *)getLibraryDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

- (void)showUpdateHeader {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            window = windowScene.windows.firstObject;
            break;
        }
    }
    if (!window) return;

    UIView *rootView = window.rootViewController.view;
    if (!rootView) return;
    
    RNAppUpdateButtonHandler *handler = [[RNAppUpdateButtonHandler alloc] init];

    UIButton *headerView = [UIButton new];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    headerView.backgroundColor = [UIColor colorWithRed:0.98 green:0.75 blue:0 alpha:1];
    [headerView addTarget:handler action:@selector(onUpdatePressed) forControlEvents:UIControlEventTouchUpInside];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"A new update is available";
    label.textColor = [UIColor blackColor];
    label.textAlignment = NSTextAlignmentLeft;
    label.font = [UIFont boldSystemFontOfSize:14];
    [headerView addSubview:label];

    UIButton *button = [UIButton new];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:handler action:@selector(onUpdatePressed) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:button];

    UILabel *btnLabel = [UILabel new];
    btnLabel.translatesAutoresizingMaskIntoConstraints = NO;
    btnLabel.font = [UIFont boldSystemFontOfSize:14];
    btnLabel.text = @"Update";
    btnLabel.textColor = [UIColor blueColor];
    [button addSubview:btnLabel];

    [rootView addSubview:headerView];
    
    objc_setAssociatedObject(headerView, "updateHandler", handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "updateHandler", handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [NSLayoutConstraint activateConstraints:@[
      [headerView.topAnchor constraintEqualToAnchor:rootView.safeAreaLayoutGuide.topAnchor],
      [headerView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
      [headerView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
      [headerView.heightAnchor constraintEqualToConstant:60],

      [label.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
      [label.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],

      [btnLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      [btnLabel.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-15],

      [button.topAnchor constraintEqualToAnchor:headerView.topAnchor],
      [button.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
      [button.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor],
      [button.leadingAnchor constraintEqualToAnchor:btnLabel.leadingAnchor constant:-15],
    ]];
  });
}

@end
