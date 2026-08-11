import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

import '../models/profile.dart';
import '../repo/repository.dart';

/// 节点延迟测试。
///
/// 两种测速方式(对齐原版):
/// - **TCP Ping**:直接 TCP 连接目标服务器端口计时。
/// - **URL 测速**:经本地代理请求 [connectionTestURL] 计时(需代理在运行,
///   否则降级为 TCP 连接)。测试地址读取设置里的 `connectionTestURL`。
class UrlTester {
  UrlTester._();

  /// TCP 连接测速:连接目标服务器端口计时。
  static Future<int> testProfile(Profile p,
      {int timeoutMs = 5000}) async {
    if (p.serverAddress.isEmpty || p.serverPort <= 0) {
      throw StateError('节点地址无效');
    }
    final sw = Stopwatch()..start();
    late Socket socket;
    try {
      socket = await Socket.connect(
        p.serverAddress,
        p.serverPort,
        timeout: Duration(milliseconds: timeoutMs),
      );
    } catch (e) {
      throw StateError('连接失败: $e');
    }
    sw.stop();
    try {
      socket.destroy();
    } catch (_) {}
    return sw.elapsedMilliseconds;
  }

  /// URL 测速:经本地代理请求 [testUrl](读取设置 connectionTestURL)计时。
  ///
  /// 代理未运行(本地端口不通)时降级为 TCP 连接测速,保证功能可用。
  /// [testUrl] 为空时使用 [Repository.instance.settings.connectionTestURL]。
  static Future<int> testUrl(
    Profile p, {
    int timeoutMs = 5000,
    String? testUrl,
  }) async {
    final settings = Repository.instance.settings;
    final url = (testUrl ?? settings.connectionTestURL).trim();
    final sw = Stopwatch()..start();
    if (url.isNotEmpty) {
      // 优先经本地代理端口请求(URL 测速语义 = 经节点测目标地址)
      final proxyPort = settings.localPort;
      final client = io_client.IOClient(
        HttpClient()
          ..connectionTimeout = Duration(milliseconds: timeoutMs)
          ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort',
      );
      try {
        final resp = await client
            .get(Uri.parse(url))
            .timeout(Duration(milliseconds: timeoutMs));
        if (resp.statusCode < 400) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {
        // 代理未运行或请求失败 → 降级 TCP 连接测速
      } finally {
        try {
          client.close();
        } catch (_) {}
      }
    }
    // 降级:TCP 连接测速
    return testProfile(p, timeoutMs: timeoutMs);
  }

  /// 测试单个节点(URL 方式,读取设置 connectionTestURL)并写回 Repository。
  static Future<int> testAndSaveUrl(Profile p) async {
    final timeout = Repository.instance.settings.urlTestTimeout;
    final delay = await testUrl(p, timeoutMs: timeout);
    await Repository.instance.updateProfileDelay(p, delay);
    return delay;
  }

  /// 测试单个节点(TCP Ping 方式)并写回 Repository。
  static Future<int> testAndSave(Profile p) async {
    final timeout = Repository.instance.settings.urlTestTimeout;
    final delay = await testProfile(p, timeoutMs: timeout);
    await Repository.instance.updateProfileDelay(p, delay);
    return delay;
  }

  /// 批量测试(TCP Ping),逐节点回调进度。
  static Future<void> testAll(
    List<Profile> profiles, {
    int timeoutMs = 5000,
    void Function(int index, int total, String name, int? delay)? onProgress,
  }) async {
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      try {
        final delay = await testProfile(p, timeoutMs: timeoutMs);
        await Repository.instance.updateProfileDelay(p, delay);
        onProgress?.call(i + 1, profiles.length, p.displayName(), delay);
      } catch (_) {
        await Repository.instance.updateProfileDelay(p, -1);
        onProgress?.call(i + 1, profiles.length, p.displayName(), null);
      }
    }
  }

  /// 批量 URL 测速(读取设置 connectionTestURL)。
  static Future<void> testAllUrl(
    List<Profile> profiles, {
    int timeoutMs = 5000,
    void Function(int index, int total, String name, int? delay)? onProgress,
  }) async {
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      try {
        final delay = await testUrl(p, timeoutMs: timeoutMs);
        await Repository.instance.updateProfileDelay(p, delay);
        onProgress?.call(i + 1, profiles.length, p.displayName(), delay);
      } catch (_) {
        await Repository.instance.updateProfileDelay(p, -1);
        onProgress?.call(i + 1, profiles.length, p.displayName(), null);
      }
    }
  }
}
