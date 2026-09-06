// lib/services/shoe_service.dart
//
// CRUD for the shoe locker (`shoes` table, see
// supabase/migrations/20260906000002_create_shoes_table.sql). Write ops are
// RLS-scoped to the signed-in user; reads also succeed for public profiles so
// the Gear tab renders on another athlete's page.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shoe.dart';

class ShoeService {
  static final ShoeService instance = ShoeService._();
  ShoeService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  /// All pairs for [userId] (defaults to the signed-in user), active first,
  /// then most-used.
  Future<List<Shoe>> locker({String? userId}) async {
    final target = userId ?? _uid;
    if (target == null) return [];
    try {
      final rows = await _client
          .from('shoes')
          .select()
          .eq('user_id', target)
          .order('is_retired', ascending: true)
          .order('distance_meters', ascending: false);
      return (rows as List)
          .map((r) => Shoe.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ShoeService] locker error: $e');
      return [];
    }
  }

  /// The user's current default pair, if any.
  Future<Shoe?> defaultShoe({String? userId}) async {
    final target = userId ?? _uid;
    if (target == null) return null;
    try {
      final row = await _client
          .from('shoes')
          .select()
          .eq('user_id', target)
          .eq('is_default', true)
          .maybeSingle();
      return row == null ? null : Shoe.fromMap(row);
    } catch (e) {
      debugPrint('[ShoeService] defaultShoe error: $e');
      return null;
    }
  }

  /// Creates a pair. If [shoe.isDefault] is set, any existing default is cleared
  /// first (the DB has a one-default-per-user partial unique index). Returns the
  /// stored row, or null on failure.
  Future<Shoe?> add(Shoe shoe) async {
    final me = _uid;
    if (me == null) return null;
    try {
      if (shoe.isDefault) await _clearDefault(me);
      final payload = shoe.toMap()..['user_id'] = me;
      final row = await _client.from('shoes').insert(payload).select().single();
      return Shoe.fromMap(row);
    } catch (e) {
      debugPrint('[ShoeService] add error: $e');
      return null;
    }
  }

  /// Updates editable fields of an existing pair.
  Future<bool> update(Shoe shoe) async {
    final me = _uid;
    if (me == null || shoe.id == null) return false;
    try {
      if (shoe.isDefault) await _clearDefault(me, exceptId: shoe.id);
      await _client
          .from('shoes')
          .update(shoe.toMap())
          .eq('id', shoe.id!)
          .eq('user_id', me);
      return true;
    } catch (e) {
      debugPrint('[ShoeService] update error: $e');
      return false;
    }
  }

  Future<bool> delete(String shoeId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      await _client.from('shoes').delete().eq('id', shoeId).eq('user_id', me);
      return true;
    } catch (e) {
      debugPrint('[ShoeService] delete error: $e');
      return false;
    }
  }

  Future<bool> setDefault(String shoeId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      await _clearDefault(me, exceptId: shoeId);
      await _client
          .from('shoes')
          .update({'is_default': true})
          .eq('id', shoeId)
          .eq('user_id', me);
      return true;
    } catch (e) {
      debugPrint('[ShoeService] setDefault error: $e');
      return false;
    }
  }

  Future<bool> setRetired(String shoeId, bool retired) async {
    final me = _uid;
    if (me == null) return false;
    try {
      // A retired shoe should not remain the default.
      await _client
          .from('shoes')
          .update({
            'is_retired': retired,
            if (retired) 'is_default': false,
          })
          .eq('id', shoeId)
          .eq('user_id', me);
      return true;
    } catch (e) {
      debugPrint('[ShoeService] setRetired error: $e');
      return false;
    }
  }

  /// Adds [meters] to a pair's mileage — call from the run-save path when a run
  /// is tagged with a shoe. No-op for a null/blank id.
  Future<bool> addDistanceMeters(String? shoeId, double meters) async {
    final me = _uid;
    if (me == null || shoeId == null || shoeId.isEmpty || meters <= 0) {
      return false;
    }
    try {
      final row = await _client
          .from('shoes')
          .select('distance_meters')
          .eq('id', shoeId)
          .eq('user_id', me)
          .maybeSingle();
      if (row == null) return false;
      final current = (row['distance_meters'] as num).toDouble();
      await _client
          .from('shoes')
          .update({'distance_meters': current + meters})
          .eq('id', shoeId)
          .eq('user_id', me);
      return true;
    } catch (e) {
      debugPrint('[ShoeService] addDistanceMeters error: $e');
      return false;
    }
  }

  Future<void> _clearDefault(String userId, {String? exceptId}) async {
    var q = _client
        .from('shoes')
        .update({'is_default': false})
        .eq('user_id', userId)
        .eq('is_default', true);
    if (exceptId != null) q = q.neq('id', exceptId);
    await q;
  }
}
