package io.github.tommasocarraro.immich_launcher

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
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
    private val briefLaunchRequestCode = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isVpnActive" -> result.success(isVpnActive())
                        "isAppInstalled" ->
                            result.success(isAppInstalled(call.argument<String>("package")!!))
                        "isAppStopped" ->
                            result.success(isAppStopped(call.argument<String>("package")!!))
                        "launchApp" ->
                            result.success(launchApp(call.argument<String>("package")!!))
                        "launchAppBriefly" ->
                            result.success(launchAppBriefly(call.argument<String>("package")!!))
                        "closeBriefApp" -> result.success(closeBriefApp())
                        "openUrlWithApp" -> result.success(
                            openUrl(call.argument<String>("url")!!, call.argument<String>("package"))
                        )
                        "openUrl" -> result.success(openUrl(call.argument<String>("url")!!, null))
                        "sendBroadcast" -> result.success(
                            sendExplicitBroadcast(
                                call.argument<String>("package")!!,
                                call.argument<String>("receiver")!!,
                                call.argument<String>("action")!!,
                            )
                        )
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

    /**
     * True if [pkg] is in Android's "stopped" state (force-stopped, or killed
     * by an aggressive battery manager). Broadcasts to such apps are dropped
     * until one of their activities is launched again.
     */
    private fun isAppStopped(pkg: String): Boolean = try {
        packageManager.getApplicationInfo(pkg, 0).flags and ApplicationInfo.FLAG_STOPPED != 0
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * Opens [pkg]'s launcher activity on top of ours, in our task, so that
     * [closeBriefApp] can dismiss it again. (Bringing ourselves back with a
     * new activity start would be blocked: by then we are in the background.)
     */
    private fun launchAppBriefly(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.flags = Intent.FLAG_ACTIVITY_NO_ANIMATION
        return try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, briefLaunchRequestCode)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Closes the activity opened by [launchAppBriefly], returning to ours. */
    private fun closeBriefApp(): Boolean {
        finishActivity(briefLaunchRequestCode)
        return true
    }

    private fun launchApp(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    /**
     * Sends [action] to the exported receiver [cls] of [pkg]. Used to tell
     * Tailscale to connect in the background (its IPNReceiver handles
     * com.tailscale.ipn.CONNECT_VPN). Returns false if the receiver is missing.
     */
    private fun sendExplicitBroadcast(pkg: String, cls: String, action: String): Boolean {
        val intent = Intent(action).apply {
            setClassName(pkg, cls)
            addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
        }
        if (packageManager.queryBroadcastReceivers(intent, 0).isEmpty()) return false
        sendBroadcast(intent)
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
