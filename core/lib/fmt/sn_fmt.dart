import 'dart:convert';

import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/base64_util.dart';

/// NekoBox 私有分享格式 sn://。
/// sn://base64_encoded_payload，payload 为包含完整 Profile 字段的 JSON。
class SnFmt {
  SnFmt._();

  static const String scheme = 'sn';

  static Profile parse(String raw) {
    if (!raw.startsWith('sn://')) {
      throw FormatException('无效的 sn:// 链接: $raw');
    }
    final payload = raw.substring('sn://'.length);
    if (payload.isEmpty) {
      throw FormatException('sn:// 链接载荷为空');
    }
    final jsonStr = Base64Util.decodeToString(payload);
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Profile.fromJson(data);
    } catch (_) {
      throw FormatException('无法解析 sn:// 链接: $raw');
    }
  }
}

/// 导出 sn:// 格式
class SnFmtExport {
  SnFmtExport._();

  static String export(Profile p) {
    final jsonStr = jsonEncode(p.toJson());
    return 'sn://${Base64Util.encodeUrlSafe(jsonStr)}';
  }
}