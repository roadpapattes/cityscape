// lib/core/widgets/themed_bottom_nav.dart
import 'package:flutter/material.dart';
import '../../models/user_preferences.dart';

class ThemedBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final ListCardStyle style;
  final GlobalKey? listTabKey;
  final GlobalKey? creatorTabKey;

  const ThemedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.style,
    this.listTabKey,
    this.creatorTabKey,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case ListCardStyle.cardCollection:
        return _buildCardCollectionBottomNav(context);
      case ListCardStyle.gamingUI:
        return _buildGamingUIBottomNav(context);
      case ListCardStyle.playful:
        return _buildPlayfulBottomNav(context);
    }
  }

  // Style Card Collection: Sobre et élégant
  Widget _buildCardCollectionBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 11,
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: Container(key: listTabKey, child: const Icon(Icons.view_list, size: 28)),
            label: 'Liste',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.map, size: 28),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Container(key: creatorTabKey, child: const Icon(Icons.create, size: 28)),
            label: 'Créer',
          ),
        ],
      ),
    );
  }

  // Style Gaming UI: Cyberpunk avec néon
  Widget _buildGamingUIBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF00D9FF).withOpacity(0.3),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9FF).withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        selectedItemColor: const Color(0xFF00D9FF),
        unselectedItemColor: Colors.grey[500],
        selectedFontSize: 12,
        unselectedFontSize: 11,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          shadows: [
            Shadow(
              color: Color(0xFF00D9FF),
              blurRadius: 4,
            ),
          ],
        ),
        items: [
          BottomNavigationBarItem(
            icon: Container(key: listTabKey, child: _buildGamingIcon(Icons.view_list, currentIndex == 0)),
            label: 'LISTE',
          ),
          BottomNavigationBarItem(
            icon: _buildGamingIcon(Icons.map, currentIndex == 1),
            label: 'CARTE',
          ),
          BottomNavigationBarItem(
            icon: Container(key: creatorTabKey, child: _buildGamingIcon(Icons.create, currentIndex == 2)),
            label: 'CRÉER',
          ),
        ],
      ),
    );
  }

  Widget _buildGamingIcon(IconData icon, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected
            ? Border.all(
                color: const Color(0xFF00D9FF).withOpacity(0.5),
                width: 2,
              )
            : null,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF00D9FF).withOpacity(0.3),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Icon(icon, size: 28),
    );
  }

  // Style Playful: Coloré et fun
  Widget _buildPlayfulBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        selectedItemColor: const Color(0xFFFF006E),
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 11,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
        ),
        items: [
          BottomNavigationBarItem(
            icon: Container(key: listTabKey, child: _buildPlayfulIcon(Icons.view_list, currentIndex == 0, 0)),
            label: 'Liste',
          ),
          BottomNavigationBarItem(
            icon: _buildPlayfulIcon(Icons.map, currentIndex == 1, 1),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Container(key: creatorTabKey, child: _buildPlayfulIcon(Icons.create, currentIndex == 2, 2)),
            label: 'Créer',
          ),
        ],
      ),
    );
  }

  Widget _buildPlayfulIcon(IconData icon, bool isSelected, int index) {
    final colors = [
      const Color(0xFFFF6B9D),
      const Color(0xFFFFA06B),
      const Color(0xFFFFD93D),
    ];
    final color = colors[index % colors.length];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? color.withOpacity(0.15) : null,
        border: isSelected
            ? Border.all(
                color: color,
                width: 2,
              )
            : null,
      ),
      child: Icon(icon, size: 28),
    );
  }
}
