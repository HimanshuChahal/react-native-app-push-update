#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface RNAppPushUpdate : NSObject

- (NSString *)getJSBundleFileWithWindow:(UIWindow *)window launchOptions:(NSDictionary *)launchOptions;

@end
