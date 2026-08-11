package io.nekobox.nekobox_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.io.File

/**
 * 开机自启:系统启动完成后,若设置了自动连接(isAutoConnect),
 * 直接拉起前台服务连接上次使用的配置——无需打开 App。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        if (!SettingsHelper.get(context, "isAutoConnect", false)) {
            Log.d("BootReceiver", "isAutoConnect 未开启,跳过开机自启")
            return
        }
        val last = File(context.filesDir, "singbox-last-config.json")
        if (!last.exists()) {
            Log.d("BootReceiver", "无上次运行配置,跳过")
            return
        }
        try {
            val obj = org.json.JSONObject(last.readText())
            val config = obj.optString("config", "")
            val port = obj.optInt("port", 2080)
            if (config.isEmpty()) return
            val svc = Intent(context, SingBoxService::class.java).apply {
                this.action = SingBoxService.ACTION_BOOT
                putExtra(SingBoxService.EXTRA_CONFIG, config)
                putExtra(SingBoxService.EXTRA_PORT, port)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svc)
            } else {
                context.startService(svc)
            }
            Log.i("BootReceiver", "开机自动连接已启动: $config")
        } catch (e: Exception) {
            Log.e("BootReceiver", "开机自启失败: $e")
        }
    }
}
