import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

// ──────────────────────────────────────────────────────────
// STUN Protocol (RFC 5389) Constants
// ──────────────────────────────────────────────────────────

const int _stunBindingRequest = 0x0001;
const int _stunBindingSuccessResponse = 0x0101;
const int _stunBindingErrorResponse = 0x0111;
const int _stunMagicCookie = 0x2112A442;

const int _attrMappedAddress = 0x0001;
const int _attrXorMappedAddress = 0x0020;
const int _attrResponseOrigin = 0x802B;
const int _attrOtherAddress = 0x802C;

const List<_StunServer> _stunServers = [
  _StunServer('stun.stunprotocol.org', 3478),
  _StunServer('stunserver.stunprotocol.org', 3478),
  _StunServer('stun.l.google.com', 3478),
  _StunServer('stun1.l.google.com', 3478),
];

const List<_LatencyServer> _latencyServers = [
  _LatencyServer('stun.stunprotocol.org', 3478),
  _LatencyServer('stunserver.stunprotocol.org', 3478),
  _LatencyServer('stun.l.google.com', 3478),
  _LatencyServer('stun1.l.google.com', 3478),
];

// ──────────────────────────────────────────────────────────
// Data Models
// ──────────────────────────────────────────────────────────

enum NatType {
  blocked,
  open,
  fullCone,
  restrictedCone,
  portRestrictedCone,
  symmetric,
  unknown,
}

class _StunServer {
  final String host;
  final int port;
  const _StunServer(this.host, this.port);
}

class _LatencyServer {
  final String host;
  final int port;
  const _LatencyServer(this.host, this.port);
}

class _ExternalIpResult {
  final String ip;
  final int port;
  final String sourceHost;
  final int latencyMs;
  _ExternalIpResult(this.ip, this.port, this.sourceHost, this.latencyMs);
}

class _NatResult {
  final NatType type;
  final String externalIp;
  final int externalPort;
  final String description;
  _NatResult(this.type, this.externalIp, this.externalPort, this.description);
}

class _LatencyResult {
  final String host;
  final int latencyMs;
  final bool success;
  _LatencyResult(this.host, this.latencyMs, this.success);
}

class _SpeedResult {
  final double downloadMbps;
  final double uploadMbps;
  _SpeedResult(this.downloadMbps, this.uploadMbps);
}

class _TestProgress {
  final int current;
  final int total;
  final String stage;
  final String detail;
  const _TestProgress(this.current, this.total, this.stage, this.detail);
}

// ──────────────────────────────────────────────────────────
// STUN Message Implementation
// ──────────────────────────────────────────────────────────

class _StunMessage {
  final int type;
  final List<int> transactionId;
  final Map<int, List<int>> attributes;

  _StunMessage({
    required this.type,
    required this.transactionId,
    this.attributes = const {},
  });

  List<int> encode() {
    final buffer = <int>[];
    final attrData = <int>[];
    attributes.forEach((type, value) {
      attrData.addAll(_writeUint16(type));
      attrData.addAll(_writeUint16(value.length));
      attrData.addAll(value);
      final padLen = (4 - (value.length % 4)) % 4;
      for (var i = 0; i < padLen; i++) {
        attrData.add(0);
      }
    });
    buffer.addAll(_writeUint16(type));
    buffer.addAll(_writeUint16(attrData.length));
    buffer.addAll(_writeUint32(_stunMagicCookie));
    buffer.addAll(transactionId);
    buffer.addAll(attrData);
    return buffer;
  }

