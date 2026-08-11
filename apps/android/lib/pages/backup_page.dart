import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:core/core.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _ctrl = _BackupController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份 / 恢复')),
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, child) {
          if (_ctrl.isBusy) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _section('导出'),
              _buildExportCheckbox('节点 (${Repository.instance.profiles.length})',
                  _ctrl.exportProfiles, (v) => _ctrl.setExportProfiles(v!)),
              _buildExportCheckbox('分组 (${Repository.instance.groups.length})',
                  _ctrl.exportGroups, (v) => _ctrl.setExportGroups(v!)),
              _buildExportCheckbox('规则 (${Repository.instance.rules.length})',
                  _ctrl.exportRules, (v) => _ctrl.setExportRules(v!)),
              _buildExportCheckbox('设置', _ctrl.exportSettings,
                  (v) => _ctrl.setExportSettings(v!)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () => _doExport(),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('导出到文件'),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              _section('导入'),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('选择备份文件'),
                subtitle: Text(_ctrl.filePath ?? '未选择文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickFile,
              ),
              if (_ctrl.filePath != null) ...[
                const SizedBox(height: 4),
                _section('导入内容'),
                _buildImportCheckbox('节点', _ctrl.importProfiles,
                    (v) => _ctrl.setImportProfiles(v!)),
                _buildImportCheckbox('分组', _ctrl.importGroups,
                    (v) => _ctrl.setImportGroups(v!)),
                _buildImportCheckbox('规则', _ctrl.importRules,
                    (v) => _ctrl.setImportRules(v!)),
                _buildImportCheckbox('设置', _ctrl.importSettings,
                    (v) => _ctrl.setImportSettings(v!)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: () => _doImport(),
                    icon: const Icon(Icons.download),
                    label: const Text('导入'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              _section('重置'),
              ListTile(
                leading: Icon(Icons.restore,
                    color: Theme.of(context).colorScheme.error),
                title: Text('重置设置',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                subtitle: const Text('清除所有设置并恢复默认值'),
                onTap: _resetSettings,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildExportCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
    );
  }

  Widget _buildImportCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _ctrl.setFilePath(path);
        _ctrl.setBackupPreview(json);
        _toast('已加载备份文件');
      }
    } catch (e) {
      _toast('选择文件失败: $e');
    }
  }

  Future<void> _doExport() async {
    final repo = Repository.instance;
    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  "version": 1,');
    buffer.writeln('  "exportTime": "${DateTime.now().toIso8601String()}",');
    final parts = <String>[];
    if (_ctrl.exportProfiles) {
      parts.add(
          '  "profiles": ${const JsonEncoder.withIndent('  ').convert(repo.profiles.map((p) => p.toJson()).toList())}');
    }
    if (_ctrl.exportGroups) {
      parts.add(
          '  "groups": ${const JsonEncoder.withIndent('  ').convert(repo.groups.map((g) => g.toJson()).toList())}');
    }
    if (_ctrl.exportRules) {
      parts.add(
          '  "rules": ${const JsonEncoder.withIndent('  ').convert(repo.rules.map((r) => r.toJson()).toList())}');
    }
    if (_ctrl.exportSettings) {
      parts.add(
          '  "settings": ${const JsonEncoder.withIndent('  ').convert(repo.settings.toJson())}');
    }
    buffer.writeln(parts.join(',\n'));
    buffer.writeln('}');

    final summary = <String>[
      if (_ctrl.exportProfiles) '节点: ${repo.profiles.length} 个',
      if (_ctrl.exportGroups) '分组: ${repo.groups.length} 个',
      if (_ctrl.exportRules) '规则: ${repo.rules.length} 条',
      if (_ctrl.exportSettings) '设置: 1 份',
    ];

    final ok = await _confirmExport(summary);
    if (ok != true) return;

    try {
      final fileName =
          'nekobox-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result != null) {
        final file = File(result);
        await file.writeAsString(buffer.toString());
        _toast('导出成功: $fileName');
      }
    } catch (e) {
      _toast('导出失败: $e');
    }
  }

  Future<bool?> _confirmExport(List<String> summary) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出摘要'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('即将导出以下内容:'),
            const SizedBox(height: 8),
            ...summary.map((s) => Text('• $s')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导出'),
          ),
        ],
      ),
    );
  }

  Future<void> _doImport() async {
    if (_ctrl.filePath == null) {
      _toast('请先选择备份文件');
      return;
    }
    final repo = Repository.instance;
    final json = _ctrl.backupPreview;
    if (json == null) {
      _toast('备份文件无效');
      return;
    }

    final summary = <String>[];
    if (_ctrl.importProfiles) {
      final list = (json['profiles'] as List?) ?? [];
      summary.add('节点: ${list.length} 个');
    }
    if (_ctrl.importGroups) {
      final list = (json['groups'] as List?) ?? [];
      summary.add('分组: ${list.length} 个');
    }
    if (_ctrl.importRules) {
      final list = (json['rules'] as List?) ?? [];
      summary.add('规则: ${list.length} 条');
    }
    if (_ctrl.importSettings) {
      final map = json['settings'];
      summary.add('设置: ${map != null ? 1 : 0} 份');
    }

    final ok = await _confirmImport(summary);
    if (ok != true) return;

    _ctrl.setBusy(true);
    try {
      if (_ctrl.importGroups) {
        final list = (json['groups'] as List?) ?? [];
        final existingMaxId =
            repo.groups.fold<int>(0, (m, g) => g.id > m ? g.id : m);
        for (int i = 0; i < list.length; i++) {
          final item = list[i] as Map<String, dynamic>;
          final g = ProxyGroup.fromJson(item);
          g.id = existingMaxId + i + 1;
          g.userOrder = repo.groups.length + i;
          await repo.addGroup(g);
        }
      }

      if (_ctrl.importProfiles) {
        final list = (json['profiles'] as List?) ?? [];
        final existingGroupIds = repo.groups.map((g) => g.id).toSet();
        final existingMaxId =
            repo.profiles.fold<int>(0, (m, p) => p.id > m ? p.id : m);
        var idCounter = existingMaxId + 1;

        for (int i = 0; i < list.length; i++) {
          final item = list[i] as Map<String, dynamic>;
          final p = Profile.fromJson(item);
          if (!existingGroupIds.contains(p.groupId)) {
            p.groupId = repo.selectedGroupId;
          }
          p.id = idCounter++;
          await repo.addProfile(p);
        }
      }

      if (_ctrl.importRules) {
        final list = (json['rules'] as List?) ?? [];
        final existingMaxId =
            repo.rules.fold<int>(0, (m, r) => r.id > m ? r.id : m);
        for (int i = 0; i < list.length; i++) {
          final item = list[i] as Map<String, dynamic>;
          final r = RouteRule.fromJson(item);
          r.id = existingMaxId + i + 1;
          await repo.addRule(r);
        }
      }

      if (_ctrl.importSettings) {
        final map = json['settings'] as Map<String, dynamic>?;
        if (map != null) {
          final s = AppSettings.fromJson(map);
          await repo.updateSettings(s);
        }
      }

      _toast('导入完成');
      _ctrl.reset();
    } catch (e) {
      _toast('导入失败: $e');
    } finally {
      _ctrl.setBusy(false);
    }
  }

  Future<bool?> _confirmImport(List<String> summary) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入摘要'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('即将导入以下内容(将追加到现有数据):'),
            const SizedBox(height: 8),
            ...summary.map((s) => Text('• $s')),
            const SizedBox(height: 8),
            Text(
              '注意:节点和分组将作为新数据追加,ID 会自动重新分配。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('重置设置',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        content: const Text(
            '确定要将所有设置恢复为默认值吗?\n此操作不可撤销,但不会影响节点、分组和规则。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Repository.instance.updateSettings(AppSettings());
        _toast('设置已重置为默认值');
      } catch (e) {
        _toast('重置失败: $e');
      }
    }
  }
}

