// lib/widgets/shoe_edit_sheet.dart
//
// Bottom sheet for adding or editing a shoe in the locker. Shared by the You
// tab's Gear sub-tab and AthleteProfileScreen. Pops `true` when a shoe was
// created / updated / deleted, so the caller can refresh its locker.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shoe.dart';
import '../services/shoe_service.dart';
import '../theme/app_colors.dart';

class ShoeEditSheet extends StatefulWidget {
  final Shoe? existing;
  const ShoeEditSheet({super.key, this.existing});

  @override
  State<ShoeEditSheet> createState() => _ShoeEditSheetState();
}

class _ShoeEditSheetState extends State<ShoeEditSheet> {
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _nickname;
  late final TextEditingController _startKm;
  late final TextEditingController _maxKm;
  late bool _isDefault;
  late bool _isRetired;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _brand = TextEditingController(text: s?.brand ?? '');
    _model = TextEditingController(text: s?.model ?? '');
    _nickname = TextEditingController(text: s?.nickname ?? '');
    _startKm = TextEditingController(
      text: s == null ? '' : s.distanceKm.toStringAsFixed(0),
    );
    _maxKm = TextEditingController(
      text: (s?.maxDistanceKm ?? 800).toStringAsFixed(0),
    );
    _isDefault = s?.isDefault ?? false;
    _isRetired = s?.isRetired ?? false;
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _nickname.dispose();
    _startKm.dispose();
    _maxKm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_brand.text.trim().isEmpty || _model.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final svc = ShoeService.instance;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final startMeters = (double.tryParse(_startKm.text.trim()) ?? 0) * 1000;
    final maxMeters = (double.tryParse(_maxKm.text.trim()) ?? 800) * 1000;

    bool ok;
    if (_isEdit) {
      ok = await svc.update(
        widget.existing!.copyWith(
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
          distanceMeters: startMeters,
          maxDistanceMeters: maxMeters,
          isDefault: _isDefault,
          isRetired: _isRetired,
        ),
      );
    } else {
      final created = await svc.add(
        Shoe(
          userId: uid,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
          distanceMeters: startMeters,
          maxDistanceMeters: maxMeters,
          isDefault: _isDefault,
        ),
      );
      ok = created != null;
    }

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _busy = true);
    final ok = await ShoeService.instance.delete(id);
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEdit ? 'Edit shoe' : 'Add a shoe',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _tf(context, 'Brand', _brand),
          _tf(context, 'Model', _model),
          _tf(context, 'Nickname (optional)', _nickname),
          Row(
            children: [
              Expanded(
                child: _tf(context, 'Start dist (km)', _startKm, number: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tf(context, 'Target (km)', _maxKm, number: true),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
            title: Text(
              'Default shoe',
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
            activeThumbColor: c.accent,
          ),
          if (_isEdit)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isRetired,
              onChanged: (v) => setState(() => _isRetired = v),
              title: Text(
                'Retired',
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
              activeThumbColor: c.accent,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_isEdit)
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: Text('Delete', style: TextStyle(color: c.danger)),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _busy ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Save',
                          style: TextStyle(
                            color: c.onAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tf(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool number = false,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(color: c.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: c.textTertiary, fontSize: 13),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
    );
  }
}
