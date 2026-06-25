import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// A standard reusable AppBar matching the Ask AI / Echo editorial standards.
class EchoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBackPressed;

  const EchoAppBar({super.key, required this.title, this.onBackPressed});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      scrolledUnderElevation: 0,
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          size: 28,
          Icons.arrow_back_ios_new_rounded,
          color: context.colors.textPrimary,
        ),
        onPressed:
            onBackPressed ??
            () {
              if (context.canPop()) {
                context.pop();
              } else {
                Navigator.of(context).pop();
              }
            },
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.displayMedium?.copyWith(color: context.colors.textPrimary),
      ),
      centerTitle: true,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// A Sliver variant of the reusable AppBar, hiding automatically on scroll.
class EchoSliverAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBackPressed;

  const EchoSliverAppBar({super.key, required this.title, this.onBackPressed});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      scrolledUnderElevation: 0,
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      backgroundColor: Colors.transparent,
      elevation: 0,
      floating: true,
      leading: IconButton(
        icon: Icon(
          size: 28,
          Icons.arrow_back_ios_new_rounded,
          color: context.colors.textPrimary,
        ),
        onPressed:
            onBackPressed ??
            () {
              if (context.canPop()) {
                context.pop();
              } else {
                Navigator.of(context).pop();
              }
            },
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.displayMedium?.copyWith(color: context.colors.textPrimary),
      ),
      centerTitle: true,
    );
  }
}
