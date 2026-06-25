part of 'vault_cubit.dart';

abstract class VaultState {}

class VaultInitial extends VaultState {}

class VaultLoading extends VaultState {}

class VaultLoaded extends VaultState {
  final List<RawData> allItems;
  final Map<String, List<RawData>> groupedItems;
  final Map<String, int> categoryCounts;
  final List<String> categories;
  final String selectedCategory;
  final List<RawData> displayedItems;
  final Map<String, String> categoryAliases;
  final List<String> blockedCategories;
  final Map<String, int> categoryIcons;

  VaultLoaded({
    required this.allItems,
    required this.groupedItems,
    required this.categoryCounts,
    required this.categories,
    required this.selectedCategory,
    required this.displayedItems,
    required this.categoryAliases,
    required this.blockedCategories,
    required this.categoryIcons,
  });

  VaultLoaded copyWith({
    List<RawData>? allItems,
    Map<String, List<RawData>>? groupedItems,
    Map<String, int>? categoryCounts,
    List<String>? categories,
    String? selectedCategory,
    List<RawData>? displayedItems,
    Map<String, String>? categoryAliases,
    List<String>? blockedCategories,
    Map<String, int>? categoryIcons,
  }) {
    return VaultLoaded(
      allItems: allItems ?? this.allItems,
      groupedItems: groupedItems ?? this.groupedItems,
      categoryCounts: categoryCounts ?? this.categoryCounts,
      categories: categories ?? this.categories,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      displayedItems: displayedItems ?? this.displayedItems,
      categoryAliases: categoryAliases ?? this.categoryAliases,
      blockedCategories: blockedCategories ?? this.blockedCategories,
      categoryIcons: categoryIcons ?? this.categoryIcons,
    );
  }
}

class VaultError extends VaultState {
  final String message;
  VaultError(this.message);
}
