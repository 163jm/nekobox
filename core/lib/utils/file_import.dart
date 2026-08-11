import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../fmt/universal_fmt.dart';
import '../models/profile.dart';
import '../models/profile_type.dart';

/// 文件导入工具类,处理 .txt/.conf/.zip 文件的代理配置导入。
class FileImport {
  FileImport._();

  /// 从文件路径导入代理配置。
  /// 支持的格式:
  /// - .txt / .conf: 逐行读取分享链接,通过 [UniversalFmt.parseLink] 解析
  /// - .zip: 解压后识别 WireGuard 配置文件(.conf/.wg) 和代理列表文件(.txt)
  ///
  /// [onProgress] 进度回调:
  /// - [current] 当前处理的条目序号(从 1 开始)
  /// - [total] zip 文件总条目数
  /// - [fileName] 当前处理的文件名
  static Future<List<Profile>> importFromFile(
    String filePath, {
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    final extension = p.extension(filePath).toLowerCase();
    switch (extension) {
      case '.txt':
      case '.conf':
      case '.text':
        return _importTextFile(filePath);
      case '.zip':
        return _importZipFile(filePath, onProgress: onProgress);
      default:
        throw FormatException(
          '不支持的文件格式: "$extension"。支持 .txt / .conf / .zip',
        );
    }
  }

  /// 打开系统文件选择器,选择文件后自动导入。
  static Future<List<Profile>> pickAndImport({
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'conf', 'zip'],
    );
    if (result == null || result.files.isEmpty) {
      throw Exception('未选择文件');
    }
    final path = result.files.single.path;
    if (path == null || path!.isEmpty) {
      throw Exception('文件路径为空');
    }
    return importFromFile(path, onProgress: onProgress);
  }

  static Future<List<Profile>> _importTextFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }
    final content = await file.readAsString();
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw Exception('文件内容为空');
    }
    return UniversalFmt.parseSubscriptionText(content);
  }

  static Future<List<Profile>> _importZipFile(
    String filePath, {
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final bytes = await file.readAsBytes();

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw Exception('ZIP 解压失败: $e');
    }

    final entries = archive.toList();
    final profiles = <Profile>[];
    final total = entries.length;
    var current = 0;
    final errors = <String>[];

    for (final entry in entries) {
      current++;
      final name = entry.name;
      onProgress?.call(current, total, name);

      if (!entry.isFile) continue;

      final lowerName = name.toLowerCase();

      if (lowerName.endsWith('.conf') || lowerName.endsWith('.wg')) {
        try {
          final content = _entryToString(entry);
          final wgProfiles = _parseWireGuardConf(content, name);
          profiles.addAll(wgProfiles);
        } catch (e) {
          errors.add('$name: ${e.toString()}');
        }
        continue;
      }

      if (lowerName.endsWith('.txt')) {
        try {
          final content = _entryToString(entry);
          final subProfiles = UniversalFmt.parseSubscriptionText(content);
          profiles.addAll(subProfiles);
        } catch (e) {
          errors.add('$name: ${e.toString()}');
        }
        continue;
      }
    }

    if (profiles.isEmpty && errors.isNotEmpty) {
      throw Exception(
        '未能从 ZIP 中解析出任何代理配置:\n${errors.join('\n')}',
      );
    }

    return profiles;
  }

  static String _entryToString(dynamic entry) {
    final data = entry.content;
    if (data is Uint8List) {
      return utf8.decode(data);
    }
    return utf8.decode(data as List<int>);
  }

  /// 解析 WireGuard .conf 配置文件(INI 格式)。
  /// 支持 [Interface] 和 [Peer] 段,可包含多个 [Peer]。
  static List<Profile> _parseWireGuardConf(String content, String fileName) {
    final lines = content.split('\n');
    final interface = <String, String>{};
    final peers = <Map<String, String>>[];
    var currentSection = '';
    Map<String, String>? currentPeer;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final section = trimmed.substring(1, trimmed.length - 1).toLowerCase();
        if (section == 'interface') {
          currentSection = 'interface';
        } else if (section == 'peer') {
          currentSection = 'peer';
          if (currentPeer != null && currentPeer!.isNotEmpty) {
            peers.add(currentPeer!);
          }
          currentPeer = {};
        }
        continue;
      }

      final eqIdx = trimmed.indexOf('=');
      if (eqIdx < 0) continue;
      final key = trimmed.substring(0, eqIdx).trim().toLowerCase();
      final value = trimmed.substring(eqIdx + 1).trim();

      if (currentSection == 'interface') {
        interface[key] = value;
      } else if (currentSection == 'peer' && currentPeer != null) {
        currentPeer![key] = value;
      }
    }
    if (currentPeer != null && currentPeer!.isNotEmpty) {
      peers.add(currentPeer!);
    }

    if (peers.isEmpty) return [];

    final profiles = <Profile>[];
    final baseName = p.basenameWithoutExtension(fileName);

    for (final peer in peers) {
      final publicKey = peer['publickey'] ?? '';
      final endpoint = peer['endpoint'] ?? '';
      final presharedKey = peer['presharedkey'] ?? '';
      final allowedIps = peer['allowedips'] ?? '0.0.0.0/0,::/0';
      final privateKey = interface['privatekey'] ?? '';
      final address = interface['address'] ?? '10.0.0.1/32';
      final mtu = int.tryParse(interface['mtu'] ?? '') ?? 1420;
      final dns = interface['dns'] ?? '';

      if (publicKey.isEmpty || endpoint.isEmpty) continue;

      String serverAddress = endpoint;
      int serverPort = 51820;
      final colonIdx = endpoint.lastIndexOf(':');
      if (colonIdx > 0) {
        serverAddress = endpoint.substring(0, colonIdx);
        serverPort = int.tryParse(endpoint.substring(colonIdx + 1)) ?? 51820;
      }

      profiles.add(Profile(
        type: ProfileType.wireguard,
        name: baseName,
        serverAddress: serverAddress,
        serverPort: serverPort,
        bean: {
          'privateKey': privateKey,
          'localAddress': address,
          'peers': [
            {
              'publicKey': publicKey,
              'preSharedKey': presharedKey,
              'allowedIps': allowedIps,
            },
          ],
          'mtu': mtu,
          if (dns.isNotEmpty) 'dns': dns,
        },
      ));
    }

    return profiles;
  }
}