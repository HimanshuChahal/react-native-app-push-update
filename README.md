# react-native-app-push-update

Over the air push update for a React Native App

## Installation

```sh
npm install react-native-app-push-update
```

### Add these changes to your project

### 📄 File: `android/app/src/main/java/<your_package>/MainApplication.kt`

```js
// ...
// ++ Add this import
import com.apppushupdate.RNAppPushUpdate

class MainApplication : Application(), ReactApplication {

  override val reactNativeHost: ReactNativeHost =
      object : DefaultReactNativeHost(this) {

        override fun getJSMainModuleName(): String = "index"

        override fun getUseDeveloperSupport(): Boolean = BuildConfig.DEBUG

        // ++ Add this function
        override fun getJSBundleFile(): String? {
          return RNAppPushUpdate.getJSBundleFile(this@MainApplication)
        }

        override val isNewArchEnabled: Boolean = BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
        override val isHermesEnabled: Boolean = BuildConfig.IS_HERMES_ENABLED
      }
}
```

### 📄 File: `android/app/src/main/res/values/strings.xml`

```js
<string name="rn_app_push_update_key">your-product-key</string>
```

**⚠️ Important:** To get your product key, run this command `npx react-native-push-update product-key`

## Usage

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
