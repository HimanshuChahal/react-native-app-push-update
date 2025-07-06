import Foundation
// import Firebase
import React

@objc public class RNAppPushUpdate: NSObject {

  private var bridge: RCTBridge?
  private var initialized = false
  private var baseUrl: String = ""
  private var productKey: String?

  public func getJSBundleFile(window: UIWindow, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> String? {
    var bundlePath: String? = nil
    
    var topic: String = ""
    
    if let bundleUrl = Bundle(for: RNAppPushUpdate.self).url(forResource: "RNAppPushUpdate", withExtension: "bundle"),
       let bundle = Bundle(url: bundleUrl),
       let path = bundle.path(forResource: "RNAppPushUpdateInfo", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
      baseUrl = dict["rn_app_push_update_base_url"] as? String ?? ""
      productKey = dict["rn_app_push_update_key"] as? String
      topic = dict["rn_app_push_update_fcm_update_topic"] as? String ?? ""
    }
    
    if !initialized {
      let fileManager = FileManager.default
      let bundleDirectory = getLibraryDirectory().appendingPathComponent("Application Support")
      if !fileManager.fileExists(atPath: bundleDirectory.path) {
        do {
          try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
          print("RNAppPushUpdate", "❌ Error creating directory: \(error.localizedDescription)")
        }
      }
      let bundleFile = bundleDirectory.appendingPathComponent("index.ios.bundle")
      if FileManager.default.fileExists(atPath: bundleFile.path) {
        let defaults = UserDefaults.standard
        let downloadedVersionCode = defaults.string(forKey: "rn_app_push_update_shared_prefs_version_code") ?? "-1"
        let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        if downloadedVersionCode == versionCode {
          print("RNAppPushUpdate", "Found the latest bundle")
          bundlePath = bundleFile.path
        } else {
          print("RNAppPushUpdate", "Downloaded bundle is for versionCode: \(downloadedVersionCode), current versionCode: \(versionCode). Deleting this bundle.")
          do {
            try FileManager.default.removeItem(at: bundleFile)
            print("RNAppPushUpdate", "✅ Bundle file deleted.")
            UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_bundle_id")
            UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_version_code")
          } catch {
            print("RNAppPushUpdate", "⚠️ Failed to delete bundle file.")
          }
        }
      }

      DispatchQueue.global(qos: .background).async {
        self.checkForUpdate()
      }

    //   if FirebaseApp.app() == nil {
    //       FirebaseApp.configure()
    //       print("RNAppPushUpdate", "Firebase initialized successfully.")
    //   }

      if !topic.isEmpty {
        //   Messaging.messaging().subscribe(toTopic: topic) { error in
        //       if let error = error {
        //           print("Firebase: Failed to subscribe to topic: \(topic)", error)
        //       } else {
        //           print("Firebase: Successfully subscribed to topic: \(topic)")
        //       }
        //   }
      }

      initialized = true
    }
    
    if let jsBundleFilePath = bundlePath {
      bridge = RCTBridge(bundleURL: URL(fileURLWithPath: jsBundleFilePath), moduleProvider: nil, launchOptions: launchOptions)
      let moduleName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? ""
      let rootView = RCTRootView(bridge: bridge!, moduleName: moduleName, initialProperties: nil)
      window.rootViewController = UIViewController()
      window.rootViewController?.view = rootView
      window.makeKeyAndVisible()
    }
    
    return bundlePath
  }

  private func getBundleFromPrivateDirectory() -> String? {
    let fileManager = FileManager.default
    let bundleDirectory = getLibraryDirectory().appendingPathComponent("Application Support")
    let filePath = bundleDirectory.appendingPathComponent("index.ios.bundle")
    
    if fileManager.fileExists(atPath: filePath.path) {
      return filePath.path
    } else {
      return nil
    }
  }

  func checkForUpdate() {
//    let baseUrl = Bundle.main.object(forInfoDictionaryKey: "rn_app_push_update_base_url") as? String ?? ""
    let key = Bundle.main.object(forInfoDictionaryKey: "rn_app_push_update_key") as? String ?? productKey ?? ""
    
    if key == "no_key" {
      print("RNAppPushUpdate", "❌ No key provided in Info.plist. Please refer to the documentation.")
      return
    }

    let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    guard let url = URL(string: "\(baseUrl)product/versions?key=\(key)&version_code=\(versionCode)") else {
      print("RNAppPushUpdate", "❌ Invalid URL")
      return
    }

    let client = URLSession.shared
    let request = URLRequest(url: url)
    
    client.dataTask(with: request) { data, response, error in
        if let error = error {
          print("RNAppPushUpdate", "❌ Error in fetching product versions: \(error.localizedDescription)")
          return
        }

        guard let data = data else {
          print("RNAppPushUpdate", "❌ No data received")
          return
        }

        do {
          if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            let isVersionAccepted = json["is_version_accepted"] as? Bool ?? true
            let downloadUrl = json["download_url"] as? String
            let bundleId = json["accepted_bundle_id"] as? Int ?? -1
            if isVersionAccepted, let downloadUrl = downloadUrl, !downloadUrl.isEmpty {
              let defaults = UserDefaults.standard
              let downloadedBundleId = defaults.integer(forKey: "rn_app_push_update_shared_prefs_bundle_id")
              
              if downloadedBundleId != bundleId {
                self.downloadBundleFromServer(urlStr: downloadUrl, bundleId: bundleId, versionCode: versionCode)
              } else {
                print("RNAppPushUpdate", "Latest bundle already downloaded")
              }
            } else {
              print("RNAppPushUpdate", "No download URL received or version not accepted")
            }
          }
        } catch {
          print("RNAppPushUpdate", "❌ Error in parsing JSON response from server: \(error.localizedDescription)")
        }
    }.resume()
  }

