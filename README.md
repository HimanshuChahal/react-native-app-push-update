# react-native-app-push-update

✅ A lightweight library for pushing over-the-air updates to your React Native app — silently and seamlessly, with no popup dialogs required.

## Installation

```sh
npm install react-native-app-push-update
```

### Add these changes to your project

# Android

### 📄 File: `android/app/src/main/java/<your_package>/MainApplication.kt`

```kotlin
// ...
// =======================
// 🟡 ++ Add this import
import com.apppushupdate.RNAppPushUpdate
// =======================

class MainApplication : Application(), ReactApplication {

  override val reactNativeHost: ReactNativeHost =
      object : DefaultReactNativeHost(this) {

        override fun getJSMainModuleName(): String = "index"

        override fun getUseDeveloperSupport(): Boolean = BuildConfig.DEBUG

        // =======================
        // 🟡 ++ Add this function
        override fun getJSBundleFile(): String? {
          return RNAppPushUpdate.getJSBundleFile(this@MainApplication)
        }
        // =======================

        override val isNewArchEnabled: Boolean = BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
        override val isHermesEnabled: Boolean = BuildConfig.IS_HERMES_ENABLED
      }
}
```

### 📄 File: `android/app/src/main/res/values/strings.xml`

```xml
<string name="rn_app_push_update_key">your-product-key</string>
```

**⚠️ Important:** To get your product key, run this command `npx react-native-push-update product-key`

# iOS

## For swift file, // AppDelegate.swift

### 📄 File: `ios/<your_project_name>/AppDelegate.swift`

```swift
// ...
// =======================
// 🟡 ++ Add this import
import RNAppPushUpdate
// =======================

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {

    // =======================
    // 🟡 ++ Add these changes
    window = UIWindow(frame: UIScreen.main.bounds)
    if let bundle = RNAppPushUpdate().getJSBundleFile(window: window!, launchOptions: launchOptions) {
      return true
    }
    // =======================
    // ...

  }
}
```

## For objective c file, // AppDelegate.m

```objc
// ...
// =======================
// 🟡 ++ Add this import
#import "RNAppPushUpdate.h"
// =======================

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  // =======================
  // 🟡 ++ Add these changes
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

  RNAppPushUpdate *pushUpdate = [[RNAppPushUpdate alloc] init];
  NSString *bundlePath = [pushUpdate getJSBundleFileWithWindow:self.window launchOptions:launchOptions];

  if (bundlePath != nil) {
    return YES;
  }
  // =======================
  // ...

}
```

### 📄 File: `ios/<your_project_name>/Info.plist`

```xml
<key>rn_app_push_update_key</key>
<string>your-product-key</string>
```

**⚠️ Important:** To get your product key, run this command `npx react-native-push-update product-key`

## 🎉🎉 Congratulations 🎉🎉

### ✅ Updates will work silently, no further changes required for the update setup.

## Usage

### How to push the update?

#### Run this command in your terminal

```sh
npx react-native-push-update
```

### To get the latest installed update version

```js
import { getPushUpdateVersion } from 'react-native-app-push-update';

// ...

// Current installed update version
const version = await getPushUpdateVersion();
```

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
