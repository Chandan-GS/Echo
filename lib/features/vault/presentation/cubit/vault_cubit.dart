import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

part 'vault_state.dart';

class VaultCubit extends Cubit<VaultState> {
  StreamSubscription<void>? _isarSubscription;

  VaultCubit() : super(VaultInitial());

  Future<void> loadEntries() async {
    // Set up real-time stream if not already active
    if (_isarSubscription == null) {
      try {
        final isar = await IsarDataSource.instance;
        _isarSubscription = isar.rawDatas.watchLazy().listen((_) async {
          // Data changed in Isar! Reload, keeping the current category
          final currentState = state;
          final selectedCat = currentState is VaultLoaded ? currentState.selectedCategory : 'All';
          
          final items = await IsarDataSource.getAllEntries();
          items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          await _emitLoadedState(items, selectedCat);
        });
      } catch (e) {
        // Ignored if instance fails to load
      }
    }

    emit(VaultLoading());
    try {
      final items = await IsarDataSource.getAllEntries();
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      await _emitLoadedState(items, 'All');
    } catch (e) {
      emit(VaultError('Failed to load notifications: $e'));
    }
  }

  void selectCategory(String category) {
    final currentState = state;
    if (currentState is VaultLoaded) {
      emit(currentState.copyWith(
        selectedCategory: category,
        displayedItems: currentState.groupedItems[category] ?? [],
      ));
    }
  }

  Future<void> deleteCategory(String category) async {
    final currentState = state;
    if (currentState is VaultLoaded) {
      emit(VaultLoading());
      try {
        final prefs = await SharedPreferences.getInstance();
        final aliasesString = prefs.getString('vault_category_aliases') ?? '{}';
        final Map<String, String> categoryAliases = Map<String, String>.from(jsonDecode(aliasesString));
        
        final sourcesToDelete = <String>{category};
        for (final entry in categoryAliases.entries) {
          if (entry.value == category) {
            sourcesToDelete.add(entry.key);
          }
        }
        
        for (final src in sourcesToDelete) {
          await IsarDataSource.deleteEntriesBySource(src);
        }
        
        final remainingItems = await IsarDataSource.getAllEntries();
        remainingItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // Return to 'All' category after deleting
        await _emitLoadedState(remainingItems, 'All');
      } catch (e) {
        emit(VaultError('Failed to delete category: $e'));
        // Fallback to reload everything
        loadEntries();
      }
    }
  }

  Future<void> _emitLoadedState(List<RawData> items, String selectedCategory) async {
    final prefs = await SharedPreferences.getInstance();
    
    final aliasesString = prefs.getString('vault_category_aliases') ?? '{}';
    final Map<String, String> categoryAliases = Map<String, String>.from(jsonDecode(aliasesString));
    
    final blockedCategories = prefs.getStringList('vault_blocked_categories') ?? [];
    
    final iconsString = prefs.getString('vault_category_icons') ?? '{}';
    final Map<String, int> categoryIcons = Map<String, int>.from(jsonDecode(iconsString));

    final Map<String, int> categoryCounts = {'All': 0};
    final Map<String, List<RawData>> grouped = {'All': []};

    for (final item in items) {
      final sourceKey = item.source.trim();
      final defaultSource = sourceKey.isEmpty ? 'Unknown' : 
          '${sourceKey[0].toUpperCase()}${sourceKey.substring(1).toLowerCase()}';
      
      final displaySource = categoryAliases[defaultSource] ?? defaultSource;
      
      grouped.putIfAbsent(displaySource, () => []).add(item);
      grouped['All']!.add(item); // All items go into All, regardless of block status
      
      // Pie chart counts only include unblocked categories
      if (!blockedCategories.contains(displaySource)) {
        categoryCounts[displaySource] = (categoryCounts[displaySource] ?? 0) + 1;
        categoryCounts['All'] = categoryCounts['All']! + 1;
      }
    }

    final categories = grouped.keys.where((c) => c == 'All' || !blockedCategories.contains(c)).toList();
    final displayedItems = grouped[selectedCategory] ?? [];

    emit(VaultLoaded(
      allItems: items,
      groupedItems: grouped,
      categoryCounts: categoryCounts,
      categories: categories,
      selectedCategory: selectedCategory,
      displayedItems: displayedItems,
      categoryAliases: categoryAliases,
      blockedCategories: blockedCategories,
      categoryIcons: categoryIcons,
    ));
  }

  Future<void> renameCategory(String oldName, String newName) async {
    if (oldName == newName || newName.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final currentState = state;
    if (currentState is VaultLoaded) {
      final updatedAliases = Map<String, String>.from(currentState.categoryAliases);
      
      bool found = false;
      for (final key in updatedAliases.keys.toList()) {
        if (updatedAliases[key] == oldName) {
          updatedAliases[key] = newName.trim();
          found = true;
        }
      }
      if (!found) {
        updatedAliases[oldName] = newName.trim();
      }
      
      await prefs.setString('vault_category_aliases', jsonEncode(updatedAliases));
      
      await IsarDataSource.updateEntriesSource(oldName, newName.trim());
      
      final newSelectedCat = currentState.selectedCategory == oldName ? newName.trim() : currentState.selectedCategory;
      final items = await IsarDataSource.getAllEntries();
      await _emitLoadedState(items, newSelectedCat);
    }
  }

  Future<void> toggleBlockCategory(String category) async {
    if (category == 'All') return;
    final prefs = await SharedPreferences.getInstance();
    final currentState = state;
    if (currentState is VaultLoaded) {
      final updatedBlocks = List<String>.from(currentState.blockedCategories);
      if (updatedBlocks.contains(category)) {
        updatedBlocks.remove(category);
      } else {
        updatedBlocks.add(category);
      }
      
      await prefs.setStringList('vault_blocked_categories', updatedBlocks);
      
      // If blocking the currently selected category, we can switch back to 'All'
      final newSelectedCat = (updatedBlocks.contains(category) && currentState.selectedCategory == category) 
          ? 'All' : currentState.selectedCategory;
          
      await _emitLoadedState(currentState.allItems, newSelectedCat);
    }
  }

  Future<void> updateCategoryIcon(String category, int iconCodePoint) async {
    final prefs = await SharedPreferences.getInstance();
    final currentState = state;
    if (currentState is VaultLoaded) {
      final updatedIcons = Map<String, int>.from(currentState.categoryIcons);
      updatedIcons[category.toLowerCase()] = iconCodePoint;
      
      await prefs.setString('vault_category_icons', jsonEncode(updatedIcons));
      
      await _emitLoadedState(currentState.allItems, currentState.selectedCategory);
    }
  }

  @override
  Future<void> close() {
    _isarSubscription?.cancel();
    return super.close();
  }
}
