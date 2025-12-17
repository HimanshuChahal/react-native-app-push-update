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
      let bundleDirectory = getLibraryDirectory()
      if !fileManager.fileExists(atPath: bundleDirectory.path) {
        do {
          try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
          print("RNAppPushUpdate", "❌ Error creating directory: \(error.localizedDescription)")
        }
      }
      let bundleFile = bundleDirectory.appendingPathComponent("index.ios.bundle")
      if FileManager.default.fileExists(atPath: bundleFile.path) {
        var fileSize = 0
        do {
          let resourceValue = try bundleFile.resourceValues(forKeys: [.fileSizeKey])
          fileSize = resourceValue.fileSize ?? 0
        } catch {}
        if fileSize < 50_000 {}
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
            UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_patch_id")
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
    let bundleDirectory = getLibraryDirectory()
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
            let bundleId = json["bundle_id"] as? Int ?? -1
            let bundleUrl = json["bundle_url"] as? String
            let patchId = json["patch_id"] as? Int ?? -1
            let patchUrl = json["patch_url"] as? String ?? ""
            if let downloadUrl = bundleUrl, !downloadUrl.isEmpty {
              let defaults = UserDefaults.standard
              let downloadedBundleId = defaults.integer(forKey: "rn_app_push_update_shared_prefs_bundle_id")
              let downloadedPatchId = defaults.integer(forKey:
                  "rn_app_push_update_shared_prefs_patch_id")
              
              if downloadedBundleId != bundleId {
                self.downloadBundleFromServer(urlStr: downloadUrl, bundleId: bundleId, patchUrl: patchUrl, patchId: patchId, versionCode: versionCode)
              } else if !patchUrl.isEmpty && downloadedPatchId != patchId {
                self.downloadPatchFromServer(patchUrl: patchUrl, patchId: patchId)
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

  private func downloadBundleFromServer(urlStr: String, bundleId: Int, patchUrl: String, patchId: Int, versionCode: String) {
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
        let bundleURL = self.getLibraryDirectory()
        let destinationURL = bundleURL.appendingPathComponent("index.ios.bundle")

        try data.write(to: destinationURL)

        let defaults = UserDefaults.standard
        defaults.set(bundleId, forKey: "rn_app_push_update_shared_prefs_bundle_id")
        defaults.set(versionCode, forKey: "rn_app_push_update_shared_prefs_version_code")

        print("RNAppPushUpdate", "✅ File downloaded to \(destinationURL.path)")
        if !patchUrl.isEmpty && patchId > 0 {
          self.downloadPatchFromServer(patchUrl: patchUrl, patchId: patchId)
        } else {
          self.showUpdateHeader()
        }
      } catch {
        print("RNAppPushUpdate", "❌ Error in saving the downloaded bundle: \(error.localizedDescription)")
        let dirPath = self.getLibraryDirectory()
        if FileManager.default.fileExists(atPath: dirPath.path) {
          let bundle = dirPath.appendingPathComponent("index.ios.bundle")
          if FileManager.default.fileExists(atPath: bundle.path) {
            do {
              try FileManager.default.removeItem(at: bundle)
              UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_bundle_id")
              UserDefaults.standard.removeObject(forKey:
                  "rn_app_push_update_shared_prefs_patch_id")
              UserDefaults.standard.removeObject(forKey: "rn_app_push_update_shared_prefs_version_code")
            } catch {}
          }
        }
      }
    }

    task.resume()
  }

  private func downloadPatchFromServer(patchUrl: String, patchId: Int) {
    guard let url = URL(string: patchUrl), patchUrl.range(of: "^[a-zA-Z0-9-]+://", options: .regularExpression) != nil else {
      print("RNAppPushUpdate", "❌ Invalid patch download URL")
      return
    }
    
    let client = URLSession.shared
    let request = URLRequest(url: url)
    
    client.dataTask(with: request) { (data, response, error) in
      if let error = error {
        print("RNAppPushUpdate", "❌ Error in downloading the patch: \(error.localizedDescription)")
        return
      }

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        print("RNAppPushUpdate", "❌ Error in downloading the patch, unexpected response")
        return
      }

      guard let data = data else {
        print("RNAppPushUpdate", "❌ Received empty or corrupted patch file, does the patch exist on the server?")
        return
      }
      
      do {
        let bundleURL = self.getLibraryDirectory()
        let destinationURL = bundleURL.appendingPathComponent("bundle.patch")
        
        try data.write(to: destinationURL)
        
        defer {
          do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
              try FileManager.default.removeItem(at: destinationURL)
            }
          } catch {
            print("RNAppPushUpdate", "Could not delete the patch file, error: \(error.localizedDescription)")
          }
        }

        let defaults = UserDefaults.standard
        defaults.set(patchId, forKey: "rn_app_push_update_shared_prefs_patch_id")
        
        let oldPath = bundleURL.appendingPathComponent("index.android.bundle")
        let patchPath = bundleURL.appendingPathComponent("bundle.patch")
        let outputPath = bundleURL.appendingPathComponent("new_index.android.bundle")
        
        let patchResult = 0
        if patchResult == 0 {
          if FileManager.default.fileExists(atPath: oldPath.path) {
              try FileManager.default.removeItem(at: oldPath)
          }
          try FileManager.default.moveItem(at: outputPath, to: oldPath)
          self.showUpdateHeader()
        } else {
          throw NSError(domain: "RNAppPushUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apply patch failed"])
        }
      } catch {
        print("RNAppPushUpdate", "❌ Error in parsing the patch downloaded from the server")
        print(error.localizedDescription)
        let bundleURL = self.getLibraryDirectory()
        let patchPath = bundleURL.appendingPathComponent("bundle.patch")
        do {
          if FileManager.default.fileExists(atPath: patchPath.path) {
            try FileManager.default.removeItem(at: patchPath)
            UserDefaults.standard.removeObject(forKey:
                "rn_app_push_update_shared_prefs_patch_id")
          }
        } catch {
          print("RNAppPushUpdate", "Could not delete the patch file, error: \(error.localizedDescription)")
        }
      }
    }.resume()
  }

  private func getLibraryDirectory() -> URL {
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    let bundleDirectory = getLibraryDirectory()
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
