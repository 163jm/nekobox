import 'package:flutter/material.dart';

import 'package:core/core.dart';

/// 节点卡片(仿原版 layout_profile.xml):
/// [选中竖条] [名称·编辑·分享] / [地址·流量] / [类型·状态]
class ProfileCard extends StatelessWidget {
  final Profile profile;

  /// 是否当前选中节点
  final bool selected;

  /// 当前连接中且为此节点
  final bool isCurrent;

  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  /// 始终显示服务器地址(默认按原版:名称存在时不显示)
  final bool alwaysShowAddress;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onLongPress,
    this.alwaysShowAddress = false,
  });

  String get _statusText {
    if (isCurrent) return '连接中';
    if (profile.delay >= 0) return '可用 ${profile.delay} ms';
    return '';
  }

  Color? _statusColor(ThemeData theme) {
    if (isCurrent) return theme.colorScheme.primary;
    if (profile.delay >= 0) return Colors.green.shade600;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = Color(ProfileType.color(profile.type));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 选中竖条
              Container(
                width: 4,
                color: selected ? scheme.primary : Colors.transparent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行:名称 + 编辑 + 分享
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.displayName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          _IconBtn(
                            icon: Icons.edit_outlined,
                            tooltip: '编辑',
                            onPressed: isCurrent ? null : onEdit,
                          ),
                          _IconBtn(
                            icon: Icons.share_outlined,
                            tooltip: '分享',
                            onPressed: onShare,
                          ),
                        ],
                      ),
                      // 第二行:地址(原版:名称存在时需 alwaysShowAddress 才显示)
                      if (alwaysShowAddress || profile.name.isEmpty)
                        Text(
                          '${profile.serverAddress}:${profile.serverPort}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      // 流量统计(tx/rx)
                      if (profile.displayTraffic().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            profile.displayTraffic(),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      // 第三行:类型(协议色)+ 状态
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ProfileType.displayName(profile.type),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: typeColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_statusText.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.circle, size: 8, color: _statusColor(theme)),
                                const SizedBox(width: 4),
                                Text(
                                  _statusText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _statusColor(theme),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}
