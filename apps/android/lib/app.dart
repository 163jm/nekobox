import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:core/core.dart';

import 'theme.dart';
import 'pages/groups_page.dart';
import 'pages/home_page.dart';
import 'pages/route_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';

/// 应用根:仿原版 NekoBox 顶部抽屉 / 底部导航。
class NekoBoxApp extends StatelessWidget {
  const NekoBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NekoBox',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
      home: const MainShell(),
    );
  }
}

/// 底部导航壳(5 项,仿原版抽屉)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Repository.instance.addListener(_onRepo);
    _initAndroid();
    _maybeAutoConnect();
  }

  /// Android 平台初始化:同步前台服务状态 + 深链接导入。
  Future<void> _initAndroid() async {
    if (!Platform.isAndroid) return;
    final bridge = CoreEnv.androidProxyBridge;
    if (bridge == null) return;
    // 1. App 重启后前台服务可能仍在运行,同步控制器状态
    try {
      await SingBoxController.instance.syncAndroidState();
    } catch (_) {}
    // 2. 深链接导入(浏览器点击 vmess:// 等)
    try {
      final pending = await bridge.getPendingImport();
      if (pending != null && pending.isNotEmpty) {
        await bridge.clearPendingImport();
        await _importDeepLink(pending);
      }
    } catch (_) {}
  }

  /// 深链接内容 → 解析 → 导入当前组。
  Future<void> _importDeepLink(String text) async {
    final repo = Repository.instance;
    try {
      final profiles = UniversalFmt.parseClipboard(text);
      if (profiles.isEmpty) {
        _toast('深链接未识别: $text');
        return;
      }
      for (final p in profiles) {
        p.groupId = repo.selectedGroupId;
        await repo.addProfile(p);
      }
      _toast('已通过深链接导入 ${profiles.length} 个节点');
    } catch (e) {
      _toast('深链接导入失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    Repository.instance.removeListener(_onRepo);
    super.dispose();
  }

  void _onRepo() {
    if (mounted) setState(() {});
  }

  /// 自动连接:设置开启且未连接时自动启动
  Future<void> _maybeAutoConnect() async {
    await Future.delayed(const Duration(milliseconds: 800));
    final repo = Repository.instance;
    final ctrl = SingBoxController.instance;
    if (repo.settings.isAutoConnect &&
        !ctrl.isRunning &&
        repo.currentProfiles.isNotEmpty) {
      try {
        await ctrl.start(
          profiles: repo.currentProfiles,
          selected: repo.currentProfile,
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = const <Widget>[
      HomePage(),
      GroupsPage(),
      RoutePage(),
      ToolsPage(),
      SettingsPage(),
    ];
    final showBottomBar = Repository.instance.settings.showBottomBar;
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: showBottomBar
          ? NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.lan_outlined),
            selectedIcon: Icon(Icons.lan),
            label: '配置',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '分组',
          ),
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route),
            label: '路由',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: '工具',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      )
          : null,
    );
  }
}