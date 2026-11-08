import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_sections.dart';

/// Every group busy today, busiest first, muted or not.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<BusyGroup> _groups = const [];
  Map<String, String> _summaries = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final feed = await HomeFeed.load(DateTime.now());
      final kept = await GroupSummaries.cached();
      if (!mounted) return;
      setState(() {
        _groups = feed.allGroups;
        _summaries = kept;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom + 30;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: 'Busy groups'),
      body: !_loaded
          ? const SizedBox.shrink()
          : _groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No group has been busy today.\nThey’ll show here once '
                  'one gets going.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    height: 1.5,
                    color: c.textSecondary,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(24, 0, 24, bottom),
              itemCount: _groups.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      'Busiest first. Echo pulls out what’s for you, muted '
                      'or not.',
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        height: 1.5,
                        color: c.textSecondary,
                      ),
                    ),
                  );
                }
                final g = _groups[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GroupRow(
                    group: g,
                    busiest: _groups.first.count,
                    summary: _summaries[g.name],
                  ),
                );
              },
            ),
    );
  }
}
