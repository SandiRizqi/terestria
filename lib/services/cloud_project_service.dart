import 'dart:convert';
import '../models/cloud_project_model.dart';
import '../models/project_model.dart';
import 'api_service.dart';
import '../config/api_config.dart';

import '../utils/app_logger.dart';
class CloudProjectService {
  final ApiService _apiService = ApiService();

  /// Fetch list of projects from cloud/server
  /// Returns CloudProjectResponse with list of available projects
  /// Uses same endpoint as sync: /mobile/projects/?user_only=true
  Future<CloudProjectResponse?> fetchCloudProjects() async {
    try {
      logDebug('🔍 Fetching cloud projects from: ${ApiConfig.syncProjectEndpoint}?user_only=true', tag: 'CLOUD');
      
      final response = await _apiService.get(
        '${ApiConfig.syncProjectEndpoint}?user_only=true',
      );

      logDebug('📥 Response status: ${response.statusCode}', tag: 'CLOUD');
      logDebug('📥 Response body length: ${response.body.length}', tag: 'CLOUD');

      if (_apiService.isSuccess(response)) {
        final jsonData = jsonDecode(response.body);
        logDebug('📦 JSON data type: ${jsonData.runtimeType}', tag: 'CLOUD');
        
        // Response should be a list of projects directly
        if (jsonData is List) {
          logDebug('✅ Got list with ${jsonData.length} items', tag: 'CLOUD');
          
          final projects = jsonData
              .map((item) {
                try {
                  logDebug('🔄 Parsing project: ${item['name']}', tag: 'CLOUD');
                  
                  // Parse as Project first to get all fields
                  final project = Project.fromJson(item as Map<String, dynamic>);
                  
                  // Convert to CloudProject
                  return CloudProject(
                    id: project.id,
                    name: project.name,
                    description: project.description,
                    geometryType: project.geometryType.toString().split('.').last,
                    createdBy: project.createdBy ?? 'Unknown',
                    createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    dataCount: project.geoDataCount ?? 0,
                    collectors: project.collectors,
                    formFields: project.formFields.map((field) {
                      return FormFieldData(
                        label: field.label,
                        type: field.typeName,
                        required: field.required,
                        options: field.options,
                        minPhotos: field.minPhotos,
                        maxPhotos: field.maxPhotos,
                        model: field,
                      );
                    }).toList(),
                  );
                } catch (e) {
                  logError('❌ Error parsing project: $e', tag: 'CLOUD');
                  return null;
                }
              })
              .whereType<CloudProject>()
              .toList();

          logDebug('✅ Successfully parsed ${projects.length} projects', tag: 'CLOUD');

          return CloudProjectResponse(
            success: true,
            data: projects,
          );
        }
        
        // If response has 'data' field
        if (jsonData is Map<String, dynamic>) {
          logDebug('📦 Got map, trying fromJson...', tag: 'CLOUD');
          return CloudProjectResponse.fromJson(jsonData);
        }

        logError('❌ Invalid response format', tag: 'CLOUD');
        return CloudProjectResponse.error('Invalid response format');
      } else {
        logError('❌ Request failed with status: ${response.statusCode}', tag: 'CLOUD');
        return CloudProjectResponse.error(
          'Failed to fetch projects: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      logError('❌ Error fetching cloud projects: $e', tag: 'CLOUD');
      logDebug('Stack trace: $stackTrace', tag: 'CLOUD');
      return CloudProjectResponse.error(e.toString());
    }
  }
}
