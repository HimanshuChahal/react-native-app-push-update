require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

min_ios_version_supported = "12.0"

Pod::Spec.new do |s|
  s.name         = "RNAppPushUpdate"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/HimanshuChahal/react-native-app-push-update.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,cpp,swift}"

  s.resource_bundles = {
    'RNAppPushUpdate' => ['ios/RNAppPushUpdateInfo.plist']
  }

  s.requires_arc = true
  s.swift_version = '5.0'

  s.dependency "React-Core"

  install_modules_dependencies(s)
end