  private func downloadBundleFromServer(urlStr: String, bundleId: Int, versionCode: String) {
    guard let url = URL(string: urlStr), urlStr.range(of: "^[a-zA-Z0-9-]+://", options: .regularExpression) != nil else {
      print("RNAppPushUpdate", "❌ Invalid download URL")
      return
    }

    let client = URLSession.shared
    let request = URLRequest(url: url)

    let task = client.dataTask(with: request) { (data, response, error) in
      if let error = error {
        print("RNAppPushUpdate", "❌ Error in downloading the bundle: \(error.localizedDescription)")
        return
      }

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        print("RNAppPushUpdate", "❌ Error in downloading the bundle, unexpected response")
        return
      }

      guard let data = data else {
        print("RNAppPushUpdate", "❌ Received empty or corrupted file, does the bundle exist on the server?")
        return
      }

      do {
        let fileManager = FileManager.default
        let bundleURL = self.getLibraryDirectory().appendingPathComponent("Application Support")
        let destinationURL = bundleURL.appendingPathComponent("index.ios.bundle")

        try data.write(to: destinationURL)

        let defaults = UserDefaults.standard
        defaults.set(bundleId, forKey: "rn_app_push_update_shared_prefs_bundle_id")
        defaults.set(versionCode, forKey: "rn_app_push_update_shared_prefs_version_code")

        print("RNAppPushUpdate", "✅ File downloaded to \(destinationURL.path)")
        self.showUpdateHeader()
      } catch {
        print("RNAppPushUpdate", "❌ Error in saving the downloaded bundle: \(error.localizedDescription)")
        let dirPath = self.getLibraryDirectory().appendingPathComponent("Application Support")
        if FileManager.default.fileExists(atPath: dirPath.path) {
          let bundle = dirPath.appendingPathComponent("index.ios.bundle")
          if FileManager.default.fileExists(atPath: bundle.path) {
            do {
              try FileManager.default.removeItem(at: bundle)
              UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_bundle_id")
              UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_version_code")
            } catch {}
          }
        }
      }
    }

    task.resume()
  }

  private func getLibraryDirectory() -> URL {
    return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
  }
  
  private func showUpdateHeader() {
    DispatchQueue.main.async {
      guard let window = self.getActiveWindow() else { return }
      guard let rootView = window.rootViewController?.view else { return }
      
      let headerView = UIButton()
      headerView.translatesAutoresizingMaskIntoConstraints = false
      headerView.backgroundColor = UIColor(red: 0.98, green: 0.75, blue: 0, alpha: 1)
      headerView.addAction(UIAction { _ in
        self.onUpdatePressed()
      }, for: .touchUpInside)
      
      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.text = "A new update is available"
      label.textColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
      label.textAlignment = .left
      label.font = UIFont.boldSystemFont(ofSize: 14)
      headerView.addSubview(label)
      
      let button = UIButton()
      button.translatesAutoresizingMaskIntoConstraints = false
      button.addAction(UIAction { _ in
        self.onUpdatePressed()
      }, for: .touchUpInside)
      headerView.addSubview(button)
      
      let btnLabel = UILabel()
      btnLabel.translatesAutoresizingMaskIntoConstraints = false
      btnLabel.font = UIFont.boldSystemFont(ofSize: 14)
      btnLabel.text = "Update"
      btnLabel.textColor = UIColor.blue
      button.addSubview(btnLabel)
      
      rootView.addSubview(headerView)
      
      NSLayoutConstraint.activate([
        headerView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
        headerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
        headerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        headerView.heightAnchor.constraint(equalToConstant: 60),
        label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 15),
        label.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        btnLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        btnLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -15),
        button.topAnchor.constraint(equalTo: headerView.topAnchor),
        button.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        button.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        button.leadingAnchor.constraint(equalTo: btnLabel.leadingAnchor, constant: -15),
      ])
    }
  }
  
  private func onUpdatePressed() {
    guard let window = getActiveWindow() else { return }

    let fileManager = FileManager.default
    let bundleDirectory = getLibraryDirectory().appendingPathComponent("Application Support")
    if !fileManager.fileExists(atPath: bundleDirectory.path) {
      return
    }
    let bundleFile = bundleDirectory.appendingPathComponent("index.ios.bundle")
    if !fileManager.fileExists(atPath: bundleFile.path) {
      return
    }
    
    let jsBundlePath = bundleFile.path
    bridge = RCTBridge(bundleURL: URL(fileURLWithPath: jsBundlePath), moduleProvider: nil, launchOptions: nil)
    let moduleName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? ""
    let rootView = RCTRootView(bridge: bridge!, moduleName: moduleName, initialProperties: nil)

    window.rootViewController = UIViewController()
    window.rootViewController?.view = rootView
    window.makeKeyAndVisible()
  }
  
  func getActiveWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .filter { $0.activationState == .foregroundActive }
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first
  }
}
