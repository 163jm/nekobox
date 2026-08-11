import 'dart:convert';

class AppSettings {
  // —— 代理核心 ——
  int localPort;
  String proxyMode;
  bool systemProxy;
  String tunAddress;
  int tunMtu;
  String tunStack;
  String vpnInterface;
  String globalCustomConfig;

  // —— 路由 / 网络 ——
  String routeFinal;
  bool bypassLan;

  /// IPv6 模式: 0=禁用 1=启用 2=优先 3=仅IPv6
  int ipv6Mode;
  bool sniff;
  bool tcpFastOpen;
  bool strictRoute;

  /// 混合端口(同时监听 SOCKS5+HTTP)
  int mixedPort;

  // —— DNS ——
  String remoteDns;
  String directDns;
  bool enableFakeDns;

  // —— Clash API ——
  bool clashApiEnabled;
  int clashApiPort;
  String clashApiSecret;

  // —— 外观 / 测速 ——
  String theme;
  String logLevel;
  int urlTestTimeout;

  // —— 原版设置项 ——
  bool isAutoConnect;
  int speedInterval;
  bool profileTrafficStatistics;
  bool showDirectSpeed;
  bool showGroupInNotification;
  bool alwaysShowAddress;
  bool meteredNetwork;
  bool acquireWakeLock;
  bool showBottomBar;
  bool proxyApps;
  List<String> proxyAppList;
  bool bypassLanInCore;
  bool appendHttpProxy;
  bool allowAccess;
  String connectionTestURL;
  bool networkChangeResetConnections;
  bool wakeResetConnections;
  bool globalAllowInsecure;
  bool allowInsecureOnRequest;
  String appTLSVersion;
  bool enableDnsRouting;
  bool resolveDestination;

  // —— 订阅自动更新 ——
  bool autoUpdateSubscription;
  int autoUpdateInterval;
  bool updateOnMeteredNetwork;
  String customUserAgent;

  // —— 备份 / 数据 ——
  bool subscriptionDeduplication;
  bool subscriptionForceResolve;

  // —— 插件 ——
  bool pluginEnabled;
  String pluginPath;

  // —— V2Ray ——
  bool v2rayEnabled;

  // —— Mieru ——
  bool mieruEnabled;

  // —— 通知 / 前台服务 ——
  bool showSpeedInNotification;
  bool showChainInNotification;

