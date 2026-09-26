import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:project_echo/core/services/app_icon_service.dart';

/// The real launcher icon of an app, or [fallback] when there isn't one (not
/// Android, uninstalled, or never seen on a notification).
class SourceIcon extends StatefulWidget {
  /// A Vault category: shows its busiest app's icon.
  final String? source;

  /// A specific app, by package.
  final String? packageName;

  final double size;
  final Widget fallback;

  const SourceIcon({
    super.key,
    required String this.source,
    required this.size,
    required this.fallback,
  }) : packageName = null;

  const SourceIcon.app({
    super.key,
    required String this.packageName,
    required this.size,
    required this.fallback,
  }) : source = null;

  @override
  State<SourceIcon> createState() => _SourceIconState();
}

class _SourceIconState extends State<SourceIcon> {
  Future<Uint8List?>? _icon;

  bool get _resolved => widget.packageName != null
      ? AppIconService.isPackageResolved(widget.packageName!)
      : AppIconService.isResolved(widget.source!);

  Uint8List? get _cached => widget.packageName != null
      ? AppIconService.cachedPackage(widget.packageName!)
      : AppIconService.cached(widget.source!);

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  @override
  void didUpdateWidget(covariant SourceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.packageName != widget.packageName) {
      _lookUp();
    }
  }

  void _lookUp() {
    if (_resolved) {
      _icon = null;
    } else if (widget.packageName != null) {
      _icon = AppIconService.iconForPackage(widget.packageName!);
    } else {
      _icon = AppIconService.iconFor(widget.source!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_icon == null) return _paint(_cached);
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
