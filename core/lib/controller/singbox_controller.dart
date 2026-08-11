import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/config_builder.dart';
import '../core_env.dart';
import '../models/profile.dart';
import '../models/profile_type.dart';
import '../repo/repository.dart';
import '../utils/android_uid.dart';
import 'android_proxy_bridge.dart';

/// sing-box 子进程控制器:启动 / 停止 / 日志 / 状态。
class SingBoxController extends ChangeNotifier {
  SingBoxController._();

  static final SingBoxController instance = SingBoxController._();

  /// sing-box 支持的出站协议
  static const Set<String> _supportedProtocols = {
    ProfileType.shadowsocks,
    ProfileType.vmess,
    ProfileType.vless,
    ProfileType.trojan,
    ProfileType.trojanGo,
    ProfileType.tuic,
    ProfileType.hysteria,
    ProfileType.hysteria2,
    ProfileType.wireguard,
    ProfileType.http,
    ProfileType.socks,
    ProfileType.ssh,
    ProfileType.anytls,
    ProfileType.shadowtls,
    ProfileType.naive,
    ProfileType.chain,
    ProfileType.v2ray,
    ProfileType.mieru,
  };

  Process? _process;
  /// Android 前台服务托管时:进程对象为 null,用此标志记录运行状态
  bool _androidRunning = false;
  Timer? _androidPoller;
  int _androidLogOffset = 0;
  bool _starting = false;
  /// 系统代理当前是否由本控制器启用(Windows 联动,断开/退出时需恢复)
  bool _systemProxyActive = false;
  bool _stopping = false;
  String? _lastError;

  final List<String> _logBuffer = [];
  static const int _maxLogLines = 500;

  /// 最近一次使用的配置文件路径
  String? _configPath;

  bool get isRunning => _useAndroidService ? _androidRunning : _process != null;

  /// 是否走 Android 前台服务托管(注入 bridge 时)
  bool get _useAndroidService =>
      Platform.isAndroid && CoreEnv.androidProxyBridge != null;
  bool get isStarting => _starting;
  bool get isStopping => _stopping;
  String? get lastError => _lastError;

  List<String> get logs => List.unmodifiable(_logBuffer);

  /// 当前是否为本地代理模式
  String proxyMode = 'local';

