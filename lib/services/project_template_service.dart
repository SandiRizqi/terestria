import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';
import '../models/form_field_model.dart';

class ProjectTemplateService {
  /// Export project as template (struktur saja, tanpa data)
  Map<String, dynamic> exportAsTemplate(Project project) {
    return {
      'templateVersion': '1.0',
      'name': project.name,
      'description': project.description,
      'geometryType': project.geometryType.toString().split('.').last,
      // Definisi field lengkap (tipe asli, default, min/maks/satuan) tanpa
      // id — project hasil impor mendapat id field baru.
      'formFields': [
        for (final field in project.formFields)
          {...field.toSyncJson()}..remove('id'),
      ],
    };
  }

  /// Import project from template
  Project importFromTemplate(Map<String, dynamic> templateData, String createdBy) {
    final uuid = const Uuid();
    
    // Parse geometry type
    GeometryType geometryType;
    final geometryTypeStr = templateData['geometryType'] as String;
    switch (geometryTypeStr.toLowerCase()) {
      case 'point':
        geometryType = GeometryType.point;
        break;
      case 'line':
        geometryType = GeometryType.line;
        break;
      case 'polygon':
        geometryType = GeometryType.polygon;
        break;
      default:
        geometryType = GeometryType.point;
    }

    // Parse form fields
    List<FormFieldModel> formFields = [];
    if (templateData['formFields'] != null) {
      final fieldsData = templateData['formFields'] as List;
      // Dibaca lewat FormFieldModel.fromJson (semua tipe, default,
      // min/maks/satuan); id field baru untuk project baru.
      formFields = [
        for (final fieldData in fieldsData)
          FormFieldModel.fromJson({
            ...Map<String, dynamic>.from(fieldData as Map),
            'id': uuid.v4(),
          }),
      ];
    }

    // Create new project with template data
    final now = DateTime.now();
    return Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: templateData['name'] as String,
      description: templateData['description'] as String? ?? '',
      geometryType: geometryType,
      formFields: formFields,
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
    );
  }

  /// Save template to file
  Future<String> saveTemplateToFile(Map<String, dynamic> templateData, String projectName) async {
    try {
      // Generate filename with project name and timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedName = projectName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final filename = '${sanitizedName}_template_$timestamp.json';

      // Get download directory
      Directory? directory;
      if (Platform.isAndroid) {
        // Try multiple directories for Android
        final downloadDir = Directory('/storage/emulated/0/Download');
        
        if (await downloadDir.exists()) {
          directory = downloadDir;
        } else {
          // Fallback to app-specific external storage
          directory = await getExternalStorageDirectory();
          
          // Create Templates folder in app directory
          if (directory != null) {
            final templatesDir = Directory('${directory.path}/ProjectTemplates');
            if (!await templatesDir.exists()) {
              await templatesDir.create(recursive: true);
            }
            directory = templatesDir;
          }
        }
      } else if (Platform.isIOS) {
        // For iOS, use documents directory
        directory = await getApplicationDocumentsDirectory();
      } else {
        // For other platforms
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      // Create file path
      final filePath = '${directory.path}/$filename';
      final file = File(filePath);

      // Write JSON to file
      final jsonString = const JsonEncoder.withIndent('  ').convert(templateData);
      await file.writeAsString(jsonString);

      return filePath;
    } catch (e) {
      throw Exception('Error saving template: $e');
    }
  }

  /// Load template from file
  Future<Map<String, dynamic>> loadTemplateFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Template file not found');
      }

      final jsonString = await file.readAsString();
      final templateData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate template version
      if (templateData['templateVersion'] == null) {
        throw Exception('Invalid template format: missing version');
      }

      return templateData;
    } catch (e) {
      throw Exception('Error loading template: $e');
    }
  }

  /// Copy template to clipboard
  Future<void> copyTemplateToClipboard(Map<String, dynamic> templateData) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(templateData);
    await Clipboard.setData(ClipboardData(text: jsonString));
  }

  /// Load template from clipboard
  Future<Map<String, dynamic>> loadTemplateFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null || clipboardData.text!.isEmpty) {
      throw Exception('Clipboard is empty');
    }

    try {
      final templateData = jsonDecode(clipboardData.text!) as Map<String, dynamic>;
      
      // Validate template
      if (templateData['templateVersion'] == null) {
        throw Exception('Invalid template format');
      }

      return templateData;
    } catch (e) {
      throw Exception('Invalid template format in clipboard');
    }
  }
}
