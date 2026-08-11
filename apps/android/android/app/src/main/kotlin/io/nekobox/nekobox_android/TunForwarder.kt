package io.nekobox.nekobox_android

/**
 * JNI 包装:VpnService tun fd → sing-box 子进程。
 *
 * 对应 native 库 `libtunfwd.so`(src/main/cpp/tun_fwd.c),
 * 通过 fork + dup2 + exec 把 tun fd 传给 sing-box(固定 fd=7,
 * 配置中 tun inbound "fd": [7] 指向它)。
 */
object TunForwarder {
    init {
        System.loadLibrary("tunfwd")
    }

    /**
     * fork 出子进程:dup2(tunFd → targetFd) 后 exec sing-box。
     * 返回子进程 pid;失败返回 -1。
     */
    external fun nativeStart(
        tunFd: Int,
        targetFd: Int,
        exePath: String,
        configPath: String,
        logPath: String,
    ): Int

    /** 终止子进程。 */
    external fun nativeKill(pid: Int)

    /** 子进程是否存活。 */
    external fun nativeAlive(pid: Int): Boolean
}
