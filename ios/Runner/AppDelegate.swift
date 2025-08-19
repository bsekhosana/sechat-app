import UIKit
import Flutter
import CryptoKit
import CommonCrypto

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("📱 iOS: Application did finish launching")
    print("📱 iOS: Launch options: \(launchOptions ?? [:])")
    
    GeneratedPluginRegistrant.register(with: self)
    print("📱 iOS: Generated plugin registrant registered")
    
    // SessionApi implementation removed - using SeSessionService instead
    print("📱 iOS: SessionApi implementation removed - using SeSessionService")
    
    // Session Protocol method channel removed - using SeSessionService instead
    
    // Get the Flutter view controller for method channels
    let controller = window?.rootViewController as! FlutterViewController
    
    print("📱 iOS: App setup completed - socket-based communication only")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - Session Protocol Implementation (Removed - using SeSessionService)
  
  // Session Protocol methods removed - now handled by SeSessionService in Flutter
  
  // MARK: - App Lifecycle
  
  override func applicationWillResignActive(_ application: UIApplication) {
    print("📱 iOS: Application will resign active")
    super.applicationWillResignActive(application)
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    print("📱 iOS: Application did enter background")
    super.applicationDidEnterBackground(application)
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    print("📱 iOS: Application will enter foreground")
    super.applicationWillEnterForeground(application)
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    print("📱 iOS: Application did become active")
    super.applicationDidBecomeActive(application)
  }
  
  override func applicationWillTerminate(_ application: UIApplication) {
    print("📱 iOS: Application will terminate")
    super.applicationWillTerminate(application)
  }
  
  // MARK: - URL Handling
  
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    print("📱 iOS: Handling URL: \(url)")
    
    // Handle custom URL schemes if needed
    if url.scheme == "sechat" {
      print("📱 iOS: Handling SeChat URL scheme")
      // URL handling logic can be added here if needed
      return true
    }
    
    return super.application(app, open: url, options: options)
  }
  
  // MARK: - Memory Warning
  
  override func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    print("📱 iOS: Application did receive memory warning")
    super.applicationDidReceiveMemoryWarning(application)
  }
}
