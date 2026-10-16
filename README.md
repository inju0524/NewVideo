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
