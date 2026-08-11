package io.nekobox.nekobox_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import org.json.JSONObject

/**
 * 非 root TUN 模式后端:VpnService 建立 tun 接口 + 流量转发。
 *
 * 流程:
 * 1. VpnService.prepare 授权(设置页切换 TUN 模式时已触发)
 * 2. 建立 tun 接口(路由全量 + DNS + **addDisallowedApplication 排除自身**,
 *    避免 sing-box 子进程连接代理服务器时被自己的 VPN 接管造成回环)
 * 3. 通过 NDK fork+dup2+exec 把 tun fd(固定 fd=7)传给 sing-box 子进程
 * 4. sing-box 配置中 tun inbound "fd": [7],直接消费该 tun 流量
 * 5. 状态写 singbox-state.json,日志由 sing-box log.output 写 singbox.log
 *
 * 与 SingBoxService(本地代理模式)共享状态/日志文件,Flutter 侧统一轮询。
 */
class ProxyVpnService : VpnService() {

    companion object {
        private const val TAG = "ProxyVpnService"
        private const val CHANNEL_ID = "nekobox_tun"
        private const val NOTIF_ID = 102

        const val ACTION_START = "io.nekobox.action.VPN_START"
        const val ACTION_STOP = "io.nekobox.action.VPN_STOP"
        const val EXTRA_CONFIG = "configPath"
        const val EXTRA_PORT = "port"

        /** 传给 sing-box 的固定 tun fd 号(配置中 "fd": [7]) */
        const val TUN_FD = 7

        @Volatile
        var running = false
            private set
        @Volatile
        var localPort = 2080
            private set
        @Volatile
        private var processPid = 0
        @Volatile
        private var tunFd: ParcelFileDescriptor? = null

        fun start(context: Context, configPath: String, port: Int) {
            val intent = Intent(context, ProxyVpnService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONFIG, configPath)
                putExtra(EXTRA_PORT, port)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, ProxyVpnService::class.java).apply { action = ACTION_STOP })
        }

        fun stateFile(context: Context): File = File(context.filesDir, "singbox-state.json")
        fun logFile(context: Context): File = File(context.filesDir, "singbox.log")

        private fun writeState(context: Context) {
            try {
                val state = JSONObject()
                    .put("running", running)
                    .put("pid", processPid)
                    .put("port", localPort)
                    .put("mode", "tun")
                stateFile(context).writeText(state.toString())
            } catch (e: Exception) {
                Log.w(TAG, "writeState failed: $e")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val cfg = intent.getStringExtra(EXTRA_CONFIG)
                val port = intent.getIntExtra(EXTRA_PORT, 2080)
                if (cfg != null) {
                    localPort = port
                    startForeground(NOTIF_ID, buildNotification())
                    startTun(cfg)
                }
            }
            ACTION_STOP -> {
                stopEverything()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }

    private fun startTun(configPath: String) {
        try {
            val settings = SettingsHelper.read(this)
            val builder = Builder()
                .setSession("NekoBox TUN")
                .setMtu(9000)
                .addAddress("10.7.0.2", 32)
                .addDnsServer("1.1.1.1")
            // app 层 bypassLan(对齐原版 VpnService.kt):addRoute 的语义是
            // "将该网段纳入 VPN 隧道"。VpnService 没有排除路由 API,因此
            // bypassLan=true 时添加"整个公网地址空间"(即原版
            // bypass_private_route 数组,155 条 CIDR 拼合,避开私有段),
            // 效果 = 公网流量进隧道、私有网段(未添加路由)直连;
            // bypassLan=false 时全量 0.0.0.0/0 进隧道。
            if (settings.optBoolean("bypassLan", true)) {
                val publicRoutes = listOf(
        "1.0.0.0/8", "2.0.0.0/7", "4.0.0.0/6", "8.0.0.0/7",
        "11.0.0.0/8", "12.0.0.0/6", "16.0.0.0/4", "32.0.0.0/3",
        "64.0.0.0/3", "96.0.0.0/6", "100.0.0.0/10", "100.128.0.0/9",
        "101.0.0.0/8", "102.0.0.0/7", "104.0.0.0/5", "112.0.0.0/10",
        "112.64.0.0/11", "112.96.0.0/12", "112.112.0.0/13", "112.120.0.0/14",
        "112.124.0.0/19", "112.124.32.0/21", "112.124.40.0/22", "112.124.44.0/23",
        "112.124.46.0/24", "112.124.48.0/20", "112.124.64.0/18", "112.124.128.0/17",
        "112.125.0.0/16", "112.126.0.0/15", "112.128.0.0/9", "113.0.0.0/8",
        "114.0.0.0/10", "114.64.0.0/11", "114.96.0.0/12", "114.112.0.0/15",
        "114.114.0.0/18", "114.114.64.0/19", "114.114.96.0/20", "114.114.112.0/23",
        "114.114.115.0/24", "114.114.116.0/22", "114.114.120.0/21", "114.114.128.0/17",
        "114.115.0.0/16", "114.116.0.0/14", "114.120.0.0/13", "114.128.0.0/9",
        "115.0.0.0/8", "116.0.0.0/6", "120.0.0.0/6", "124.0.0.0/7",
        "126.0.0.0/8", "128.0.0.0/3", "160.0.0.0/5", "168.0.0.0/8",
        "169.0.0.0/9", "169.128.0.0/10", "169.192.0.0/11", "169.224.0.0/12",
        "169.240.0.0/13", "169.248.0.0/14", "169.252.0.0/15", "169.255.0.0/16",
        "170.0.0.0/7", "172.0.0.0/12", "172.32.0.0/11", "172.64.0.0/10",
        "172.128.0.0/9", "173.0.0.0/8", "174.0.0.0/7", "176.0.0.0/4",
        "192.0.0.8/29", "192.0.0.16/28", "192.0.0.32/27", "192.0.0.64/26",
        "192.0.0.128/25", "192.0.1.0/24", "192.0.3.0/24", "192.0.4.0/22",
        "192.0.8.0/21", "192.0.16.0/20", "192.0.32.0/19", "192.0.64.0/18",
        "192.0.128.0/17", "192.1.0.0/16", "192.2.0.0/15", "192.4.0.0/14",
        "192.8.0.0/13", "192.16.0.0/12", "192.32.0.0/11", "192.64.0.0/12",
        "192.80.0.0/13", "192.88.0.0/18", "192.88.64.0/19", "192.88.96.0/23",
        "192.88.98.0/24", "192.88.100.0/22", "192.88.104.0/21", "192.88.112.0/20",
        "192.88.128.0/17", "192.89.0.0/16", "192.90.0.0/15", "192.92.0.0/14",
        "192.96.0.0/11", "192.128.0.0/11", "192.160.0.0/13", "192.169.0.0/16",
        "192.170.0.0/15", "192.172.0.0/14", "192.176.0.0/12", "192.192.0.0/10",
        "193.0.0.0/8", "194.0.0.0/7", "196.0.0.0/7", "198.0.0.0/12",
        "198.16.0.0/15", "198.20.0.0/14", "198.24.0.0/13", "198.32.0.0/12",
        "198.48.0.0/15", "198.50.0.0/16", "198.51.0.0/18", "198.51.64.0/19",
        "198.51.96.0/22", "198.51.101.0/24", "198.51.102.0/23", "198.51.104.0/21",
        "198.51.112.0/20", "198.51.128.0/17", "198.52.0.0/14", "198.56.0.0/13",
        "198.64.0.0/10", "198.128.0.0/9", "199.0.0.0/8", "200.0.0.0/7",
        "202.0.0.0/8", "203.0.0.0/18", "203.0.64.0/19", "203.0.96.0/20",
        "203.0.112.0/24", "203.0.114.0/23", "203.0.116.0/22", "203.0.120.0/21",
        "203.0.128.0/17", "203.1.0.0/16", "203.2.0.0/15", "203.4.0.0/14",
        "203.8.0.0/13", "203.16.0.0/12", "203.32.0.0/11", "203.64.0.0/10",
        "203.128.0.0/9", "204.0.0.0/6", "208.0.0.0/4"
                )
                publicRoutes.forEach { cidr ->
                    val parts = cidr.split("/")
                    if (parts.size == 2) {
                        val prefix = parts[1].toIntOrNull()
                        if (prefix != null) builder.addRoute(parts[0], prefix)
                    }
                }
                // fakeip 段(sing-box 默认 198.18.0.0/15,原版 FAKEDNS_VLAN4_CLIENT)
                builder.addRoute("198.18.0.0", 15)
                // IPv6 公网段(避开 fc00::/7 私有、fe80::/10、ff00::/8)
                builder.addRoute("2000::", 3)
            } else {
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
            }
            // 计费网络标记(API 29+,对齐原版 builder.setMetered)
            if (Build.VERSION.SDK_INT >= 29 &&
                settings.optBoolean("meteredNetwork", false)) {
                builder.setMetered(true)
            }
            // 追加 HTTP 代理:让非代理感知应用也能走系统代理(API 29+)
            if (Build.VERSION.SDK_INT >= 29 &&
                settings.optBoolean("appendHttpProxy", false)) {
                builder.setHttpProxy(
                    android.net.ProxyInfo.buildDirectProxy("127.0.0.1", localPort))
            }
            // 关键:排除自身 App——sing-box 子进程连接代理服务器时
            // 走原始网络,避免流量再次进入 tun 造成回环
            builder.addDisallowedApplication(packageName)
            val fd = builder.establish()
            if (fd == null) {
                Log.e(TAG, "VpnService.establish() 返回 null(未授权?)")
                writeState(this)
                stopSelf()
                return
            }
            tunFd = fd
            val exe = File(filesDir, "sing-box")
            if (!exe.exists()) {
                Log.e(TAG, "sing-box 不存在: ${exe.absolutePath}")
                writeState(this)
                stopSelf()
                return
            }
            val pid = TunForwarder.nativeStart(
                fd.fd, TUN_FD, exe.absolutePath, configPath,
                logFile(this).absolutePath)
            if (pid <= 0) {
                Log.e(TAG, "nativeStart 失败 pid=$pid")
                writeState(this)
                stopSelf()
                return
            }
            processPid = pid
            running = true
            appendLog(this, "TUN 已启动: fd=${fd.fd} → sing-box(pid=$pid)")
            writeState(this)
            updateNotification()

            // 子进程存活监控
            Thread {
                try {
                    while (running) {
                        Thread.sleep(1000)
                        if (!TunForwarder.nativeAlive(pid)) break
                    }
                    running = false
                    appendLog(this, "TUN sing-box 进程已退出")
                    writeState(this)
                    updateNotification()
                } catch (_: InterruptedException) {}
            }.start()
        } catch (e: Exception) {
            Log.e(TAG, "startTun failed", e)
            running = false
            appendLog(this, "TUN 启动失败: $e")
            writeState(this)
            stopSelf()
        }
    }

    private fun stopEverything() {
        running = false
        try {
            if (processPid > 0) TunForwarder.nativeKill(processPid)
        } catch (_: Exception) {}
        processPid = 0
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        writeState(this)
        try { stopForeground(true) } catch (_: Exception) {}
    }

    // ---------- 通知 ----------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "TUN 代理", NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("NekoBox TUN")
            .setContentText("全局代理运行中")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }

    private fun updateNotification() {
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            if (running) nm.notify(NOTIF_ID, buildNotification())
        } catch (_: Exception) {}
    }

    private fun appendLog(context: Context, line: String) {
        try {
            val f = logFile(context)
            if (f.length() > 1024 * 1024) f.delete()
            java.io.FileOutputStream(f, true).use {
                it.write((line + "\n").toByteArray())
            }
        } catch (_: Exception) {}
    }
}
