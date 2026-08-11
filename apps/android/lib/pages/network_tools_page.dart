import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class _PingResult {
  final int sequence;
  final int latencyMs;
  final bool success;
  final String? error;
  _PingResult(this.sequence, this.latencyMs, this.success, this.error);
}

class _TraceHop {
  final int ttl;
  final String? ip;
  final int latencyMs;
  final bool reached;
  final String? error;
  _TraceHop(this.ttl, this.ip, this.latencyMs, this.reached, this.error);
}

class _PortInfo {
  final int port;
  final String service;
  const _PortInfo(this.port, this.service);
}

class _PortScanResult {
  final int port;
  final String service;
  final bool isOpen;
  final int latencyMs;
  _PortScanResult(this.port, this.service, this.isOpen, this.latencyMs);
}

class _PingTool {
  Stream<_PingResult> ping(
    String host,
    int port,
    int count, {
    Duration timeout = const Duration(seconds: 2),
  }) async* {
    for (int i = 0; i < count; i++) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        sw.stop();
        final latency = sw.elapsedMilliseconds;
        yield _PingResult(i + 1, latency, true, null);
        try { socket.close(); } catch (_) {}
      } catch (e) {
        sw.stop();
        yield _PingResult(i + 1, -1, false, e.toString());
      }
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}

class _TracerouteTool {
  Stream<_TraceHop> trace(
    String host,
    int port, {
    int maxHops = 20,
    Duration timeout = const Duration(seconds: 3),
  }) async* {
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host);
      for (final addr in addresses) {
        yield _TraceHop(0, addr.address, 0, true, 'DNS 解析成功');
      }
    } catch (e) {
      yield _TraceHop(0, null, -1, false, 'DNS 解析失败: $e');
      return;
    }

    var reached = false;
    for (int ttl = 1; ttl <= maxHops; ttl++) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        sw.stop();
        yield _TraceHop(ttl, host, sw.elapsedMilliseconds, true, null);
        try { socket.close(); } catch (_) {}
        reached = true;
        break;
      } catch (e) {
        sw.stop();
        yield _TraceHop(ttl, null, sw.elapsedMilliseconds, false, e.toString());
      }
      if (reached) break;
    }
    if (!reached) {
      yield _TraceHop(maxHops, null, -1, false, '已达最大跳数');
    }
  }
}

class _PortScanner {
  static const List<_PortInfo> commonPorts = [
    _PortInfo(21, 'FTP'),
    _PortInfo(22, 'SSH'),
    _PortInfo(23, 'Telnet'),
    _PortInfo(25, 'SMTP'),
    _PortInfo(53, 'DNS'),
    _PortInfo(80, 'HTTP'),
    _PortInfo(110, 'POP3'),
    _PortInfo(143, 'IMAP'),
    _PortInfo(443, 'HTTPS'),
    _PortInfo(993, 'IMAPS'),
    _PortInfo(995, 'POP3S'),
    _PortInfo(3306, 'MySQL'),
    _PortInfo(3389, 'RDP'),
    _PortInfo(5432, 'PostgreSQL'),
    _PortInfo(6379, 'Redis'),
    _PortInfo(8080, 'HTTP Alt'),
    _PortInfo(8443, 'HTTPS Alt'),
  ];

  Stream<_PortScanResult> scan(
    String host, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async* {
    for (final info in commonPorts) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(host, info.port, timeout: timeout);
        sw.stop();
        yield _PortScanResult(
            info.port, info.service, true, sw.elapsedMilliseconds);
        try { socket.close(); } catch (_) {}
      } catch (e) {
        sw.stop();
        yield _PortScanResult(info.port, info.service, false, -1);
      }
    }
  }
}

class NetworkToolsPage extends StatefulWidget {
  const NetworkToolsPage({super.key});

  @override
  State<NetworkToolsPage> createState() => _NetworkToolsPageState();
}

class _NetworkToolsPageState extends State<NetworkToolsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络工具'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ping'),
            Tab(text: 'TCP 测试'),
            Tab(text: '端口扫描'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PingTab(),
          _TracerouteTab(),
          _PortScannerTab(),
        ],
      ),
    );
  }
}

class _PingTab extends StatefulWidget {
  @override
  State<_PingTab> createState() => _PingTabState();
}

class _PingTabState extends State<_PingTab> {
  final _hostCtrl = TextEditingController(text: 'google.com');
  final _portCtrl = TextEditingController(text: '80');
  final _countCtrl = TextEditingController(text: '4');

  final _pingTool = _PingTool();
  StreamSubscription<_PingResult>? _subscription;
  final List<_PingResult> _results = [];
  Stream<_PingResult>? _currentStream;
  bool _running = false;

