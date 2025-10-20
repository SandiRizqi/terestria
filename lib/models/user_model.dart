class User {
  final String id;
  final String username;
  final String? email;
  final String? fullName;
  final String? token;
  final List<int>? scope; // Menambahkan scope dari backend

  User({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    this.token,
    this.scope,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'fullName': fullName,
      'token': token,
      'scope': scope,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['user_id'] ?? json['username'] ?? '',
      username: json['username'] ?? '',
      email: json['email'],
      fullName: json['fullName'] ?? json['full_name'],
      token: json['token'] ?? json['access_token'],
      scope: json['scope'] != null 
          ? List<int>.from(json['scope']) 
          : null,
    );
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? fullName,
    String? token,
    List<int>? scope,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      token: token ?? this.token,
      scope: scope ?? this.scope,
    );
  }

  // Helper method untuk cek apakah user memiliki scope tertentu
  bool hasScope(int scopeId) {
    return scope?.contains(scopeId) ?? false;
  }

  // Helper method untuk cek apakah user memiliki salah satu dari beberapa scope
  bool hasAnyScope(List<int> scopeIds) {
    if (scope == null) return false;
    return scopeIds.any((id) => scope!.contains(id));
  }

  // Helper method untuk cek apakah user memiliki semua scope yang dibutuhkan
  bool hasAllScopes(List<int> scopeIds) {
    if (scope == null) return false;
    return scopeIds.every((id) => scope!.contains(id));
  }
}
