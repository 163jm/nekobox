/*
 * tun_fwd.c — VpnService tun fd 传递 + sing-box 子进程启动。
 *
 * 非 root 下 sing-box 无法自己创建 tun 接口,必须使用 VpnService
 * 建立的接口。但 Java 的 ProcessBuilder 无法把任意 fd 传给子进程,
 * 因此用 fork() + dup2() 把 tun fd 复制到固定 fd,再 exec sing-box。
 * sing-box 配置中 tun inbound 的 "fd" 字段指向该固定 fd。
 *
 * 同时把子进程 stdout/stderr 重定向到日志文件(sing-box 自身也可
 * 通过 log.output 写同一文件)。
 */
#include <jni.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <fcntl.h>
#include <stdio.h>

JNIEXPORT jint JNICALL
Java_io_nekobox_nekobox_android_TunForwarder_nativeStart(
    JNIEnv *env, jclass clazz, jint tunFd, jint targetFd,
    jstring exePath, jstring configPath, jstring logPath) {
  const char *exe = (*env)->GetStringUTFChars(env, exePath, NULL);
  const char *cfg = (*env)->GetStringUTFChars(env, configPath, NULL);
  const char *logf = (*env)->GetStringUTFChars(env, logPath, NULL);

  pid_t pid = fork();
  if (pid == 0) {
    /* 子进程:继承 tun fd 到固定号码 */
    if (tunFd >= 0 && tunFd != targetFd) {
      dup2(tunFd, targetFd);
    }
    /* 日志重定向 */
    int lfd = open(logf, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (lfd >= 0) {
      dup2(lfd, STDOUT_FILENO);
      dup2(lfd, STDERR_FILENO);
      if (lfd > 2) close(lfd);
    }
    execl(exe, "sing-box", "run", "-c", cfg, (char *)NULL);
    _exit(127);
  }

  (*env)->ReleaseStringUTFChars(env, exePath, exe);
  (*env)->ReleaseStringUTFChars(env, configPath, cfg);
  (*env)->ReleaseStringUTFChars(env, logPath, logf);
  return (jint)pid;
}

JNIEXPORT void JNICALL
Java_io_nekobox_nekobox_android_TunForwarder_nativeKill(
    JNIEnv *env, jclass clazz, jint pid) {
  if (pid > 0) {
    kill((pid_t)pid, SIGTERM);
  }
}

JNIEXPORT jboolean JNICALL
Java_io_nekobox_nekobox_android_TunForwarder_nativeAlive(
    JNIEnv *env, jclass clazz, jint pid) {
  if (pid <= 0) return JNI_FALSE;
  return kill((pid_t)pid, 0) == 0 ? JNI_TRUE : JNI_FALSE;
}
