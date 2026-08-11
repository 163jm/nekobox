import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/base64_util.dart';
import '../utils/uri_util.dart';

/// Shadowsocks 链接解析与生成。
/// 支持两种格式:
/// - ss://base64(method:password@host:port)#name
/// - ss://method:password@host:port#name(带 plugin 时)
class ShadowsocksFmt {
  ShadowsocksFmt._();

  static const String type = ProfileType.shadowsocks;

  static Profile parse(String raw) {
    final withoutScheme = raw.substring('ss://'.length);
    final hashIdx = withoutScheme.indexOf('#');
    final name = hashIdx >= 0
        ? Uri.decodeComponent(withoutScheme.substring(hashIdx + 1))
        : '';
    var body = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

    // 尝试直接解析 method:password@host:port
    final direct = _tryParseDirect(body);
    if (direct != null) {
      final p = direct;
      p.name = name;
      return p;
    }

    // 否则按 base64(method:password@host:port) 解析
    final decoded = Base64Util.decodeToString(body);
    final p = _tryParseDirect(decoded);
    if (p != null) {
      p.name = name;
      return p;
    }

    // 兼容 plugin 形式:base64 部分只包含 server 信息,plugin 在查询参数
    // 例如 ss://base64(method:pass@host:port)?plugin=...&name=...
    final qIdx = body.indexOf('?');
    if (qIdx >= 0) {
      final params = Uri.splitQueryString(body.substring(qIdx + 1));
      final plugin = params['plugin'];
      body = body.substring(0, qIdx);
      final decoded2 = Base64Util.decodeToString(body);
      final p2 = _tryParseDirect(decoded2);
      if (p2 != null) {
        p2.name = params['name'] ?? name;
        if (plugin != null && plugin.isNotEmpty) {
          p2.bean['plugin'] = _pluginName(plugin);
          p2.bean['plugin_opts'] = _pluginOpts(plugin);
        }
        return p2;
      }
    }

    throw FormatException('无法解析 Shadowsocks 链接: $raw');
  }

  static Profile? _tryParseDirect(String body) {
    final atIdx = body.indexOf('@');
    if (atIdx < 0) return null;
    final methodPass = body.substring(0, atIdx);
    final authority = body.substring(atIdx + 1);
    final mpIdx = methodPass.indexOf(':');
    if (mpIdx < 0) return null;
    final method = methodPass.substring(0, mpIdx);
    final password = Uri.decodeComponent(methodPass.substring(mpIdx + 1));
    if (method.isEmpty || password.isEmpty) return null;
    final (host, port) = UriUtil.parseHostPort(authority, 8388);
    if (host.isEmpty || port <= 0) return null;
    return Profile(
      type: type,
      serverAddress: host,
      serverPort: port,
      bean: {'method': method, 'password': password},
    );
  }

  static String _pluginName(String plugin) {
    // 形如 "obfs-local;obfs=http;obfs-host=..." 或 "v2ray-plugin;..."
    final idx = plugin.indexOf(';');
    return idx >= 0 ? plugin.substring(0, idx) : plugin;
  }

  static String _pluginOpts(String plugin) {
    final idx = plugin.indexOf(';');
    return idx >= 0 ? plugin.substring(idx + 1) : '';
  }
}

/// 导出(生成 ss:// 链接)
class ShadowsocksFmtExport {
  ShadowsocksFmtExport._();

  static String export(Profile p) {
    final method = p.bean['method'] ?? 'aes-128-gcm';
    final password = p.bean['password'] ?? '';
    final userInfo = '$method:$password@${p.serverAddress}:${p.serverPort}';
    final encoded = Base64Util.encodeUrlSafe(userInfo);
    final name = p.name.isNotEmpty ? '#${Uri.encodeComponent(p.name)}' : '';
    final plugin = p.bean['plugin'];
    if (plugin != null && plugin.toString().isNotEmpty) {
      final opts = p.bean['plugin_opts']?.toString() ?? '';
      final pluginStr = opts.isNotEmpty ? '$plugin;$opts' : plugin;
      return 'ss://$encoded?plugin=${Uri.encodeComponent(pluginStr)}$name';
    }
    return 'ss://$encoded$name';
  }
}
