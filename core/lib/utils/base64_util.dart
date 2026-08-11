import 'dart:convert';
import 'dart:typed_data';

/// Base64 工具,兼容 url-safe 与缺失 padding 等常见变体。
class Base64Util {
  Base64Util._();

  /// 解码为字符串(容错处理:url-safe 字符、补齐 padding)
  static String decodeToString(String input) {
    final bytes = decodeToBytes(input);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Uint8List decodeToBytes(String input) {
    var s = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    // 移除可能的 scheme 前缀(如 data URI)
    if (s.contains(',')) s = s.substring(s.indexOf(',') + 1);
    while (s.length % 4 != 0) {
      s += '=';
    }
    return base64.decode(s);
  }

  /// 标准 base64 编码(不带 padding 的 urlsafe 形式,常用于分享链接)
  static String encodeUrlSafe(String input) {
    return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
  }

  static String encodeUrlSafeBytes(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 判断是否为合法的 base64(粗略)
  static bool isBase64(String input) {
    if (input.isEmpty) return false;
    final s = input.replaceAll('-', '+').replaceAll('_', '/');
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final valid = (c >= 48 && c <= 57) || // 0-9
          (c >= 65 && c <= 90) || // A-Z
          (c >= 97 && c <= 122) || // a-z
          c == 43 || // +
          c == 47 || // /
          c == 61; // =
      if (!valid) return false;
    }
    return true;
  }
}
