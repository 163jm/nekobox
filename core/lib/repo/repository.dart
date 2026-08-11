import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core_env.dart';
import '../models/profile.dart';
import '../models/proxy_group.dart';
import '../models/route_rule.dart';
import '../models/settings.dart';

/// 全局数据仓库:组 / 节点 / 设置 的 SQLite 持久化 + 内存状态。
/// UI 通过 [ChangeNotifier] 监听变化。
///
/// 存储:数据目录下 `nekobox.db`(Android 原生 SQLite / 桌面 ffi),
/// 首次启动自动把旧的 groups.json/profiles.json 等迁移进库。
class Repository extends ChangeNotifier {
  Repository._();

  static final Repository instance = Repository._();

  static bool _initialized = false;
  static Future<Repository>? _initFuture;

  late Directory dataDir;

  Database? _db;

  List<ProxyGroup> groups = [];
  List<Profile> profiles = [];
  List<RouteRule> rules = [];
  AppSettings settings = AppSettings();

  int _selectedGroupId = 0;

  /// 全局选中的组
  int get selectedGroupId => _selectedGroupId;
  ProxyGroup? get selectedGroup {
    for (final g in groups) {
      if (g.id == _selectedGroupId) return g;
    }
    return null;
  }

  /// 当前组内的节点
  List<Profile> get currentProfiles {
    final g = selectedGroup;
    if (g == null) return [];
    final list = profiles.where((p) => p.groupId == g.id).toList();
    switch (g.order) {
      case 1:
        list.sort((a, b) => a.displayName().compareTo(b.displayName()));
        break;
      case 2:
        list.sort((a, b) {
          final ad = a.delay < 0 ? 0x7fffffff : a.delay;
          final bd = b.delay < 0 ? 0x7fffffff : b.delay;
          return ad.compareTo(bd);
        });
        break;
      default:
        list.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    }
    return list;
  }

  /// 当前选中的节点
  Profile? get currentProfile {
    final g = selectedGroup;
    if (g == null) return null;
    if (g.selectedProfileId > 0) {
      for (final p in profiles) {
        if (p.id == g.selectedProfileId) return p;
      }
    }
    return null;
  }

  static Future<Repository> init({Directory? overrideDataDir}) {
    if (_initialized && _initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _doInit(overrideDataDir);
    return _initFuture!;
  }

  static Future<Repository> _doInit(Directory? overrideDataDir) async {
    final repo = instance;
    if (overrideDataDir != null) {
      repo.dataDir = overrideDataDir;
    } else {
      repo.dataDir = await repo._defaultDataDir();
    }
    await repo.dataDir.create(recursive: true);
    await repo._openDb();
    await repo._migrateFromJsonIfNeeded();
    await repo._load();
    _initialized = true;
    return repo;
  }

  Future<Directory> _defaultDataDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(
        '${supportDir.path}${Platform.pathSeparator}nekobox');
  }

  // ---------- 数据库 ----------

