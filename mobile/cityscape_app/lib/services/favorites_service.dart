// lib/services/favorites_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static FavoritesService? _instance;
  static FavoritesService get instance => _instance ??= FavoritesService._();

  FavoritesService._();

  static const _key = 'favorites';

  Future<Set<int>> getAllFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((e) => int.parse(e)).toSet();
  }

  Future<bool> isFavorite(int escapeId) async {
    final favs = await getAllFavoriteIds();
    return favs.contains(escapeId);
  }

  Future<void> addFavorite(int escapeId) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await getAllFavoriteIds();
    favs.add(escapeId);
    await prefs.setStringList(_key, favs.map((e) => e.toString()).toList());
  }

  Future<void> removeFavorite(int escapeId) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await getAllFavoriteIds();
    favs.remove(escapeId);
    await prefs.setStringList(_key, favs.map((e) => e.toString()).toList());
  }

  Future<void> toggleFavorite(int escapeId) async {
    if (await isFavorite(escapeId)) {
      await removeFavorite(escapeId);
    } else {
      await addFavorite(escapeId);
    }
  }
}
