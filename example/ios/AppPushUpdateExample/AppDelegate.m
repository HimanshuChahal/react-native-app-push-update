#import "AppDelegate.h"
#import "RNAppPushUpdate.h"
#import <React/RCTBridge.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTRootView.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

  RNAppPushUpdate *pushUpdate = [[RNAppPushUpdate alloc] init];
  NSString *bundlePath = [pushUpdate getJSBundleFileWithWindow:self.window launchOptions:launchOptions];

  if (bundlePath != nil) {
    return YES;
  }

  NSURL *jsCodeLocation = [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index" fallbackResource:nil];
  RCTRootView *rootView = [[RCTRootView alloc] initWithBundleURL:jsCodeLocation
                                                      moduleName:@"YourApp"
                                               initialProperties:nil
                                                   launchOptions:launchOptions];

  UIViewController *rootViewController = [UIViewController new];
  rootViewController.view = rootView;
  self.window.rootViewController = rootViewController;
  [self.window makeKeyAndVisible];

  return YES;
}

@end
