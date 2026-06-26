import Foundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeModelsFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func excludeModelsFromBackup() {
    guard let applicationSupportFolder = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return
    }
    var modelsFolder = applicationSupportFolder.appendingPathComponent("models", isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try modelsFolder.setResourceValues(values)
    } catch {
      NSLog("Failed to prepare models folder: \(error.localizedDescription)")
    }
  }
}