import 'dart:convert';
import 'api_service.dart';
import '../config/api_config.dart';

import '../utils/app_logger.dart';
/// Model untuk hasil search user
class UserSearchResult {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;

  UserSearchResult({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'] as int,
      username: json['username'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  String get displayName {
    final full = '${firstName.trim()} ${lastName.trim()}'.trim();
    return full.isEmpty ? username : full;
  }
}

class CollectorService {
  final ApiService _apiService = ApiService();

  static final CollectorService _instance = CollectorService._internal();
  factory CollectorService() => _instance;
  CollectorService._internal();

  /// Search users by username query
  /// GET /mobile/users/search/?q={query}
  Future<List<UserSearchResult>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await _apiService.get(
        '${ApiConfig.userSearchEndpoint}?q=${Uri.encodeComponent(query.trim())}',
      );

      if (_apiService.isSuccess(response)) {
        final json = jsonDecode(response.body);
        if (json['success'] == true && json['data'] is List) {
          return (json['data'] as List)
              .map((item) => UserSearchResult.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      logWarn('Error searching users: $e', tag: 'CLOUD');
      return [];
    }
  }

  /// Update collectors list for a project
  /// PATCH /mobile/projects/{projectId}/ dengan body {"collectors": [...usernames]}
  /// Hanya boleh dipanggil oleh created_by project
  Future<CollectorUpdateResult> updateCollectors(
    String projectId,
    List<String> collectors,
  ) async {
    try {
      final response = await _apiService.patch(
        '${ApiConfig.syncProjectEndpoint}$projectId/',
        body: {'collectors': collectors},
      );

      if (_apiService.isSuccess(response)) {
        return CollectorUpdateResult(success: true);
      } else {
        final body = jsonDecode(response.body);
        final message = body['message'] ?? body['detail'] ?? 'Failed to update collectors';
        return CollectorUpdateResult(success: false, message: message.toString());
      }
    } catch (e) {
      return CollectorUpdateResult(success: false, message: e.toString());
    }
  }
}

class CollectorUpdateResult {
  final bool success;
  final String? message;

  CollectorUpdateResult({required this.success, this.message});
}
