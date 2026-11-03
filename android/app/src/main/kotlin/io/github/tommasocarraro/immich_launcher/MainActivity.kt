package io.github.tommasocarraro.immich_launcher

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native helpers exposed to Dart over the "immich_launcher/platform" channel:
 * VPN detection and launching other apps / URLs.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "immich_launcher/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isVpnActive" -> result.success(isVpnActive())
                        "isAppInstalled" ->
                            result.success(isAppInstalled(call.argument<String>("package")!!))
                        "launchApp" ->
                            result.success(launchApp(call.argument<String>("package")!!))
                        "openUrlWithApp" -> result.success(
                            openUrl(call.argument<String>("url")!!, call.argument<String>("package"))
                        )
                        "openUrl" -> result.success(openUrl(call.argument<String>("url")!!, null))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("PLATFORM_ERROR", e.message, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun isVpnActive(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }

    private fun isAppInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun launchApp(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun openUrl(url: String, pkg: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (pkg != null) setPackage(pkg)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
