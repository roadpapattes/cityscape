// lib/core/widgets/themed_app_bar.dart
import 'package:flutter/material.dart';
import '../../models/user_preferences.dart';

class ThemedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final ListCardStyle style;
  final List<Widget>? actions;
  final bool showBackButton;

  const ThemedAppBar({
    super.key,
    required this.title,
    required this.style,
    this.actions,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case ListCardStyle.cardCollection:
        return _buildCardCollectionAppBar(context);
      case ListCardStyle.gamingUI:
        return _buildGamingUIAppBar(context);
      case ListCardStyle.playful:
        return _buildPlayfulAppBar(context);
    }
  }

  // Style Card Collection: Élégant avec dégradé doux
  AppBar _buildCardCollectionAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      automaticallyImplyLeading: showBackButton,
      actions: actions,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.2),
    );
  }

  // Style Gaming UI: Cyberpunk avec effet néon
  AppBar _buildGamingUIAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          shadows: [
            Shadow(
              color: Color(0xFF00D9FF),
              blurRadius: 8,
            ),
          ],
        ),
      ),
      automaticallyImplyLeading: showBackButton,
      actions: actions,
      backgroundColor: const Color(0xFF0A0E27),
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                const Color(0xFF00D9FF).withOpacity(0.5),
                const Color(0xFFFF006E).withOpacity(0.5),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D9FF).withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Style Playful: Coloré et fun
  AppBar _buildPlayfulAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      automaticallyImplyLeading: showBackButton,
      actions: actions,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFF6B9D),
              Color(0xFFFFA06B),
              Color(0xFFFFD93D),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.3),
    );
  }
}
