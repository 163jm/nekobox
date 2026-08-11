/// Android 前台服务桥接抽象接口。
///
/// Android 端由前台服务(SingBoxService)托管 sing-box 子进程,
/// 与桌面端(Process.start)是两套后端。核心层通过本接口
/// 与 Android 实现解耦:存在则走服务托管,否则回退子进程。
abstract class AndroidProxyBridge {
  /// 启动前台服务托管 sing-box。
  Future<void> startService(String configPath, int port);

  /// 停止前台服务与子进程。
  Future<void> stopService();

  /// 重启前台服务内的子进程。
  Future<void> restartService();

  /// 启动 TUN 模式:VpnService 建立 tun 并托管 sing-box(VpnService 模式)。
  Future<void> startVpn(String configPath, int port);

  /// 停止 TUN 模式。
  Future<void> stopVpn();

  /// 当前是否运行(读状态文件)。
  Future<bool> isRunning();

  /// 读取 sing-box 日志尾部(供日志页显示)。
  Future<List<String>> readLogTail({int maxLines = 300});

  /// 拉取深链接待导入内容(浏览器点击 vmess:// 等)。
  Future<String?> getPendingImport();

  /// 清除已处理的深链接。
  Future<void> clearPendingImport();

  /// VpnService 授权弹窗;返回是否已授权。
  Future<bool> prepareVpn();
}
