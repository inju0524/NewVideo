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

private final class NativeDockContainerView: UIView {
  var onLayout: ((CGRect) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?(bounds)
  }
}

final class NativeGlassDockPlugin: NSObject, FlutterPlugin {
  private weak var dockView: NativeGlassDockView?

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
  private let container: NativeDockContainerView
  private let tabBar: UITabBar
  private let chibiView: UIImageView
  private let onSelect: (Int) -> Void
  private var chibiSpacerItem: UITabBarItem?
  private var appItems: [UITabBarItem] = []
  private var isMitsuri = false

  init(
    frame: CGRect,
    arguments: [String: Any],
    onSelect: @escaping (Int) -> Void
  ) {
    container = NativeDockContainerView(frame: frame)
    tabBar = UITabBar(frame: CGRect(x: 0, y: 0, width: frame.width, height: 68))
    self.onSelect = onSelect
    chibiView = UIImageView(image: UIImage(named: "MitsuriDockChibi"))
    super.init()

    container.backgroundColor = .clear
    container.clipsToBounds = false
    tabBar.delegate = self
    tabBar.overrideUserInterfaceStyle = .dark
    tabBar.autoresizingMask = [.flexibleWidth]
    tabBar.isTranslucent = true
    chibiView.contentMode = .scaleAspectFit
    chibiView.isUserInteractionEnabled = false
    chibiView.accessibilityElementsHidden = true
    chibiView.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
    let sourceImage = UIImage(systemName: "point.3.connected.trianglepath.dotted")
      ?? UIImage(systemName: "network")
    appItems = [
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
    let spacerItem = UITabBarItem(title: "", image: nil, selectedImage: nil)
    spacerItem.isEnabled = false
    chibiSpacerItem = spacerItem
    tabBar.items = [spacerItem] + appItems
    applyTheme(arguments: arguments)
    container.addSubview(tabBar)
    container.addSubview(chibiView)
    container.onLayout = { [weak self] bounds in
      self?.updateLayout(in: bounds)
    }
  }

  deinit {
    tabBar.delegate = nil
  }

  func view() -> UIView {
    container
  }

  func select(index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    let nativeIndex = index + (isMitsuri ? 1 : 0)
    guard items.indices.contains(nativeIndex) else { return }
    tabBar.selectedItem = items[nativeIndex]
  }

  func applyTheme(arguments: [String: Any]) {
    isMitsuri = arguments["isMitsuri"] as? Bool ?? false
    let primaryValue = (arguments["primary"] as? NSNumber)?.uint32Value
    let mutedValue = (arguments["muted"] as? NSNumber)?.uint32Value
    tabBar.tintColor = primaryValue.map { UIColor(argb: $0) }
      ?? UIColor(argb: 0xFFE9B66E)
    tabBar.unselectedItemTintColor = mutedValue.map { UIColor(argb: $0) }
      ?? .secondaryLabel
    let spacerItems = isMitsuri ? [chibiSpacerItem].compactMap { $0 } : []
    tabBar.items = spacerItems + appItems
    if let selectedIndex = arguments["selectedIndex"] as? Int {
      select(index: selectedIndex)
    }
    chibiView.isHidden = !isMitsuri
    updateLayout(in: container.bounds)

    if #available(iOS 26.0, *) {
      // Keep UIKit's native Liquid Glass appearance.
    } else {
      let appearance = UITabBarAppearance()
      appearance.configureWithDefaultBackground()
      if isMitsuri {
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
      }
      tabBar.standardAppearance = appearance
      tabBar.scrollEdgeAppearance = appearance
    }
  }

  private func updateLayout(in bounds: CGRect) {
    let topInset: CGFloat = isMitsuri ? 28 : 0
    let measuredHeight = tabBar.sizeThatFits(
      CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
    ).height
    let barHeight = max(68, measuredHeight)
    tabBar.frame = CGRect(
      x: 0,
      y: topInset,
      width: bounds.width,
      height: barHeight
    )
    let characterWidth = isMitsuri ? min(62, bounds.width * 0.17) : 0
    let itemCount = max(1, tabBar.items?.count ?? 1)
    let spacerCenter = bounds.width / CGFloat(itemCount) / 2
    chibiView.frame = CGRect(
      x: isMitsuri ? spacerCenter - characterWidth / 2 : 0,
      y: 0,
      width: characterWidth,
      height: isMitsuri ? topInset + barHeight : 0
    )
  }

  func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool {
    guard isMitsuri, let spacer = chibiSpacerItem, item === spacer else {
      return true
    }
    return false
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let nativeIndex = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
    let appIndex = nativeIndex - (isMitsuri ? 1 : 0)
    guard appItems.indices.contains(appIndex) else { return }
    onSelect(appIndex)
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
