import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

/// Picks the people who always get through. Returns the new list, or null if
/// dismissed.
Future<List<String>?> showQuietPeopleSheet(
  BuildContext context,
  List<String> chosen,
) {
  return showModalBottomSheet<List<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (_) => _QuietPeopleSheet(chosen: chosen),
  );
}

class _QuietPeopleSheet extends StatefulWidget {
  final List<String> chosen;
  const _QuietPeopleSheet({required this.chosen});

  @override
  State<_QuietPeopleSheet> createState() => _QuietPeopleSheetState();
}

class _QuietPeopleSheetState extends State<_QuietPeopleSheet> {
  late final Set<String> _chosen = {...widget.chosen};
  List<String> _names = const [];
  bool _loaded = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var names = <String>[];
    try {
      final isar = await IsarDataSource.instance;
      final rows = await isar.rawDatas
          .filter()
          .addressedIsNotNull()
          .sortByTimestampDesc()
          .limit(2000)
          .findAll();
      final seen = <String>{};
      for (final row in await withoutExcludedSources(rows)) {
        final name = row.sender.trim();
        if (name.isNotEmpty && seen.add(name.toLowerCase())) names.add(name);
      }
    } catch (e) {
      debugPrint('Listing people for quiet hours failed: $e');
    }
    // Someone chosen earlier stays listed even if they've gone quiet since.
    final known = names.map((n) => n.toLowerCase()).toSet();
    names = [
      ...widget.chosen.where((n) => !known.contains(n.toLowerCase())),
      ...names,
    ];
    if (mounted) {
      setState(() {
        _names = names;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = _filter.trim().toLowerCase();
    final shown = query.isEmpty
        ? _names
        : _names.where((n) => n.toLowerCase().contains(query)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Always let through',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_chosen.toList()),
                      child: Text(
                        'Done',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: c.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'These people reach you during quiet hours, whatever else is switched off.',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    height: 1.4,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _filter = v),
                  cursorColor: c.primaryGreen,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search people',
                    prefixIcon: Icon(
                      Symbols.search_rounded,
                      size: 20,
                      color: c.textSecondary,
                    ),
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(99),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: !_loaded
                      ? const SizedBox(height: 120)
                      : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              _names.isEmpty
                                  ? "Nobody yet. People you get messages from will show up here."
                                  : 'Nobody by that name.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 13.5,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final name = shown[i];
                            final on = _chosen.any(
                              (n) => n.toLowerCase() == name.toLowerCase(),
                            );
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: on,
                              activeColor: c.primaryGreen,
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              onChanged: (_) => setState(() {
                                if (on) {
                                  _chosen.removeWhere(
                                    (n) =>
                                        n.toLowerCase() == name.toLowerCase(),
                                  );
                                } else {
                                  _chosen.add(name);
                                }
                              }),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
