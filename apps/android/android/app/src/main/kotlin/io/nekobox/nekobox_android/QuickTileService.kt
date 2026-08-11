package io.nekobox.nekobox_android

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import java.io.File

/**
 * 通知栏快捷磁贴:一键开关代理。
 *
 * 开启:使用上次运行配置(latest config)启动前台服务;
 * 关闭:停止服务。磁贴状态与服务运行状态同步。
 */
class QuickTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (SingBoxService.running) {
            SingBoxService.stop(this)
        } else {
            val last = File(filesDir, "singbox-last-config.json")
            if (!last.exists()) {
                Log.d("QuickTile", "无上次运行配置")
                return
            }
            try {
                val obj = org.json.JSONObject(last.readText())
                val config = obj.optString("config", "")
                val port = obj.optInt("port", 2080)
                if (config.isEmpty()) return
                SingBoxService.start(this, config, port)
            } catch (e: Exception) {
                Log.e("QuickTile", "磁贴启动失败: $e")
            }
        }
        // 稍等状态写入后刷新
        updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        tile.state = if (SingBoxService.running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (SingBoxService.running) "NekoBox 已连接" else "NekoBox 代理"
        tile.updateTile()
    }
}
