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
import '../utils/date_format_utils.dart';

class _P {
  static const surface = Color(0xFF12161A);
  static const border = Color(0xFF23262B);
  static const field = Color(0xFF1A1F25);
  static const accent = Color(0xFF00B2FF);
  static const textHigh = Color(0xFFF3F5F7);
  static const textMid = Color(0xFF9BA3AD);
  static const textLow = Color(0xFF6A7178);
}

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
          decoration: const BoxDecoration(
            color: _P.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: _P.border),
              left: BorderSide(color: _P.border),
              right: BorderSide(color: _P.border),
            ),
          ),
          child: Column(
            children: [
              _grabber(),
              _header(),
              const Divider(height: 1, color: _P.border),
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
      color: _P.border,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
    child: Row(
      children: [
        Text(
          _count > 0 ? 'Comments · $_count' : 'Comments',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _P.textHigh,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: _P.textMid, size: 22),
          onPressed: () => Navigator.pop(context, _count),
        ),
      ],
    ),
  );

  Widget _body(ScrollController sheetScroll) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _P.accent),
        ),
      );
    }
    if (_comments.isEmpty) {
      return SingleChildScrollView(
        controller: sheetScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(
            children: [
              Icon(
                Icons.mode_comment_outlined,
                size: 34,
                color: _P.textLow,
              ),
              SizedBox(height: 14),
              Text(
                'No comments yet.\nBe the first to leave one!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _P.textMid,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _comments.length,
      itemBuilder: (context, i) => _CommentTile(comment: _comments[i]),
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
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _P.border)),
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
                style: const TextStyle(color: _P.textHigh, fontSize: 14),
                cursorColor: _P.accent,
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  hintStyle: const TextStyle(color: _P.textLow, fontSize: 14),
                  filled: true,
                  fillColor: _P.field,
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _P.accent,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: _P.accent),
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
  const _CommentTile({required this.comment});

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
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _P.textHigh,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      relativeTime(comment.createdAt),
                      style: const TextStyle(fontSize: 11, color: _P.textLow),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.comment,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: _P.textMid,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
