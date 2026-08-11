import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 协议类型图标(仿原版左侧圆形类型标识)。
class TypeIcon extends StatelessWidget {
  final String type;
  final double size;

  const TypeIcon({super.key, required this.type, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      alignment: Alignment.center,
      child: Icon(_iconFor(type), color: color, size: size * 0.58),
    );
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case ProfileType.shadowsocks:
        return Icons.blur_circular;
      case ProfileType.vmess:
        return Icons.vpn_lock_outlined;
      case ProfileType.vless:
        return Icons.bolt_outlined;
      case ProfileType.trojan:
        return Icons.shield_outlined;
      case ProfileType.tuic:
        return Icons.speed_outlined;
      case ProfileType.hysteria2:
        return Icons.air;
      case ProfileType.wireguard:
        return Icons.lock_outline;
      case ProfileType.http:
        return Icons.language;
      case ProfileType.socks:
        return Icons.route_outlined;
      case ProfileType.ssh:
        return Icons.terminal;
      case ProfileType.anytls:
        return Icons.enhanced_encryption_outlined;
      case ProfileType.shadowtls:
        return Icons.shield_moon_outlined;
      case ProfileType.chain:
        return Icons.link;
      default:
        return Icons.dns_outlined;
    }
  }

  static Color _colorFor(String type) {
    switch (type) {
      case ProfileType.shadowsocks:
        return const Color(0xFF00897B);
      case ProfileType.vmess:
        return const Color(0xFF1E88E5);
      case ProfileType.vless:
        return const Color(0xFF8E24AA);
      case ProfileType.trojan:
        return const Color(0xFFE53935);
      case ProfileType.tuic:
        return const Color(0xFFFB8C00);
      case ProfileType.hysteria2:
        return const Color(0xFF43A047);
      case ProfileType.wireguard:
        return const Color(0xFF546E7A);
      case ProfileType.http:
        return const Color(0xFF039BE5);
      case ProfileType.socks:
        return const Color(0xFF6D4C41);
      case ProfileType.ssh:
        return const Color(0xFF455A64);
      case ProfileType.anytls:
        return const Color(0xFFD81B60);
      case ProfileType.shadowtls:
        return const Color(0xFF3949AB);
      default:
        return const Color(0xFF757575);
    }
  }
}