  @override
  void dispose() {
    _subscription?.cancel();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 80;
    final count = int.tryParse(_countCtrl.text.trim()) ?? 4;

    setState(() {
      _running = true;
      _results.clear();
      _currentStream = _pingTool.ping(host, port, count);
    });

    _subscription?.cancel();
    _subscription = _currentStream!.listen((result) {
      if (!mounted) return;
      setState(() {
        _results.add(result);
      });
    }, onDone: () {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    });
  }

  void _stop() {
    _subscription?.cancel();
    setState(() {
      _running = false;
    });
  }

  void _clear() {
    _subscription?.cancel();
    setState(() {
      _running = false;
      _results.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildInputRow(scheme),
        Expanded(child: _buildResults(scheme)),
      ],
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标主机',
                    hintText: '例如 google.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _countCtrl,
                  decoration: const InputDecoration(
                    labelText: '次数',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? '停止' : '开始 Ping'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _running ? null : _clear,
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    if (_results.isEmpty && !_running) {
      return Center(
        child: Text(
          '点击开始 Ping 按钮开始测试',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (_results.isEmpty && _running) {
      return const Center(child: CircularProgressIndicator());
    }

    final successful = _results.where((r) => r.success);
    final avgLatency = successful.isEmpty
        ? 0
        : successful.map((r) => r.latencyMs).reduce((a, b) => a + b) /
            successful.length;
    final minLatency = successful.isEmpty
        ? 0
        : successful.map((r) => r.latencyMs).reduce((a, b) => a < b ? a : b);
    final maxLatency = successful.isEmpty
        ? 0
        : successful.map((r) => r.latencyMs).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(scheme, '发送', '${_results.length}'),
              _statItem(scheme, '成功', '${successful.length}',
                  color: Colors.green),
              _statItem(scheme, '丢包',
                  '${_results.length - successful.length}',
                  color: scheme.error),
              _statItem(scheme, '平均',
                  avgLatency > 0 ? '${avgLatency.toStringAsFixed(0)}ms' : '-'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(scheme, '最低',
                  minLatency > 0 ? '${minLatency}ms' : '-',
                  color: Colors.green),
              _statItem(scheme, '最高',
                  maxLatency > 0 ? '${maxLatency}ms' : '-',
                  color: Colors.orange),
              _statItem(scheme, '状态', _running ? '测试中' : '完成',
                  color: _running ? scheme.primary : scheme.tertiary),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ..._results.map((r) => _buildPingTile(scheme, r)),
      ],
    );
  }

  Widget _statItem(ColorScheme scheme, String label, String value,
      {Color? color}) {
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
            color: color ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildPingTile(ColorScheme scheme, _PingResult result) {
    final color = !result.success
        ? scheme.error
        : result.latencyMs < 100
            ? Colors.green
            : result.latencyMs < 300
                ? Colors.orange
                : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Text(
            '#${result.sequence}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          if (result.success)
            Text(
              '${result.latencyMs} ms',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            )
          else
            Text(
              result.error ?? '失败',
              style: TextStyle(
                fontSize: 12,
                color: scheme.error,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _TracerouteTab extends StatefulWidget {
  @override
  State<_TracerouteTab> createState() => _TracerouteTabState();
}

class _TracerouteTabState extends State<_TracerouteTab> {
  final _hostCtrl = TextEditingController(text: 'google.com');
  final _portCtrl = TextEditingController(text: '80');

  final _traceTool = _TracerouteTool();
  StreamSubscription<_TraceHop>? _subscription;
  final List<_TraceHop> _hops = [];
  bool _running = false;

  @override
  void dispose() {
    _subscription?.cancel();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 80;

    setState(() {
      _running = true;
      _hops.clear();
    });

    final stream = _traceTool.trace(host, port);
    _subscription?.cancel();
    _subscription = stream.listen((hop) {
      if (!mounted) return;
      setState(() {
        _hops.add(hop);
      });
    }, onDone: () {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    });
  }

  void _stop() {
    _subscription?.cancel();
    setState(() {
      _running = false;
    });
  }

  void _clear() {
    _subscription?.cancel();
    setState(() {
      _running = false;
      _hops.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildInputRow(scheme),
        Expanded(child: _buildResults(scheme)),
      ],
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标主机',
                    hintText: '例如 google.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? '停止' : '开始 TCP 测试'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _running ? null : _clear,
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    if (_hops.isEmpty && !_running) {
      return Center(
        child: Text(
          '点击开始按钮测试 TCP 连接',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (_hops.isEmpty && _running) {
      return const Center(child: CircularProgressIndicator());
    }

    final reached = _hops.where((h) => h.reached && h.ttl > 0);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(scheme, '解析', '${_hops.where((h) => h.ttl == 0).length > 0 ? "成功" : "失败"}'),
              _statItem(
                  scheme,
                  '连接',
                  reached.isNotEmpty ? '成功' : '失败',
                  color: reached.isNotEmpty ? Colors.green : scheme.error),
              _statItem(
                  scheme,
                  '状态',
                  _running
                      ? '测试中'
                      : (reached.isNotEmpty ? '完成' : '超时'),
                  color: _running ? scheme.primary : scheme.tertiary),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            itemCount: _hops.length,
            itemBuilder: (context, i) {
              final hop = _hops[i];
              return _buildHopTile(scheme, hop);
            },
          ),
        ),
      ],
    );
  }

  Widget _statItem(ColorScheme scheme, String label, String value,
      {Color? color}) {
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
            color: color ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildHopTile(ColorScheme scheme, _TraceHop hop) {
    final isDnsHop = hop.ttl == 0;
    final color = isDnsHop
        ? scheme.tertiary
        : hop.reached
            ? Colors.green
            : hop.latencyMs >= 0
                ? scheme.primary
                : scheme.error;

    final label = isDnsHop
        ? 'DNS 解析'
        : hop.reached
            ? '连接成功'
            : (hop.error ?? '连接失败');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isDnsHop
                ? Icon(Icons.language, size: 16, color: color)
                : Icon(
                    hop.reached ? Icons.check : Icons.error,
                    size: 16,
                    color: color,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                ),
                if (hop.ip != null)
                  Text(
                    hop.ip!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (!isDnsHop && hop.latencyMs >= 0)
            Text(
              '${hop.latencyMs} ms',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            )
          else if (isDnsHop)
            Icon(Icons.check_circle, size: 16, color: Colors.green)
          else
            Icon(Icons.help_outline, size: 16, color: scheme.outline),
        ],
      ),
    );
  }
}

class _PortScannerTab extends StatefulWidget {
  @override
  State<_PortScannerTab> createState() => _PortScannerTabState();
}

class _PortScannerTabState extends State<_PortScannerTab> {
  final _hostCtrl = TextEditingController(text: 'localhost');

  final _scanner = _PortScanner();
  StreamSubscription<_PortScanResult>? _subscription;
  final List<_PortScanResult> _results = [];
  bool _running = false;

  @override
  void dispose() {
    _subscription?.cancel();
    _hostCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;

    setState(() {
      _running = true;
      _results.clear();
    });

    final stream = _scanner.scan(host);
    _subscription?.cancel();
    _subscription = stream.listen((result) {
      if (!mounted) return;
      setState(() {
        _results.add(result);
      });
    }, onDone: () {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    });
  }

  void _stop() {
    _subscription?.cancel();
    setState(() {
      _running = false;
    });
  }

  void _clear() {
    _subscription?.cancel();
    setState(() {
      _running = false;
      _results.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildInputRow(scheme),
        Expanded(child: _buildResults(scheme)),
      ],
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '目标主机',
                    hintText: '例如 192.168.1.1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? '停止' : '开始扫描'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _running ? null : _clear,
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    if (_results.isEmpty && !_running) {
      return Center(
        child: Text(
          '点击开始扫描按钮扫描常见端口',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (_results.isEmpty && _running) {
      return const Center(child: CircularProgressIndicator());
    }

    final openPorts = _results.where((r) => r.isOpen);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(scheme, '扫描', '${_results.length}/${_PortScanner.commonPorts.length}'),
              _statItem(scheme, '开放', '${openPorts.length}',
                  color: Colors.green),
              _statItem(scheme, '关闭',
                  '${_results.length - openPorts.length}',
                  color: scheme.onSurfaceVariant),
              _statItem(
                  scheme,
                  '状态',
                  _running ? '扫描中' : '完成',
                  color: _running ? scheme.primary : scheme.tertiary),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final result = _results[i];
              return _buildPortTile(scheme, result);
            },
          ),
        ),
      ],
    );
  }

  Widget _statItem(ColorScheme scheme, String label, String value,
      {Color? color}) {
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
            color: color ?? scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildPortTile(ColorScheme scheme, _PortScanResult result) {
    final color = result.isOpen ? Colors.green : scheme.onSurfaceVariant;
    final icon = result.isOpen ? Icons.check_circle : Icons.cancel_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${result.port}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.service,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (result.isOpen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '开放 · ${result.latencyMs}ms',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
            )
          else
            Text(
              '关闭',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
