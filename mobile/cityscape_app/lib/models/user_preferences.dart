// lib/models/user_preferences.dart

enum ListCardStyle {
  cardCollection,
  gamingUI,
  playful,
}

class UserPreferences {
  final ListCardStyle listCardStyle;
  final bool tutorialCompleted;
  final bool audioMuted; // fond sonore des escapes coupé par le joueur

  const UserPreferences({
    this.listCardStyle = ListCardStyle.cardCollection,
    this.tutorialCompleted = false,
    this.audioMuted = false,
  });

  UserPreferences copyWith({
    ListCardStyle? listCardStyle,
    bool? tutorialCompleted,
    bool? audioMuted,
  }) {
    return UserPreferences(
      listCardStyle: listCardStyle ?? this.listCardStyle,
      tutorialCompleted: tutorialCompleted ?? this.tutorialCompleted,
      audioMuted: audioMuted ?? this.audioMuted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'listCardStyle': listCardStyle.index,
      'tutorialCompleted': tutorialCompleted,
      'audioMuted': audioMuted,
    };
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      listCardStyle: ListCardStyle.values[json['listCardStyle'] ?? 0],
      tutorialCompleted: json['tutorialCompleted'] ?? false,
      audioMuted: json['audioMuted'] ?? false,
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
