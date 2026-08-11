import '../models/profile.dart';
import '../models/profile_type.dart';
import '../utils/uri_util.dart';

/// AnyTLS 链接解析与生成。
/// anytls://password@host:port?sni=...#name
class AnyTLSFmt {
  AnyTLSFmt._();

  static const String type = ProfileType.anytls;

  static Profile parse(String raw) {
    final uri = Uri.parse(raw);
    final password = Uri.decodeComponent(uri.userInfo);
    final host = uri.host;
    final port = uri.port != 0 ? uri.port : 443;
    if (host.isEmpty) {
      throw FormatException('无法解析 AnyTLS 链接: $raw');
    }
    return Profile(
      type: type,
      name: uri.fragment,
      serverAddress: host,
      serverPort: port,
      bean: {
        'password': password,
        'sni': UriUtil.strParam(uri, 'sni', ''),
        'fp': UriUtil.strParam(uri, 'fp', ''),
        'allowInsecure': UriUtil.strParam(uri, 'allowInsecure', '') == '1',
      },
    );
  }
}
