import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let iconRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppIconPlugin") {
      AppIconPlugin.register(with: iconRegistrar)
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeGlassDockPlugin") else {
      return
    }
    NativeGlassDockPlugin.register(with: registrar)
  }
}

private final class AppIconPlugin: NSObject, FlutterPlugin {
  private static let shared = AppIconPlugin()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zhuying/app-icon",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setLauncherIcon" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    guard let useMitsuri = arguments?["isMitsuri"] as? Bool else {
      result(FlutterError(code: "invalid_arguments", message: "Expected theme arguments", details: nil))
      return
    }
    UIApplication.shared.setAlternateIconName(useMitsuri ? "MitsuriIcon" : nil) { error in
      if let error {
        result(FlutterError(code: "icon_update_failed", message: error.localizedDescription, details: nil))
      } else {
        result(nil)
      }
    }
  }
}

private let dockViewType = "zhuying/native-glass-dock"
private let dockChannelName = "zhuying/native-dock"

final class NativeGlassDockPlugin: NSObject, FlutterPlugin {
  private var dockView: NativeGlassDockView?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeGlassDockPlugin()
    let channel = FlutterMethodChannel(
      name: dockChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      NativeGlassDockFactory(
        onCreate: { instance.dockView = $0 },
        onSelect: { index in channel.invokeMethod("selected", arguments: index) }
      ),
      withId: dockViewType
    )
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "select":
      guard let index = call.arguments as? Int else {
        result(FlutterError(code: "invalid_arguments", message: "Expected tab index", details: nil))
        return
      }
      dockView?.select(index: index)
      result(nil)
    case "theme":
      guard let values = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected theme colors", details: nil))
        return
      }
      dockView?.applyTheme(arguments: values)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class NativeGlassDockFactory: NSObject, FlutterPlatformViewFactory {
  private let onCreate: (NativeGlassDockView) -> Void
  private let onSelect: (Int) -> Void

  init(
    onCreate: @escaping (NativeGlassDockView) -> Void,
    onSelect: @escaping (Int) -> Void
  ) {
    self.onCreate = onCreate
    self.onSelect = onSelect
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let view = NativeGlassDockView(
      frame: frame,
      arguments: args as? [String: Any] ?? [:],
      onSelect: onSelect
    )
    onCreate(view)
    return view
  }
}

private final class NativeGlassDockView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar: UITabBar
  private let onSelect: (Int) -> Void

  init(
    frame: CGRect,
    arguments: [String: Any],
    onSelect: @escaping (Int) -> Void
  ) {
    container = UIView(frame: frame)
    tabBar = UITabBar(frame: CGRect(x: 0, y: 0, width: frame.width, height: 58))
    self.onSelect = onSelect
    let bottomInset = CGFloat(
      (arguments["bottomInset"] as? NSNumber)?.doubleValue ?? 0
    )
    super.init()

    container.backgroundColor = .clear
    container.clipsToBounds = false
    tabBar.delegate = self
    tabBar.overrideUserInterfaceStyle = .dark
    tabBar.autoresizingMask = [.flexibleWidth]
    tabBar.tintColor = UIColor(red: 0.91, green: 0.69, blue: 0.35, alpha: 1)
    tabBar.unselectedItemTintColor = .secondaryLabel
    let sourceImage = UIImage(systemName: "point.3.connected.trianglepath.dotted")
      ?? UIImage(systemName: "network")
    tabBar.items = [
      UITabBarItem(
        title: "首页",
        image: UIImage(systemName: "house"),
        selectedImage: UIImage(systemName: "house.fill")
      ),
      UITabBarItem(
        title: "分类",
        image: UIImage(systemName: "square.grid.2x2"),
        selectedImage: UIImage(systemName: "square.grid.2x2.fill")
      ),
      UITabBarItem(title: "片源", image: sourceImage, selectedImage: sourceImage),
      UITabBarItem(
        title: "我的",
        image: UIImage(systemName: "person"),
        selectedImage: UIImage(systemName: "person.fill")
      ),
    ]
    applyTheme(arguments: arguments)
    container.addSubview(tabBar)
    if bottomInset > 0 {
      let footer = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      footer.frame = CGRect(x: 0, y: 58, width: frame.width, height: bottomInset)
      footer.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
      container.insertSubview(footer, belowSubview: tabBar)
    }

    if let selectedIndex = arguments["selectedIndex"] as? Int {
      select(index: selectedIndex)
    }
  }

  func view() -> UIView {
    container
  }

  func select(index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  func applyTheme(arguments: [String: Any]) {
    if let primary = arguments["primary"] as? NSNumber {
      tabBar.tintColor = UIColor(argb: primary.uint32Value)
    }
    if let surface = arguments["surface"] as? NSNumber {
      tabBar.backgroundColor = UIColor(argb: surface.uint32Value).withAlphaComponent(0.94)
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
    onSelect(index)
  }
}

private extension UIColor {
  convenience init(argb: UInt32) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
