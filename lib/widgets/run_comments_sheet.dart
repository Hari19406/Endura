// lib/widgets/run_comments_sheet.dart
//
// Draggable bottom sheet of comments on a feed run. Returns the resulting
// comment count so the caller can refresh the badge on RunFeedCard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity_comment.dart';
import '../models/athlete_profile.dart';
import '../screens/athlete_list_screen.dart' show AthleteAvatar;
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format_utils.dart';

/// Opens the comments sheet for [runId]. Resolves to the final comment count
/// once the sheet is dismissed (>= [initialCount]).
Future<int> showRunCommentsSheet(
  BuildContext context, {
  required int runId,
  int initialCount = 0,
}) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RunCommentsSheet(runId: runId, initialCount: initialCount),
  );
  return result ?? initialCount;
}

class _RunCommentsSheet extends StatefulWidget {
  final int runId;
  final int initialCount;
  const _RunCommentsSheet({required this.runId, required this.initialCount});

  @override
  State<_RunCommentsSheet> createState() => _RunCommentsSheetState();
}

class _RunCommentsSheetState extends State<_RunCommentsSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  List<ActivityComment> _comments = [];
  bool _loading = true;
  bool _sending = false;

  int get _count => _comments.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await SocialService.instance.fetchComments(widget.runId);
    if (!mounted) return;
    setState(() {
      _comments = list;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();

    // Optimistic row.
    final optimistic = ActivityComment(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      runId: widget.runId,
      userId: 'me',
      comment: text,
      createdAt: DateTime.now().toUtc(),
      displayName: 'You',
    );
    setState(() {
      _comments = [..._comments, optimistic];
      _controller.clear();
    });
    _jumpToBottom();

    ActivityComment? saved;
    try {
      saved = await SocialService.instance.postComment(widget.runId, text);
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (saved != null) {
        // Swap the optimistic row for the persisted one.
        final i = _comments.indexWhere((c) => c.id == optimistic.id);
        if (i != -1) _comments[i] = saved;
      } else {
        // Roll back and restore the draft.
        _comments = _comments.where((c) => c.id != optimistic.id).toList();
        _controller.text = text;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text("Couldn't post your comment.")),
          );
      }
    });
  }

  Future<void> _deleteComment(ActivityComment comment) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(
          'Delete comment?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          "This can't be undone.",
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(dctx, true);
            },
            child: Text('Delete', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await SocialService.instance.deleteComment(comment.id);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
      });
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't delete that comment.")),
        );
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, sheetScroll) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: context.colors.border),
              left: BorderSide(color: context.colors.border),
              right: BorderSide(color: context.colors.border),
            ),
          ),
          child: Column(
            children: [
              _grabber(),
              _header(),
              Divider(height: 1, color: context.colors.border),
              Expanded(child: _body(sheetScroll)),
              _composer(),
            ],
          ),
        );
      },
    );
  }

  Widget _grabber() => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: context.colors.border,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
    child: Row(
      children: [
        Text(
          _count > 0 ? 'Comments · $_count' : 'Comments',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.colors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.close, color: context.colors.textSecondary, size: 22),
          onPressed: () => Navigator.pop(context, _count),
        ),
      ],
    ),
  );

  Widget _body(ScrollController sheetScroll) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.chartAccent),
        ),
      );
    }
    if (_comments.isEmpty) {
      return SingleChildScrollView(
        controller: sheetScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(
            children: [
              Icon(
                Icons.mode_comment_outlined,
                size: 34,
                color: context.colors.textTertiary,
              ),
              SizedBox(height: 14),
              Text(
                'No comments yet.\nBe the first to leave one!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final me = SocialService.instance.currentUserId;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _comments.length,
      itemBuilder: (context, i) {
        final comment = _comments[i];
        // Not the still-sending optimistic row — that has no real id yet.
        final isOwn = me != null &&
            comment.userId == me &&
            !comment.id.startsWith('local-');
        return _CommentTile(
          comment: comment,
          onDelete: isOwn ? () => _deleteComment(comment) : null,
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          8,
          8 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                cursorColor: context.colors.chartAccent,
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  hintStyle: TextStyle(color: context.colors.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: context.colors.surfaceAlt,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: _sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.chartAccent,
                      ),
                    )
                  : Icon(Icons.send_rounded, color: context.colors.chartAccent),
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final ActivityComment comment;

  /// Non-null only for the signed-in user's own comment — shows the delete
  /// affordance.
  final VoidCallback? onDelete;

  const _CommentTile({required this.comment, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AthleteAvatar(
            athlete: AthleteProfile(
              id: comment.userId,
              displayName: comment.displayName,
              avatarUrl: comment.avatarUrl,
            ),
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      relativeTime(comment.createdAt),
                      style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.comment,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: context.colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 17,
                color: context.colors.textTertiary,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Delete comment',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
