import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// Mieru 链接解析(对齐原版 MieruBean)。
/// mieru://host:port?mport=xxx&mtu=xxx&cipher=xxx&hash=xxx&username=xxx&password=xxx#name
///
/// ⚠️ sing-box 不支持 Mieru 协议:链接可解析入库(保留信息),但
/// 连接时会明确提示不可用(ConfigBuilder 对 mieru 返回 null)。
class MieruFmt {
  MieruFmt._();

  static const String type = ProfileType.mieru;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 Mieru 链接: $raw');
    }
    final mport = UriUtil.strParam(uri, 'mport', '');
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: mport.isNotEmpty ? (int.tryParse(mport) ?? port) : port,
      bean: {
        'username': UriUtil.strParam(uri, 'username', ''),
        'password': UriUtil.strParam(uri, 'password', ''),
        'cipher': UriUtil.strParam(uri, 'cipher', ''),
        'hash': UriUtil.strParam(uri, 'hash', ''),
        'mtu': UriUtil.strParam(uri, 'mtu', ''),
      },
    );
  }
}
