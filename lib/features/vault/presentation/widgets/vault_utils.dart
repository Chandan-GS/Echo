import 'package:flutter/material.dart';

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

IconData getCategoryIcon(String source, Map<String, int> customIcons) {
  final lowerSource = source.toLowerCase().trim();
  if (customIcons.containsKey(lowerSource)) {
    return IconData(customIcons[lowerSource]!, fontFamily: 'MaterialIcons');
  }
  return getSourceIcon(source);
}
