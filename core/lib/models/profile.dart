import 'dart:convert';

import 'profile_type.dart';

class Profile {
  int id;
  int groupId;
  String type;
  String name;
  String serverAddress;
  int serverPort;
  String notes;

  Map<String, dynamic> bean;

  int delay;
  int sortIndex;
  bool isSelected;

  int tx;
  int rx;

  Profile({
    this.id = 0,
    this.groupId = 0,
    String? type,
    this.name = '',
    this.serverAddress = '',
    this.serverPort = 0,
    this.notes = '',
    Map<String, dynamic>? bean,
    this.delay = -1,
    this.sortIndex = 0,
    this.isSelected = false,
    this.tx = 0,
    this.rx = 0,
  })  : type = type ?? ProfileType.vmess,
        bean = bean ?? {};

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      groupId: (json['groupId'] as num?)?.toInt() ?? 0,
      type: (json['type'] as String?) ?? ProfileType.vmess,
      name: (json['name'] as String?) ?? '',
      serverAddress: (json['serverAddress'] as String?) ?? '',
      serverPort: (json['serverPort'] as num?)?.toInt() ?? 0,
      notes: (json['notes'] as String?) ?? '',
      bean: (json['bean'] as Map<String, dynamic>?) ?? {},
      delay: (json['delay'] as num?)?.toInt() ?? -1,
      sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
      isSelected: (json['isSelected'] as bool?) ?? false,
      tx: (json['tx'] as num?)?.toInt() ?? 0,
      rx: (json['rx'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'type': type,
      'name': name,
      'serverAddress': serverAddress,
      'serverPort': serverPort,
      'notes': notes,
      'bean': bean,
      'delay': delay,
      'sortIndex': sortIndex,
      'isSelected': isSelected,
      'tx': tx,
      'rx': rx,
    };
  }

  Profile copy() => Profile.fromJson(jsonDecode(jsonEncode(toJson())));

  String displayName() {
    if (name.isNotEmpty) return name;
    if (serverAddress.isNotEmpty) return '$serverAddress:$serverPort';
    return '(未命名)';
  }

  String displayTraffic() {
    if (tx == 0 && rx == 0) return '';
    return '↓${_fmtBytes(rx)} ↑${_fmtBytes(tx)}';
  }

  static String _fmtBytes(int b) {
    if (b <= 0) return '0B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double v = b.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)}${units[i]}';
  }
}
