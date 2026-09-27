import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class GameProfile {
  final String id;
  final String name;
  final int    colorValue;
  final String? avatarPath;

  const GameProfile({
    required this.id,
    required this.name,
    required this.colorValue,
    this.avatarPath,
  });

  Color get color => Color(colorValue);

  GameProfile copyWith({String? name, int? colorValue, String? avatarPath}) =>
      GameProfile(
        id:          id,
        name:        name         ?? this.name,
        colorValue:  colorValue   ?? this.colorValue,
        avatarPath:  avatarPath   ?? this.avatarPath,
      );

  // avatarPath is local-only — not serialised for network play
  Map<String, dynamic> toJson() => {
    'id':    id,
    'name':  name,
    'color': colorValue,
    if (avatarPath != null) 'avatar': avatarPath,
  };

  factory GameProfile.fromJson(Map<String, dynamic> j) => GameProfile(
    id:         j['id']    as String,
    name:       j['name']  as String,
    colorValue: j['color'] as int,
    avatarPath: j['avatar'] as String?,
  );
}

// ── Singleton ─────────────────────────────────────────────────────────────────

class ProfileStore {
  static final ProfileStore _i = ProfileStore._();
  factory ProfileStore() => _i;
  ProfileStore._();

  static const _kProfiles  = 'profiles_v1';
  static const _kActiveId  = 'active_profile_id';
  static const kMaxProfiles = 6;

  final List<GameProfile> _profiles = [];
  String? _activeId;

  bool _loaded = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  List<GameProfile> get profiles => List.unmodifiable(_profiles);

  GameProfile? get active =>
      _profiles.isEmpty ? null :
      _profiles.firstWhere((p) => p.id == _activeId,
          orElse: () => _profiles.first);

  bool get hasProfiles => _profiles.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Migrate legacy single-profile prefs into profiles list
      final raw = prefs.getString(_kProfiles);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _profiles.addAll(list.map(
          (j) => GameProfile.fromJson(j as Map<String, dynamic>)));
        _activeId = prefs.getString(_kActiveId) ?? _profiles.first.id;
      } else {
        // First launch or pre-profiles build — migrate old flat prefs
        final oldName  = prefs.getString('player_name');
        final oldColor = prefs.getInt('player_color');
        final oldAvatar = prefs.getString('avatar_path');
        if (oldName != null && oldName.isNotEmpty) {
          final migrated = GameProfile(
            id:         _newId(),
            name:       oldName,
            colorValue: oldColor ?? kPlayerColors[0].value,
            avatarPath: oldAvatar,
          );
          _profiles.add(migrated);
          _activeId = migrated.id;
          await _persist(prefs);
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  Future<GameProfile> createProfile({
    required String name,
    required int colorValue,
    String? avatarPath,
  }) async {
    final profile = GameProfile(
      id:         _newId(),
      name:       name,
      colorValue: colorValue,
      avatarPath: avatarPath,
    );
    _profiles.add(profile);
    _activeId = profile.id;
    await _persist();
    return profile;
  }

  Future<void> updateProfile(GameProfile updated) async {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    _profiles[idx] = updated;
    await _persist();
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
    await _persist();
  }

  Future<void> setActive(String id) async {
    if (_profiles.any((p) => p.id == id)) {
      _activeId = id;
      await _persist();
    }
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  String _newId() => 'prof-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _persist([SharedPreferences? prefs]) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setString(_kProfiles,
          jsonEncode(_profiles.map((pr) => pr.toJson()).toList()));
      if (_activeId != null) await p.setString(_kActiveId, _activeId!);
    } catch (_) {}
  }
}
