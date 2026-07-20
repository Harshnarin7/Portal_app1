// lib/models/user.dart
// ─────────────────────────────────────────────────────────────────────────────
// All user-related models used across the PORTAL app.
// Replaces the old UserSession class in auth_service.dart entirely.
// ─────────────────────────────────────────────────────────────────────────────

enum UserRole {
  admin,
  pi,
  scientist,
  nurse,
  deo,
  monitor;

  static UserRole fromString(String s) {
    switch (s.toUpperCase()) {
      case 'ADMIN':     return UserRole.admin;
      case 'PI':        return UserRole.pi;
      case 'SCIENTIST': return UserRole.scientist;
      case 'NURSE':     return UserRole.nurse;
      case 'DEO':       return UserRole.deo;
      case 'MONITOR':   return UserRole.monitor;
      default:          return UserRole.nurse;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.admin:     return 'Super Admin';
      case UserRole.pi:        return 'Principal Investigator';
      case UserRole.scientist: return 'Project Scientist';
      case UserRole.nurse:     return 'Research Nurse';
      case UserRole.deo:       return 'Data Entry Operator';
      case UserRole.monitor:   return 'Monitor';
    }
  }

  /// Whether this role can see data from ALL sites.
  bool get isGlobal => this == UserRole.admin || this == UserRole.monitor;

  /// Whether this role can add new participants.
  bool get canAddParticipant =>
      this == UserRole.nurse || this == UserRole.admin;

  /// Whether this role can approve / lock forms.
  bool get canApprove =>
      this == UserRole.pi || this == UserRole.admin;

  /// Whether this role has read-only access.
  bool get isReadOnly => this == UserRole.monitor;
}

class UserProfile {
  final String id;
  final String username;
  final String email;
  final String fullName;
  final String? mobile;
  final UserRole role;
  final String? siteId;
  final String? siteName;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    this.mobile,
    required this.role,
    this.siteId,
    this.siteName,
    required this.mustChangePassword,
    this.lastLoginAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id:                  json['id'] as String,
      username:            json['username'] as String,
      email:               json['email'] as String,
      fullName:            json['full_name'] as String,
      mobile:              json['mobile'] as String?,
      role:                UserRole.fromString(json['role'] as String),
      siteId:              json['site_id'] as String?,
      siteName:            json['site_name'] as String?,
      mustChangePassword:  json['must_change_password'] as bool? ?? false,
      lastLoginAt:         json['last_login_at'] != null
                             ? DateTime.tryParse(json['last_login_at'] as String)
                             : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':                   id,
    'username':             username,
    'email':                email,
    'full_name':            fullName,
    'mobile':               mobile,
    'role':                 role.name.toUpperCase(),
    'site_id':              siteId,
    'site_name':            siteName,
    'must_change_password': mustChangePassword,
    'last_login_at':        lastLoginAt?.toIso8601String(),
  };

  UserProfile copyWith({
    bool? mustChangePassword,
    String? siteName,
  }) {
    return UserProfile(
      id:                 id,
      username:           username,
      email:              email,
      fullName:           fullName,
      mobile:             mobile,
      role:               role,
      siteId:             siteId,
      siteName:           siteName ?? this.siteName,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      lastLoginAt:        lastLoginAt,
    );
  }
}

/// Initials helper for avatar widgets.
extension UserProfileX on UserProfile {
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}
