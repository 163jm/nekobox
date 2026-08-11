import '../models/profile.dart';
import '../models/profile_type.dart';
import 'anytls_fmt.dart';
import 'clash_fmt.dart';
import 'http_fmt.dart';
import 'hysteria1_fmt.dart';
import 'hysteria2_fmt.dart';
import 'mieru_fmt.dart';
import 'naive_fmt.dart';
import 'shadowtls_fmt.dart';
import 'shadowsocks_fmt.dart';
import 'singbox_json_fmt.dart';
import 'socks_fmt.dart';
import 'ssh_fmt.dart';
import 'trojan_fmt.dart';
import 'trojan_go_fmt.dart';
import 'tuic_fmt.dart';
import 'vmess_fmt.dart';
import 'vless_fmt.dart';
import 'wireguard_fmt.dart';

/// 订阅文本解析统一入口:自动识别单链接 / Clash YAML / sing-box JSON。
class UniversalFmt {
  UniversalFmt._();

  /// 解析一条分享链接,返回 Profile。
  static Profile parseLink(String link) {
    final trimmed = link.trim();
    if (trimmed.isEmpty) {
      throw FormatException('链接为空');
    }
    final schemeEnd = trimmed.indexOf('://');
    if (schemeEnd < 0) {
      // 兼容 sn:// 无 :// 形式(原版私有格式,已不再支持 Kryo 二进制)
      if (trimmed.startsWith('sn://')) {
        throw FormatException('原版 sn:// 私有格式已不支持,请使用标准链接');
      }
      throw FormatException('无法识别的链接: $trimmed');
    }
    final scheme = trimmed.substring(0, schemeEnd).toLowerCase();
    switch (scheme) {
      case 'ss':
        return ShadowsocksFmt.parse(trimmed);
      case 'vmess':
        return VMessFmt.parse(trimmed);
      case 'vless':
        return VLESSFmt.parse(trimmed);
      case 'trojan':
        return TrojanFmt.parse(trimmed);
      case 'hysteria':
        return Hysteria1Fmt.parse(trimmed);
      case 'hysteria2':
      case 'hy2':
        return Hysteria2Fmt.parse(trimmed);
      case 'trojan-go':
        return TrojanGoFmt.parse(trimmed);
      case 'naive':
      case 'naive+https':
        return NaiveFmt.parse(trimmed);
      case 'mieru':
        return MieruFmt.parse(trimmed);
      case 'tuic':
        return TuicFmt.parse(trimmed);
      case 'socks':
      case 'socks4':
      case 'socks5':
        return SocksFmt.parse(trimmed);
      case 'http':
      case 'https':
        return HttpFmt.parse(trimmed);
      case 'ssh':
        return SSHfmt.parse(trimmed);
      case 'anytls':
        return AnyTLSFmt.parse(trimmed);
      case 'shadowtls':
        return ShadowTLSFmt.parse(trimmed);
      case 'wg':
      case 'wireguard':
        return WireGuardFmt.parse(trimmed);
      default:
        throw FormatException('不支持的链接协议: $scheme');
    }
  }

  /// 解析订阅文本(可能包含多行链接 / Clash YAML / sing-box JSON)。
  static List<Profile> parseSubscriptionText(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return [];

    // sing-box JSON(以 [ 或 {"outbounds" 开头)
    final firstChar = trimmed.substring(0, 1);
    if (firstChar == '[' || trimmed.startsWith('{"outbounds"')) {
      return SingBoxJsonFmt.parse(trimmed);
    }

    // Clash YAML(包含 proxies: 且不是链接)
    if (trimmed.contains('proxies:') &&
        !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://')) {
      try {
        return ClashFmt.parse(trimmed);
      } on FormatException {
        // 落到逐行解析
      }
    }

    // 逐行解析链接
    final result = <Profile>[];
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      // 跳过注释
      if (l.startsWith('#') || l.startsWith('//')) continue;
      try {
        result.add(parseLink(l));
      } on FormatException {
        // 忽略无法解析的行
        continue;
      }
    }
    return result;
  }

  /// 从剪贴板文本中提取所有可识别的链接。
  static List<Profile> parseClipboard(String text) {
    final profiles = <Profile>[];
    final seen = <String>{};
    final reg = RegExp(
        r'(?<![A-Za-z0-9])(ss|vmess|vless|trojan|trojan-go|hysteria2|hysteria|'
        r'hy2|tuic|socks5?|http|https|ssh|anytls|shadowtls|wg|wireguard|'
        r'naive\+https|naive|mieru)://[^\s]+',
        caseSensitive: false);
    for (final m in reg.allMatches(text)) {
      final link = m.group(0)!;
      if (seen.contains(link)) continue;
      seen.add(link);
      try {
        profiles.add(parseLink(link));
      } on FormatException {
        continue;
      }
    }
    return profiles;
  }

  /// 生成分享链接(仅支持可导出的协议)。
  static String export(Profile p) {
    switch (p.type) {
      case ProfileType.shadowsocks:
        return ShadowsocksFmtExport.export(p);
      case ProfileType.vmess:
        return VMessFmtExport.export(p);
      case ProfileType.vless:
        return VLESSFmtExport.export(p);
      case ProfileType.trojan:
        return TrojanFmtExport.export(p);
      case ProfileType.tuic:
        return TuicFmtExport.export(p);
      case ProfileType.hysteria2:
        return Hysteria2FmtExport.export(p);
      case ProfileType.http:
        return HttpFmtExport.export(p);
      case ProfileType.socks:
        return SocksFmtExport.export(p);
      case ProfileType.ssh:
        return SSHfmtExport.export(p);
      case ProfileType.hysteria:
        return Hysteria1FmtExport.export(p);
      case ProfileType.naive:
        return NaiveFmtExport.export(p);
      case ProfileType.trojanGo:
        return TrojanGoFmtExport.export(p);
      default:
        throw FormatException('该协议暂不支持导出: ${ProfileType.displayName(p.type)}');
    }
  }
}
