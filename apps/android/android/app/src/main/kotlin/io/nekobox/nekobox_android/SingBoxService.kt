package io.nekobox.nekobox_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/**
 * 前台服务:在后台托管 sing-box 子进程。
 *
 * 对齐原版 ProxyService 的职责:
 * - 前台通知常驻(服务不被系统回收,App 退后台代理不断)
 * - 子进程生命周期由 Service 管理(START_STICKY,被杀自动重建)
 * - 网络切换 / 唤醒 / doze 监听,按设置自动重启连接
 * - 保持唤醒锁(设置开启时)
 * - 状态与日志写入文件,供 Flutter 侧轮询读取
 */
class SingBoxService : Service() {

    companion object {
        private const val TAG = "SingBoxService"
        private const val CHANNEL_ID = "nekobox_proxy"
        private const val NOTIF_ID = 101

        const val ACTION_START = "io.nekobox.action.START"
        const val ACTION_STOP = "io.nekobox.action.STOP"
        const val ACTION_RESTART = "io.nekobox.action.RESTART"
        const val ACTION_BOOT = "io.nekobox.action.BOOT"
        const val EXTRA_CONFIG = "configPath"
        const val EXTRA_PORT = "port"

        @Volatile
        var running = false
            private set
        @Volatile
        var localPort = 2080
            private set
        @Volatile
        var configPath: String? = null
            private set

        @Volatile
        private var process: Process? = null
        @Volatile
        private var stopping = false
        @Volatile
        private var lastRestartAt = 0L

        fun start(context: Context, configPath: String, port: Int) {
            val intent = Intent(context, SingBoxService::class.java).apply {
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
                Intent(context, SingBoxService::class.java).apply { action = ACTION_STOP })
        }

        fun restart(context: Context) {
            context.startService(
                Intent(context, SingBoxService::class.java).apply { action = ACTION_RESTART })
        }

        fun stateFile(context: Context): File = File(context.filesDir, "singbox-state.json")

        /** Flutter 侧轮询用的状态文件。 */
        fun writeState(context: Context) {
            try {
                val state = JSONObject()
                    .put("running", running)
                    .put("pid", process?.hashCode() ?: -1)
                    .put("port", localPort)
                    .put("config", configPath ?: "")
                stateFile(context).writeText(state.toString())
            } catch (e: Exception) {
                Log.w(TAG, "writeState failed: $e")
            }
        }

        fun logFile(context: Context): File = File(context.filesDir, "singbox.log")

        private fun appendLog(context: Context, line: String) {
            try {
                val f = logFile(context)
                if (f.length() > 1024 * 1024) { // 1MB 上限,超出截断
                    f.delete()
                }
                FileOutputStream(f, true).use { it.write((line + "\n").toByteArray()) }
            } catch (_: Exception) {}
        }
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_BOOT -> {
                val cfg = intent.getStringExtra(EXTRA_CONFIG)
                val port = intent.getIntExtra(EXTRA_PORT, 2080)
                if (cfg != null) {
                    configPath = cfg
                    localPort = port
                    startForeground(NOTIF_ID, buildNotification())
                    registerListeners()
                    startProcess()
                    // 供磁贴/开机自启复用
                    File(filesDir, "singbox-last-config.json").writeText(
                        JSONObject()
                            .put("config", cfg)
                            .put("port", port)
                            .toString())
                }
            }
            ACTION_RESTART -> {
                if (running) {
                    startForeground(NOTIF_ID, buildNotification())
                    startProcess()
                }
            }
            ACTION_STOP -> {
                stopEverything()
                stopSelf()
            }
        }
        // 被系统杀死后重建时保持连接(对齐原版 START_STICKY)
        return START_STICKY
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }

    private fun startProcess() {
        val cfg = configPath ?: return
        val exe = File(filesDir, "sing-box")
        if (!exe.exists()) {
            appendLog(this, "未找到 sing-box 可执行文件: ${exe.absolutePath}")
            writeState(this)
            return
        }
        stopping = false
        try {
            val pb = ProcessBuilder(exe.absolutePath, "run", "-c", cfg)
            pb.redirectErrorStream(true)
            val p = pb.start()
            process = p
            running = true
            appendLog(this, "sing-box 已启动 (pid=${p.hashCode()}, 配置=$cfg)")
            writeState(this)
            updateNotification()

            // 日志管道 → 文件
            Thread {
                try {
                    val reader = BufferedReader(InputStreamReader(p.inputStream))
                    while (true) {
                        val line = reader.readLine() ?: break
                        appendLog(this, line)
                    }
                } catch (_: Exception) {}
            }.start()

            // 退出监听
            Thread {
                try {
                    val code = p.waitFor()
                    if (!stopping) {
                        appendLog(this, "sing-box 异常退出 (code=$code)")
                    } else {
                        appendLog(this, "sing-box 已停止")
                    }
                } catch (_: Exception) {}
                running = false
                process = null
                writeState(this)
                updateNotification()
            }.start()
        } catch (e: Exception) {
            running = false
            appendLog(this, "启动 sing-box 失败: $e")
            writeState(this)
        }
    }

    private fun restartProcess() {
        // 节流:5 秒内不重复重启
        val now = System.currentTimeMillis()
        if (now - lastRestartAt < 5000) return
        lastRestartAt = now
        appendLog(this, "网络/唤醒事件触发重启连接")
        val old = process
        stopping = true
        try { old?.destroy() } catch (_: Exception) {}
        stopping = false
        startProcess()
    }

    private fun stopEverything() {
        stopping = true
        try { process?.destroy() } catch (_: Exception) {}
        process = null
        running = false
        unregisterListeners()
        releaseWakeLock()
        writeState(this)
        try { stopForeground(true) } catch (_: Exception) {}
    }

    // ---------- 监听器 ----------

    private fun registerListeners() {
        val settings = SettingsHelper.read(this)
        // 网络切换重置(registerDefaultNetworkCallback 需 API 24+)
        if (settings.optBoolean("networkChangeResetConnections", true) &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val cm = getSystemService(ConnectivityManager::class.java) ?: return
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    if (running && !stopping) restartProcess()
                }

                override fun onLost(network: Network) {
                    if (running && !stopping) restartProcess()
                }
            }
            try { cm.registerDefaultNetworkCallback(networkCallback!!) } catch (_: Exception) {}
        }
        // 唤醒重置 + doze 监听
        if (settings.optBoolean("wakeResetConnections", false)) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
            screenReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action == Intent.ACTION_SCREEN_ON && running && !stopping) {
                        restartProcess()
                    }
                }
            }
            try { registerReceiver(screenReceiver, filter) } catch (_: Exception) {}
        }
        // 保持唤醒锁
        if (settings.optBoolean("acquireWakeLock", false)) {
            val pm = getSystemService(PowerManager::class.java) ?: return
            try {
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK, "NekoBox:proxy")
                wakeLock?.acquire()
            } catch (_: Exception) {}
        }
    }

    private fun unregisterListeners() {
        networkCallback?.let {
            try { getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(it) } catch (_: Exception) {}
        }
        networkCallback = null
        screenReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        screenReceiver = null
    }

    private fun releaseWakeLock() {
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
    }

    // ---------- 通知 ----------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "代理服务", NotificationManager.IMPORTANCE_LOW)
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
            .setContentTitle("NekoBox")
            .setContentText("代理运行中 · 127.0.0.1:$localPort")
            .setSmallIcon(android.R.drawable.stat_sys_upload) // 使用系统图标,避免资源缺失
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
}
