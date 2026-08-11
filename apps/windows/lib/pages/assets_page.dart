import 'dart:io';

import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 规则集资源管理(仿原版 AssetsActivity):
/// 可视化列表管理已下载的 .srs 文件(新增/删除/查看更新时间)。
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final files = await Repository.instance.listRuleSets();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _addFromUrl() async {
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 URL 下载规则集'),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(
            labelText: '规则集 URL',
            hintText: 'https://example.com/rule.srs',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;
    try {
      final name = url.split('/').last;
      final fileName = name.endsWith('.srs') ? name : '$name.srs';
      final dest = await _downloadTo(fileName, url);
      if (dest != null) {
        _toast('已下载 ${dest.split(Platform.pathSeparator).last}');
        await _reload();
      } else {
        _toast('下载失败');
      }
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  Future<String?> _downloadTo(String fileName, String url) async {
    final srsDir = await CoreEnv.getSrsDirectory();
    await srsDir.create(recursive: true);
    final dest = File('${srsDir.path}${Platform.pathSeparator}$fileName');
    final resp = await httpGet(url);
    if (resp != null && resp.isNotEmpty) {
      await dest.writeAsBytes(resp, flush: true);
      return dest.path;
    }
    return null;
  }

  Future<List<int>?> httpGet(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode == 200) {
        return await resp.fold<List<int>>(
            [], (acc, chunk) => acc..addAll(chunk));
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则集'),
        content: Text('确定删除「${f.path.split(Platform.pathSeparator).last}」?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Repository.instance
          .deleteRuleSet(f.path.split(Platform.pathSeparator).last);
      await _reload();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则集资源'),
        actions: [
          IconButton(
            tooltip: '从 URL 下载',
            icon: const Icon(Icons.download_outlined),
            onPressed: _addFromUrl,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Text(
                    '暂无规则集文件\n点右上角从 URL 下载',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    final stat = f.statSync();
                    final size = _fmtSize(stat.size);
                    final modified = DateTime.fromMillisecondsSinceEpoch(
                        stat.modified.millisecondsSinceEpoch);
                    return ListTile(
                      leading: Icon(Icons.rule,
                          color: scheme.primary),
                      title: Text(f.path.split(Platform.pathSeparator).last),
                      subtitle: Text('$size · '
                          '${modified.year}-${modified.month.toString().padLeft(2, '0')}-'
                          '${modified.day.toString().padLeft(2, '0')} '
                          '${modified.hour.toString().padLeft(2, '0')}:'
                          '${modified.minute.toString().padLeft(2, '0')}'),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(f),
                      ),
                    );
                  },
                ),
    );
  }
}
