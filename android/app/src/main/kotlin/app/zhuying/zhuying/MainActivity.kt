package app.zhuying.zhuying

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zhuying/app-icon")
            .setMethodCallHandler { call, result ->
                if (call.method != "setLauncherIcon") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val arguments = call.arguments as? Map<*, *>
                val useMitsuri = arguments?.get("isMitsuri") as? Boolean
                if (useMitsuri == null) {
                    result.error("invalid_arguments", "Expected theme arguments", null)
                    return@setMethodCallHandler
                }

                val active = if (useMitsuri) "MitsuriLauncher" else "XuanlanLauncher"
                val inactive = if (useMitsuri) "XuanlanLauncher" else "MitsuriLauncher"
                setTitle(if (useMitsuri) "我爱看电视" else "玄览")
                val manager = packageManager
                manager.setComponentEnabledSetting(
                    ComponentName(this, "$packageName.$inactive"),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
                manager.setComponentEnabledSetting(
                    ComponentName(this, "$packageName.$active"),
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP,
                )
                result.success(null)
            }
    }
}
