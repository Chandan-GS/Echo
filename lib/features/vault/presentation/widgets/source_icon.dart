import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:project_echo/core/services/app_icon_service.dart';

/// The real launcher icon of the app behind [source], or [fallback] when
/// there isn't one (not Android, uninstalled, or never seen on a notification).
class SourceIcon extends StatefulWidget {
  final String source;
  final double size;
  final Widget fallback;

  const SourceIcon({
    super.key,
    required this.source,
    required this.size,
    required this.fallback,
  });

  @override
  State<SourceIcon> createState() => _SourceIconState();
}

class _SourceIconState extends State<SourceIcon> {
  Future<Uint8List?>? _icon;

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  @override
  void didUpdateWidget(covariant SourceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _lookUp();
  }

  void _lookUp() {
    _icon = AppIconService.isResolved(widget.source)
        ? null
        : AppIconService.iconFor(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    if (_icon == null) return _paint(AppIconService.cached(widget.source));
    return FutureBuilder<Uint8List?>(
      future: _icon,
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? _paint(snap.data)
          // Hold the space, not the glyph, so a real icon doesn't flash in over it.
          : SizedBox.square(dimension: widget.size),
    );
  }

  Widget _paint(Uint8List? png) {
    if (png == null) return widget.fallback;
    return Image.memory(
      png,
      width: widget.size,
      height: widget.size,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
