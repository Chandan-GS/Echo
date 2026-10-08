import 'package:flutter/material.dart';
import 'package:project_echo/features/vault/data/vault_icons.dart';
import 'package:material_symbols_icons/symbols.dart';

IconData getSourceIcon(String source) {
  switch (source.toLowerCase()) {
    case 'slack':
      return Symbols.chat_bubble_rounded;
    case 'sms':
      return Symbols.sms_rounded;
    case 'whatsapp':
      return Symbols.message_rounded;
    case 'calendar':
      return Symbols.calendar_today_rounded;
    case 'gmail':
      return Symbols.mail_rounded;
    case 'email':
      return Symbols.mail_rounded;
    default:
      return Symbols.notifications_rounded;
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