  /// 启动代理。
  /// [profiles] 节点列表,[selected] 选中节点,来自 Repository。
  Future<void> start({
    required List<Profile> profiles,
    required Profile? selected,
  }) async {
    if (isRunning || _starting) return;
    final repo = Repository.instance;
    // 不支持协议提前提示(Mieru 等 sing-box 无实现)
    if (selected != null &&
        !_supportedProtocols.contains(selected.type)) {
      _lastError = '该协议暂不支持连接: ${ProfileType.displayName(selected.type)}';
      notifyListeners();
      throw StateError(_lastError!);
    }
    // Shadowsocks 插件需要外部二进制(v2ray-plugin/obfs-local 等),
    // 仓库未捆绑,检查避免"看似支持、实测失败"
    if (selected != null && selected.type == ProfileType.shadowsocks) {
      final plugin = selected.bean['plugin']?.toString() ?? '';
      if (plugin.isNotEmpty) {
        _lastError =
            '该节点使用 SS 插件($plugin),需要系统安装对应插件二进制'
            '(v2ray-plugin / obfs-local),当前版本未捆绑';
        notifyListeners();
        throw StateError(_lastError!);
      }
    }
    final executable = CoreEnv.singBoxPath;
    if (executable.isEmpty) {
      _lastError = '未找到 sing-box 二进制,请检查运行环境';
      notifyListeners();
      throw StateError(_lastError!);
    }

    _starting = true;
    _lastError = null;
    notifyListeners();

    try {
      // 生成配置
      final settings = repo.settings;
      // 同步 srs 规则集到本地(Android 从 assets 解压,桌面复制)
      final availableSrs = await CoreEnv.syncSrsFiles();
      final srsDir = await CoreEnv.getSrsDirectory();
      // 同步 Clash 面板(dashboard),启用 Clash API 时 external_ui 指向它
      var clashApiUi = '';
      if (settings.clashApiEnabled) {
        await CoreEnv.syncDashboard();
        clashApiUi = (await CoreEnv.getDashboardDirectory()).path;
      }
      final config = ConfigBuilder.build(
        profiles: profiles,
        selected: selected,
        localPort: settings.localPort,
        logLevel: settings.logLevel,
        proxyMode: settings.proxyMode,
        tunAddress: settings.tunAddress,
        tunMtu: settings.tunMtu,
        bypassLan: settings.bypassLan,
        enableIpv6: settings.ipv6Mode != 0,
        ipv6Mode: settings.ipv6Mode,
        sniff: settings.sniff,
        strictRoute: settings.strictRoute,
        tcpFastOpen: settings.tcpFastOpen,
        remoteDns: settings.remoteDns,
        directDns: settings.directDns,
        clashApiEnabled: settings.clashApiEnabled,
        clashApiPort: settings.clashApiPort,
        clashApiSecret: settings.clashApiSecret,
        clashApiUi: clashApiUi,
        vpnInterface: settings.vpnInterface.isEmpty ? null : settings.vpnInterface,
        // 非 root TUN:VpnService 建立的固定 fd(与 ProxyVpnService.TUN_FD 一致)
        tunFd: (Platform.isAndroid && settings.proxyMode == 'tun') ? 7 : null,
        routeFinal: settings.routeFinal,
        rules: repo.rules,
        availableSrsFiles: availableSrs,
        srsDirectory: srsDir.path,
        tunStack: settings.tunStack,
        globalCustomConfig: settings.globalCustomConfig,
        groups: repo.groups,
        enableFakeDns: settings.enableFakeDns,
        packageUids: await AndroidUidResolver.load(),
        // 分应用代理:选中应用包名 → uid(仅 proxyApps 开启且非空时生效)
        proxyAppUids: settings.proxyApps
            ? (await AndroidUidResolver.load())
                .entries
                .where((e) => settings.proxyAppList.contains(e.key) && e.value >= 1000)
                .map((e) => e.value)
                .toList()
            : const [],
        allowAccess: settings.allowAccess,
        resolveDestination: settings.resolveDestination,
        enableDnsRouting: settings.enableDnsRouting,
        bypassLanInCore: settings.bypassLanInCore,
        globalAllowInsecure: settings.globalAllowInsecure,
        mixedPort: settings.mixedPort,
        pluginEnabled: settings.pluginEnabled,
        pluginPath: settings.pluginPath,
        subscriptionDeduplication: settings.subscriptionDeduplication,
        subscriptionForceResolve: settings.subscriptionForceResolve,
      );
      final dir = await CoreEnv.getTempDirectory();
      await dir.create(recursive: true);
      _configPath = '${dir.path}${Platform.pathSeparator}singbox-config.json';
      await File(_configPath!).writeAsString(jsonEncode(config));
      _addLog('配置已写入: $_configPath');
      _addLog('启动 sing-box (模式: ${repo.settings.proxyMode})');

      if (_useAndroidService) {
        // Android:前台服务托管子进程(通知常驻,退后台不断连)
        final bridge = CoreEnv.androidProxyBridge!;
        if (settings.proxyMode == 'tun') {
          // 非 root TUN:VpnService 建接口 + fd 传给 sing-box
          await bridge.startVpn(_configPath!, settings.localPort);
          _addLog('TUN 模式:VpnService 已接管全局流量');
        } else {
          await bridge.startService(_configPath!, settings.localPort);
          _addLog('前台服务已启动(通知栏常驻)');
        }
        _androidRunning = true;
        _startAndroidPoller(bridge);
        proxyMode = repo.settings.proxyMode;
        _starting = false;
        notifyListeners();
        return;
      }

      final process = await Process.start(
        executable,
        ['run', '-c', _configPath!],
        workingDirectory: dir.path,
      );
      _process = process;
      proxyMode = repo.settings.proxyMode;

      // 日志管道
      process.stdout.transform(utf8.decoder).listen(_addLog,
          onError: (Object e) {});
      process.stderr.transform(utf8.decoder).listen(_addLog,
          onError: (Object e) {});

      // 进程退出监听:无论正常/异常退出都恢复系统代理,避免残留
      unawaited(process.exitCode.then((code) {
        _process = null;
        _addLog('sing-box 已退出, exitCode=$code');
        if (code != 0 && !_stopping) {
          _lastError = 'sing-box 异常退出 (code $code),请查看日志';
        }
        if (_systemProxyActive) {
          _systemProxyActive = false;
          unawaited(CoreEnv.systemProxyDisable?.call() ?? Future.value());
        }
        _starting = false;
        notifyListeners();
      }));

      // 本地代理模式 + 启用系统代理 → 设置 Windows 系统代理
      if (CoreEnv.systemProxyEnable != null &&
          settings.systemProxy &&
          settings.proxyMode == 'local') {
        try {
          await CoreEnv.systemProxyEnable!(
              '127.0.0.1:${settings.localPort}');
          _systemProxyActive = true;
          _addLog('系统代理已启用: 127.0.0.1:${settings.localPort}');
        } catch (e) {
          _addLog('系统代理启用失败: $e');
        }
      }

      _starting = false;
      notifyListeners();
    } catch (e) {
      _starting = false;
      _process = null;
      _lastError = '启动失败: $e';
      _addLog(_lastError!);
      notifyListeners();
      rethrow;
    }
  }