class _BackupController extends ChangeNotifier {
  bool _exportProfiles = true;
  bool _exportGroups = true;
  bool _exportRules = true;
  bool _exportSettings = true;

  bool _importProfiles = true;
  bool _importGroups = true;
  bool _importRules = true;
  bool _importSettings = true;

  String? _filePath;
  Map<String, dynamic>? _backupPreview;
  bool _busy = false;

  bool get exportProfiles => _exportProfiles;
  bool get exportGroups => _exportGroups;
  bool get exportRules => _exportRules;
  bool get exportSettings => _exportSettings;

  bool get importProfiles => _importProfiles;
  bool get importGroups => _importGroups;
  bool get importRules => _importRules;
  bool get importSettings => _importSettings;

  String? get filePath => _filePath;
  Map<String, dynamic>? get backupPreview => _backupPreview;
  bool get isBusy => _busy;

  void setExportProfiles(bool v) {
    _exportProfiles = v;
    notifyListeners();
  }

  void setExportGroups(bool v) {
    _exportGroups = v;
    notifyListeners();
  }

  void setExportRules(bool v) {
    _exportRules = v;
    notifyListeners();
  }

  void setExportSettings(bool v) {
    _exportSettings = v;
    notifyListeners();
  }

  void setImportProfiles(bool v) {
    _importProfiles = v;
    notifyListeners();
  }

  void setImportGroups(bool v) {
    _importGroups = v;
    notifyListeners();
  }

  void setImportRules(bool v) {
    _importRules = v;
    notifyListeners();
  }

  void setImportSettings(bool v) {
    _importSettings = v;
    notifyListeners();
  }

  void setFilePath(String path) {
    _filePath = path;
    notifyListeners();
  }

  void setBackupPreview(Map<String, dynamic> json) {
    _backupPreview = json;
    final hasProfiles = json['profiles'] != null;
    final hasGroups = json['groups'] != null;
    final hasRules = json['rules'] != null;
    final hasSettings = json['settings'] != null;
    _importProfiles = hasProfiles;
    _importGroups = hasGroups;
    _importRules = hasRules;
    _importSettings = hasSettings;
    notifyListeners();
  }

  void setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  void reset() {
    _filePath = null;
    _backupPreview = null;
    _importProfiles = true;
    _importGroups = true;
    _importRules = true;
    _importSettings = true;
    notifyListeners();
  }
}