  static _StunMessage decode(List<int> data) {
    if (data.length < 20) throw const FormatException('STUN message too short');
    final type = _readUint16(data, 0);
    final length = _readUint16(data, 2);
    final magic = _readUint32(data, 4);
    if (magic != _stunMagicCookie) {
      throw const FormatException('Invalid STUN magic cookie');
    }
    final transactionId = data.sublist(8, 20);
    final attributes = <int, List<int>>{};
    var offset = 20;
    final end = 20 + length;
    while (offset < end) {
      final attrType = _readUint16(data, offset);
      final attrLen = _readUint16(data, offset + 2);
      offset += 4;
      final value = data.sublist(offset, offset + attrLen);
      attributes[attrType] = value;
      offset += attrLen;
      final padLen = (4 - (attrLen % 4)) % 4;
      offset += padLen;
    }
    return _StunMessage(
      type: type,
      transactionId: transactionId,
      attributes: attributes,
    );
  }

  static List<int> _writeUint16(int value) {
    return [(value >> 8) & 0xFF, value & 0xFF];
  }

  static List<int> _writeUint32(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  static int _readUint16(List<int> data, int offset) {
    return (data[offset] << 8) | data[offset + 1];
  }

  static int _readUint32(List<int> data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }
}

// ──────────────────────────────────────────────────────────
// STUN Client
// ──────────────────────────────────────────────────────────

class _StunClient {
  final _random = Random();

  List<int> _generateTransactionId() {
    return List.generate(12, (_) => _random.nextInt(256));
  }

  Future<_ExternalIpResult?> getExternalIp(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final transactionId = _generateTransactionId();
    final request = _StunMessage(
      type: _stunBindingRequest,
      transactionId: transactionId,
    );

    final tcpResult = await _getExternalIpTcp(
      host,
      port,
      transactionId,
      request,
      timeout,
    );
    if (tcpResult != null) return tcpResult;

    return _getExternalIpUdp(
      host,
      port,
      transactionId,
      request,
      timeout,
    );
  }

  Future<_ExternalIpResult?> _getExternalIpTcp(
    String host,
    int port,
    List<int> transactionId,
    _StunMessage request,
    Duration timeout,
  ) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: timeout,
      );
      final completer = Completer<_ExternalIpResult?>();
      final buffer = <int>[];

      socket.add(request.encode());

