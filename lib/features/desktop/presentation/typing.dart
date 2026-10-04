import 'package:flutter/widgets.dart';

/// Whether the keyboard is in a field the owner can type into, where letters
/// are words and not shortcuts. Selectable but read-only text (a message
/// clicked to copy from) doesn't count, so the shortcuts keep working.
bool typingInAField() {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  final widget = focus.widget;
  final field = widget is EditableText
      ? widget
      : focus.findAncestorWidgetOfExactType<EditableText>();
  return field != null && !field.readOnly;
}
