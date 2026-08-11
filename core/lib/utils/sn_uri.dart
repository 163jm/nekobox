import 'dart:convert';

import '../models/profile.dart';
import 'base64_util.dart';

class SnUri {
  SnUri._();

  static const String scheme = 'sn://';

  static String encode(Profile profile) {
    final payload = <String, dynamic>{
      'type': profile.type,
      'name': profile.name,
      'serverAddress': profile.serverAddress,
      'serverPort': profile.serverPort,
      'bean': profile.bean,
    };
    final jsonStr = jsonEncode(payload);
    final encoded = Base64Util.encodeUrlSafe(jsonStr);
    final name = profile.name;
    if (name.isNotEmpty) {
      return '$scheme$encoded#${Uri.encodeComponent(name)}';
    }
    return '$scheme$encoded';
  }

  static Profile? decode(String uri) {
    try {
      if (!uri.startsWith(scheme)) return null;
      final payload = uri.substring(scheme.length);
      if (payload.isEmpty) return null;

      String jsonStr;
      String name = '';

      final hashIdx = payload.indexOf('#');
      if (hashIdx >= 0) {
        final encodedPart = payload.substring(0, hashIdx);
        name = Uri.decodeComponent(payload.substring(hashIdx + 1));
        jsonStr = Base64Util.decodeToString(encodedPart);
      } else {
        jsonStr = Base64Util.decodeToString(payload);
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Profile(
        type: (data['type'] as String?) ?? '',
        name: name.isNotEmpty ? name : (data['name'] as String?) ?? '',
        serverAddress: (data['serverAddress'] as String?) ?? '',
        serverPort: (data['serverPort'] as num?)?.toInt() ?? 0,
        bean: (data['bean'] as Map<String, dynamic>?) ?? {},
      );
    } catch (_) {
      return null;
    }
  }
}