// lib/models/user_preferences.dart

enum ListCardStyle {
  cardCollection,
  gamingUI,
  playful,
}

class UserPreferences {
  final ListCardStyle listCardStyle;

  const UserPreferences({
    this.listCardStyle = ListCardStyle.cardCollection,
  });

  UserPreferences copyWith({
    ListCardStyle? listCardStyle,
  }) {
    return UserPreferences(
      listCardStyle: listCardStyle ?? this.listCardStyle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'listCardStyle': listCardStyle.index,
    };
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      listCardStyle: ListCardStyle.values[json['listCardStyle'] ?? 0],
    );
  }

  String getStyleDisplayName() {
    switch (listCardStyle) {
      case ListCardStyle.cardCollection:
        return 'Collection de cartes';
      case ListCardStyle.gamingUI:
        return 'Gaming UI';
      case ListCardStyle.playful:
        return 'Fun & Coloré';
    }
  }

  String getStyleDescription() {
    switch (listCardStyle) {
      case ListCardStyle.cardCollection:
        return 'Style élégant avec dégradés et effets brillants';
      case ListCardStyle.gamingUI:
        return 'Style moderne avec bordures néon et effets lumineux';
      case ListCardStyle.playful:
        return 'Style joyeux avec couleurs vives et animations';
    }
  }
}
