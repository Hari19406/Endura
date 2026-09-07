// lib/models/activity_comment.dart
//
// One comment on a run in the activity feed. Built by SocialService from an
// `activity_comments` row joined app-side with the commenter's `profiles` row.

class ActivityComment {
  final String id;
  final int runId;
  final String userId;
  final String comment;
  final DateTime createdAt;

  // Commenter identity (from profiles).
  final String displayName;
  final String? avatarUrl;

  const ActivityComment({
    required this.id,
    required this.runId,
    required this.userId,
    required this.comment,
    required this.createdAt,
    required this.displayName,
    this.avatarUrl,
  });

  factory ActivityComment.fromRows(
    Map<String, dynamic> row,
    Map<String, dynamic>? profileRow,
  ) {
    final name = (profileRow?['display_name'] as String?)?.trim();
    return ActivityComment(
      id: row['id'] as String,
      runId: (row['run_id'] as num).toInt(),
      userId: row['user_id'] as String,
      comment: row['comment'] as String? ?? '',
      createdAt:
          DateTime.tryParse('${row['created_at']}')?.toUtc() ??
          DateTime.now().toUtc(),
      displayName: (name != null && name.isNotEmpty) ? name : 'Runner',
      avatarUrl: profileRow?['avatar_url'] as String?,
    );
  }
}
