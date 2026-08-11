package io.nekobox.nekobox_android

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 主 Activity。
 *
 * MethodChannel `nekobox/core`:
 *  - getSingBoxPath: 部署 sing-box 到 filesDir 并 chmod,返回可执行路径
 *  - getDataDir: 应用私有数据目录
 *  - startService / stopService / restartService / isServiceRunning:
 *    前台服务托管 sing-box(通知常驻,退后台不断连)
 *  - getPendingImport / clearPendingImport: 深链接导入(浏览器点击 vmess:// 等)
 *  - prepareVpn: VpnService 授权弹窗(Android TUN 后端)
 *  - requestNotificationPermission: Android 13+ 通知权限
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "nekobox/core"
        private const val PREFS = "nekobox_pending"
        private const val KEY_IMPORT = "import"
        private const val VPN_REQUEST = 2001
        private const val NOTIF_REQUEST = 1001
        // 深链接支持的代理协议 scheme
        private val PROXY_SCHEMES = listOf(
            "vmess", "vless", "trojan", "trojan-go", "ss", "shadowsocks",
            "hysteria", "hysteria2", "hy2", "tuic", "socks", "socks5",
            "http", "https", "ssh", "anytls", "shadowtls", "wg", "wireguard",
            "naive+https", "naive", "mieru")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 冷启动深链接
        handleDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST) {
            Log.i("NekoBox",
                if (resultCode == RESULT_OK) "VpnService 授权成功" else "VpnService 授权被拒绝")
        }
    }

    /** 深链接:浏览器点击代理链接 → 存待导入 → 通知 Flutter。 */
    private fun handleDeepLink(intent: Intent?) {
        val data = intent?.dataString ?: return
        val scheme = data.substringBefore("://").lowercase()
        if (scheme !in PROXY_SCHEMES) return
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit().putString(KEY_IMPORT, data).apply()
        Log.i("NekoBox", "深链接待导入: $scheme://...")
        // 若 Flutter 已启动,通知它(可能正在前台)
        try {
            MethodChannel(
                flutterEngine?.dartExecutor?.binaryMessenger ?: return, CHANNEL)
                .invokeMethod("onPendingImport", data)
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSingBoxPath" -> result.success(ensureSingBox())
                    "getDataDir" -> result.success(filesDir.absolutePath)
                    "startService" -> {
                        val cfg = call.argument<String>("configPath")
                        val port = call.argument<Int>("port") ?: 2080
                        if (cfg == null) {
                            result.error("bad_args", "configPath missing", null)
                        } else {
                            SingBoxService.start(this, cfg, port)
                            result.success(null)
                        }
                    }
                    "stopService" -> {
                        SingBoxService.stop(this)
                        result.success(null)
                    }
                    "restartService" -> {
                        SingBoxService.restart(this)
                        result.success(null)
                    }
                    "startVpn" -> {
                        val cfg = call.argument<String>("configPath")
                        val port = call.argument<Int>("port") ?: 2080
                        if (cfg == null) {
                            result.error("bad_args", "configPath missing", null)
                        } else {
                            // TUN 模式需先确认 VpnService 已授权
                            if (VpnService.prepare(this) == null) {
                                ProxyVpnService.start(this, cfg, port)
                                result.success(null)
                            } else {
                                // 未授权:弹窗
                                @Suppress("DEPRECATION")
                                startActivityForResult(
                                    VpnService.prepare(this)!!, VPN_REQUEST)
                                result.success(false)
                            }
                        }
                    }
                    "stopVpn" -> {
                        ProxyVpnService.stop(this)
                        result.success(null)
                    }
                    "isServiceRunning" -> result.success(SingBoxService.running)
                    "getPendingImport" -> {
                        val pending = getSharedPreferences(PREFS, MODE_PRIVATE)
                            .getString(KEY_IMPORT, null)
                        result.success(pending)
                    }
                    "clearPendingImport" -> {
                        getSharedPreferences(PREFS, MODE_PRIVATE)
                            .edit().remove(KEY_IMPORT).apply()
                        result.success(null)
                    }
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, VPN_REQUEST)
                            result.success(false) // 等待授权结果(异步)
                        } else {
                            result.success(true) // 已授权
                        }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(
                                android.Manifest.permission.POST_NOTIFICATIONS)
                            != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                NOTIF_REQUEST)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 定位并部署 sing-box:复制到 filesDir(可执行)并 chmod 755。 */
    private fun ensureSingBox(): String? {
        return try {
            val src = File(applicationInfo.nativeLibraryDir, "libsingbox.so")
            if (!src.exists()) {
                Log.w("NekoBox", "libsingbox.so not found in " +
                        applicationInfo.nativeLibraryDir)
                return null
            }
            val dest = File(filesDir, "sing-box")
            if (dest.exists() && dest.length() == src.length()) {
                return dest.absolutePath
            }
            src.copyTo(dest, overwrite = true)
            dest.setExecutable(true, false)
            dest.setReadable(true, false)
            Log.i("NekoBox", "sing-box deployed to ${dest.absolutePath}")
            dest.absolutePath
        } catch (e: Exception) {
            Log.e("NekoBox", "ensureSingBox failed", e)
            null
        }
    }
}
