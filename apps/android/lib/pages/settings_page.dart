import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:core/core.dart';

import 'assets_page.dart';
import 'app_selector_page.dart';
import 'backup_page.dart';
import 'dashboard_page.dart';
import 'plugins_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// 设置页:本地服务 / 外观 / 测速 / 日志 / 关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    Repository.instance.addListener(_onRepoChange);
  }

  @override
  void dispose() {
    Repository.instance.removeListener(_onRepoChange);
    super.dispose();
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = Repository.instance.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _section('本地服务'),
          ListTile(
            leading: const Icon(Icons.portrait_outlined),
            title: const Text('本地代理端口'),
            subtitle: Text('当前: ${settings.localPort}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editPort,
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('复制本地代理地址'),
            subtitle: const Text('供浏览器 / 应用手动配置'),
            trailing: const Icon(Icons.copy),
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: '127.0.0.1:${settings.localPort}'),
              );
              _toast('已复制 127.0.0.1:${settings.localPort}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('sing-box 核心'),
            subtitle: Text(
              CoreEnv.hasSingBox
                  ? '已就绪: ${CoreEnv.singBoxPath}'
                  : '未找到 sing-box 二进制!',
            ),
            trailing: IconButton(
              tooltip: '重新检测',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () async {
                SingBoxLocator.reset();
                final path = await SingBoxLocator.locate();
                if (mounted) setState(() {});
                _toast(path != null && path.isNotEmpty
                    ? 'sing-box 核心已就绪'
                    : '仍未找到 sing-box 二进制');
              },
            ),
          ),
          const Divider(),
          _section('代理模式'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('代理模式'),
            subtitle: Text(settings.proxyMode == 'tun'
                ? 'TUN 全局(需要 root 或 VpnService)'
                : '本地代理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editProxyMode,
          ),
          if (settings.proxyMode == 'tun')
            ListTile(
              leading: const Icon(Icons.settings_input_antenna),
              title: const Text('Android VPN 接口名'),
              subtitle: Text(settings.vpnInterface.isEmpty
                  ? '默认(tun0)'
                  : settings.vpnInterface),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editText(
                  'Android VPN 接口名', settings.vpnInterface, (v) {
                final s = Repository.instance.settings.copy();
                s.vpnInterface = v;
                Repository.instance.updateSettings(s);
              }, hint: '留空使用默认'),
            ),
          const Divider(),
          _section('Clash API'),
          SwitchListTile(
            secondary: const Icon(Icons.dashboard_outlined),
            title: const Text('启用 Clash API'),
            subtitle: Text(settings.clashApiEnabled
                ? '控制台: http://127.0.0.1:${settings.clashApiPort}'
                : '关闭'),
            value: settings.clashApiEnabled,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.clashApiEnabled = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Clash 面板'),
            subtitle: Text(settings.clashApiEnabled
                ? '控制台: http://127.0.0.1:${settings.clashApiPort}'
                : '启用 Clash API 后可用'),
            enabled: settings.clashApiEnabled,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DashboardPage(
                  url: CoreEnv.dashboardUrl(settings.clashApiPort),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.numbers),
            title: const Text('API 端口'),
            subtitle: Text('${settings.clashApiPort}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPortDialog('Clash API 端口',
                settings.clashApiPort.toString(), (v) {
              final s = Repository.instance.settings.copy();
              s.clashApiPort = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('API 密钥'),
            subtitle: Text(settings.clashApiSecret.isEmpty
                ? '无(不启用认证)'
                : '已设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('Clash API 密钥',
                settings.clashApiSecret, (v) {
              final s = Repository.instance.settings.copy();
              s.clashApiSecret = v;
              Repository.instance.updateSettings(s);
            }, hint: '留空不启用认证'),
          ),
          const Divider(),
          _section('DNS'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_tethering),
            title: const Text('FakeIP'),
            subtitle: const Text('TUN/VPN 模式生效,分配虚拟 IP 加速解析'),
            value: settings.enableFakeDns,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.enableFakeDns = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('远端 DNS'),
            subtitle: Text(settings.remoteDns),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('远端 DNS', settings.remoteDns, (v) {
              final s = Repository.instance.settings.copy();
              s.remoteDns = v;
              Repository.instance.updateSettings(s);
            }, hint: 'https://1.1.1.1/dns-query'),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('直连 DNS'),
            subtitle: Text(settings.directDns),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('直连 DNS', settings.directDns, (v) {
              final s = Repository.instance.settings.copy();
              s.directDns = v;
              Repository.instance.updateSettings(s);
            }, hint: 'localhost'),
          ),
          const Divider(),
          _section('路由行为'),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('绕过局域网'),
            subtitle: const Text('局域网流量直连'),
            value: settings.bypassLan,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.bypassLan = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.vpn_lock_outlined),
            title: const Text('IPv6 模式'),
            subtitle: Text(_ipv6ModeName(settings.ipv6Mode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editIpv6Mode,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.travel_explore),
            title: const Text('协议嗅探'),
            value: settings.sniff,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.sniff = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.flash_on_outlined),
            title: const Text('TCP Fast Open'),
            value: settings.tcpFastOpen,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.tcpFastOpen = v;
              Repository.instance.updateSettings(s);
            },
          ),
          const Divider(),
          _section('TUN 参数'),
          ListTile(
            leading: const Icon(Icons.adjust),
            title: const Text('TUN 网卡地址'),
            subtitle: Text(settings.tunAddress),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('TUN 网卡地址', settings.tunAddress, (v) {
              final s = Repository.instance.settings.copy();
              s.tunAddress = v;
              Repository.instance.updateSettings(s);
            }, hint: '172.19.0.1/30'),
          ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('TUN MTU'),
            subtitle: Text('${settings.tunMtu}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPortDialog('TUN MTU',
                settings.tunMtu.toString(), (v) {
              final s = Repository.instance.settings.copy();
              s.tunMtu = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alt_route),
            title: const Text('Strict Route'),
            subtitle: const Text('严格路由表'),
            value: settings.strictRoute,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.strictRoute = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_input_component),
            title: const Text('TUN 实现'),
            subtitle: Text(_tunStackName(settings.tunStack)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editTunStack,
          ),
          const Divider(),
          _section('自定义配置(高级)'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('全局自定义配置'),
            subtitle: Text(settings.globalCustomConfig.isEmpty
                ? '未设置'
                : '已设置 ${settings.globalCustomConfig.length} 字符'),
            trailing: const Icon(Icons.edit_note),
            onTap: _editGlobalConfig,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.rule),
            title: const Text('规则集资源'),
            subtitle: const Text('管理已下载的 .srs 规则集文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AssetsPage()),
            ),
          ),
          const Divider(),
          _section('数据(备份/恢复)'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份数据'),
            subtitle: const Text('保存/恢复全部数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('恢复数据'),
            subtitle: const Text('从备份列表选择并恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showBackups,
          ),
          const Divider(),
          _section('通用'),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('速度刷新间隔(秒)'),
            subtitle: Text('${settings.speedInterval}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editInt('速度刷新间隔(秒)', settings.speedInterval, (v) {
              final s = Repository.instance.settings.copy();
              s.speedInterval = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('自动连接'),
            subtitle: const Text('启动后自动开启代理'),
            value: settings.isAutoConnect,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.isAutoConnect = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.data_usage),
            title: const Text('节点流量统计'),
            
            value: settings.profileTrafficStatistics,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.profileTrafficStatistics = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.speed),
            title: const Text('显示直连速度'),
            
            value: settings.showDirectSpeed,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.showDirectSpeed = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('通知栏显示分组名'),
            
            value: settings.showGroupInNotification,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.showGroupInNotification = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('始终显示服务器地址'),
            
            value: settings.alwaysShowAddress,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.alwaysShowAddress = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_tethering),
            title: const Text('标记为计费网络'),
            subtitle: const Text('Android 流量统计'),
            value: settings.meteredNetwork,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.meteredNetwork = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.power),
            title: const Text('保持唤醒锁'),
            
            value: settings.acquireWakeLock,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.acquireWakeLock = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.view_agenda),
            title: const Text('显示底部导航栏'),
            
            value: settings.showBottomBar,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.showBottomBar = v;
              Repository.instance.updateSettings(s);
            },
          ),

          const Divider(),
          _section('入站/路由'),
          SwitchListTile(
            secondary: const Icon(Icons.apps),
            title: const Text('分应用代理'),
            subtitle: const Text('仅 TUN/VPN 模式生效,本地代理模式不适用'),
            value: settings.proxyApps,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.proxyApps = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_box_outlined),
            title: const Text('选择代理应用'),
            subtitle: Text(
              settings.proxyAppList.isEmpty
                  ? '未选择(开启分应用代理后仅所选应用走代理)'
                  : '已选 ${settings.proxyAppList.length} 个应用',
            ),
            enabled: settings.proxyApps,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AppSelectorPage()),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lan),
            title: const Text('核心层绕过局域网'),
            
            value: settings.bypassLanInCore,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.bypassLanInCore = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.http),
            title: const Text('追加 HTTP 代理入站'),
            subtitle: const Text('需 VPN 模式'),
            value: settings.appendHttpProxy,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.appendHttpProxy = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.language),
            title: const Text('允许局域网访问本地代理'),
            subtitle: const Text('入站监听 0.0.0.0'),
            value: settings.allowAccess,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.allowAccess = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dns),
            title: const Text('DNS 遵循路由分流'),
            subtitle: const Text('控制自定义 DNS 规则,与全局 DNS 解析方式无关'),
            
            value: settings.enableDnsRouting,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.enableDnsRouting = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.travel_explore),
            title: const Text('连接目标解析为 IP'),
            
            value: settings.resolveDestination,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.resolveDestination = v;
              Repository.instance.updateSettings(s);
            },
          ),

          const Divider(),
          _section('连接/安全'),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('测速地址'),
            subtitle: Text(settings.connectionTestURL),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('测速地址', settings.connectionTestURL, (v) {
              final s = Repository.instance.settings.copy();
              s.connectionTestURL = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('App TLS 版本'),
            subtitle: Text(settings.appTLSVersion.isEmpty ? '默认' : settings.appTLSVersion),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('App TLS 版本', settings.appTLSVersion, (v) {
              final s = Repository.instance.settings.copy();
              s.appTLSVersion = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_off),
            title: const Text('网络切换重置连接'),
            
            value: settings.networkChangeResetConnections,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.networkChangeResetConnections = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny),
            title: const Text('唤醒时重置连接'),
            
            value: settings.wakeResetConnections,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.wakeResetConnections = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.verified_user),
            title: const Text('全局跳过证书校验'),
            
            value: settings.globalAllowInsecure,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.globalAllowInsecure = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_open),
            title: const Text('按需允许不安全连接'),
            
            value: settings.allowInsecureOnRequest,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.allowInsecureOnRequest = v;
              Repository.instance.updateSettings(s);
            },
          ),

          const Divider(),
          _section('外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_themeName(settings.theme)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editTheme,
          ),
          const Divider(),
          _section('日志'),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('日志级别'),
            subtitle: Text(settings.logLevel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editLogLevel,
          ),
          const Divider(),
          _section('测速'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('测速超时'),
            subtitle: Text('${settings.urlTestTimeout} ms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editTimeout,
          ),
          const Divider(),
          _section('混合端口'),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('混合端口'),
            subtitle: Text(settings.mixedPort == 0
                ? '禁用'
                : '${settings.mixedPort} (SOCKS5 + HTTP)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ctrl = TextEditingController(
                  text: settings.mixedPort.toString());
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('混合端口'),
                  content: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '0 = 禁用'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                final v = int.tryParse(ctrl.text.trim());
                if (v == null || v < 0 || v > 65535) {
                  _toast('端口无效');
                  return;
                }
                final s = Repository.instance.settings.copy();
                s.mixedPort = v;
                Repository.instance.updateSettings(s);
              }
            },
          ),
          const Divider(),
          _section('订阅自动更新'),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('启用自动更新'),
            subtitle: const Text('定时自动更新订阅'),
            value: settings.autoUpdateSubscription,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.autoUpdateSubscription = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('更新间隔(分钟)'),
            subtitle: Text('${settings.autoUpdateInterval} 分钟'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editInt('更新间隔(分钟)',
                settings.autoUpdateInterval, (v) {
              final s = Repository.instance.settings.copy();
              s.autoUpdateInterval = v;
              Repository.instance.updateSettings(s);
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_tethering),
            title: const Text('计费网络时更新'),
            subtitle: const Text('移动数据网络下也更新'),
            value: settings.updateOnMeteredNetwork,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.updateOnMeteredNetwork = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('自定义 User-Agent'),
            subtitle: Text(settings.customUserAgent.isEmpty
                ? '默认'
                : settings.customUserAgent),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('自定义 User-Agent',
                settings.customUserAgent, (v) {
              final s = Repository.instance.settings.copy();
              s.customUserAgent = v;
              Repository.instance.updateSettings(s);
            }, hint: '留空使用默认'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.delete_sweep_outlined),
            title: const Text('订阅去重'),
            subtitle: const Text('自动移除重复节点'),
            value: settings.subscriptionDeduplication,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.subscriptionDeduplication = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dns),
            title: const Text('强制解析订阅地址'),
            subtitle: const Text('更新时强制 DNS 解析'),
            value: settings.subscriptionForceResolve,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.subscriptionForceResolve = v;
              Repository.instance.updateSettings(s);
            },
          ),
          const Divider(),
          _section('插件'),
          SwitchListTile(
            secondary: const Icon(Icons.extension_outlined),
            title: const Text('启用插件'),
            value: settings.pluginEnabled,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.pluginEnabled = v;
              Repository.instance.updateSettings(s);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('插件路径'),
            subtitle: Text(settings.pluginPath.isEmpty
                ? '未设置'
                : settings.pluginPath),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editText('插件路径', settings.pluginPath, (v) {
              final s = Repository.instance.settings.copy();
              s.pluginPath = v;
              Repository.instance.updateSettings(s);
            }, hint: '/path/to/plugins'),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('插件管理'),
            subtitle: const Text('查看和管理已安装的插件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PluginsPage()),
            ),
          ),
          const Divider(),
          _section('协议支持'),
          SwitchListTile(
            secondary: const Icon(Icons.vpn_lock),
            title: const Text('V2Ray 支持'),
            subtitle: const Text('启用 V2Ray 协议支持'),
            value: settings.v2rayEnabled,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.v2rayEnabled = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Mieru 支持'),
            subtitle: const Text('启用 Mieru 协议支持'),
            value: settings.mieruEnabled,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.mieruEnabled = v;
              Repository.instance.updateSettings(s);
            },
          ),
          const Divider(),
          _section('通知'),
          SwitchListTile(
            secondary: const Icon(Icons.speed),
            title: const Text('通知栏显示速度'),
            subtitle: const Text('在通知中显示实时速度'),
            value: settings.showSpeedInNotification,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.showSpeedInNotification = v;
              Repository.instance.updateSettings(s);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.account_tree_outlined),
            title: const Text('通知栏显示链路'),
            subtitle: const Text('在通知中显示节点链路信息'),
            value: settings.showChainInNotification,
            onChanged: (v) {
              final s = Repository.instance.settings.copy();
              s.showChainInNotification = v;
              Repository.instance.updateSettings(s);
            },
          ),
          const Divider(),
          _section('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('NekoBox Flutter · 基于 sing-box'),
            onTap: () => _toast('NekoBox Flutter v1.0.0\n基于 sing-box 核心'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

  String _themeName(String theme) {
    switch (theme) {
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      default:
        return '跟随系统';
    }
  }

  Future<void> _editPort() async {
    final ctrl = TextEditingController(
        text: Repository.instance.settings.localPort.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本地代理端口'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '默认 2080'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final port = int.tryParse(ctrl.text.trim());
      if (port == null || port <= 0 || port > 65535) {
        _toast('端口无效');
        return;
      }
      await Repository.instance.setLocalPort(port);
    }
  }

  Future<void> _editProxyMode() async {
    final current = Repository.instance.settings.proxyMode;
    final ok = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('代理模式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'local'),
            child: Row(
              children: [
                Radio<String>(
                    value: 'local',
                    groupValue: current,
                    onChanged: null),
                const Text('本地代理(127.0.0.1:端口)'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'tun'),
            child: Row(
              children: [
                Radio<String>(
                    value: 'tun',
                    groupValue: current,
                    onChanged: null),
                const Text('TUN 全局(需要 root 或 VpnService)'),
              ],
            ),
          ),
        ],
      ),
    );
    if (ok != null && ok != current) {
      // 选 TUN 模式:先走 VpnService 授权流程(Android 13+ 还顺带通知权限)
      if (ok == 'tun' && Platform.isAndroid) {
        try {
          final bridge = CoreEnv.androidProxyBridge;
          if (bridge != null) {
            final authorized = await bridge.prepareVpn();
            if (!authorized) {
              _toast('TUN 模式需要 VPN 授权,请在弹窗中允许');
            }
          }
        } catch (e) {
          _toast('VPN 授权调用失败: $e');
        }
      }
      final s = Repository.instance.settings.copy();
      s.proxyMode = ok;
      await Repository.instance.updateSettings(s);
      _toast(ok == 'tun'
          ? 'TUN 模式(需 VpnService 后端,完整接管二期)'
          : '已切换为本地代理');
    }
  }

  Future<void> _editTheme() async {
    final current = Repository.instance.settings.theme;
    final ok = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('主题'),
        children: ['system', 'light', 'dark']
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Row(
                    children: [
                      Radio<String>(
                          value: t,
                          groupValue: current,
                          onChanged: null),
                      Text(_themeName(t)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (ok != null && ok != current) {
      final s = Repository.instance.settings.copy();
      s.theme = ok;
      await Repository.instance.updateSettings(s);
    }
  }

  Future<void> _editLogLevel() async {
    final current = Repository.instance.settings.logLevel;
    const levels = ['trace', 'debug', 'info', 'warn', 'error'];
    final ok = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('日志级别'),
        children: levels
            .map((l) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, l),
                  child: Row(
                    children: [
                      Radio<String>(
                          value: l,
                          groupValue: current,
                          onChanged: null),
                      Text(l.toUpperCase()),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (ok != null && ok != current) {
      final s = Repository.instance.settings.copy();
      s.logLevel = ok;
      await Repository.instance.updateSettings(s);
    }
  }

  Future<void> _editTimeout() async {
    final ctrl = TextEditingController(
        text: Repository.instance.settings.urlTestTimeout.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('测速超时(毫秒)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final t = int.tryParse(ctrl.text.trim());
      if (t == null || t <= 0) {
        _toast('超时时间无效');
        return;
      }
      final s = Repository.instance.settings.copy();
      s.urlTestTimeout = t;
      await Repository.instance.updateSettings(s);
    }
  }

  String _tunStackName(String stack) {
    switch (stack) {
      case 'gvisor':
        return 'gVisor(兼容性好)';
      case 'mixed':
        return 'Mixed(自动)';
      default:
        return 'System(性能好)';
    }
  }

  String _ipv6ModeName(int mode) {
    switch (mode) {
      case 1:
        return '启用';
      case 2:
        return '优先';
      case 3:
        return '仅 IPv6';
      default:
        return '禁用';
    }
  }

  Future<void> _editIpv6Mode() async {
    final current = Repository.instance.settings.ipv6Mode;
    const labels = ['禁用', '启用', '优先', '仅 IPv6'];
    final ok = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('IPv6 模式'),
        children: List.generate(4, (i) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, i),
            child: Row(
              children: [
                Radio<int>(value: i, groupValue: current, onChanged: null),
                Text(labels[i]),
              ],
            ),
          );
        }),
      ),
    );
    if (ok != null && ok != current) {
      final s = Repository.instance.settings.copy();
      s.ipv6Mode = ok;
      await Repository.instance.updateSettings(s);
    }
  }

  Future<void> _editTunStack() async {
    final current = Repository.instance.settings.tunStack;
    final ok = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('TUN 实现'),
        children: ['system', 'gvisor', 'mixed']
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Row(
                    children: [
                      Radio<String>(
                          value: t,
                          groupValue: current,
                          onChanged: null),
                      Text(_tunStackName(t)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (ok != null && ok != current) {
      final s = Repository.instance.settings.copy();
      s.tunStack = ok;
      await Repository.instance.updateSettings(s);
    }
  }

  Future<void> _editGlobalConfig() async {
    final ctrl = TextEditingController(
        text: Repository.instance.settings.globalCustomConfig);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全局自定义配置(merge 进 sing-box 配置)'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: '{"route":{"final":"direct"}}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final s = Repository.instance.settings.copy();
      s.globalCustomConfig = ctrl.text.trim();
      await Repository.instance.updateSettings(s);
    }
  }

  Future<void> _openDashboard(int port) async {
    final uri = Uri.parse(CoreEnv.dashboardUrl(port));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开面板: ${uri.toString()}')),
      );
    }
  }

  Future<void> _doBackup() async {
    try {
      final path = await Repository.instance.backup();
      _toast('备份成功: ${path.split(Platform.pathSeparator).last}');
    } catch (e) {
      _toast('备份失败: $e');
    }
  }

  Future<void> _showBackups() async {
    final backups = await Repository.instance.listBackups();
    if (backups.isEmpty) {
      _toast('暂无备份,先执行「备份数据」');
      return;
    }
    final sel = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择要恢复的备份'),
        children: backups.map((f) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f.path),
              child: Row(
                children: [
                  const Icon(Icons.storage, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.path.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )).toList(),
      ),
    );
    if (sel == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text(
            '恢复将覆盖当前全部数据,且正在运行的连接会中断。确定继续?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Repository.instance.restoreBackup(sel);
        _toast('已恢复备份');
      } catch (e) {
        _toast('恢复失败: $e');
      }
    }
  }

  Future<void> _editPortDialog(
      String title, String current, void Function(int) onChanged) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final v = int.tryParse(ctrl.text.trim());
      if (v == null || v <= 0 || v > 65535) {
        _toast('数值无效');
        return;
      }
      onChanged(v);
    }
  }

  Future<void> _editInt(
      String title, int current, void Function(int) onChanged) async {
    final ctrl = TextEditingController(text: current.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final v = int.tryParse(ctrl.text.trim());
      if (v != null && v > 0) onChanged(v);
    }
  }

  Future<void> _editText(
      String title, String current, void Function(String) onChanged,
      {String hint = ''}) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) onChanged(ctrl.text.trim());
  }
}