# 烛影

Flutter 影视浏览与播放应用，支持订阅源搜索、分类筛选、播放进度记录及封面缓存。

## Android 构建与安装

需要安装 Flutter、Android SDK 和 JDK 17 或更新版本。连接 Android 设备并启用 USB 调试后：

```powershell
flutter pub get
flutter build apk --release --no-pub `
  --android-project-arg=kotlin.incremental=false `
  --android-project-arg=kotlin.compiler.execution.strategy=in-process
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

APK 输出位置：`build/app/outputs/flutter-apk/app-release.apk`。当前 release 构建使用项目内的 debug 签名，适合本机测试和侧载；正式分发前应配置独立的 release keystore，并妥善保管签名凭据。

Windows 下额外关闭 Kotlin 增量编译，避免项目盘符与 Pub 缓存盘符不同时出现 Kotlin 缓存路径错误。版本号使用 `pubspec.yaml` 中的 `version` 字段；每次发布 Android 更新时递增 `+` 后的 build number，确保设备可识别为新版本。

片源管理内置经列表响应验证的标准苹果 CMS API，新增源默认关闭，可在片源列表按需启用。也可以从仍可读取的公开 TVBox JSON/JSONC 配置仓导入标准 CMS API；仓库中的 JS/JAR 爬虫依赖 TVBox 运行环境，本项目不会执行这些脚本。多仓 `urls` 在有限请求数与配置大小内递归解析。Web 端通过受限 source proxy 读取公开配置，拒绝私网目标与危险重定向。

片库、分类、搜索与首页展示按片名、年份、季数和已知内容类型合并跨源重复记录，播放器仍保留各片源的原始记录用于换线。播放界面默认支持触屏滑动与鼠标拖动预览并调节进度；居中靠右的锁定按钮可临时禁用进度手势和其他播放控件。设置中的“关于”提供作者与 GitHub 仓库链接。

## iOS 构建与真机安装

没有 Mac 时，可使用 GitHub Actions 的 macOS 26 runner（Xcode 26.6 / iOS 26 SDK）。GitHub runner 只构建 GitHub 上已推送的提交，不会读取本机未提交文件；**每次构建前先检查并提交需要发布的本地改动，推送到 `main`，再确认 Actions 运行记录对应最新提交**。推送后会自动构建，也可在 GitHub 仓库 **Actions → iOS package → Run workflow** 手动触发。默认 `unsigned` 模式会运行测试并上传 `zhuying-ios-unsigned.ipa`，适用于检查构建产物；**未签名 IPA 不能安装到 iPhone**。

要安装到已登记的 iPhone，需要 Apple Developer Program、Apple Distribution `.p12` 证书和包含该设备 UDID 的 Ad Hoc provisioning profile。将以下内容添加到仓库 **Settings → Secrets and variables → Actions → Repository secrets**，不要提交证书或私钥到 Git：

- `IOS_CERTIFICATE_P12_BASE64`：`.p12` 文件的 Base64 文本。
- `IOS_CERTIFICATE_PASSWORD`：导出 `.p12` 时设置的密码。
- `IOS_PROVISIONING_PROFILE_BASE64`：Ad Hoc `.mobileprovision` 文件的 Base64 文本。
- `IOS_TEAM_ID`：Apple Developer Team ID。

在 Windows PowerShell 中可用以下命令生成不带换行的 Base64 值，再直接粘贴到对应 GitHub secret；在本机安全存放证书文件，命令不会上传或打印证书内容：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\distribution.p12')) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\profile.mobileprovision')) | Set-Clipboard
```

每次只运行一行：先把剪贴板内容放进对应 secret，再运行下一行。Ad Hoc profile 必须登记目标 iPhone 的 UDID、使用 `app.zhuying.zhuying` App ID，并与该 Apple Distribution 证书属于同一个 Team。

之后手动运行 workflow 并选择 `adhoc`。生成的 `zhuying-ios-adhoc.ipa` 可安装到该 provisioning profile 已登记且未过期的设备；Ad Hoc 安装仍需通过 Apple Devices、Apple Configurator 或其他签名安装工具完成。TestFlight 分发需另行配置 App Store Connect 发布流程。

iOS 底部导航由原生 UIKit `UITabBar` 承载。使用 iOS 26 SDK 时由系统应用 Liquid Glass 外观；较旧系统继续使用系统原生 Tab Bar 外观。导航内容和页面转场仍由 Flutter 管理。

## Web source proxy

The three preset CMS endpoints do not expose browser CORS headers. Android and
iOS request them directly; Flutter Web uses the loopback proxy below:

```powershell
dart run tool/source_proxy.dart --port 8124
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8123
```

The proxy only binds to `127.0.0.1` and does not log source URLs or credentials.

## 开发与测试

```powershell
flutter pub get
flutter analyze
flutter test
```

## Web 预览

Web 端需要本地片源代理处理 CMS 接口的跨域请求。按上方说明先启动代理，再运行 Flutter Web 服务。代理仅绑定本机回环地址，不应暴露到公网。
