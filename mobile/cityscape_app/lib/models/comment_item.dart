// lib/models/comment_item.dart

class CommentItem {
  final String user;
  final int stars;
  final String comment;
  final String? createdAt;

  CommentItem({
    required this.user,
    required this.stars,
    required this.comment,
    this.createdAt,
  });

  factory CommentItem.fromJson(Map<String, dynamic> j) => CommentItem(
        user: (j['user'] ?? 'Anonyme') as String,
        stars: (j['stars'] ?? 0) as int,
        comment: (j['comment'] ?? j['text'] ?? '') as String,
        createdAt: j['created_at'] as String?,
      );
}