  /// 停止代理。
  Future<void> stop() async {
    if (_useAndroidService) {
      _androidPoller?.cancel();
      _androidPoller = null;
      try {
        await CoreEnv.androidProxyBridge?.stopService();
      } catch (_) {}
      try {
        await CoreEnv.androidProxyBridge?.stopVpn();
      } catch (_) {}
      _androidRunning = false;
      if (_systemProxyActive) {
        _systemProxyActive = false;
        try {
          await CoreEnv.systemProxyDisable?.call();
        } catch (_) {}
      }
      _stopping = false;
      _addLog('sing-box 已停止');
      notifyListeners();
      return;
    }
    final p = _process;
    if (p == null) {
      _stopping = false;
      notifyListeners();
      return;
    }
    _stopping = true;
    notifyListeners();
    try {
      // 先尝试正常终止,再强制 kill
      p.kill(ProcessSignal.sigterm);
      await p.exitCode.timeout(const Duration(seconds: 3),
          onTimeout: () {
            p.kill(ProcessSignal.sigkill);
            return p.exitCode;
          });
    } catch (_) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _process = null;
    // 恢复系统代理(主动断开)
    if (_systemProxyActive) {
      _systemProxyActive = false;
      try {
        await CoreEnv.systemProxyDisable?.call();
      } catch (_) {}
    }
    _stopping = false;
    _addLog('sing-box 已停止');
    notifyListeners();
  }

  /// 切换(重启):停止后按新配置启动。
  Future<void> restart({
    required List<Profile> profiles,
    required Profile? selected,
  }) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await start(profiles: profiles, selected: selected);
  }

  /// 开关切换
  Future<void> toggle({
    required List<Profile> profiles,
    required Profile? selected,
  }) async {
    if (isRunning) {
      await stop();
    } else {
      await start(profiles: profiles, selected: selected);
    }
  }

  void _addLog(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logBuffer.add('[$ts] $line');
    if (_logBuffer.length > _maxLogLines) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxLogLines);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logBuffer.clear();
    notifyListeners();
  }

  /// 更新节点流量统计(tx/rx 字节数)。
  /// 用于运行时从 sing-box 日志或 API 采集流量数据后回写仓库。
  Future<void> updateProfileTraffic(int profileId, int tx, int rx) async {
    final repo = Repository.instance;
    final idx = repo.profiles.indexWhere((p) => p.id == profileId);
    if (idx < 0) return;
    final profile = repo.profiles[idx];
    profile.tx = tx;
    profile.rx = rx;
    await repo.updateProfile(profile);
    _addLog('流量统计更新: ${profile.displayName()} ↓${_fmtBytes(rx)} ↑${_fmtBytes(tx)}');
  }

  /// 批量更新所有节点流量(从 sing-box API / 日志解析后调用)。
  Future<void> updateAllTraffic(Map<int, Map<String, int>> trafficData) async {
    final repo = Repository.instance;
    var updated = 0;
    for (final entry in trafficData.entries) {
      final idx = repo.profiles.indexWhere((p) => p.id == entry.key);
      if (idx < 0) continue;
      final profile = repo.profiles[idx];
      final tx = entry.value['tx'] ?? 0;
      final rx = entry.value['rx'] ?? 0;
      profile.tx = tx;
      profile.rx = rx;
      updated++;
    }
    if (updated > 0) {
      final futures = <Future<void>>[];
      for (final p in repo.profiles) {
        futures.add(repo.updateProfile(p));
      }
      await Future.wait(futures);
      _addLog('批量流量统计更新: $updated 个节点');
    }
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 同步 Android 前台服务运行状态(App 重启后服务可能仍在跑,
  /// 或从通知/磁贴启动后,让控制器与实际状态对齐)。
  Future<void> syncAndroidState() async {
    if (!_useAndroidService) return;
    final bridge = CoreEnv.androidProxyBridge!;
    try {
      _androidRunning = await bridge.isRunning();
      if (_androidRunning) {
        _startAndroidPoller(bridge);
        _addLog('检测到前台服务运行中,已同步状态');
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Android 前台服务轮询:日志增量读取 + 意外退出检测。
  void _startAndroidPoller(AndroidProxyBridge bridge) {
    _androidPoller?.cancel();
    _androidLogOffset = 0;
    _androidPoller = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final lines = await bridge.readLogTail(maxLines: 1000);
        if (lines.length > _androidLogOffset) {
          for (final l in lines.sublist(_androidLogOffset)) {
            _addLog(l);
          }
          _androidLogOffset = lines.length;
        }
        final running = await bridge.isRunning();
        if (_androidRunning && !running) {
          _androidRunning = false;
          _lastError = 'sing-box 已退出,请查看日志';
          _addLog('sing-box 已退出(前台服务)');
          if (_systemProxyActive) {
            _systemProxyActive = false;
            await CoreEnv.systemProxyDisable?.call();
          }
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _androidPoller?.cancel();
    _process?.kill();
    super.dispose();
  }
}
