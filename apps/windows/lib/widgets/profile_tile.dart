import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 桌面节点行(仿原版卡片信息结构,桌面化紧凑样式)。
class ProfileTile extends StatelessWidget {
  final Profile profile;
  final bool selected;
  final bool isCurrent;
  final VoidCallback? onTap;

  const ProfileTile({
    super.key,
    required this.profile,
    required this.selected,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delayColor = _delayColor(profile.delay, scheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: selected ? 1.5 : 0,
        ),
      ),
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _typeBadge(profile.type, scheme),
              const SizedBox(width: 12),
              // 名称(占 30%)
              SizedBox(
                width: 240,
                child: Text(
                  profile.displayName(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              // 类型
              SizedBox(
                width: 110,
                child: Text(
                  ProfileType.displayName(profile.type),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              // 地址
              Expanded(
                child: Text(
                  '${profile.serverAddress}:${profile.serverPort}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              // 延迟
              SizedBox(
                width: 80,
                child: profile.delay >= 0
                    ? Text(
                        '${profile.delay} ms',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: delayColor,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: '右键更多操作',
                child: Icon(Icons.more_vert,
                    size: 16, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String type, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        ProfileType.displayName(type).substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  static Color _delayColor(int delay, ColorScheme scheme) {
    if (delay < 0) return scheme.outline;
    if (delay < 200) return const Color(0xFF2E7D32);
    if (delay < 500) return const Color(0xFFF9A825);
    return const Color(0xFFC62828);
  }
}
