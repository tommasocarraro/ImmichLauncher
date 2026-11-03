import 'package:flutter/material.dart';

import '../controllers/launcher_controller.dart';
import '../models/server_config.dart';

/// Coloured dot + text describing whether the server is reachable.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    required this.onlineVia,
    required this.lastChecked,
    required this.onRefresh,
  });

  final ServerStatus status;
  final ConnectionRoute? onlineVia;
  final DateTime? lastChecked;
  final VoidCallback onRefresh;

  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color color, String title) = switch (status) {
      ServerStatus.online => (_green, 'Online'),
      ServerStatus.offline => (_red, 'Offline'),
      ServerStatus.checking => (theme.colorScheme.outline, 'Checking…'),
      ServerStatus.unknown => (theme.colorScheme.outline, 'Unknown'),
    };
    final subtitle = switch (status) {
      ServerStatus.online when onlineVia != null =>
        'Reachable via ${onlineVia!.label}',
      ServerStatus.offline => 'Not reachable locally or via Tailscale',
      _ => null,
    };
    final checked = lastChecked == null
        ? null
        : 'Last check ${TimeOfDay.fromDateTime(lastChecked!).format(context)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
        child: Row(
          children: [
            Semantics(
              label: 'Server status: $title',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Server $title', style: theme.textTheme.titleMedium),
                  if (subtitle != null)
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  if (checked != null)
                    Text(checked, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Check now',
              onPressed: status == ServerStatus.checking ? null : onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}