      socket.listen(
        (data) {
          buffer.addAll(data);
          if (buffer.length >= 20) {
            try {
              final msg = _StunMessage.decode(buffer);
              if (msg.type == _stunBindingSuccessResponse &&
                  _listEquals(msg.transactionId, transactionId)) {
                final result = _parseStunAttributes(msg, host);
                if (!completer.isCompleted) completer.complete(result);
              } else {
                if (!completer.isCompleted) completer.complete(null);
              }
            } catch (_) {
              if (!completer.isCompleted) completer.complete(null);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
          try {
            socket.destroy();
          } catch (_) {}
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      final result = await completer.future.timeout(timeout, onTimeout: () {
        try {
          socket.destroy();
        } catch (_) {}
        return null;
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<_ExternalIpResult?> _getExternalIpUdp(
    String host,
    int port,
    List<int> transactionId,
    _StunMessage request,
    Duration timeout,
  ) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      final completer = Completer<_ExternalIpResult?>();

      socket.send(request.encode(), InternetAddress(host), 3478);

      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram == null) return;
            try {
              final msg = _StunMessage.decode(datagram.data);
              if (msg.type == _stunBindingSuccessResponse &&
                  _listEquals(msg.transactionId, transactionId)) {
                final result = _parseStunAttributes(msg, host);
                if (!completer.isCompleted) completer.complete(result);
              }
            } catch (_) {
              if (!completer.isCompleted) completer.complete(null);
            }
          } else if (event == RawSocketEvent.closed) {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      final result = await completer.future.timeout(timeout, onTimeout: () {
        try {
          socket.close();
        } catch (_) {}
        return null;
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  _ExternalIpResult? _parseStunAttributes(
    _StunMessage msg,
    String sourceHost,
  ) {
    final xorAddr = msg.attributes[_attrXorMappedAddress];
    if (xorAddr != null && xorAddr.length >= 8) {
      return _parseXorMappedAddress(xorAddr, msg.transactionId, sourceHost);
    }
    final mappedAddr = msg.attributes[_attrMappedAddress];
    if (mappedAddr != null && mappedAddr.length >= 8) {
      return _parseMappedAddress(mappedAddr, sourceHost);
    }
    return null;
  }

  _ExternalIpResult _parseXorMappedAddress(
    List<int> data,
    List<int> transactionId,
    String sourceHost,
  ) {
    final family = data[0];
    final xorPort = (data[1] << 8) | data[2];
    final port = xorPort ^ ((_stunMagicCookie >> 16) & 0xFFFF);

    String ip;
    if (family == 0x0001) {
      final ipBytes = List<int>.generate(4, (i) {
        return data[3 + i] ^ ((_stunMagicCookie >> (24 - i * 8)) & 0xFF);
      });
      ip = ipBytes.join('.');
    } else {
      final ipBytes = <int>[];
      for (var i = 0; i < 16; i++) {
        final byte = data[3 + i];
        if (i < 4) {
          ipBytes.add(byte ^ ((_stunMagicCookie >> (24 - i * 8)) & 0xFF));
        } else {
          ipBytes.add(byte ^ transactionId[i - 4]);
        }
      }
      final buffer = StringBuffer();
      for (var i = 0; i < 16; i += 2) {
        if (i > 0) buffer.write(':');
        buffer.write(ipBytes[i].toRadixString(16).padLeft(2, '0'));
        buffer.write(ipBytes[i + 1].toRadixString(16).padLeft(2, '0'));
      }
      ip = buffer.toString();
    }

    return _ExternalIpResult(ip, port, sourceHost, 0);
  }

  _ExternalIpResult _parseMappedAddress(
    List<int> data,
    String sourceHost,
  ) {
    final family = data[0];
    final port = (data[1] << 8) | data[2];
    String ip;
    if (family == 0x0001) {
      ip = '${data[3]}.${data[4]}.${data[5]}.${data[6]}';
    } else {
      final buffer = StringBuffer();
      for (var i = 3; i < 19; i += 2) {
        if (i > 3) buffer.write(':');
        buffer.write(data[i].toRadixString(16).padLeft(2, '0'));
        buffer.write(data[i + 1].toRadixString(16).padLeft(2, '0'));
      }
      ip = buffer.toString();
    }
    return _ExternalIpResult(ip, port, sourceHost, 0);
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<_NatResult> detectNatType() async {
    final serverResults = <_ExternalIpResult>[];

    for (final server in _stunServers) {
      final result = await getExternalIp(server.host, server.port);
      if (result != null) {
        serverResults.add(result);
      }
      if (serverResults.length >= 3) break;
    }

    if (serverResults.isEmpty) {
      return _NatResult(
        NatType.blocked,
        '',
        0,
        '无法连接到 STUN 服务器，可能被防火墙阻断或无网络连接',
      );
    }

    final first = serverResults.first;

    if (serverResults.length == 1) {
      return _NatResult(
        NatType.unknown,
        first.ip,
        first.port,
        '仅连接到一个 STUN 服务器，无法确定 NAT 类型。外部 IP: ${first.ip}:${first.port}',
      );
    }

    final allSameIp = serverResults.every((r) => r.ip == first.ip);
    final allSamePort = serverResults.every((r) => r.port == first.port);

    if (!allSameIp || !allSamePort) {
      final reason = !allSameIp
          ? '不同服务器返回不同的外部 IP'
          : '同一 IP 但不同端口';
      return _NatResult(
        NatType.symmetric,
        first.ip,
        first.port,
        '对称 NAT：$reason。外部 IP: ${first.ip}:${first.port}',
      );
    }

    final localIp = await _getLocalIp();
    if (localIp == first.ip) {
      return _NatResult(
        NatType.open,
        first.ip,
        first.port,
        '开放网络：本地 IP 与外部 IP 相同，无 NAT',
      );
    }

    if (serverResults.length >= 3) {
      return _NatResult(
        NatType.fullCone,
        first.ip,
        first.port,
        '全锥形 NAT：多台服务器返回相同的外部映射，外部主机可通过固定端口访问',
      );
    }

    return _NatResult(
      NatType.restrictedCone,
      first.ip,
      first.port,
      '受限 NAT：外部 IP 固定但端口受限，仅已通信的主机可访问',
    );
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type.name == 'IPv4' && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}

// ──────────────────────────────────────────────────────────
// Latency Tester
// ──────────────────────────────────────────────────────────

class _LatencyTester {
  Future<List<_LatencyResult>> testAll(
    List<_LatencyServer> servers, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final results = <_LatencyResult>[];
    for (final server in servers) {
      final result = await _testOne(server, timeout: timeout);
      results.add(result);
    }
    return results;
  }

  Future<_LatencyResult> _testOne(
    _LatencyServer server, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server.host,
        server.port,
        timeout: timeout,
      );
      sw.stop();
      try {
        socket.destroy();
      } catch (_) {}
      return _LatencyResult(server.host, sw.elapsedMilliseconds, true);
    } catch (e) {
      sw.stop();
      return _LatencyResult(server.host, -1, false);
    }
  }
}

// ──────────────────────────────────────────────────────────
// Speed Tester
// ──────────────────────────────────────────────────────────

class _SpeedTester {
  Future<_SpeedResult> testDownload({
    String url = 'https://speed.hetzner.de/10MB.bin',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<_SpeedResult>();
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'NekoBox/1.0');

      final response = await request.close().timeout(timeout);
      final sw = Stopwatch()..start();
      var bytesReceived = 0;

      response.listen(
        (data) {
          bytesReceived += data.length;
        },
        onDone: () {
          sw.stop();
          final seconds = sw.elapsedMicroseconds / 1000000;
          if (seconds > 0) {
            final speedMbps = (bytesReceived * 8) / (seconds * 1000000);
            completer.complete(_SpeedResult(speedMbps, 0));
          } else {
            completer.complete(_SpeedResult(0, 0));
          }
          try {
            client.close();
          } catch (_) {}
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(_SpeedResult(0, 0));
          try {
            client.close();
          } catch (_) {}
        },
      );
    } catch (e) {
      if (!completer.isCompleted) completer.complete(_SpeedResult(0, 0));
    }

    return completer.future.timeout(timeout, onTimeout: () {
      return _SpeedResult(0, 0);
    });
  }

  Future<double> testUpload({
    String url = 'https://httpbin.org/post',
    int sizeBytes = 512 * 1024,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;

      final request = await client.postUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      request.headers.set(HttpHeaders.userAgentHeader, 'NekoBox/1.0');

      final random = Random(42);
      final data = List<int>.generate(sizeBytes, (_) => random.nextInt(256));

      final sw = Stopwatch()..start();
      request.add(data);

      final response = await request.close().timeout(timeout);
      await response.drain();
      sw.stop();

      try {
        client.close();
      } catch (_) {}

      final seconds = sw.elapsedMicroseconds / 1000000;
      if (seconds > 0) {
        return (sizeBytes * 8) / (seconds * 1000000);
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}

// ──────────────────────────────────────────────────────────
// STUN Test Page
// ──────────────────────────────────────────────────────────

class StunPage extends StatefulWidget {
  const StunPage({super.key});

  @override
  State<StunPage> createState() => _StunPageState();
}

class _StunPageState extends State<StunPage> {
  final _stunClient = _StunClient();
  final _latencyTester = _LatencyTester();
  final _speedTester = _SpeedTester();

  bool _testing = false;
  _TestProgress? _progress;

  _NatResult? _natResult;
  List<_LatencyResult> _latencyResults = [];
  _SpeedResult? _speedResult;

  String _externalIp = '';
  int _externalIpPort = 0;

  Future<void> _runAllTests() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _natResult = null;
      _latencyResults = [];
      _speedResult = null;
      _progress = const _TestProgress(0, 4, '初始化', '准备开始网络诊断…');
    });

    try {
      if (!mounted) return;

      setState(() {
        _progress = const _TestProgress(1, 4, 'NAT 类型检测', '正在通过 STUN 检测 NAT 类型…');
      });
      final natResult = await _stunClient.detectNatType();
      if (!mounted) return;
      setState(() {
        _natResult = natResult;
        _externalIp = natResult.externalIp;
        _externalIpPort = natResult.externalPort;
      });

      setState(() {
        _progress = const _TestProgress(2, 4, '延迟测试', '正在测试多台服务器延迟…');
      });
      final latencyResults = await _latencyTester.testAll(_latencyServers);
      if (!mounted) return;
      setState(() {
        _latencyResults = latencyResults;
      });

      setState(() {
        _progress = const _TestProgress(3, 4, '下载测速', '正在测试下载速度…');
      });
      final downloadResult = await _speedTester.testDownload();
      if (!mounted) return;
      setState(() {
        _speedResult = downloadResult;
      });

      setState(() {
        _progress = const _TestProgress(4, 4, '上传测速', '正在测试上传速度…');
      });
      final uploadSpeed = await _speedTester.testUpload();
      if (!mounted) return;
      setState(() {
        _speedResult = _SpeedResult(
          _speedResult?.downloadMbps ?? 0,
          uploadSpeed,
        );
      });

      if (mounted) {
        setState(() {
          _progress = null;
          _testing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络诊断完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _testing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试异常: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('网络诊断')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStartButton(scheme),
            const SizedBox(height: 16),
            if (_progress != null) _buildProgressCard(scheme),
            if (_testing) const SizedBox(height: 16),
            if (!_testing) ...[
              _buildNatCard(scheme),
              const SizedBox(height: 12),
              _buildExternalIpCard(scheme),
              const SizedBox(height: 12),
              _buildLatencyCard(scheme),
              const SizedBox(height: 12),
              _buildSpeedCard(scheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton(ColorScheme scheme) {
    return FilledButton.icon(
      onPressed: _testing ? null : _runAllTests,
      icon: _testing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(_testing ? '测试进行中…' : '开始网络诊断'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }

  Widget _buildProgressCard(ColorScheme scheme) {
    final progress = _progress!;
    final step = progress.current / progress.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.network_check, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.stage,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              Text(
                '${progress.current}/${progress.total}',
                style: TextStyle(
                  color: scheme.onPrimaryContainer.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: step,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress.detail,
            style: TextStyle(
              color: scheme.onPrimaryContainer.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNatCard(ColorScheme scheme) {
    final result = _natResult;
    if (result == null) {
      return _buildPlaceholderCard(
        scheme,
        icon: Icons.language,
        title: 'NAT 类型',
        subtitle: '尚未测试',
      );
    }

    final statusColor = _getNatColor(result.type, scheme);
    final icon = _getNatIcon(result.type);
    final label = _getNatLabel(result.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NAT 类型',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  result.type == NatType.blocked ? '异常' : '正常',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.description,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 13,
            ),
          ),
          if (result.externalIp.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '外部端口: ${result.externalIp}:${result.externalPort}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExternalIpCard(ColorScheme scheme) {
    if (_externalIp.isEmpty) {
      return _buildPlaceholderCard(
        scheme,
        icon: Icons.language,
        title: '外部 IP',
        subtitle: '尚未测试',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.public, color: scheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '外部 IP 地址',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _externalIp,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: scheme.onSurface,
                  ),
                ),
                if (_externalIpPort > 0)
                  Text(
                    '端口: $_externalIpPort',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyCard(ColorScheme scheme) {
    if (_latencyResults.isEmpty) {
      return _buildPlaceholderCard(
        scheme,
        icon: Icons.speed,
        title: '服务器延迟',
        subtitle: '尚未测试',
      );
    }

    final avgLatency = _latencyResults
        .where((r) => r.success)
        .map((r) => r.latencyMs)
        .isEmpty
        ? 0
        : _latencyResults
                .where((r) => r.success)
                .map((r) => r.latencyMs)
                .reduce((a, b) => a + b) /
            _latencyResults.where((r) => r.success).length;

    final minLatency = _latencyResults
        .where((r) => r.success)
        .map((r) => r.latencyMs)
        .isEmpty
        ? 0
        : _latencyResults
            .where((r) => r.success)
            .map((r) => r.latencyMs)
            .reduce((a, b) => a < b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.timer, color: scheme.tertiary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '服务器延迟',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLatencyStat(
                  scheme,
                  '平均',
                  avgLatency > 0 ? '${avgLatency.toStringAsFixed(0)} ms' : '-',
                  scheme.tertiary,
                ),
              ),
              Expanded(
                child: _buildLatencyStat(
                  scheme,
                  '最低',
                  minLatency > 0 ? '$minLatency ms' : '-',
                  Colors.green,
                ),
              ),
              Expanded(
                child: _buildLatencyStat(
                  scheme,
                  '成功',
                  '${_latencyResults.where((r) => r.success).length}/${_latencyResults.length}',
                  scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._latencyResults.map((r) => _buildLatencyTile(scheme, r)),
        ],
      ),
    );
  }

  Widget _buildLatencyStat(
    ColorScheme scheme,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLatencyTile(ColorScheme scheme, _LatencyResult result) {
    final color = !result.success
        ? scheme.error
        : result.latencyMs < 100
            ? Colors.green
            : result.latencyMs < 300
                ? Colors.orange
                : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.host,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            result.success ? '${result.latencyMs} ms' : '超时',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedCard(ColorScheme scheme) {
    final result = _speedResult;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.speed, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                '网络速度',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSpeedStat(
                  scheme,
                  Icons.download,
                  '下载',
                  result?.downloadMbps ?? 0,
                  scheme.primary,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: scheme.outlineVariant,
              ),
              Expanded(
                child: _buildSpeedStat(
                  scheme,
                  Icons.upload,
                  '上传',
                  result?.uploadMbps ?? 0,
                  scheme.tertiary,
                ),
              ),
            ],
          ),
          if (result == null) ...[
            const SizedBox(height: 12),
            Text(
              '尚未测试',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeedStat(
    ColorScheme scheme,
    IconData icon,
    String label,
    double speedMbps,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          speedMbps > 0 ? speedMbps.toStringAsFixed(2) : '-',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          'Mbps',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderCard(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.outlineVariant.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.outline, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.outline,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getNatColor(NatType type, ColorScheme scheme) {
    switch (type) {
      case NatType.open:
        return Colors.green;
      case NatType.fullCone:
        return Colors.teal;
      case NatType.restrictedCone:
        return Colors.blue;
      case NatType.portRestrictedCone:
        return Colors.orange;
      case NatType.symmetric:
        return Colors.deepOrange;
      case NatType.blocked:
        return scheme.error;
      case NatType.unknown:
        return scheme.outline;
    }
  }

  IconData _getNatIcon(NatType type) {
    switch (type) {
      case NatType.open:
        return Icons.check_circle;
      case NatType.fullCone:
        return Icons.public;
      case NatType.restrictedCone:
        return Icons.security;
      case NatType.portRestrictedCone:
        return Icons.shield;
      case NatType.symmetric:
        return Icons.swap_horiz;
      case NatType.blocked:
        return Icons.block;
      case NatType.unknown:
        return Icons.help;
    }
  }

  String _getNatLabel(NatType type) {
    switch (type) {
      case NatType.open:
        return '开放 (Open)';
      case NatType.fullCone:
        return '全锥形 (Full Cone)';
      case NatType.restrictedCone:
        return '受限锥形 (Restricted)';
      case NatType.portRestrictedCone:
        return '端口受限 (Port-Restricted)';
      case NatType.symmetric:
        return '对称 (Symmetric)';
      case NatType.blocked:
        return '被阻断 (Blocked)';
      case NatType.unknown:
        return '未知';
    }
  }
}