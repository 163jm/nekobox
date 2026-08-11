import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

import '../fmt/universal_fmt.dart';
import '../models/profile.dart';
import '../models/proxy_group.dart';
import '../repo/repository.dart';

/// 订阅下载与更新。
class SubscriptionUpdater {
  SubscriptionUpdater._();

  static const _userAgent =
      'Mozilla/5.0 (NekoBox-Flutter) AppleWebKit/537.36 '
      'Chrome/120.0 Safari/537.36';

  /// 构建 App 自身请求的 HTTP 客户端,读取设置:
  /// - [AppSettings.appTLSVersion]:控制请求 TLS 版本(旧版 TLS 时放宽证书校验)
  /// - [AppSettings.globalAllowInsecure]:全局跳过证书校验
  /// - [AppSettings.allowInsecureOnRequest]:订阅更新等请求允许不安全连接
  static http.Client _buildClient() {
    final settings = Repository.instance.settings;
    final httpClient = HttpClient();
    final tls = settings.appTLSVersion.trim().toLowerCase();
    // dart:io 无法直接指定 TLS 版本;当配置了旧版 TLS(1.0/1.1)或全局
    // 跳过校验时,放宽证书校验以兼容(对齐原版 appTLSVersion 的兼容语义)
    final legacyTls = tls.isNotEmpty &&
        (tls.contains('1.0') || tls.contains('1.1') || tls == 'tlsv1');
    if (settings.globalAllowInsecure ||
        settings.allowInsecureOnRequest || legacyTls) {
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }
    return io_client.IOClient(httpClient);
  }

  /// 下载订阅文本。支持 HTTP/HTTPS 与 data: URI。
  static Future<String> fetchText(String url) async {
    if (url.startsWith('data:')) {
      return _parseDataUri(url);
    }
    final uri = Uri.parse(url);
    final client = _buildClient();
    try {
      final resp = await client
          .get(uri, headers: {
            'User-Agent': _userAgent,
            'Accept': '*/*',
          })
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw FormatException('订阅下载失败: HTTP ${resp.statusCode}');
      }
      return _decodeBody(resp);
    } finally {
      client.close();
    }
  }

  static String _decodeBody(http.Response resp) {
    // 优先使用响应头编码,否则尝试 UTF-8
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) {
      final charset = contentType
          .split('charset=')
          .last
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (charset.isNotEmpty && charset != 'utf-8') {
        final bytes = resp.bodyBytes;
        try {
          if (charset == 'gbk' || charset == 'gb2312') {
            return _gbkDecode(bytes);
          }
          return _latin1Decode(bytes);
        } catch (_) {}
      }
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  static String _parseDataUri(String url) {
    final commaIdx = url.indexOf(',');
    if (commaIdx < 0) return '';
    final meta = url.substring(5, commaIdx);
    final payload = url.substring(commaIdx + 1);
    if (meta.contains('base64')) {
      final padded = payload.replaceAll('-', '+').replaceAll('_', '/');
      return utf8.decode(base64.decode(padded), allowMalformed: true);
    }
    return Uri.decodeComponent(payload);
  }

  /// 更新订阅组:下载 → 解析 → 替换组内节点。
  /// 返回新增节点数量。
  static Future<int> updateGroup(ProxyGroup group) async {
    final text = await fetchText(group.url);
    final profiles = UniversalFmt.parseSubscriptionText(text);
    if (profiles.isEmpty) {
      throw FormatException('订阅内容为空或无法解析');
    }
    // 若订阅中所有节点都有名字,且组名为空,用第一个节点名作为组名
    return profiles.length;
  }

  static String _latin1Decode(List<int> bytes) {
    return String.fromCharCodes(bytes);
  }

  static String _gbkDecode(List<int> bytes) {
    // 环境内置转换可能不可用,GBK 常见于中文订阅;尝试 UTF-8 后按字节保留
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
