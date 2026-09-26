import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/log_group.dart';
import '../models/member.dart';

class GroupService {
  GroupService._();
  static final GroupService instance = GroupService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<EfocLogGroup>> fetchMyGroups() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final memberships = await _client
        .from('group_members')
        .select('group_id, role')
        .eq('user_id', userId);

    if (memberships.isEmpty) return [];

    final groupIds =
        memberships.map((m) => m['group_id'] as String).toList();

    final groupRows = await _client
        .from('groups')
        .select()
        .inFilter('id', groupIds);

    if (groupRows.isEmpty) return [];

    final memberRows = await _client
        .from('group_members')
        .select(
          'group_id, user_id, role, profiles(id, display_name, username, avatar_url)',
        )
        .inFilter('group_id', groupIds);

    final Map<String, List<EfocMember>> membersByGroup = {};
    for (final row in memberRows) {
      final gid = row['group_id'] as String;
      final profile = row['profiles'] as Map<String, dynamic>?;
      if (profile == null) continue;

      membersByGroup.putIfAbsent(gid, () => []).add(
            EfocMember(
              id: row['user_id'] as String,
              name: (profile['display_name'] as String?)
                          ?.trim()
                          .isNotEmpty ==
                      true
                  ? profile['display_name'] as String
                  : (profile['username'] as String? ?? 'User'),
              color: _colorForId(row['user_id'] as String),
              isMe: row['user_id'] == userId,
            ),
          );
    }

    final groups = groupRows.map((row) {
      final id = row['id'] as String;
      return EfocLogGroup(
        id: id,
        name: row['name'] as String,
        avatarColor: _colorForId(id),
        members: membersByGroup[id] ?? const [],
        isPersonal: (row['is_personal'] as bool?) ?? false,
      );
    }).toList()
      ..sort((a, b) {
        if (a.isPersonal != b.isPersonal) return a.isPersonal ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return groups;
  }

  Future<String> createGroup(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Name required');

    final inviteCode = _generateInviteCode();

    final row = await _client
        .from('groups')
        .insert({
          'name': trimmed,
          'owner_id': userId,
          'invite_code': inviteCode,
          'is_personal': false,
        })
        .select('id')
        .single();

    final groupId = row['id'] as String;

    await _client.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
      'role': 'owner',
    });

    return groupId;
  }

  Future<String> joinGroup(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.length != 6) throw Exception('Code must be 6 characters');

    final result = await _client.rpc(
      'join_group_by_code',
      params: {'code': code},
    );

    return result as String;
  }

  Future<String> fetchInviteCode(String groupId) async {
    final row = await _client
        .from('groups')
        .select('invite_code')
        .eq('id', groupId)
        .single();
    return row['invite_code'] as String;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Color _colorForId(String id) {
    const palette = [
      Color(0xFFA855F7),
      Color(0xFF06B6D4),
      Color(0xFF4ECDC4),
      Color(0xFFFF8A65),
      Color(0xFFC77DFF),
      Color(0xFFFFD93D),
      Color(0xFFB388FF),
      Color(0xFFEF5350),
    ];
    final hash =
        id.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return palette[hash % palette.length];
  }
}