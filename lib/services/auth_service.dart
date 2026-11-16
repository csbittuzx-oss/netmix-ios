// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetmixUser {
  final String id;
  final String name;
  final String email;

  const NetmixUser({
    required this.id,
    required this.name,
    required this.email,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
      };

  factory NetmixUser.fromJson(Map<String, dynamic> json) => NetmixUser(
        id: json['id']?.toString() ?? 'user_1',
        name: json['name']?.toString() ?? 'User 1',
        email: json['email']?.toString() ?? 'user1@netmix.app',
      );
}

class AuthService extends ChangeNotifier {
  static const String _prefCurrentUserId = 'netmix_active_user_id';
  static const String _prefUsersList = 'netmix_users_list_v1';

  static final AuthService instance = AuthService._();
  AuthService._() {
    _init();
  }

  static const defaultUser = NetmixUser(
    id: 'user_1',
    name: 'Profile 1',
    email: 'user1@netmix.app',
  );

  NetmixUser _currentUser = defaultUser;
  List<NetmixUser> _allUsers = [defaultUser];
  bool _isInitialized = false;

  NetmixUser get currentUser => _currentUser;
  List<NetmixUser> get allUsers => List.unmodifiable(_allUsers);
  bool get isInitialized => _isInitialized;

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final usersRaw = prefs.getString(_prefUsersList);
      if (usersRaw != null) {
        final decoded = jsonDecode(usersRaw) as List?;
        if (decoded != null && decoded.isNotEmpty) {
          _allUsers = decoded
              .map((u) => NetmixUser.fromJson(u as Map<String, dynamic>))
              .toList();
        }
      }

      final activeId = prefs.getString(_prefCurrentUserId) ?? 'user_1';
      _currentUser = _allUsers.firstWhere(
        (u) => u.id == activeId,
        orElse: () => _allUsers.first,
      );
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthService] Init error: $e');
      _isInitialized = true;
    }
  }

  Future<void> switchUser(NetmixUser user) async {
    _currentUser = user;
    if (!_allUsers.any((u) => u.id == user.id)) {
      _allUsers.add(user);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCurrentUserId, user.id);
    await prefs.setString(
        _prefUsersList, jsonEncode(_allUsers.map((u) => u.toJson()).toList()));
    notifyListeners();
    debugPrint('[AuthService] Switched active user to: ${user.name} (${user.id})');
  }

  Future<void> createAndSwitchUser(String name) async {
    final cleanName = name.trim().isEmpty ? 'User ${_allUsers.length + 1}' : name.trim();
    final newId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final newUser = NetmixUser(
      id: newId,
      name: cleanName,
      email: '${cleanName.toLowerCase().replaceAll(' ', '')}@netmix.app',
    );
    await switchUser(newUser);
  }

  Future<void> signOut() async {
    // Switch to a clean Guest profile with no watch history
    final guestUser = NetmixUser(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Guest',
      email: 'guest@netmix.app',
    );
    await switchUser(guestUser);
  }
}

final authProvider = ChangeNotifierProvider<AuthService>((ref) {
  return AuthService.instance;
});