  DatabaseFactory get _factory {
    if (Platform.isAndroid || Platform.isIOS) {
      return sqflite.databaseFactory;
    }
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final path = await CoreEnv.getDatabasePath();
    await Directory(p.dirname(path)).create(recursive: true);
    _db = await _factory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 4, onCreate: _onCreate, onUpgrade: _onUpgrade));
    return _db!;
  }

  Future<void> _closeDb() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups(
        id INTEGER PRIMARY KEY,
        name TEXT,
        url TEXT,
        subscription INTEGER,
        update_time INTEGER,
        selected_profile_id INTEGER,
        front_proxy_id INTEGER,
        landing_proxy_id INTEGER,
        order INTEGER DEFAULT 0,
        user_order INTEGER DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE profiles(
        id INTEGER PRIMARY KEY,
        group_id INTEGER,
        type TEXT,
        name TEXT,
        server_address TEXT,
        server_port INTEGER,
        sort_index INTEGER,
        delay INTEGER,
        data TEXT
      )''');
    await db.execute('''
      CREATE TABLE rules(
        id INTEGER PRIMARY KEY,
        sort_index INTEGER,
        data TEXT
      )''');
    await db.execute('''
      CREATE TABLE settings(
        id INTEGER PRIMARY KEY,
        data TEXT
      )''');
    await db.execute('''
      CREATE TABLE state(
        id INTEGER PRIMARY KEY,
        selected_group_id INTEGER,
        default_rules_seeded INTEGER DEFAULT 0
      )''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
            'ALTER TABLE groups ADD COLUMN order INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
            'ALTER TABLE groups ADD COLUMN user_order INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
            'ALTER TABLE state ADD COLUMN default_rules_seeded INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  /// 旧 JSON 文件 → 数据库迁移(仅首次:db 为空且存在 json 时)
  Future<void> _migrateFromJsonIfNeeded() async {
    final db = await _openDb();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM groups');
    final count = rows.isNotEmpty ? ((rows.first['c'] as num?)?.toInt() ?? 0) : 0;
    if (count > 0) return;

    final groupsFile = File(p.join(dataDir.path, 'groups.json'));
    if (!await groupsFile.exists()) return;

    final rawGroups = await _readJsonList('groups.json');
    final rawProfiles = await _readJsonList('profiles.json');
    final rawRules = await _readJsonList('rules.json');
    final rawSettings = await _readJsonMap('settings.json');
    final rawState = await _readJsonMap('state.json');

    final batch = db.batch();
    for (final g in rawGroups) {
      batch.insert('groups', _groupRow(ProxyGroup.fromJson(g)));
    }
    for (final pr in rawProfiles) {
      final model = Profile.fromJson(pr);
      batch.insert('profiles', _profileRow(model));
    }
    for (final r in rawRules) {
      final model = RouteRule.fromJson(r);
      batch.insert('rules', {
        'id': model.id,
        'sort_index': model.sortIndex,
        'data': jsonEncode(model.toJson()),
      });
    }
    if (rawSettings.isNotEmpty) {
      batch.insert('settings', {'id': 1, 'data': jsonEncode(rawSettings)});
    }
    final sg = (rawState['selectedGroupId'] as num?)?.toInt() ?? 0;
    batch.insert('state', {'id': 1, 'selected_group_id': sg});
    await batch.commit(noResult: true);

    // 迁移成功后移除旧 JSON,避免下次重复导入
    for (final name in [
      'groups.json', 'profiles.json', 'rules.json',
      'settings.json', 'state.json'
    ]) {
      final f = File(p.join(dataDir.path, name));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<List<Map<String, dynamic>>> _readJsonList(String name) async {
    final f = File(p.join(dataDir.path, name));
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> _readJsonMap(String name) async {
    final f = File(p.join(dataDir.path, name));
    if (!await f.exists()) return {};
    try {
      final data = jsonDecode(await f.readAsString());
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return {};
  }

  Map<String, dynamic> _groupRow(ProxyGroup g) => {
        'id': g.id,
        'name': g.name,
        'url': g.url,
        'subscription': g.subscription ? 1 : 0,
        'update_time': g.updateTime,
        'selected_profile_id': g.selectedProfileId,
        'front_proxy_id': g.frontProxyId,
        'landing_proxy_id': g.landingProxyId,
        'order': g.order,
        'user_order': g.userOrder,
      };

  Map<String, dynamic> _profileRow(Profile pr) => {
        'id': pr.id,
        'group_id': pr.groupId,
        'type': pr.type,
        'name': pr.name,
        'server_address': pr.serverAddress,
        'server_port': pr.serverPort,
        'sort_index': pr.sortIndex,
        'delay': pr.delay,
        'data': jsonEncode(pr.toJson()),
      };

  Future<void> _load() async {
    final db = await _openDb();

    final groupRows = await db.query('groups');
    groups = groupRows.map((r) => ProxyGroup(
          id: r['id'] as int,
          name: (r['name'] as String?) ?? '',
          url: (r['url'] as String?) ?? '',
          subscription: (r['subscription'] as int? ?? 0) == 1,
          updateTime: (r['update_time'] as int?) ?? 0,
          selectedProfileId: (r['selected_profile_id'] as int?) ?? 0,
          frontProxyId: (r['front_proxy_id'] as int?) ?? -1,
          landingProxyId: (r['landing_proxy_id'] as int?) ?? -1,
          order: (r['order'] as int?) ?? 0,
          userOrder: (r['user_order'] as int?) ?? 0,
        )).toList();

    final profileRows = await db.query('profiles');
    profiles = profileRows.map((r) {
      final data = r['data'] as String?;
      if (data != null) {
        try {
          return Profile.fromJson(
              jsonDecode(data) as Map<String, dynamic>);
        } catch (_) {}
      }
      // 兜底:从关键列重建
      return Profile(
        id: r['id'] as int,
        groupId: (r['group_id'] as int?) ?? 0,
        type: (r['type'] as String?) ?? 'vmess',
        name: (r['name'] as String?) ?? '',
        serverAddress: (r['server_address'] as String?) ?? '',
        serverPort: (r['server_port'] as int?) ?? 0,
        sortIndex: (r['sort_index'] as int?) ?? 0,
        delay: (r['delay'] as int?) ?? -1,
      );
    }).toList();

    final ruleRows = await db.query('rules');
    rules = ruleRows.map((r) {
      final data = r['data'] as String?;
      if (data != null) {
        try {
          return RouteRule.fromJson(
              jsonDecode(data) as Map<String, dynamic>);
        } catch (_) {}
      }
      return RouteRule(
          id: r['id'] as int, sortIndex: (r['sort_index'] as int?) ?? 0);
    }).toList();

    final settingsRows = await db.query('settings', where: 'id = 1');
    if (settingsRows.isNotEmpty) {
      final data = settingsRows.first['data'] as String?;
      if (data != null) {
        try {
          settings = AppSettings.fromJson(
              jsonDecode(data) as Map<String, dynamic>);
        } catch (_) {}
      }
    }

    groups.sort((a, b) => a.userOrder.compareTo(b.userOrder));

    final stateRows = await db.query('state', where: 'id = 1');
    var rulesSeeded = false;
    if (stateRows.isNotEmpty) {
      _selectedGroupId = (stateRows.first['selected_group_id'] as int?) ?? 0;
      rulesSeeded = (stateRows.first['default_rules_seeded'] as int? ?? 0) == 1;
    }
    // 首次使用且无任何规则时,注入默认路由配置(对齐原版开箱即用)
    if (rules.isEmpty && !rulesSeeded) {
      await _seedDefaultRules();
    }
    if (_selectedGroupId == 0 && groups.isNotEmpty) {
      _selectedGroupId = groups.first.id;
    }
    // 同步组内选中节点
    for (final g in groups) {
      if (g.selectedProfileId > 0) continue;
      for (final p in profiles) {
        if (p.groupId == g.id) {
          g.selectedProfileId = p.id;
          break;
        }
      }
    }
  }

  // ---------- 持久化 ----------

  Future<void> _persistGroups() async {
    final db = await _openDb();
    final batch = db.batch();
    batch.delete('groups');
    for (final g in groups) {
      batch.insert('groups', _groupRow(g));
    }
    await batch.commit(noResult: true);
  }

  Future<void> _persistProfiles() async {
    final db = await _openDb();
    final batch = db.batch();
    batch.delete('profiles');
    for (final pr in profiles) {
      batch.insert('profiles', _profileRow(pr));
    }
    await batch.commit(noResult: true);
  }

  Future<void> _persistRules() async {
    final db = await _openDb();
    final batch = db.batch();
    batch.delete('rules');
    for (final r in rules) {
      batch.insert('rules', {
        'id': r.id,
        'sort_index': r.sortIndex,
        'data': jsonEncode(r.toJson()),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _persistSettings() async {
    final db = await _openDb();
    await db.insert('settings', {
      'id': 1,
      'data': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _persistState() async {
    final db = await _openDb();
    await db.insert('state', {
      'id': 1,
      'selected_group_id': _selectedGroupId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 默认路由规则(基于内置 srs 规则集,对齐原版默认分流):
  /// 广告拦截 → 国内域名直连 → 国内 IP 直连。
  Future<void> _seedDefaultRules() async {
    rules = [
      RouteRule(
        id: 1,
        name: '广告拦截',
        srsName: 'category-ads.srs',
        outboundMode: 2,
        enabled: true,
        sortIndex: 0,
      ),
      RouteRule(
        id: 2,
        name: '国内直连',
        srsName: 'geosite-cn.srs',
        outboundMode: 1,
        enabled: true,
        sortIndex: 1,
      ),
      RouteRule(
        id: 3,
        name: '国内 IP 直连',
        srsName: 'geoip-cn.srs',
        outboundMode: 1,
        enabled: true,
        sortIndex: 2,
      ),
    ];
    await _persistRules();
    final db = await _openDb();
    await db.insert('state', {
      'id': 1,
      'selected_group_id': _selectedGroupId,
      'default_rules_seeded': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- 组操作 ----------

  Future<ProxyGroup> addGroup(ProxyGroup group) async {
    final maxId = groups.fold<int>(0, (m, g) => g.id > m ? g.id : m);
    group.id = maxId + 1;
    final maxOrder =
        groups.fold<int>(0, (m, g) => g.userOrder > m ? g.userOrder : m);
    group.userOrder = maxOrder + 1;
    if (_selectedGroupId == 0) _selectedGroupId = group.id;
    groups.add(group);
    await _persistGroups();
    await _persistState();
    notifyListeners();
    return group;
  }

  Future<void> updateGroup(ProxyGroup group) async {
    final idx = groups.indexWhere((g) => g.id == group.id);
    if (idx >= 0) {
      groups[idx] = group;
      await _persistGroups();
      notifyListeners();
    }
  }

  Future<void> removeGroup(ProxyGroup group) async {
    groups.removeWhere((g) => g.id == group.id);
    profiles.removeWhere((p) => p.groupId == group.id);
    if (_selectedGroupId == group.id) {
      _selectedGroupId = groups.isNotEmpty ? groups.first.id : 0;
    }
    await _persistGroups();
    await _persistProfiles();
    await _persistState();
    notifyListeners();
  }

  /// 拖拽排序分组(按传入顺序重排 userOrder)
  Future<void> reorderGroups(List<ProxyGroup> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final idx = groups.indexWhere((g) => g.id == ordered[i].id);
      if (idx >= 0) groups[idx].userOrder = i;
    }
    groups.sort((a, b) => a.userOrder.compareTo(b.userOrder));
    await _persistGroups();
    notifyListeners();
  }

  Future<void> selectGroup(int id) async {
    if (_selectedGroupId == id) return;
    _selectedGroupId = id;
    await _persistState();
    notifyListeners();
  }

  // ---------- 节点操作 ----------

  Future<Profile> addProfile(Profile profile) async {
    final maxId = profiles.fold<int>(0, (m, p) => p.id > m ? p.id : m);
    profile.id = maxId + 1;
    profile.sortIndex = _nextSortIndex(profile.groupId);
    profiles.add(profile);
    await _persistProfiles();
    notifyListeners();
    return profile;
  }

  int _nextSortIndex(int groupId) {
    final inGroup = profiles.where((p) => p.groupId == groupId).toList();
    if (inGroup.isEmpty) return 0;
    return inGroup.fold<int>(0, (m, p) => p.sortIndex > m ? p.sortIndex : m) + 1;
  }

  Future<void> updateProfile(Profile profile) async {
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
      await _persistProfiles();
      notifyListeners();
    }
  }

  Future<void> removeProfile(Profile profile) async {
    profiles.removeWhere((p) => p.id == profile.id);
    final g = groups.where((g) => g.id == profile.groupId).toList();
    if (g.isNotEmpty && g.first.selectedProfileId == profile.id) {
      g.first.selectedProfileId = 0;
      await _persistGroups();
    }
    await _persistProfiles();
    notifyListeners();
  }

  /// 拖拽排序后重排组内节点 sortIndex(按传入顺序)
  Future<void> reorderProfiles(List<Profile> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final idx = profiles.indexWhere((x) => x.id == ordered[i].id);
      if (idx >= 0) profiles[idx].sortIndex = i;
    }
    await _persistProfiles();
    notifyListeners();
  }

  /// 批量删除节点(删除重复 / 删除不可用)
  Future<void> removeProfiles(List<Profile> list) async {
    final ids = list.map((e) => e.id).toSet();
    profiles.removeWhere((p) => ids.contains(p.id));
    for (final p in list) {
      final g = groups.where((g) => g.id == p.groupId).toList();
      if (g.isNotEmpty && g.first.selectedProfileId == p.id) {
        g.first.selectedProfileId = 0;
        await _persistGroups();
      }
    }
    await _persistProfiles();
    notifyListeners();
  }

  /// 替换组内全部节点(订阅更新)
  Future<void> replaceProfiles(int groupId, List<Profile> newProfiles) async {
    profiles.removeWhere((p) => p.groupId == groupId);
    final maxId = profiles.fold<int>(0, (m, p) => p.id > m ? p.id : m);
    for (var i = 0; i < newProfiles.length; i++) {
      final p = newProfiles[i];
      p.id = maxId + i + 1;
      p.groupId = groupId;
      p.sortIndex = i;
    }
    profiles.addAll(newProfiles);
    final g = groups.where((g) => g.id == groupId).toList();
    if (g.isNotEmpty) {
      g.first.selectedProfileId = newProfiles.isNotEmpty ? newProfiles.first.id : 0;
      // 记录订阅更新时间(分组页显示 MM-DD 更新)
      g.first.updateTime = DateTime.now().millisecondsSinceEpoch;
      await _persistGroups();
    }
    await _persistProfiles();
    notifyListeners();
  }

  // ---------- 路由规则 ----------

  /// 全局规则(启用 + 按优先级排序)
  List<RouteRule> get activeRules {
    final list = rules.where((r) => r.enabled).toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return list;
  }

  Future<RouteRule> addRule(RouteRule rule) async {
    final maxId = rules.fold<int>(0, (m, r) => r.id > m ? r.id : m);
    rule.id = maxId + 1;
    rule.sortIndex = rules.isEmpty ? 0 : rules.length;
    rules.add(rule);
    await _persistRules();
    // 远程规则集自动下载(srsUrl → srs 目录)
    await _downloadRuleSet(rule);
    notifyListeners();
    return rule;
  }

  Future<void> updateRule(RouteRule rule) async {
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
      await _persistRules();
      await _downloadRuleSet(rule);
      notifyListeners();
    }
  }

  /// 下载远程规则集到 srs 目录(保存/更新规则时,对齐原版行为)。
  /// 下载失败不阻断保存,由 UI 提示。
  Future<String?> _downloadRuleSet(RouteRule rule) async {
    final url = rule.srsUrl.trim();
    if (url.isEmpty) return null;
    // 已有同名本地文件则跳过
    final srsDir = await CoreEnv.getSrsDirectory();
    await srsDir.create(recursive: true);
    final name = rule.srsName.trim().isEmpty
        ? url.split('/').last
        : (rule.srsName.endsWith('.srs')
            ? rule.srsName
            : '${rule.srsName}.srs');
    if (name.isEmpty || !name.endsWith('.srs')) return null;
    final dest = File(p.join(srsDir.path, name));
    try {
      final resp = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 15),
          );
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        await dest.writeAsBytes(resp.bodyBytes, flush: true);
        return dest.path;
      }
    } catch (_) {}
    return null;
  }

  /// 已下载的规则集文件列表(供资源管理页)。
  Future<List<File>> listRuleSets() async {
    final dir = await CoreEnv.getSrsDirectory();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.srs'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// 删除已下载的规则集文件。
  Future<void> deleteRuleSet(String fileName) async {
    final dir = await CoreEnv.getSrsDirectory();
    final f = File(p.join(dir.path, fileName));
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<void> removeRule(RouteRule rule) async {
    rules.removeWhere((r) => r.id == rule.id);
    // 重排 sortIndex
    rules.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    for (var i = 0; i < rules.length; i++) {
      rules[i].sortIndex = i;
    }
    await _persistRules();
    notifyListeners();
  }

  Future<void> toggleRule(RouteRule rule) async {
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx].enabled = !rules[idx].enabled;
      await _persistRules();
      notifyListeners();
    }
  }

  /// 上移/下移规则(priority)。delta = -1 上移,1 下移。
  Future<void> moveRule(RouteRule rule, int delta) async {
    final sorted = rules.toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    final idx = sorted.indexWhere((r) => r.id == rule.id);
    final target = idx + delta;
    if (idx < 0 || target < 0 || target >= sorted.length) return;
    final tmp = sorted[idx].sortIndex;
    sorted[idx].sortIndex = sorted[target].sortIndex;
    sorted[target].sortIndex = tmp;
    rules.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    await _persistRules();
    notifyListeners();
  }

  /// 选中节点
  Future<void> selectProfile(Profile profile) async {
    final g = groups.where((g) => g.id == profile.groupId).toList();
    if (g.isNotEmpty && g.first.selectedProfileId != profile.id) {
      g.first.selectedProfileId = profile.id;
      await _persistGroups();
    }
    notifyListeners();
  }

  /// 更新测速结果(只写单行 delay,避免全量重写)
  Future<void> updateProfileDelay(Profile profile, int delay) async {
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx].delay = delay;
      final db = await _openDb();
      await db.update('profiles', {'delay': delay},
          where: 'id = ?', whereArgs: [profile.id]);
      notifyListeners();
    }
  }

  // ---------- 设置 ----------

  Future<void> updateSettings(AppSettings newSettings) async {
    settings = newSettings;
    await _persistSettings();
    notifyListeners();
  }

  /// 仅更新本地端口
  Future<void> setLocalPort(int port) async {
    settings.localPort = port;
    await _persistSettings();
    notifyListeners();
  }

  // ---------- 备份 / 恢复 ----------

  static const int maxBackups = 10;

  /// 备份目录下的文件列表(按时间倒序)。
  Future<List<File>> listBackups() async {
    final dir = await CoreEnv.getBackupDirectory();
    if (!await dir.exists()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 创建备份(复制数据库文件到 backups/,带时间戳,保留最近 [maxBackups] 份)。
  /// 返回备份文件路径。
  Future<String> backup() async {
    final db = await _openDb();
    // 先 checkpoint,确保数据落盘
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}

    final dir = await CoreEnv.getBackupDirectory();
    await dir.create(recursive: true);

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    final srcPath = await CoreEnv.getDatabasePath();
    final dstPath = p.join(dir.path, 'nekobox-$ts.db');
    await File(srcPath).copy(dstPath);

    // 清理旧备份
    final backups = await listBackups();
    if (backups.length > maxBackups) {
      for (final old in backups.skip(maxBackups)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    }
    return dstPath;
  }

  /// 从指定备份文件恢复:关闭连接 → 覆盖数据库 → 重载内存。
  Future<void> restoreBackup(String backupPath) async {
    await _closeDb();
    final srcPath = await CoreEnv.getDatabasePath();
    await File(backupPath).copy(srcPath);
    await _load();
    notifyListeners();
  }
}
