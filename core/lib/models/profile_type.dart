/// 协议类型常量,与原版 NekoBox TypeMap 对应。
class ProfileType {
  ProfileType._();

  static const String socks = 'socks';
  static const String http = 'http';
  static const String ssh = 'ssh';
  static const String shadowsocks = 'shadowsocks';
  static const String vmess = 'vmess';
  static const String trojan = 'trojan';
  static const String vless = 'vless';
  static const String anytls = 'anytls';
  static const String shadowtls = 'shadowtls';
  static const String tuic = 'tuic';
  static const String hysteria = 'hysteria';
  static const String hysteria2 = 'hysteria2';
  static const String wireguard = 'wireguard';
  static const String trojanGo = 'trojan_go';
  static const String naive = 'naive';
  static const String mieru = 'mieru';
  static const String chain = 'chain';
  static const String v2ray = 'v2ray';

  static const List<String> all = [
    socks,
    http,
    ssh,
    shadowsocks,
    vmess,
    trojan,
    vless,
    anytls,
    shadowtls,
    tuic,
    hysteria,
    hysteria2,
    wireguard,
    trojanGo,
    naive,
    mieru,
    chain,
    v2ray,
  ];

  /// 订阅链接 scheme → 类型
  static const Map<String, String> schemeMap = {
    'socks': socks,
    'socks4': socks,
    'socks5': socks,
    'http': http,
    'https': http,
    'ssh': ssh,
    'ss': shadowsocks,
    'vmess': vmess,
    'trojan': trojan,
    'vless': vless,
    'anytls': anytls,
    'shadowtls': shadowtls,
    'tuic': tuic,
    'hysteria': hysteria,
    'hysteria2': hysteria2,
    'wg': wireguard,
    'wireguard': wireguard,
    'naive': naive,
    'naive+https': naive,
    'mieru': mieru,
    'trojan-go': trojanGo,
    'v2ray': v2ray,
  };

  /// 类型 → 显示名(UI 用)
  static String displayName(String type) {
    switch (type) {
      case socks:
        return 'SOCKS';
      case http:
        return 'HTTP';
      case ssh:
        return 'SSH';
      case shadowsocks:
        return 'Shadowsocks';
      case vmess:
        return 'VMess';
      case trojan:
        return 'Trojan';
      case vless:
        return 'VLESS';
      case anytls:
        return 'AnyTLS';
      case shadowtls:
        return 'ShadowTLS';
      case tuic:
        return 'TUIC';
      case hysteria:
        return 'Hysteria';
      case hysteria2:
        return 'Hysteria2';
      case wireguard:
        return 'WireGuard';
      case trojanGo:
        return 'Trojan-Go';
      case naive:
        return 'Naive';
      case mieru:
        return 'Mieru';
      case chain:
        return 'Chain';
      case v2ray:
        return 'V2Ray';
      default:
        return type;
    }
  }

  /// 协议颜色(0xAARRGGBB,仿原版 Protocols.getProtocolColor)。
  /// UI 层用 [Color(color)] 转换。
  static int color(String type) {
    switch (type) {
      case vmess:
        return 0xFF00A6FF;
      case vless:
        return 0xFF3A86FF;
      case trojan:
        return 0xFF9C27B0;
      case trojanGo:
        return 0xFFAB47BC;
      case shadowsocks:
        return 0xFFFF9800;
      case tuic:
        return 0xFF00BCD4;
      case hysteria:
        return 0xFF43A047;
      case hysteria2:
        return 0xFF4CAF50;
      case wireguard:
        return 0xFF607D8B;
      case http:
        return 0xFF8BC34A;
      case socks:
        return 0xFF795548;
      case ssh:
        return 0xFF37474F;
      case anytls:
        return 0xFFE91E63;
      case shadowtls:
        return 0xFF009688;
      case naive:
        return 0xFF7CB342;
      case mieru:
        return 0xFF66BB6A;
      case chain:
        return 0xFFB0BEC5;
      case v2ray:
        return 0xFF2196F3;
      default:
        return 0xFF757575;
    }
  }
}
