import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var currentPushToken: String?
  private var waitingRegistration: (() -> Void)?

  private func registration(_ result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .badge]) { _, _ in
      center.getNotificationSettings { settings in
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
          let defaults = UserDefaults.standard
          let installation = defaults.string(forKey: "pushInstallation") ?? UUID().uuidString
          defaults.set(installation, forKey: "pushInstallation")
          var payload: [String: Any] = [
            "installation_id": installation,
            "environment": Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String ?? "sandbox",
            "authorized": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
          ]
          let reply = {
            if let token = self.currentPushToken { payload["token"] = token }
            result(payload)
          }
          if self.currentPushToken != nil {
            reply()
          } else {
            self.waitingRegistration = reply
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
              let pending = self.waitingRegistration
              self.waitingRegistration = nil
              pending?()
            }
          }
        }
      }
    }
  }

  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    currentPushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    let pending = waitingRegistration
    waitingRegistration = nil
    pending?()
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "system_app/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "register": self.registration(result)
      case "reconcile":
        let args = call.arguments as? [String: Any]
        let count = args?["badge"] as? Int ?? 0
        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
          let ids = notifications.filter {
            $0.request.content.userInfo["kind"] as? String == "section_windows"
          }.map { $0.request.identifier }
          center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
