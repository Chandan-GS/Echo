import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGranted;
  final ValueChanged<bool>? onChanged;

  const PermissionTile({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGranted,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 26),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: isGranted, onChanged: onChanged),
        ],
      ),
    );
  }
}
