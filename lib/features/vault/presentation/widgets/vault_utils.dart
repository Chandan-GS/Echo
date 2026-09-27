import 'package:flutter/material.dart';
import 'package:project_echo/features/vault/data/vault_icons.dart';

IconData getSourceIcon(String source) {
  switch (source.toLowerCase()) {
    case 'slack':
      return Icons.chat_bubble_outline_rounded;
    case 'sms':
      return Icons.sms_outlined;
    case 'whatsapp':
      return Icons.message_outlined;
    case 'calendar':
      return Icons.calendar_today_outlined;
    case 'gmail':
      return Icons.mail_outline_rounded;
    case 'email':
      return Icons.mail_outline_rounded;
    default:
      return Icons.notifications_none_rounded;
  }
}

/// The glyph the user picked for [source] in its category sheet, if any.
/// Looked up in [curatedVaultIcons] so the icon font can still be tree-shaken.
IconData? customIconFor(String source, Map<String, int> customIcons) {
  final code = customIcons[source.toLowerCase().trim()];
  if (code == null) return null;
  for (final icon in curatedVaultIcons) {
    if (icon.codePoint == code) return icon;
  }
  return null;
}
