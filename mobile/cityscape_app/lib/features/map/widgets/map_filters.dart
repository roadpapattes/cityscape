// lib/features/map/widgets/map_filters.dart
import 'package:flutter/material.dart';

class MapFilters {
  final Set<int> difficulties;
  final double minRating;
  final bool favoritesOnly;

  const MapFilters({
    this.difficulties = const {1, 2, 3},
    this.minRating = 0.0,
    this.favoritesOnly = false,
  });

  MapFilters copyWith({
    Set<int>? difficulties,
    double? minRating,
    bool? favoritesOnly,
  }) {
    return MapFilters(
      difficulties: difficulties ?? this.difficulties,
      minRating: minRating ?? this.minRating,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }

  bool get hasActiveFilters =>
      difficulties.length != 3 || minRating > 0 || favoritesOnly;
}

class MapFiltersButton extends StatefulWidget {
  final MapFilters filters;
  final ValueChanged<MapFilters> onFiltersChanged;

  const MapFiltersButton({
    super.key,
    required this.filters,
    required this.onFiltersChanged,
  });

  @override
  State<MapFiltersButton> createState() => _MapFiltersButtonState();
}

class _MapFiltersButtonState extends State<MapFiltersButton>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Panneau de filtres
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.scale(
              scale: _animation.value,
              alignment: Alignment.topRight,
              child: Opacity(
                opacity: _animation.value,
                child: _isExpanded ? child : const SizedBox.shrink(),
              ),
            );
          },
          child: Container(
            width: 280,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Filtres',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (widget.filters.hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            widget.onFiltersChanged(const MapFilters());
                          },
                          child: const Text('Réinitialiser'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Difficulté
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Difficulté',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildDifficultyChip(1, 'Facile', Colors.green),
                          _buildDifficultyChip(2, 'Moyen', Colors.orange),
                          _buildDifficultyChip(3, 'Difficile', Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),

                // Note minimale
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Note minimale',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            widget.filters.minRating > 0
                                ? '${widget.filters.minRating.toStringAsFixed(1)} ⭐'
                                : 'Aucune',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: widget.filters.minRating,
                        min: 0,
                        max: 5,
                        divisions: 10,
                        onChanged: (value) {
                          widget.onFiltersChanged(
                            widget.filters.copyWith(minRating: value),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Favoris uniquement
                CheckboxListTile(
                  title: const Text(
                    'Favoris uniquement',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: widget.filters.favoritesOnly,
                  onChanged: (value) {
                    widget.onFiltersChanged(
                      widget.filters.copyWith(favoritesOnly: value),
                    );
                  },
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),

        // Bouton principal
        FloatingActionButton(
          heroTag: 'filters',
          onPressed: _toggleExpanded,
          child: Stack(
            children: [
              Center(
                child: Icon(_isExpanded ? Icons.close : Icons.tune),
              ),
              if (widget.filters.hasActiveFilters && !_isExpanded)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDifficultyChip(int difficulty, String label, Color color) {
    final isSelected = widget.filters.difficulties.contains(difficulty);
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : color,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        final newDifficulties = Set<int>.from(widget.filters.difficulties);
        if (selected) {
          newDifficulties.add(difficulty);
        } else {
          newDifficulties.remove(difficulty);
        }
        widget.onFiltersChanged(
          widget.filters.copyWith(difficulties: newDifficulties),
        );
      },
      selectedColor: color,
      checkmarkColor: Colors.white,
      side: BorderSide(color: color),
    );
  }
}
