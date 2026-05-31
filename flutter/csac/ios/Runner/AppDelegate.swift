import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundRefreshChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      backgroundRefreshChannel = FlutterMethodChannel(
        name: "ink.jjmm.csacflutter/background_refresh",
        binaryMessenger: controller.binaryMessenger
      )
    }
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard let backgroundRefreshChannel = backgroundRefreshChannel else {
      completionHandler(.failed)
      return
    }
    backgroundRefreshChannel.invokeMethod("performBackgroundFetch", arguments: nil) { result in
      if let hasNewData = result as? Bool {
        completionHandler(hasNewData ? .newData : .noData)
      } else {
        completionHandler(.failed)
      }
    }
  }
}
