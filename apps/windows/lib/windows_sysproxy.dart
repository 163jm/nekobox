import 'dart:ffi';
import 'dart:io';

/// Windows 系统代理设置:注册表 + wininet 通知刷新。
class WindowsSystemProxy {
  WindowsSystemProxy._();

  static const String _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // 启用前保存的原系统代理状态(断开时恢复,不覆盖用户原有配置)
  static bool? _originalEnabled;
  static String? _originalServer;

  /// 启用系统代理。首次启用时记录用户原有代理配置,断开时恢复。
  static Future<void> enable(String proxyServer) async {
    if (_originalEnabled == null) {
      _originalEnabled = await isEnabled();
      _originalServer = await _queryReg('ProxyServer');
    }
    await _setReg('ProxyEnable', 'REG_DWORD', '1');
    await _setReg('ProxyServer', 'REG_SZ', proxyServer);
    await _notifySettingsChanged();
  }

  /// 关闭系统代理。若用户原本就有代理,恢复其原配置;
  /// 否则仅关闭开关(保留 ProxyServer 值,下次启用直接复用)。
  static Future<void> disable() async {
    if (_originalEnabled == true && _originalServer != null) {
      await _setReg('ProxyEnable', 'REG_DWORD', '1');
      await _setReg('ProxyServer', 'REG_SZ', _originalServer!);
    } else {
      await _setReg('ProxyEnable', 'REG_DWORD', '0');
    }
    await _notifySettingsChanged();
  }

  /// 查询是否已启用。
  static Future<bool> isEnabled() async {
    final value = await _queryReg('ProxyEnable');
    if (value == null) return false;
    final m = RegExp(r'0x([0-9a-fA-F]+)').firstMatch(value);
    if (m != null) {
      return int.parse(m.group(1)!, radix: 16) != 0;
    }
    return value.trim() == '1';
  }

  /// 读取注册表字符串值;不存在返回 null。
  static Future<String?> _queryReg(String name) async {
    try {
      final result = await Process.run('reg', [
        'query',
        _regPath,
        '/v',
        name,
      ]);
      final out = (result.stdout as String?) ?? '';
      // 输出形如 ProxyServer REG_SZ 127.0.0.1:8080
      final lines = out.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('!') ||
            trimmed.startsWith('HKEY') || trimmed.startsWith('reg')) {
          continue;
        }
        final parts = trimmed.split(RegExp(r'\s{2,}'));
        if (parts.length >= 3 && parts[1].startsWith('REG_')) {
          return parts.sublist(2).join(' ').trim();
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _setReg(
      String name, String type, String value) async {
    await Process.run('reg', [
      'add',
      _regPath,
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
  }

  /// 通知 WinINet 设置已变更(立即生效)。
  static Future<void> _notifySettingsChanged() async {
    await _internetSetOption(39); // INTERNET_OPTION_SETTINGS_CHANGED
    await _internetSetOption(37); // INTERNET_OPTION_REFRESH
  }

  static Future<void> _internetSetOption(int option) async {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final func = wininet.lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Int32),
          int Function(Pointer<Void>, int, Pointer<Void>, int)>(
        'InternetSetOptionW',
      );
      func(Pointer<Void>.fromAddress(0), option,
          Pointer<Void>.fromAddress(0), 0);
    } catch (_) {
      // 通知失败不影响注册表生效,部分应用会在下次刷新时生效
    }
  }
}
