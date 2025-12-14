import 'dart:convert';
import '../models/cloud_project_model.dart';
import '../models/project_model.dart';
import 'api_service.dart';
import '../config/api_config.dart';

class CloudProjectService {
  final ApiService _apiService = ApiService();

  /// Fetch list of projects from cloud/server
  /// Returns CloudProjectResponse with list of available projects
  /// Uses same endpoint as sync: /mobile/projects/?user_only=true
  Future<CloudProjectResponse?> fetchCloudProjects() async {
    try {
      print('🔍 Fetching cloud projects from: ${ApiConfig.syncProjectEndpoint}?user_only=true');
      
      final response = await _apiService.get(
        '${ApiConfig.syncProjectEndpoint}?user_only=true',
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body length: ${response.body.length}');

      if (_apiService.isSuccess(response)) {
        final jsonData = jsonDecode(response.body);
        print('📦 JSON data type: ${jsonData.runtimeType}');
        
        // Response should be a list of projects directly
        if (jsonData is List) {
          print('✅ Got list with ${jsonData.length} items');
          
          final projects = jsonData
              .map((item) {
                try {
                  print('🔄 Parsing project: ${item['name']}');
                  
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
                    dataCount: 0, // Server doesn't provide this in project list
                    formFields: project.formFields.map((field) {
                      return FormFieldData(
                        label: field.label,
                        type: field.type.toString().split('.').last,
                        required: field.required,
                        options: field.options,
                      );
                    }).toList(),
                  );
                } catch (e) {
                  print('❌ Error parsing project: $e');
                  return null;
                }
              })
              .whereType<CloudProject>()
              .toList();

          print('✅ Successfully parsed ${projects.length} projects');

          return CloudProjectResponse(
            success: true,
            data: projects,
          );
        }
        
        // If response has 'data' field
        if (jsonData is Map<String, dynamic>) {
          print('📦 Got map, trying fromJson...');
          return CloudProjectResponse.fromJson(jsonData);
        }

        print('❌ Invalid response format');
        return CloudProjectResponse.error('Invalid response format');
      } else {
        print('❌ Request failed with status: ${response.statusCode}');
        return CloudProjectResponse.error(
          'Failed to fetch projects: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error fetching cloud projects: $e');
      print('Stack trace: $stackTrace');
      return CloudProjectResponse.error(e.toString());
    }
  }
}
