// lib/services/shoe_service.dart
//
// Offline-first shoe locker. The local SQLite `shoes` table (see
// DatabaseService v9) is the source of truth for the signed-in user; every
// mutation writes locally first, then pushes to the Supabase `shoes` table
// best-effort and flips `synced_to_cloud` on success. Viewing *another*
// athlete's locker reads Supabase directly (their rows never live locally).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shoe.dart';
import '../utils/database_service.dart';
import '../utils/uuid.dart';

class ShoeService {
  static final ShoeService instance = ShoeService._();
  ShoeService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  DatabaseService get _db => DatabaseService.instance;

  // ── Reads ────────────────────────────────────────────────────────────────

  /// Locker for [userId] (defaults to the signed-in user). Own locker comes
  /// from local SQLite; another athlete's comes from Supabase.
  Future<List<Shoe>> locker({String? userId}) async {
    final me = _uid;
    if (userId == null || userId == me) {
      final rows = await _db.getShoeRows();
      return rows
          .map((r) => Shoe.fromMap(r, fallbackUserId: me ?? ''))
          .toList();
    }
    try {
      final rows = await _client
          .from('shoes')
          .select()
          .eq('user_id', userId)
          .order('is_retired', ascending: true)
          .order('distance_meters', ascending: false);
      return (rows as List)
          .map((r) => Shoe.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ShoeService] locker(remote) error: $e');
      return [];
    }
  }

  Future<Shoe?> defaultShoe({String? userId}) async {
    final shoes = await locker(userId: userId);
    for (final s in shoes) {
      if (s.isDefault && !s.isRetired) return s;
    }
    return null;
  }

  // ── Writes (local-first) ─────────────────────────────────────────────────

  Future<Shoe?> add(Shoe shoe) async {
    final me = _uid;
    if (me == null) return null;
    final created = shoe.copyWith(id: shoe.id ?? uuidV4());
    try {
      if (created.isDefault) await _clearLocalDefault();
      await _db.upsertShoeRow(created.toLocalMap(synced: false));
      unawaited(_pushRow(created));
      return created;
    } catch (e) {
      debugPrint('[ShoeService] add error: $e');
      return null;
    }
  }

  Future<bool> update(Shoe shoe) async {
    if (_uid == null || shoe.id == null) return false;
    try {
      if (shoe.isDefault) await _clearLocalDefault(exceptId: shoe.id);
      await _db.upsertShoeRow(shoe.toLocalMap(synced: false));
      unawaited(_pushRow(shoe));
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
      // Tombstone locally, then try the remote delete; drop the local row
      // only once the server has confirmed.
      final db = await _db.database;
      await db.update(
        'shoes',
        {'pending_delete': 1, 'synced_to_cloud': 0},
        where: 'id = ?',
        whereArgs: [shoeId],
      );
      try {
        await _client
            .from('shoes')
            .delete()
            .eq('id', shoeId)
            .eq('user_id', me);
        await _db.deleteShoeRow(shoeId);
      } catch (e) {
        debugPrint('[ShoeService] delete(remote) deferred: $e');
      }
      return true;
    } catch (e) {
      debugPrint('[ShoeService] delete error: $e');
      return false;
    }
  }

  Future<bool> setDefault(String shoeId) async {
    if (_uid == null) return false;
    try {
      final db = await _db.database;
      await db.update('shoes', {'is_default': 0, 'synced_to_cloud': 0},
          where: 'is_default = 1');
      await db.update(
        'shoes',
        {'is_default': 1, 'synced_to_cloud': 0},
        where: 'id = ?',
        whereArgs: [shoeId],
      );
      unawaited(pushPending());
      return true;
    } catch (e) {
      debugPrint('[ShoeService] setDefault error: $e');
      return false;
    }
  }

  Future<bool> setRetired(String shoeId, bool retired) async {
    if (_uid == null) return false;
    try {
      final db = await _db.database;
      await db.update(
        'shoes',
        {
          'is_retired': retired ? 1 : 0,
          if (retired) 'is_default': 0,
          'synced_to_cloud': 0,
        },
        where: 'id = ?',
        whereArgs: [shoeId],
      );
      unawaited(pushPending());
      return true;
    } catch (e) {
      debugPrint('[ShoeService] setRetired error: $e');
      return false;
    }
  }

  /// Adds [meters] to one pair's mileage, locally and (best-effort) remotely.
  Future<bool> addDistanceMeters(String? shoeId, double meters) async {
    if (_uid == null || shoeId == null || shoeId.isEmpty || meters <= 0) {
      return false;
    }
    try {
      final db = await _db.database;
      final rows = await db.query(
        'shoes',
        columns: ['distance_meters'],
        where: 'id = ?',
        whereArgs: [shoeId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final next = (rows.first['distance_meters'] as num).toDouble() + meters;
      await db.update(
        'shoes',
        {
          'distance_meters': next,
          'synced_to_cloud': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [shoeId],
      );
      unawaited(pushPending());
      return true;
    } catch (e) {
      debugPrint('[ShoeService] addDistanceMeters error: $e');
      return false;
    }
  }

  /// Convenience for the run-save path: bump the active default pair, if any.
  Future<void> addDistanceToDefaultShoe(double meters) async {
    if (meters <= 0) return;
    final def = await defaultShoe();
    if (def?.id != null) await addDistanceMeters(def!.id, meters);
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  /// Pushes every local row that isn't marked synced. Safe to call often.
  Future<void> pushPending() async {
    final me = _uid;
    if (me == null) return;
    try {
      final rows = await _db.getUnsyncedShoeRows();
      for (final r in rows) {
        final id = r['id'] as String;
        try {
          if ((r['pending_delete'] as int? ?? 0) == 1) {
            await _client.from('shoes').delete().eq('id', id).eq('user_id', me);
            await _db.deleteShoeRow(id);
          } else {
            final shoe = Shoe.fromMap(r, fallbackUserId: me);
            await _client.from('shoes').upsert({
              'id': id,
              'user_id': me,
              ...shoe.toMap(),
            });
            await _db.markShoeSynced(id);
          }
        } catch (e) {
          debugPrint('[ShoeService] pushPending row $id deferred: $e');
        }
      }
    } catch (e) {
      debugPrint('[ShoeService] pushPending error: $e');
    }
  }

  /// Replaces the local locker with the server's copy. Used by first-login
  /// hydration on a fresh device.
  Future<void> hydrateFromRemote() async {
    final me = _uid;
    if (me == null) return;
    try {
      final rows = await _client.from('shoes').select().eq('user_id', me);
      final local = (rows as List)
          .map(
            (r) => Shoe.fromMap(r as Map<String, dynamic>)
                .toLocalMap(synced: true),
          )
          .toList();
      await _db.replaceAllShoeRows(local);
    } catch (e) {
      debugPrint('[ShoeService] hydrateFromRemote error: $e');
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<void> _clearLocalDefault({String? exceptId}) async {
    final db = await _db.database;
    await db.update(
      'shoes',
      {'is_default': 0, 'synced_to_cloud': 0},
      where: exceptId == null
          ? 'is_default = 1'
          : 'is_default = 1 AND id != ?',
      whereArgs: exceptId == null ? null : [exceptId],
    );
  }

  Future<void> _pushRow(Shoe shoe) async {
    final me = _uid;
    if (me == null || shoe.id == null) return;
    try {
      await _client.from('shoes').upsert({
        'id': shoe.id,
        'user_id': me,
        ...shoe.toMap(),
      });
      await _db.markShoeSynced(shoe.id!);
    } catch (e) {
      debugPrint('[ShoeService] _pushRow deferred: $e');
    }
  }
}
