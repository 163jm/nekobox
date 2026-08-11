import 'dart:convert';

/// 订阅组,对应原版 [ProxyGroup]。
class ProxyGroup {
  int id;
  String name;

  /// 订阅链接;为空表示手动组
  String url;

  /// true = 订阅组(可更新),false = 手动组
  bool subscription;
  int updateTime;

  /// 组内当前选中节点 id(仅本组范围)
  int selectedProfileId;

  /// 前置代理节点 id(链式:客户端先连它);-1 = 无(对齐原版 frontProxy)
  int frontProxyId;

  /// 落地代理节点 id(链式:最终出口);-1 = 无(对齐原版 landingProxy)
  int landingProxyId;

  /// 节点排序:0=原始顺序 1=按名称 2=按延迟(对齐原版 GroupOrder)
  int order;

  /// 组显示顺序(拖拽排序,对齐原版 userOrder)
  int userOrder;

  ProxyGroup({
    this.id = 0,
    this.name = '',
    this.url = '',
    this.subscription = false,
    this.updateTime = 0,
    this.selectedProfileId = 0,
    this.frontProxyId = -1,
    this.landingProxyId = -1,
    this.order = 0,
    this.userOrder = 0,
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) {
    return ProxyGroup(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      subscription: (json['subscription'] as bool?) ?? false,
      updateTime: (json['updateTime'] as num?)?.toInt() ?? 0,
      selectedProfileId: (json['selectedProfileId'] as num?)?.toInt() ?? 0,
      frontProxyId: (json['frontProxyId'] as num?)?.toInt() ?? -1,
      landingProxyId: (json['landingProxyId'] as num?)?.toInt() ?? -1,
      order: (json['order'] as num?)?.toInt() ?? 0,
      userOrder: (json['userOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'subscription': subscription,
      'updateTime': updateTime,
      'selectedProfileId': selectedProfileId,
      'frontProxyId': frontProxyId,
      'landingProxyId': landingProxyId,
      'order': order,
      'userOrder': userOrder,
    };
  }

  /// 组内节点由 Repository 管理,这里只存元数据。
  /// [clone] 供 UI 复制编辑。
  ProxyGroup clone() => ProxyGroup.fromJson(jsonDecode(jsonEncode(toJson())));
}
