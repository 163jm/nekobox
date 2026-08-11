import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:core/core.dart';

import 'theme.dart';
import 'pages/groups_page.dart';
import 'pages/home_page.dart';
import 'pages/route_page.dart';
import 'pages/settings_page.dart';
import 'pages/tools_page.dart';

/// 应用根:Windows 桌面布局(左侧 NavigationRail + 内容区)。
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

/// 桌面主壳:5 项 NavigationRail
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
    _maybeAutoConnect();
  }

  /// 自动连接:设置开启且未连接时自动启动(桌面端同样支持)
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
        // 系统代理联动由 SingBoxController.start 内部处理
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Icon(
                Icons.bolt,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.lan_outlined),
                selectedIcon: Icon(Icons.lan),
                label: Text('配置'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt),
                label: Text('分组'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.alt_route_outlined),
                selectedIcon: Icon(Icons.alt_route),
                label: Text('路由'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.speed_outlined),
                selectedIcon: Icon(Icons.speed),
                label: Text('工具'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
    );
  }
}