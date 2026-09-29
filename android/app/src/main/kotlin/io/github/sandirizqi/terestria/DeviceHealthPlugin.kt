package io.github.sandirizqi.terestria

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Device health info for field readiness checks.
 *
 * Channel: io.github.sandirizqi.terestria/device_health
 * Methods:
 *   getFreeDiskBytes() → Long
 *   isIgnoringBatteryOptimizations() → Boolean
 *   openBatteryOptimizationSettings() → Boolean (true = battery list opened,
 *     false = fell back to the app details page)
 *   getManufacturer() → String
 *
 * No extra permission is needed: the battery settings screen is opened with
 * ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS (not the restricted
 * REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog).
 */
class DeviceHealthPlugin(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "io.github.sandirizqi.terestria/device_health"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "getFreeDiskBytes" -> {
                    val stat = StatFs(context.filesDir.absolutePath)
                    result.success(stat.availableBytes)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
                }
                "openBatteryOptimizationSettings" -> {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        // Some OEM builds hide this screen → app details page.
                        val details = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", context.packageName, null)
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(details)
                        result.success(false)
                    }
                }
                "getManufacturer" -> result.success(Build.MANUFACTURER)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DEVICE_HEALTH_ERROR", e.message, null)
        }
    }
}
