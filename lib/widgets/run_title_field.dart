// lib/widgets/run_title_field.dart
//
// The editable run name on the post-run summary: reads like a heading, with a
// pencil that focuses it. The caller owns the [controller] and reads the text
// when the athlete taps Done.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/run_title.dart';

class RunTitleField extends StatefulWidget {
  final TextEditingController controller;

  const RunTitleField({super.key, required this.controller});

  @override
  State<RunTitleField> createState() => _RunTitleFieldState();
}

class _RunTitleFieldState extends State<RunTitleField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    HapticFeedback.selectionClick();
    _focus.requestFocus();
    final c = widget.controller;
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      maxLength: RunTitle.maxLength,
      maxLines: 1,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _focus.unfocus(),
      cursorColor: c.chartAccent,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: 'Name your run',
        hintStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: c.textTertiary,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.chartAccent, width: 1),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        suffixIcon: _focus.hasFocus
            ? null
            : IconButton(
                tooltip: 'Edit title',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: c.textTertiary,
                ),
                onPressed: _startEditing,
              ),
      ),
    );
  }
}
