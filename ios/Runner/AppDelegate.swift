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
  var onWindowChange: ((Bool) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?(bounds)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onWindowChange?(window != nil)
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

private final class NativeGlassDockView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private let container: NativeDockContainerView
  private let dockController: UITabBarController
  private let tabBar: UITabBar
  private let chibiView: UIImageView
  private let onSelect: (Int) -> Void
  private var defaultStandardAppearance: UITabBarAppearance!
  private var defaultScrollEdgeAppearance: UITabBarAppearance?
  private var appItems: [UITabBarItem] = []
  private var spacerController: UIViewController?
  private var appControllers: [UIViewController] = []
  private var isMitsuri = false
  private var isLight = false
  private var isApplyingSelection = false

  init(
    frame: CGRect,
    arguments: [String: Any],
    onSelect: @escaping (Int) -> Void
  ) {
    container = NativeDockContainerView(frame: frame)
    dockController = UITabBarController()
    tabBar = dockController.tabBar
    self.onSelect = onSelect
    chibiView = UIImageView(image: UIImage(named: "MitsuriDockChibi"))
    super.init()

    container.backgroundColor = .clear
    container.clipsToBounds = false
    dockController.delegate = self
    dockController.view.backgroundColor = .clear
    dockController.view.clipsToBounds = false
    tabBar.overrideUserInterfaceStyle = .dark
    tabBar.isTranslucent = true
    defaultStandardAppearance = tabBar.standardAppearance.copy() as? UITabBarAppearance
    defaultScrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy() as? UITabBarAppearance
    chibiView.contentMode = .scaleAspectFit
    chibiView.isUserInteractionEnabled = false
    chibiView.accessibilityElementsHidden = true
    chibiView.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
    let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
    let sourceImage = UIImage(systemName: "point.3.connected.trianglepath.dotted", withConfiguration: symbolConfiguration)
      ?? UIImage(systemName: "network", withConfiguration: symbolConfiguration)
    appItems = [
      UITabBarItem(
        title: "首页",
        image: UIImage(systemName: "house", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate),
        selectedImage: UIImage(systemName: "house.fill", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate)
      ),
      UITabBarItem(
        title: "分类",
        image: UIImage(systemName: "square.grid.2x2", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate),
        selectedImage: UIImage(systemName: "square.grid.2x2.fill", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate)
      ),
      UITabBarItem(
        title: "片源",
        image: sourceImage?.withRenderingMode(.alwaysTemplate),
        selectedImage: sourceImage?.withRenderingMode(.alwaysTemplate)
      ),
      UITabBarItem(
        title: "我的",
        image: UIImage(systemName: "person", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate),
        selectedImage: UIImage(systemName: "person.fill", withConfiguration: symbolConfiguration)?
          .withRenderingMode(.alwaysTemplate)
      ),
    ]
    let spacerItem = UITabBarItem(title: " ", image: nil, selectedImage: nil)
    spacerItem.isEnabled = false
    spacerItem.accessibilityLabel = ""
    let spacer = UIViewController()
    spacer.tabBarItem = spacerItem
    spacer.view.backgroundColor = .clear
    spacerController = spacer
    appControllers = appItems.map { item in
      let controller = UIViewController()
      controller.tabBarItem = item
      controller.view.backgroundColor = .clear
      return controller
    }
    dockController.setViewControllers(appControllers, animated: false)
    applyTheme(arguments: arguments)
    container.onLayout = { [weak self] bounds in
      guard let self else { return }
      if self.dockController.parent == nil {
        self.attachDockController()
      } else {
        self.updateLayout(in: bounds)
      }
    }
    container.onWindowChange = { [weak self] isAttached in
      if isAttached {
        self?.attachDockController()
      } else {
        self?.detachDockController()
      }
    }
  }

  deinit {
    dockController.delegate = nil
    detachDockController()
  }

  func view() -> UIView {
    container
  }

  func select(index: Int) {
    guard appControllers.indices.contains(index) else { return }
    isApplyingSelection = true
    dockController.selectedViewController = appControllers[index]
    isApplyingSelection = false
  }

  func applyTheme(arguments: [String: Any]) {
    isMitsuri = arguments["isMitsuri"] as? Bool ?? false
    isLight = arguments["isLight"] as? Bool ?? false
    let primaryValue = (arguments["primary"] as? NSNumber)?.uint32Value
    let mutedValue = (arguments["muted"] as? NSNumber)?.uint32Value
    tabBar.tintColor = primaryValue.map { UIColor(argb: $0) }
      ?? UIColor(argb: 0xFFE9B66E)
    tabBar.unselectedItemTintColor = mutedValue.map { UIColor(argb: $0) }
      ?? .secondaryLabel
    let selectedColor = tabBar.tintColor ?? .label
    let unselectedColor = tabBar.unselectedItemTintColor ?? .secondaryLabel
    tabBar.overrideUserInterfaceStyle = isLight ? .light : .dark
    let mitsuriControllers = [spacerController].compactMap { $0 } + appControllers
    let controllers = isMitsuri ? mitsuriControllers : appControllers
    dockController.setViewControllers(controllers, animated: false)
    tabBar.itemPositioning = isMitsuri ? .fill : .automatic
    if #available(iOS 26.0, *) {
      dockController.tabBarMinimizeBehavior = .never
    }
    if let selectedIndex = arguments["selectedIndex"] as? Int {
      select(index: selectedIndex)
    }
    chibiView.isHidden = !isMitsuri
    updateLayout(in: container.bounds)

    if isMitsuri || isLight {
      let appearance: UITabBarAppearance
      if #available(iOS 26.0, *) {
        // Keep the native Liquid Glass background and customize only item content.
        appearance = tabBar.standardAppearance.copy() as! UITabBarAppearance
      } else {
        appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(
          style: isLight ? .systemMaterial : .systemChromeMaterial
        )
      }
      configureItemAppearance(
        appearance,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor
      )
      tabBar.standardAppearance = appearance
      tabBar.scrollEdgeAppearance = appearance
    } else {
      tabBar.standardAppearance = defaultStandardAppearance.copy() as! UITabBarAppearance
      tabBar.scrollEdgeAppearance = defaultScrollEdgeAppearance?.copy() as? UITabBarAppearance
    }
    attachDockController()
    updateLayout(in: container.bounds)
  }

  private func updateLayout(in bounds: CGRect) {
    dockController.view.frame = CGRect(
      x: 0,
      y: 0,
      width: bounds.width,
      height: bounds.height
    )
    dockController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    dockController.view.layoutIfNeeded()
    tabBar.setNeedsLayout()
    tabBar.layoutIfNeeded()
    let characterSize = characterFrame(in: bounds)
    chibiView.frame = CGRect(
      x: characterSize.minX,
      y: characterSize.minY,
      width: characterSize.width,
      height: characterSize.height
    )
    if chibiView.superview !== dockController.view {
      chibiView.removeFromSuperview()
      dockController.view.addSubview(chibiView)
    } else {
      dockController.view.bringSubviewToFront(chibiView)
    }
  }

  private func characterFrame(in bounds: CGRect) -> CGRect {
    guard isMitsuri else { return .zero }

    let characterHeight = min(104, bounds.height)
    let imageAspectRatio = chibiView.image.map { $0.size.width / max($0.size.height, 1) } ?? 0.75
    let characterWidth = min(72, characterHeight * imageAspectRatio)
    let spacerButton = tabBarButtons(in: tabBar).first
    let itemCount = CGFloat(max(tabBar.items?.count ?? 5, 1))
    let itemArea = tabBar.safeAreaLayoutGuide.layoutFrame
    let estimatedCapsuleWidth = min(
      itemArea.width,
      max(320, itemCount * 72)
    )
    let fallbackCenterX = itemArea.midX - estimatedCapsuleWidth * (itemCount - 1) / (2 * itemCount)
    let spacerCenterX = spacerButton.map { button in
      button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: dockController.view).x
    } ?? tabBar.convert(CGPoint(x: fallbackCenterX, y: tabBar.bounds.midY), to: dockController.view).x
    let barBottom = tabBar.convert(CGPoint(x: 0, y: tabBar.bounds.maxY), to: dockController.view).y
    let characterY = max(0, barBottom - characterHeight)
    return CGRect(
      x: spacerCenterX - characterWidth / 2,
      y: characterY,
      width: characterWidth,
      height: characterHeight
    )
  }

  private func tabBarButtons(in view: UIView) -> [UIView] {
    var buttons: [UIView] = []
    for subview in view.subviews {
      if String(describing: type(of: subview)).contains("UITabBarButton") {
        buttons.append(subview)
      } else {
        buttons.append(contentsOf: tabBarButtons(in: subview))
      }
    }
    return buttons.sorted {
      $0.convert($0.bounds, to: tabBar).minX < $1.convert($1.bounds, to: tabBar).minX
    }
  }

  private func attachDockController() {
    guard dockController.parent == nil,
          let parent = containingViewController() else { return }
    parent.addChild(dockController)
    container.addSubview(dockController.view)
    dockController.didMove(toParent: parent)
    dockController.view.addSubview(chibiView)
    updateLayout(in: container.bounds)
  }

  private func detachDockController() {
    guard dockController.parent != nil else { return }
    dockController.willMove(toParent: nil)
    dockController.view.removeFromSuperview()
    dockController.removeFromParent()
  }

  private func containingViewController() -> UIViewController? {
    var responder: UIResponder? = container
    while let current = responder {
      if let controller = current as? UIViewController {
        return controller
      }
      responder = current.next
    }
    return nil
  }

  private func configureItemAppearance(
    _ appearance: UITabBarAppearance,
    selectedColor: UIColor,
    unselectedColor: UIColor
  ) {
    appearance.stackedItemPositioning = .centered
    appearance.stackedItemWidth = 0
    appearance.stackedItemSpacing = 8
    let layouts = [
      appearance.stackedLayoutAppearance,
      appearance.inlineLayoutAppearance,
      appearance.compactInlineLayoutAppearance,
    ]
    let font = UIFont.systemFont(ofSize: 11, weight: .medium)
    for layout in layouts {
      layout.normal.iconColor = unselectedColor
      layout.normal.titleTextAttributes = [
        .foregroundColor: unselectedColor,
        .font: font,
      ]
      layout.selected.iconColor = selectedColor
      layout.selected.titleTextAttributes = [
        .foregroundColor: selectedColor,
        .font: font,
      ]
    }
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    shouldSelect viewController: UIViewController
  ) -> Bool {
    guard isMitsuri, let spacer = spacerController, viewController === spacer else {
      return true
    }
    return false
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard !isApplyingSelection else { return }
    guard let appIndex = appControllers.firstIndex(where: { $0 === viewController }) else {
      return
    }
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
