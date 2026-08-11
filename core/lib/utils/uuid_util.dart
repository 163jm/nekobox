import 'dart:math';

/// 生成 UUID(v4),用于 VMess/VLESS/TUIC 等协议的客户端标识。
class UuidUtil {
  UuidUtil._();

  static final Random _rng = Random.secure();

  static String generateV4() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    // 设置版本 4 与变体位
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
