package io.nekobox.nekobox_android

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.File

/**
 * 从应用 SQLite 数据库读取设置(App 未打开时 Service/开机广播也能用)。
 *
 * Repository 将全部设置序列化为 JSON 存入 settings 表(data 列,单行 id=1)。
 * 这里只做只读解析,Flutter 侧仍是唯一写入方。
 */
object SettingsHelper {

    private const val DB_NAME = "nekobox.db"

    /** 读取全部设置(JSON);失败返回空对象。 */
    fun read(context: Context): JSONObject {
        return try {
            val dbPath = File(context.filesDir, DB_NAME).absolutePath
            val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
            var cursor: android.database.Cursor? = null
            try {
                cursor = db.rawQuery("SELECT data FROM settings WHERE id = 1", null)
                if (cursor!!.moveToFirst()) {
                    val raw = cursor.getString(0) ?: "{}"
                    JSONObject(raw)
                } else {
                    JSONObject()
                }
            } finally {
                cursor?.let { runCatching { it.close() } }
                runCatching { db.close() }
            }
        } catch (e: Exception) {
            JSONObject()
        }
    }

    /** 读取单项设置。 */
    fun get(context: Context, key: String, default: Boolean = false): Boolean {
        val v = read(context).opt(key)
        return when (v) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v == "true" || v == "1"
            else -> default
        }
    }

    fun getInt(context: Context, key: String, default: Int = 0): Int {
        val v = read(context).opt(key)
        return when (v) {
            is Number -> v.toInt()
            is String -> v.toIntOrNull() ?: default
            else -> default
        }
    }

    fun getString(context: Context, key: String, default: String = ""): String {
        val v = read(context).opt(key)
        return when (v) {
            is String -> v
            else -> default
        }
    }
}