  AppSettings({
    this.localPort = 2080,
    this.proxyMode = 'local',
    this.systemProxy = true,
    this.tunAddress = '172.19.0.1/30',
    this.tunMtu = 9000,
    this.tunStack = 'system',
    this.vpnInterface = '',
    this.globalCustomConfig = '',
    this.routeFinal = '0',
    this.bypassLan = true,
    this.ipv6Mode = 0,
    this.sniff = true,
    this.tcpFastOpen = false,
    this.strictRoute = false,
    this.mixedPort = 0,
    this.remoteDns = 'https://1.1.1.1/dns-query',
    this.directDns = 'localhost',
    this.enableFakeDns = true,
    this.clashApiEnabled = false,
    this.clashApiPort = 9090,
    this.clashApiSecret = '',
    this.theme = 'system',
    this.logLevel = 'info',
    this.urlTestTimeout = 5000,
    this.isAutoConnect = false,
    this.speedInterval = 2,
    this.profileTrafficStatistics = true,
    this.showDirectSpeed = true,
    this.showGroupInNotification = false,
    this.alwaysShowAddress = false,
    this.meteredNetwork = false,
    this.acquireWakeLock = false,
    this.showBottomBar = true,
    this.proxyApps = false,
    this.proxyAppList = const [],
    this.bypassLanInCore = true,
    this.appendHttpProxy = false,
    this.allowAccess = false,
    this.connectionTestURL = 'https://www.gstatic.com/generate_204',
    this.networkChangeResetConnections = true,
    this.wakeResetConnections = false,
    this.globalAllowInsecure = false,
    this.allowInsecureOnRequest = false,
    this.appTLSVersion = '',
    this.enableDnsRouting = true,
    this.resolveDestination = true,
    this.autoUpdateSubscription = false,
    this.autoUpdateInterval = 60,
    this.updateOnMeteredNetwork = true,
    this.customUserAgent = '',
    this.subscriptionDeduplication = true,
    this.subscriptionForceResolve = false,
    this.pluginEnabled = false,
    this.pluginPath = '',
    this.v2rayEnabled = false,
    this.mieruEnabled = false,
    this.showSpeedInNotification = true,
    this.showChainInNotification = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      localPort: (json['localPort'] as num?)?.toInt() ?? 2080,
      proxyMode: (json['proxyMode'] as String?) ?? 'local',
      systemProxy: (json['systemProxy'] as bool?) ?? true,
      tunAddress: (json['tunAddress'] as String?) ?? '172.19.0.1/30',
      tunMtu: (json['tunMtu'] as num?)?.toInt() ?? 9000,
      tunStack: (json['tunStack'] as String?) ?? 'system',
      vpnInterface: (json['vpnInterface'] as String?) ?? '',
      globalCustomConfig: (json['globalCustomConfig'] as String?) ?? '',
      routeFinal: (json['routeFinal'] as String?) ?? '0',
      bypassLan: (json['bypassLan'] as bool?) ?? true,
      ipv6Mode: (json['ipv6Mode'] as num?)?.toInt() ?? 0,
      sniff: (json['sniff'] as bool?) ?? true,
      tcpFastOpen: (json['tcpFastOpen'] as bool?) ?? false,
      strictRoute: (json['strictRoute'] as bool?) ?? false,
      mixedPort: (json['mixedPort'] as num?)?.toInt() ?? 0,
      remoteDns: (json['remoteDns'] as String?) ?? 'https://1.1.1.1/dns-query',
      directDns: (json['directDns'] as String?) ?? 'localhost',
      enableFakeDns: (json['enableFakeDns'] as bool?) ?? true,
      clashApiEnabled: (json['clashApiEnabled'] as bool?) ?? false,
      clashApiPort: (json['clashApiPort'] as num?)?.toInt() ?? 9090,
      clashApiSecret: (json['clashApiSecret'] as String?) ?? '',
      theme: (json['theme'] as String?) ?? 'system',
      logLevel: (json['logLevel'] as String?) ?? 'info',
      urlTestTimeout: (json['urlTestTimeout'] as num?)?.toInt() ?? 5000,
      isAutoConnect: (json['isAutoConnect'] as bool?) ?? false,
      speedInterval: (json['speedInterval'] as num?)?.toInt() ?? 2,
      profileTrafficStatistics: (json['profileTrafficStatistics'] as bool?) ?? true,
      showDirectSpeed: (json['showDirectSpeed'] as bool?) ?? true,
      showGroupInNotification: (json['showGroupInNotification'] as bool?) ?? false,
      alwaysShowAddress: (json['alwaysShowAddress'] as bool?) ?? false,
      meteredNetwork: (json['meteredNetwork'] as bool?) ?? false,
      acquireWakeLock: (json['acquireWakeLock'] as bool?) ?? false,
      showBottomBar: (json['showBottomBar'] as bool?) ?? true,
      proxyApps: (json['proxyApps'] as bool?) ?? false,
      proxyAppList:
          (json['proxyAppList'] as List?)?.whereType<String>().toList() ?? [],
      bypassLanInCore: (json['bypassLanInCore'] as bool?) ?? true,
      appendHttpProxy: (json['appendHttpProxy'] as bool?) ?? false,
      allowAccess: (json['allowAccess'] as bool?) ?? false,
      connectionTestURL: (json['connectionTestURL'] as String?) ??
          'https://www.gstatic.com/generate_204',
      networkChangeResetConnections:
          (json['networkChangeResetConnections'] as bool?) ?? true,
      wakeResetConnections: (json['wakeResetConnections'] as bool?) ?? false,
      globalAllowInsecure: (json['globalAllowInsecure'] as bool?) ?? false,
      allowInsecureOnRequest: (json['allowInsecureOnRequest'] as bool?) ?? false,
      appTLSVersion: (json['appTLSVersion'] as String?) ?? '',
      enableDnsRouting: (json['enableDnsRouting'] as bool?) ?? true,
      resolveDestination: (json['resolveDestination'] as bool?) ?? true,
      autoUpdateSubscription:
          (json['autoUpdateSubscription'] as bool?) ?? false,
      autoUpdateInterval:
          (json['autoUpdateInterval'] as num?)?.toInt() ?? 60,
      updateOnMeteredNetwork:
          (json['updateOnMeteredNetwork'] as bool?) ?? true,
      customUserAgent: (json['customUserAgent'] as String?) ?? '',
      subscriptionDeduplication:
          (json['subscriptionDeduplication'] as bool?) ?? true,
      subscriptionForceResolve:
          (json['subscriptionForceResolve'] as bool?) ?? false,
      pluginEnabled: (json['pluginEnabled'] as bool?) ?? false,
      pluginPath: (json['pluginPath'] as String?) ?? '',
      v2rayEnabled: (json['v2rayEnabled'] as bool?) ?? false,
      mieruEnabled: (json['mieruEnabled'] as bool?) ?? false,
      showSpeedInNotification:
          (json['showSpeedInNotification'] as bool?) ?? true,
      showChainInNotification:
          (json['showChainInNotification'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'localPort': localPort,
      'proxyMode': proxyMode,
      'systemProxy': systemProxy,
      'tunAddress': tunAddress,
      'tunMtu': tunMtu,
      'tunStack': tunStack,
      'vpnInterface': vpnInterface,
      'globalCustomConfig': globalCustomConfig,
      'routeFinal': routeFinal,
      'bypassLan': bypassLan,
      'ipv6Mode': ipv6Mode,
      'sniff': sniff,
      'tcpFastOpen': tcpFastOpen,
      'strictRoute': strictRoute,
      'mixedPort': mixedPort,
      'remoteDns': remoteDns,
      'directDns': directDns,
      'enableFakeDns': enableFakeDns,
      'clashApiEnabled': clashApiEnabled,
      'clashApiPort': clashApiPort,
      'clashApiSecret': clashApiSecret,
      'theme': theme,
      'logLevel': logLevel,
      'urlTestTimeout': urlTestTimeout,
      'isAutoConnect': isAutoConnect,
      'speedInterval': speedInterval,
      'profileTrafficStatistics': profileTrafficStatistics,
      'showDirectSpeed': showDirectSpeed,
      'showGroupInNotification': showGroupInNotification,
      'alwaysShowAddress': alwaysShowAddress,
      'meteredNetwork': meteredNetwork,
      'acquireWakeLock': acquireWakeLock,
      'showBottomBar': showBottomBar,
      'proxyApps': proxyApps,
      'proxyAppList': proxyAppList,
      'bypassLanInCore': bypassLanInCore,
      'appendHttpProxy': appendHttpProxy,
      'allowAccess': allowAccess,
      'connectionTestURL': connectionTestURL,
      'networkChangeResetConnections': networkChangeResetConnections,
      'wakeResetConnections': wakeResetConnections,
      'globalAllowInsecure': globalAllowInsecure,
      'allowInsecureOnRequest': allowInsecureOnRequest,
      'appTLSVersion': appTLSVersion,
      'enableDnsRouting': enableDnsRouting,
      'resolveDestination': resolveDestination,
      'autoUpdateSubscription': autoUpdateSubscription,
      'autoUpdateInterval': autoUpdateInterval,
      'updateOnMeteredNetwork': updateOnMeteredNetwork,
      'customUserAgent': customUserAgent,
      'subscriptionDeduplication': subscriptionDeduplication,
      'subscriptionForceResolve': subscriptionForceResolve,
      'pluginEnabled': pluginEnabled,
      'pluginPath': pluginPath,
      'v2rayEnabled': v2rayEnabled,
      'mieruEnabled': mieruEnabled,
      'showSpeedInNotification': showSpeedInNotification,
      'showChainInNotification': showChainInNotification,
    };
  }

  AppSettings copy() => AppSettings.fromJson(jsonDecode(jsonEncode(toJson())));
}
