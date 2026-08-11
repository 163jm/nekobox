/// URL 解析辅助:从分享链接提取用户信息与查询参数。
class UriUtil {
  UriUtil._();

  /// 解析 userinfo 部分 `user:pass@host:port`
  /// 返回 [user, pass] 或空数组。
  static List<String> parseUserInfo(String userInfo) {
    if (userInfo.isEmpty) return [];
    final idx = userInfo.indexOf(':');
    if (idx < 0) return [Uri.decodeComponent(userInfo)];
    return [
      Uri.decodeComponent(userInfo.substring(0, idx)),
      Uri.decodeComponent(userInfo.substring(idx + 1)),
    ];
  }

  /// 解析 `host:port`,无端口时返回默认端口。
  static (String, int) parseHostPort(String authority, int defaultPort) {
    final idx = authority.lastIndexOf(':');
    if (idx > 0) {
      final host = authority.substring(0, idx);
      final portStr = authority.substring(idx + 1);
      final port = int.tryParse(portStr);
      if (port != null && port > 0) {
        return (host, port);
      }
    }
    return (authority, defaultPort);
  }

  /// 从查询参数中读取 int
  static int intParam(Uri uri, String key, int def) {
    final v = uri.queryParameters[key];
    if (v == null) return def;
    return int.tryParse(v) ?? def;
  }

  /// 从查询参数中读取字符串
  static String strParam(Uri uri, String key, String def) {
    final v = uri.queryParameters[key];
    if (v == null || v.isEmpty) return def;
    return v;
  }
}
