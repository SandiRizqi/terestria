import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../config/api_config.dart';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import '../models/form_field_model.dart';
import '../models/json_parse.dart';
import 'storage_service.dart';
import 'photo_sync_service.dart';
import 'crashlytics_service.dart';
import 'connectivity_service.dart';
import 'sync_watermark_service.dart';
import 'pull_preflight.dart';

import '../utils/app_logger.dart';

/// Progres sync untuk UI: [message] siap tampil, [done]/[total] opsional.
typedef SyncProgressCallback = void Function(String message,
    {int? done, int? total});

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;

  final ApiService _apiService;
  final StorageService _storageService;
  final PhotoSyncService _photoSyncService;
  final ConnectivityService _connectivity;
  final SyncWatermarkService _watermark;

  static const _tag = 'SYNC';

  SyncService._internal()
      : _apiService = ApiService(),
        _storageService = StorageService(),
        _photoSyncService = PhotoSyncService(),
        _connectivity = ConnectivityService(),
        _watermark = SyncWatermarkService();

  /// Konstruktor untuk pengujian: memungkinkan injeksi dependency.
  /// Argumen yang tidak diberikan jatuh ke singleton default.
  SyncService.forTest({
    ApiService? apiService,
    StorageService? storageService,
    PhotoSyncService? photoSyncService,
    ConnectivityService? connectivity,
    SyncWatermarkService? watermark,
  })  : _apiService = apiService ?? ApiService(),
        _storageService = storageService ?? StorageService(),
        _photoSyncService = photoSyncService ?? PhotoSyncService(),
        _connectivity = connectivity ?? ConnectivityService(),
        _watermark = watermark ?? SyncWatermarkService();

  // ==================== EKSKLUSIVITAS ====================

  /// True selama ada proses sync (manual atau otomatis) yang berjalan.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  Future<void>? _running;

  /// Jalankan [body] setelah sync lain selesai — sync manual & auto-sync tak
  /// pernah tumpang tindih (dua upload record yang sama bersamaan).
  Future<T> runExclusive<T>(Future<T> Function() body) async {
    while (_running != null) {
      try {
        await _running;
      } catch (_) {}
    }
    final done = Completer<void>();
    _running = done.future;
    isSyncing.value = true;
    try {
      return await body();
    } finally {
      _running = null;
      isSyncing.value = false;
      done.complete();
    }
  }

  // ==================== UPLOAD TO SERVER ====================

  /// Payload push untuk [geoData]. Semua waktu dikirim UTC eksplisit (akhiran
  /// Z) — dulu waktu lokal tanpa zona, sehingga server tak bisa membedakan
  /// WIB/WITA/WIT. Titik membawa seluruh metadata (termasuk kualitas RTK).
  @visibleForTesting
  static Map<String, dynamic> buildGeoDataPayload(
    GeoData geoData,
    Project project,
    Map<String, dynamic> formData, {
    DateTime? now,
  }) =>
      {
        'id': geoData.id,
        'project_id': geoData.projectId,
        'project_name': project.name,
        'geometry_type': project.geometryType.toString().split('.').last,
        'form_data': formData,
        'points': geoData.points
            .map((point) => {
                  'latitude': point.latitude,
                  'longitude': point.longitude,
                  'altitude': point.altitude,
                  'accuracy': point.accuracy,
                  'speed': point.speed,
                  'fixQuality': point.fixQuality,
                  'satelliteCount': point.satelliteCount,
                  'timestamp': point.timestamp.toUtc().toIso8601String(),
                })
            .toList(),
        'created_at': geoData.createdAt.toUtc().toIso8601String(),
        'updated_at': geoData.updatedAt.toUtc().toIso8601String(),
        'synced_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// Sync single GeoData to backend
  Future<SyncResult> syncGeoData(GeoData geoData, Project project) async {
    try {
      // Step 1: Upload photos to OSS and get URLs
      logDebug('Processing photos for geodata ${geoData.id}...', tag: _tag);
      final processedFormData = await _photoSyncService.processFormDataForPush(
        geoData.formData,
        project,
      );

      // Step 1b: Guard integritas — jangan tandai synced kalau masih ada foto
      // yang belum ter-upload (serverKey null). Simpan dulu progres parsial ke
      // lokal supaya foto yang SUDAH berhasil upload tidak di-upload ulang saat
      // retry, lalu batalkan sync agar record tetap unsynced & dicoba lagi.
      final pendingPhotos =
          _photoSyncService.pendingPhotoUploads(processedFormData, project);
      if (pendingPhotos.isNotEmpty) {
        final kept = await _storageService.saveGeoDataIfUnchanged(
          geoData.copyWith(formData: processedFormData, isSynced: false),
          expectedUpdatedAt: geoData.updatedAt,
        );
        if (!kept) {
          logWarn(
              'Record ${geoData.id} was edited during photo upload; '
              'upload progress not saved (photos will be re-sent)',
              tag: _tag);
        }
        final missing = pendingPhotos.where((p) => !p.fileExists).length;
        crashlytics.recordError(
          Exception('Incomplete photo upload'),
          StackTrace.current,
          reason: 'Sync: photos not fully uploaded, record kept unsynced',
          information: [
            'geodata_id: ${geoData.id}',
            'project_id: ${geoData.projectId}',
            'pending_count: ${pendingPhotos.length}',
            'missing_files: $missing',
            'pending_photos: ${pendingPhotos.map((p) => p.name).join(", ")}',
          ],
        );
        return SyncResult(
          success: false,
          message: missing > 0
              ? '$missing photo file(s) are missing on this device; '
                  'the record cannot be uploaded completely'
              : '${pendingPhotos.length} photo(s) not uploaded yet; '
                  'the record will be retried',
        );
      }

      // Step 2: Prepare data untuk dikirim (dengan OSS URLs)
      final payload = buildGeoDataPayload(geoData, project, processedFormData);

      // Gunakan ApiService yang sudah include token
      final response = await _apiService.post(
        ApiConfig.syncDataEndpoint,
        body: payload,
      );

      if (response.statusCode == 401) {
        return SyncResult(
          success: false,
          message: 'Your session has expired. Sign in again to continue.',
          isAuthError: true,
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = _decodeObject(response.body);
        if (responseData == null) {
          // 2xx tapi bukan JSON: biasanya halaman login hotspot/proxy, bukan
          // server kita → JANGAN tandai synced.
          logWarn(
              'Upload of ${geoData.id}: 2xx with non-JSON body — treating as '
              'connection problem (captive portal?)',
              tag: _tag);
          return SyncResult(
            success: false,
            message: 'Unexpected response from the server. If you are on a '
                'hotspot or office Wi-Fi, sign in to the network first.',
            isConnectionError: true,
          );
        }

        // Tandai synced HANYA bila record belum diedit selama upload.
        final updatedGeoData = geoData.copyWith(
          formData: processedFormData,
          isSynced: true,
          syncedAt: DateTime.now(),
        );
        final marked = await _storageService.saveGeoDataIfUnchanged(
          updatedGeoData,
          expectedUpdatedAt: geoData.updatedAt,
        );
        if (!marked) {
          logWarn(
              'Record ${geoData.id} changed during upload; keeping local '
              'edits unsynced so they are uploaded next time',
              tag: _tag);
        }

        return SyncResult(
          success: true,
          message: responseData['message']?.toString() ??
              'Data synced successfully',
          data: responseData,
        );
      } else {
        logWarn(
            'Upload of ${geoData.id} rejected: HTTP ${response.statusCode} '
            '${_snippet(response.body)}',
            tag: _tag);
        return SyncResult(
          success: false,
          message: _serverErrorMessage(response.statusCode, response.body),
        );
      }
    } on SocketException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: No internet connection (syncGeoData)',
          information: ['geodata_id: ${geoData.id}', 'project_id: ${geoData.projectId}']);
      return SyncResult(
          success: false,
          message: 'No connection to the server',
          isConnectionError: true);
    } on TimeoutException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: Connection timeout (syncGeoData)',
          information: ['geodata_id: ${geoData.id}']);
      return SyncResult(
          success: false,
          message: 'Connection timed out',
          isConnectionError: true);
    } on ApiException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: API error (syncGeoData)',
          information: ['message: ${e.message}', 'geodata_id: ${geoData.id}']);
      return SyncResult(
          success: false,
          message: e.isConnectionError
              ? 'No connection to the server'
              : 'Upload failed. Please try again.',
          isConnectionError: e.isConnectionError);
    } catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: syncGeoData failed',
          information: ['geodata_id: ${geoData.id}', 'project_id: ${geoData.projectId}']);
      return SyncResult(
          success: false,
          message: 'Upload failed unexpectedly. Details were saved to the '
              'diagnostic log.');
    }
  }

  /// Sync Project to backend
  Future<SyncResult> syncProject(Project project) async {
    try {
      // Prepare project data untuk dikirim
      final Map<String, dynamic> payload = {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'geometry_type': project.geometryType.toString().split('.').last,
        'form_fields': project.formFields.map((field) => {
          'id': field.id,
          'label': field.label,
          'type': field.type.toString().split('.').last,
          'required': field.required,
          'options': field.options,
          if (field.defaultValue != null) 'defaultValue': field.defaultValue,
          if (field.minPhotos != null) 'minPhotos': field.minPhotos,
          if (field.maxPhotos != null) 'maxPhotos': field.maxPhotos,
        }).toList(),
        'created_at': project.createdAt.toUtc().toIso8601String(),
        'updated_at': project.updatedAt.toUtc().toIso8601String(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Gunakan ApiService yang sudah include token
      final response = await _apiService.post(
        ApiConfig.syncProjectEndpoint,
        body: payload,
      );

      if (response.statusCode == 401) {
        return SyncResult(
          success: false,
          message: 'Your session has expired. Sign in again to continue.',
          isAuthError: true,
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = _decodeObject(response.body);
        if (responseData == null) {
          logWarn('Project ${project.id}: 2xx with non-JSON body', tag: _tag);
          return SyncResult(
            success: false,
            message: 'Unexpected response from the server. If you are on a '
                'hotspot or office Wi-Fi, sign in to the network first.',
            isConnectionError: true,
          );
        }

        // Update sync status in local database
        await _storageService.updateProjectSyncStatus(
          project.id,
          true,
          syncedAt: DateTime.now(),
        );
        logInfo('Project "${project.name}" synced', tag: _tag);

        return SyncResult(
          success: true,
          message: responseData['message']?.toString() ??
              'Project synced successfully',
          data: responseData,
        );
      } else {
        logWarn(
            'Project ${project.id} rejected: HTTP ${response.statusCode} '
            '${_snippet(response.body)}',
            tag: _tag);
        return SyncResult(
          success: false,
          message: _serverErrorMessage(response.statusCode, response.body),
        );
      }
    } on SocketException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: No internet connection (syncProject)',
          information: ['project_id: ${project.id}']);
      return SyncResult(
          success: false,
          message: 'No connection to the server',
          isConnectionError: true);
    } on TimeoutException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: Connection timeout (syncProject)');
      return SyncResult(
          success: false,
          message: 'Connection timed out',
          isConnectionError: true);
    } on ApiException catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: API error (syncProject)',
          information: ['project_id: ${project.id}', 'message: ${e.message}']);
      return SyncResult(
          success: false,
          message: e.isConnectionError
              ? 'No connection to the server'
              : 'Project upload failed. Please try again.',
          isConnectionError: e.isConnectionError);
    } catch (e, stack) {
      crashlytics.recordError(e, stack,
          reason: 'Sync: syncProject failed',
          information: ['project_id: ${project.id}']);
      return SyncResult(
          success: false,
          message: 'Project upload failed unexpectedly. Details were saved '
              'to the diagnostic log.');
    }
  }

  /// Sync multiple GeoData
  Future<BatchSyncResult> syncMultipleGeoData(
    List<GeoData> geoDataList,
    Project project, {
    SyncProgressCallback? onProgress,
  }) async {
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];
    final failedIds = <String>[];

    // Pre-flight: pastikan host server bisa di-resolve sebelum loop.
    final reachable = await _connectivity.checkServerReachable();
    if (!reachable) {
      return BatchSyncResult(
        total: geoDataList.length,
        successCount: 0,
        failCount: geoDataList.length,
        errors: ['No connection to the server'],
        abortedDueToConnection: true,
        failedIds: geoDataList.map((g) => g.id).toList(),
      );
    }

    for (var i = 0; i < geoDataList.length; i++) {
      final geoData = geoDataList[i];
      onProgress?.call('Uploading record ${i + 1} of ${geoDataList.length}…',
          done: i, total: geoDataList.length);
      final result = await syncGeoData(geoData, project);
      if (result.success) {
        successCount++;
      } else {
        // Early-abort: koneksi putus / sesi habis → hentikan; sisa item
        // dibiarkan belum tersync (offline-first) dan bisa dicoba lagi nanti.
        if (result.isConnectionError || result.isAuthError) {
          final remaining = geoDataList.sublist(i).map((g) => g.id);
          return BatchSyncResult(
            total: geoDataList.length,
            successCount: successCount,
            failCount: geoDataList.length - successCount,
            errors: [...errors, result.message],
            abortedDueToConnection: result.isConnectionError,
            abortedDueToAuth: result.isAuthError,
            failedIds: [...failedIds, ...remaining],
          );
        }
        failCount++;
        failedIds.add(geoData.id);
        errors.add(result.message);
      }
    }

    logInfo(
        'Upload "${project.name}": $successCount/${geoDataList.length} ok'
        '${failCount > 0 ? ', $failCount failed' : ''}',
        tag: _tag);
    return BatchSyncResult(
      total: geoDataList.length,
      successCount: successCount,
      failCount: failCount,
      errors: errors,
      failedIds: failedIds,
    );
  }

  /// Satu tombol "Sync" per project: project (bila belum tersinkron) → data
  /// yang belum tersinkron (foto ikut terunggah per record). [onlyIds]
  /// membatasi ke record tertentu (dipakai "Retry failed").
  Future<BatchSyncResult> syncProjectAndData(
    Project project, {
    SyncProgressCallback? onProgress,
    Set<String>? onlyIds,
  }) {
    return runExclusive(() async {
      final reachable = await _connectivity.checkServerReachable();
      if (!reachable) {
        final pending =
            await _storageService.getUnsyncedGeoData(projectId: project.id);
        return BatchSyncResult(
          total: pending.length,
          successCount: 0,
          failCount: pending.length,
          errors: ['No connection to the server'],
          abortedDueToConnection: true,
          failedIds: pending.map((g) => g.id).toList(),
        );
      }

      // Project harus ada di server dulu (server menolak data tanpa project).
      final current = await _storageService.getProjectById(project.id) ?? project;
      if (!current.isSynced) {
        onProgress?.call('Uploading project…');
        final pr = await syncProject(current);
        if (!pr.success) {
          final pending =
              await _storageService.getUnsyncedGeoData(projectId: project.id);
          return BatchSyncResult(
            total: pending.length,
            successCount: 0,
            failCount: pending.length,
            errors: ['Project: ${pr.message}'],
            abortedDueToConnection: pr.isConnectionError,
            abortedDueToAuth: pr.isAuthError,
            failedIds: pending.map((g) => g.id).toList(),
            projectFailed: true,
          );
        }
      }

      var pending =
          await _storageService.getUnsyncedGeoData(projectId: project.id);
      if (onlyIds != null) {
        pending = pending.where((g) => onlyIds.contains(g.id)).toList();
      }
      if (pending.isEmpty) {
        return BatchSyncResult(
            total: 0, successCount: 0, failCount: 0, errors: const []);
      }
      return syncMultipleGeoData(pending, current, onProgress: onProgress);
    });
  }

  /// Sync all unsynced data to server (Upload)
  Future<FullSyncResult> syncAllUnsyncedData({
    SyncProgressCallback? onProgress,
  }) {
    return runExclusive(() => _syncAllUnsyncedData(onProgress: onProgress));
  }

  Future<FullSyncResult> _syncAllUnsyncedData({
    SyncProgressCallback? onProgress,
  }) async {
    int projectsSuccess = 0;
    int projectsFail = 0;
    int geoDataSuccess = 0;
    int geoDataFail = 0;
    final errors = <String>[];

    try {
      // Pre-flight: pastikan host server bisa di-resolve sebelum sync apa pun.
      final reachable = await _connectivity.checkServerReachable();
      if (!reachable) {
        return FullSyncResult(
          projectsTotal: 0,
          projectsSuccess: 0,
          projectsFail: 0,
          geoDataTotal: 0,
          geoDataSuccess: 0,
          geoDataFail: 0,
          errors: ['No connection to the server'],
          abortedDueToConnection: true,
        );
      }

      // 1. Sync unsynced projects first
      final unsyncedProjects = await _storageService.getUnsyncedProjects();
      final failedProjectIds = <String>{};

      for (var i = 0; i < unsyncedProjects.length; i++) {
        final project = unsyncedProjects[i];
        onProgress?.call('Uploading project ${i + 1} of '
            '${unsyncedProjects.length}…');
        final result = await syncProject(project);
        if (result.success) {
          projectsSuccess++;
        } else {
          if (result.isConnectionError || result.isAuthError) {
            return FullSyncResult(
              projectsTotal: unsyncedProjects.length,
              projectsSuccess: projectsSuccess,
              projectsFail: unsyncedProjects.length - projectsSuccess,
              geoDataTotal: 0,
              geoDataSuccess: 0,
              geoDataFail: 0,
              errors: [...errors, result.message],
              abortedDueToConnection: result.isConnectionError,
              abortedDueToAuth: result.isAuthError,
            );
          }
          projectsFail++;
          failedProjectIds.add(project.id);
          errors.add('Project ${project.name}: ${result.message}');
        }
      }

      // 2. Sync unsynced geo data
      final unsyncedGeoData = await _storageService.getUnsyncedGeoData();
      final projectCache = <String, Project?>{};

      for (var i = 0; i < unsyncedGeoData.length; i++) {
        final geoData = unsyncedGeoData[i];
        onProgress?.call(
            'Uploading record ${i + 1} of ${unsyncedGeoData.length}…',
            done: i,
            total: unsyncedGeoData.length);
        // Get project info
        final project = projectCache.containsKey(geoData.projectId)
            ? projectCache[geoData.projectId]
            : (projectCache[geoData.projectId] =
                await _storageService.getProjectById(geoData.projectId));
        if (project == null) {
          geoDataFail++;
          errors.add('Record ${geoData.id}: project not found on this device');
          continue;
        }
        // Server menolak data tanpa project → jangan unggah foto sia-sia.
        if (failedProjectIds.contains(project.id) || !project.isSynced) {
          geoDataFail++;
          errors.add('Project ${project.name}: not uploaded yet');
          continue;
        }
        final result = await syncGeoData(geoData, project);
        if (result.success) {
          geoDataSuccess++;
        } else {
          // Early-abort saat koneksi putus — sisa data dibiarkan unsynced.
          if (result.isConnectionError || result.isAuthError) {
            return FullSyncResult(
              projectsTotal: unsyncedProjects.length,
              projectsSuccess: projectsSuccess,
              projectsFail: projectsFail,
              geoDataTotal: unsyncedGeoData.length,
              geoDataSuccess: geoDataSuccess,
              geoDataFail: unsyncedGeoData.length - geoDataSuccess,
              errors: [...errors, result.message],
              abortedDueToConnection: result.isConnectionError,
              abortedDueToAuth: result.isAuthError,
            );
          }
          geoDataFail++;
          errors.add('${project.name}: ${result.message}');
        }
      }

      logInfo(
          'Upload all: projects $projectsSuccess/${unsyncedProjects.length}, '
          'records $geoDataSuccess/${unsyncedGeoData.length}',
          tag: _tag);
      return FullSyncResult(
        projectsTotal: unsyncedProjects.length,
        projectsSuccess: projectsSuccess,
        projectsFail: projectsFail,
        geoDataTotal: unsyncedGeoData.length,
        geoDataSuccess: geoDataSuccess,
        geoDataFail: geoDataFail,
        errors: errors,
      );
    } catch (e, st) {
      logError('Full upload failed', tag: _tag, error: e, stack: st);
      return FullSyncResult(
        projectsTotal: 0,
        projectsSuccess: projectsSuccess,
        projectsFail: projectsFail,
        geoDataTotal: 0,
        geoDataSuccess: geoDataSuccess,
        geoDataFail: geoDataFail,
        errors: [
          ...errors,
          'Upload stopped unexpectedly. Details were saved to the diagnostic log.'
        ],
      );
    }
  }

  // ==================== DOWNLOAD FROM SERVER ====================

  /// Pull projects from server and save to local database
  Future<SyncResult> pullProjectsFromServer() async {
    try {
      final response = await _apiService.get(ApiConfig.syncProjectEndpoint);

      if (response.statusCode == 401) {
        return SyncResult(
          success: false,
          message: 'Your session has expired. Sign in again to continue.',
          isAuthError: true,
        );
      }

      if (response.statusCode == 200) {
        final responseData = _decodeObject(response.body);
        if (responseData == null) {
          return SyncResult(
            success: false,
            message: 'Unexpected response from the server.',
            isConnectionError: true,
          );
        }
        final projectsList = responseData['data'] as List? ?? [];

        int savedCount = 0;
        int conflictCount = 0;
        int failedCount = 0;
        for (var projectJson in projectsList) {
          try {
            // Parse project from server format
            final serverProject = parseProjectFromServer(
                Map<String, dynamic>.from(projectJson as Map));

            // Check if project exists locally
            final existingProject =
                await _storageService.getProjectById(serverProject.id);

            if (existingProject == null) {
              // New project from server - save it
              await _storageService.saveProject(serverProject);
              savedCount++;
            } else if (!existingProject.isSynced) {
              // Perubahan lokal belum ter-upload: JANGAN timpa.
              conflictCount++;
              logWarn(
                  'Project ${serverProject.id} has unsynced local changes; '
                  'server version not applied',
                  tag: _tag);
            } else if (serverProject.updatedAt
                .isAfter(existingProject.updatedAt)) {
              // Server version is newer - update local. Kolaborator dari
              // server hanya dipakai bila server memang mengirimnya.
              final hasCollectors = (projectJson).containsKey('collectors');
              await _storageService.saveProject(hasCollectors
                  ? serverProject
                  : serverProject.copyWith(
                      collectors: existingProject.collectors));
              savedCount++;
            }
          } catch (e, st) {
            failedCount++;
            logError(
                'Skipping unreadable project from server '
                '(id=${projectJson is Map ? projectJson['id'] : '?'})',
                tag: _tag,
                error: e,
                stack: st);
          }
        }

        return SyncResult(
          success: true,
          message: 'Downloaded $savedCount projects from server'
              '${conflictCount > 0 ? '; $conflictCount kept your unsynced changes' : ''}'
              '${failedCount > 0 ? '; $failedCount could not be read' : ''}',
          data: {
            'count': savedCount,
            'conflicts': conflictCount,
            'failed': failedCount,
          },
        );
      } else {
        logWarn('Pull projects: HTTP ${response.statusCode}', tag: _tag);
        return SyncResult(
          success: false,
          message: _serverErrorMessage(response.statusCode, response.body),
        );
      }
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
        isConnectionError: true,
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timed out',
        isConnectionError: true,
      );
    } on ApiException catch (e) {
      return SyncResult(
        success: false,
        message: e.isConnectionError
            ? 'No connection to the server'
            : 'Downloading projects failed. Please try again.',
        isConnectionError: e.isConnectionError,
      );
    } catch (e, st) {
      logError('Pull projects failed', tag: _tag, error: e, stack: st);
      return SyncResult(
        success: false,
        message: 'Downloading projects failed. Details were saved to the '
            'diagnostic log.',
      );
    }
  }

  /// Pull geo data for a specific project from server (with pagination support)
  /// Bangun rangkaian query `&f=key:value` untuk filter dinamis form_data
  /// (JSONB) di backend. Key & value di-encode; separator `:` tetap literal
  /// agar backend bisa `split(':', 1)`. Map kosong/null → string kosong.
  String _buildFormDataFilterParam(Map<String, String>? filters) {
    if (filters == null || filters.isEmpty) return '';
    final sb = StringBuffer();
    filters.forEach((k, v) {
      sb.write('&f=${Uri.encodeQueryComponent(k)}:${Uri.encodeQueryComponent(v)}');
    });
    return sb.toString();
  }

  /// Ambang jumlah record yang memicu peringatan ekstra di dialog konfirmasi.
  static const int pullWarnThreshold = 1000;

  /// Preflight sebelum pull: (1) pastikan server reachable (online), (2) tanya
  /// berapa record yang akan dikirim untuk [projectId] + [formDataFilters].
  /// Tidak menampilkan UI — mengembalikan keputusan; caller (UI) yang
  /// menampilkan pesan/konfirmasi lalu memanggil [pullGeoDataFromServer].
  Future<PullPreflightResult> preflightPull(
    String projectId, {
    Map<String, String>? formDataFilters,
  }) async {
    final reachable = await _connectivity.checkServerReachable();
    if (!reachable) {
      return const PullPreflightResult(
        PullPreflightStatus.offline,
        message: 'Cannot reach the server. Make sure you are online and try again.',
      );
    }
    try {
      final count = await countGeoDataOnServer(
        projectId,
        formDataFilters: formDataFilters,
      );
      if (count <= 0) {
        return const PullPreflightResult(PullPreflightStatus.empty, count: 0);
      }
      return PullPreflightResult(
        PullPreflightStatus.ready,
        count: count,
        warnLarge: count > pullWarnThreshold,
      );
    } catch (e, st) {
      logWarn('Pull preflight failed: $e', tag: _tag);
      logDebug('$st', tag: _tag);
      return const PullPreflightResult(
        PullPreflightStatus.error,
        message: 'Could not check how much data is on the server. '
            'Please try again.',
      );
    }
  }

  /// Preflight: tanya server berapa record yang akan di-pull untuk project +
  /// filter ini (mode `count_only=true`, tanpa serialisasi record). Melempar
  /// [Exception] bila server tidak membalas 200.
  Future<int> countGeoDataOnServer(
    String projectId, {
    Map<String, String>? formDataFilters,
  }) async {
    final filterParam = _buildFormDataFilterParam(formDataFilters);
    final response = await _apiService.get(
      '${ApiConfig.syncDataEndpoint}by-project/?project_id=$projectId&count_only=true$filterParam',
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['total_count'] as num?)?.toInt() ?? 0;
    }
    throw Exception('Count failed: HTTP ${response.statusCode}');
  }

  Future<SyncResult> pullGeoDataFromServer(
    String projectId, {
    void Function(String message)? onProgress,
    bool forceFull = false,
    DateTime? updatedAfter,
    Map<String, String>? formDataFilters,
  }) async {
    try {
      // Get project for photo field identification (once, outside the loop)
      final project = await _storageService.getProjectById(projectId);

      // Delta sync: hanya tarik record yang berubah sejak pull sukses terakhir.
      // Null → full pull (sync pertama, atau [forceFull] untuk pull-to-refresh
      // manual/pemulihan). Watermark tetap dimajukan setelah seluruh halaman
      // project sukses (lihat akhir metode).
      // Pull manual "sejak tanggal" (updatedAfter): pakai tanggal itu sebagai
      // filter TAPI berdiri sendiri — TIDAK membaca/menulis watermark, agar delta
      // sync otomatis tidak terganggu (mencegah gap record yang lebih lama).
      final bool manualDate = updatedAfter != null;
      final watermark = manualDate
          ? null
          : (forceFull ? null : await _watermark.getLastPull(projectId));
      final DateTime? effectiveAfter = manualDate ? updatedAfter : watermark;
      final deltaParam = effectiveAfter != null
          ? '&updated_after=${effectiveAfter.toUtc().toIso8601String()}'
          : '';
      final filterParam = _buildFormDataFilterParam(formDataFilters);

      // Watermark hanya boleh maju sejauh record yang TUNTAS (disimpan atau
      // sengaja dilewati). Record gagal menahan watermark di updatedAt-nya
      // (filter server inklusif → record itu ditarik lagi lain kali). Dulu
      // watermark maju melewati record gagal → record hilang permanen.
      final tracker = PullWatermarkTracker();

      int savedCount = 0;
      int updatedCount = 0;
      int conflictCount = 0;
      int currentPage = 1;
      int totalPages = 1;

      do {
        onProgress?.call(
          'Fetching page $currentPage${totalPages > 1 ? "/$totalPages" : ""}...',
        );

        final response = await _apiService.get(
          '${ApiConfig.syncDataEndpoint}by-project/?project_id=$projectId&page=$currentPage$deltaParam$filterParam',
        );

        if (response.statusCode == 401) {
          return SyncResult(
            success: false,
            message: 'Your session has expired. Sign in again to continue.',
            isAuthError: true,
          );
        }
        if (response.statusCode != 200) {
          logWarn(
              'Pull $projectId page $currentPage: HTTP ${response.statusCode}',
              tag: _tag);
          return SyncResult(
            success: false,
            message: _serverErrorMessage(response.statusCode, response.body),
          );
        }

        final responseData = _decodeObject(response.body);
        if (responseData == null) {
          return SyncResult(
            success: false,
            message: 'Unexpected response from the server.',
            isConnectionError: true,
          );
        }
        totalPages = parseInt(responseData['total_pages']) ?? 1;
        final geoDataList = responseData['data'] as List? ?? [];

        onProgress?.call(
          'Processing ${geoDataList.length} records (page $currentPage/$totalPages)...',
        );

        for (var i = 0; i < geoDataList.length; i++) {
          final raw = geoDataList[i];
          GeoData geoData;
          try {
            geoData = GeoData.fromJson(Map<String, dynamic>.from(raw as Map));
          } catch (e, st) {
            final rawMap = raw is Map ? raw : const {};
            tracker.failed(
                parseDateTime(rawMap['updated_at'] ?? rawMap['updatedAt']));
            logError(
                'Skipping unreadable record from server (id=${rawMap['id']})',
                tag: _tag,
                error: e,
                stack: st);
            continue;
          }

          try {
            // Check if geo data exists locally
            final existingGeoData =
                await _storageService.getGeoDataById(geoData.id);

            if (existingGeoData == null) {
              // New geo data from server - download photos and save
              logDebug('New geodata from server: ${geoData.id}', tag: _tag);
              onProgress?.call(
                'Downloading photos for record ${i + 1}/${geoDataList.length} (page $currentPage/$totalPages)...',
              );

              final processedFormData =
                  await _photoSyncService.processFormDataForPull(
                geoData.formData,
                project,
              );

              await _storageService.saveGeoData(
                geoData.copyWith(formData: processedFormData, isSynced: true),
              );
              savedCount++;
            } else if (!existingGeoData.isSynced) {
              // Edit lokal belum ter-upload: JANGAN timpa. Upload berikutnya
              // mengirim versi lokal ke server.
              conflictCount++;
              logWarn(
                  'Record ${geoData.id} has unsynced local changes; '
                  'server version not applied',
                  tag: _tag);
            } else if (geoData.updatedAt.isAfter(existingGeoData.updatedAt)) {
              // Server version is newer - download photos and update local
              logDebug('Updating geodata from server: ${geoData.id}', tag: _tag);
              onProgress?.call(
                'Updating record ${i + 1}/${geoDataList.length} (page $currentPage/$totalPages)...',
              );

              final processedFormData =
                  await _photoSyncService.processFormDataForPull(
                geoData.formData,
                project,
              );

              await _storageService.saveGeoData(
                geoData.copyWith(formData: processedFormData, isSynced: true),
              );
              updatedCount++;
            }
            tracker.handled(geoData.updatedAt);
          } catch (e, st) {
            tracker.failed(geoData.updatedAt);
            logError('Failed to store record ${geoData.id} from server',
                tag: _tag, error: e, stack: st);
          }
        }

        currentPage++;
      } while (currentPage <= totalPages);

      // Semua halaman sukses → majukan watermark (tak pernah mundur, tak
      // melewati record gagal). Pull manual by-tanggal tak menyentuh watermark.
      if (!manualDate) {
        final newWatermark = tracker.nextWatermark(watermark);
        if (newWatermark != null && newWatermark != watermark) {
          await _watermark.setLastPull(projectId, newWatermark);
        }
      }

      if (tracker.failedCount > 0) {
        logWarn(
            'Pull $projectId: ${tracker.failedCount} record(s) failed; '
            'they will be retried on the next pull',
            tag: _tag);
      }
      logInfo(
          'Pull $projectId: $savedCount new, $updatedCount updated'
          '${conflictCount > 0 ? ', $conflictCount kept local' : ''}',
          tag: _tag);

      return SyncResult(
        success: true,
        message: 'Downloaded $savedCount new, $updatedCount updated records'
            '${conflictCount > 0 ? '; $conflictCount kept your unsynced changes' : ''}'
            '${tracker.failedCount > 0 ? '; ${tracker.failedCount} failed and will be retried' : ''}',
        data: {
          'saved': savedCount,
          'updated': updatedCount,
          'count': savedCount + updatedCount,
          'conflicts': conflictCount,
          'failed': tracker.failedCount,
        },
      );
    } on SocketException {
      return SyncResult(
        success: false,
        message: 'No internet connection',
        isConnectionError: true,
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        message: 'Connection timed out',
        isConnectionError: true,
      );
    } on ApiException catch (e) {
      return SyncResult(
        success: false,
        message: e.isConnectionError
            ? 'No connection to the server'
            : 'Downloading data failed. Please try again.',
        isConnectionError: e.isConnectionError,
      );
    } catch (e, st) {
      logError('Pull $projectId failed', tag: _tag, error: e, stack: st);
      return SyncResult(
        success: false,
        message: 'Downloading data failed. Details were saved to the '
            'diagnostic log.',
      );
    }
  }

  /// Two-way sync: Upload local changes and download server changes
  Future<TwoWaySyncResult> performTwoWaySync() async {
    try {
      // Step 1: Upload local unsynced data to server
      final uploadResult = await syncAllUnsyncedData();

      // Step 2: Download projects from server
      final projectsDownloadResult = await pullProjectsFromServer();

      // Step 3: Download geo data for all projects
      final projects = await _storageService.loadProjects();
      int totalGeoDataDownloaded = 0;

      for (var project in projects) {
        final geoDataDownloadResult = await pullGeoDataFromServer(project.id);
        if (geoDataDownloadResult.success && geoDataDownloadResult.data != null) {
          totalGeoDataDownloaded += geoDataDownloadResult.data!['count'] as int? ?? 0;
        }
      }

      return TwoWaySyncResult(
        success: true,
        uploadResult: uploadResult,
        projectsDownloaded: projectsDownloadResult.data?['count'] as int? ?? 0,
        geoDataDownloaded: totalGeoDataDownloaded,
        message: 'Two-way sync completed successfully',
      );
    } catch (e, st) {
      logError('Two-way sync failed', tag: _tag, error: e, stack: st);
      return TwoWaySyncResult(
        success: false,
        uploadResult: FullSyncResult(
          projectsTotal: 0,
          projectsSuccess: 0,
          projectsFail: 0,
          geoDataTotal: 0,
          geoDataSuccess: 0,
          geoDataFail: 0,
          errors: [],
        ),
        projectsDownloaded: 0,
        geoDataDownloaded: 0,
        message: 'Two-way sync failed. Details were saved to the diagnostic log.',
      );
    }
  }

  // ==================== HELPER METHODS ====================

  /// Project dari format server. Memakai parser field yang sama dengan data
  /// lokal (tipe `decimal`, `defaultValue`, snake/camelCase) — dulu tipe
  /// `decimal` berubah jadi `text` saat pull.
  @visibleForTesting
  static Project parseProjectFromServer(Map<String, dynamic> json) {
    final formFieldsList = json['form_fields'] ?? json['formFields'];
    final formFields = formFieldsList is List
        ? formFieldsList
            .map((f) =>
                FormFieldModel.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList()
        : <FormFieldModel>[];
    final collectors = json['collectors'];

    final id = parseString(json['id']);
    if (id == null) throw const FormatException('Project without "id"');
    return Project(
      id: id,
      name: parseString(json['name']) ?? 'Untitled project',
      description: json['description']?.toString() ?? '',
      geometryType:
          geometryTypeFromName(json['geometry_type'] ?? json['geometryType']),
      formFields: formFields,
      createdAt: requireDateTime(
          json['created_at'] ?? json['createdAt'], 'created_at'),
      updatedAt: requireDateTime(
          json['updated_at'] ?? json['updatedAt'], 'updated_at'),
      isSynced: true,
      syncedAt: parseDateTime(json['synced_at'] ?? json['syncedAt']) ??
          DateTime.now(),
      createdBy: parseString(json['created_by'] ?? json['createdBy']),
      collectors: collectors is List
          ? collectors.map((e) => e.toString()).toList()
          : const [],
    );
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _snippet(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;

  /// Pesan ramah untuk respons server non-2xx (detail teknis → log).
  static String _serverErrorMessage(int status, String body) {
    final data = _decodeObject(body);
    final serverMsg = data?['message'] ?? data?['detail'] ?? data?['error'];
    if (status == 403) {
      return 'You do not have permission for this project on the server.';
    }
    if (status >= 400 && status < 500 && serverMsg != null) {
      return 'Rejected by the server: $serverMsg';
    }
    if (status >= 500) {
      return 'The server had a problem (error $status). Please try again later.';
    }
    return 'Request failed (error $status).';
  }

  /// Process form data for pull (wrapper for PhotoSyncService)
  Future<Map<String, dynamic>> processFormDataForPull(
    Map<String, dynamic> formData,
    Project? project,
  ) async {
    return await _photoSyncService.processFormDataForPull(formData, project);
  }

  /// Process form data for push (wrapper for PhotoSyncService)
  Future<Map<String, dynamic>> processFormDataForPush(
    Map<String, dynamic> formData,
    Project project,
  ) async {
    return await _photoSyncService.processFormDataForPush(formData, project);
  }

  /// Gabungkan pesan error yang identik menjadi satu baris dengan hitungan,
  /// mis. ["A","A","B"] → ["A (2×)", "B"]. Mencegah dialog jadi tembok teks.
  static List<String> groupErrors(List<String> errors) {
    final counts = <String, int>{};
    final order = <String>[];
    for (final e in errors) {
      if (!counts.containsKey(e)) order.add(e);
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return order
        .map((e) => counts[e]! > 1 ? '$e (${counts[e]}×)' : e)
        .toList();
  }

  /// Test connection to backend
  Future<bool> testConnection() async {
    try {
      // Test dengan endpoint root atau health check
      final response = await _apiService.get('/')
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 ||
             response.statusCode == 404 ||
             response.statusCode == 401; // Server responds
    } catch (_) {
      return false;
    }
  }
}

/// Pelacak watermark delta-pull: maju hanya sejauh record yang tuntas, dan
/// tertahan di record gagal paling awal (filter server inklusif → record itu
/// diambil ulang). Record gagal tanpa waktu yang bisa dibaca menahan watermark
/// sepenuhnya (lebih baik mengunduh ulang daripada kehilangan data).
class PullWatermarkTracker {
  DateTime? _maxHandled;
  DateTime? _earliestFailed;
  bool _blocked = false;
  int failedCount = 0;

  void handled(DateTime updatedAt) {
    if (_maxHandled == null || updatedAt.isAfter(_maxHandled!)) {
      _maxHandled = updatedAt;
    }
  }

  void failed(DateTime? updatedAt) {
    failedCount++;
    if (updatedAt == null) {
      _blocked = true;
      return;
    }
    if (_earliestFailed == null || updatedAt.isBefore(_earliestFailed!)) {
      _earliestFailed = updatedAt;
    }
  }

  /// Watermark baru (tak pernah mundur dari [previous]).
  DateTime? nextWatermark(DateTime? previous) {
    if (_blocked) return previous;
    DateTime? candidate = _maxHandled;
    final failedAt = _earliestFailed;
    if (failedAt != null &&
        (candidate == null || failedAt.isBefore(candidate))) {
      candidate = failedAt;
    }
    if (candidate == null) return previous;
    if (previous != null && !candidate.isAfter(previous)) return previous;
    return candidate;
  }
}

// ==================== RESULT CLASSES ====================

class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  /// True bila kegagalan karena masalah koneksi/DNS/timeout (bukan error
  /// data atau server). Dipakai untuk early-abort & pesan ramah.
  final bool isConnectionError;

  /// True bila server menolak sesi (HTTP 401) → user perlu login ulang.
  final bool isAuthError;

  SyncResult({
    required this.success,
    required this.message,
    this.data,
    this.isConnectionError = false,
    this.isAuthError = false,
  });
}

class BatchSyncResult {
  final int total;
  final int successCount;
  final int failCount;
  final List<String> errors;

  /// True bila sync dihentikan karena koneksi/server tidak terjangkau.
  final bool abortedDueToConnection;

  /// True bila sync dihentikan karena sesi login kedaluwarsa (401).
  final bool abortedDueToAuth;

  /// True bila project gagal di-upload (data project tak dikirim).
  final bool projectFailed;

  /// Record yang belum ter-upload (gagal atau tak sempat) → "Retry failed".
  final List<String> failedIds;

  BatchSyncResult({
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.errors,
    this.abortedDueToConnection = false,
    this.abortedDueToAuth = false,
    this.projectFailed = false,
    this.failedIds = const [],
  });

  bool get hasErrors => failCount > 0;
  bool get allSuccess => successCount == total;

  String get summary {
    if (total == 0) return 'Everything is already synced';
    if (allSuccess) {
      return 'All $total records synced successfully';
    } else if (successCount > 0) {
      return '$successCount of $total records synced. $failCount failed.';
    } else {
      return 'No records could be synced';
    }
  }
}

class FullSyncResult {
  final int projectsTotal;
  final int projectsSuccess;
  final int projectsFail;
  final int geoDataTotal;
  final int geoDataSuccess;
  final int geoDataFail;
  final List<String> errors;

  /// True bila sync dihentikan karena koneksi/server tidak terjangkau.
  final bool abortedDueToConnection;

  /// True bila sync dihentikan karena sesi login kedaluwarsa (401).
  final bool abortedDueToAuth;

  FullSyncResult({
    required this.projectsTotal,
    required this.projectsSuccess,
    required this.projectsFail,
    required this.geoDataTotal,
    required this.geoDataSuccess,
    required this.geoDataFail,
    required this.errors,
    this.abortedDueToConnection = false,
    this.abortedDueToAuth = false,
  });

  bool get hasErrors => projectsFail > 0 || geoDataFail > 0 || errors.isNotEmpty;
  bool get allSuccess => projectsSuccess == projectsTotal && geoDataSuccess == geoDataTotal;

  String get summary {
    final List<String> parts = [];

    if (projectsTotal > 0) {
      parts.add('Projects: $projectsSuccess/$projectsTotal synced');
    }

    if (geoDataTotal > 0) {
      parts.add('Data: $geoDataSuccess/$geoDataTotal synced');
    }

    if (parts.isEmpty) {
      return 'No data to sync';
    }

    return parts.join(', ');
  }
}

class TwoWaySyncResult {
  final bool success;
  final FullSyncResult uploadResult;
  final int projectsDownloaded;
  final int geoDataDownloaded;
  final String message;

  TwoWaySyncResult({
    required this.success,
    required this.uploadResult,
    required this.projectsDownloaded,
    required this.geoDataDownloaded,
    required this.message,
  });

  String get summary {
    final List<String> parts = [];

    // Upload summary
    if (uploadResult.projectsTotal > 0 || uploadResult.geoDataTotal > 0) {
      parts.add('Uploaded: ${uploadResult.summary}');
    }

    // Download summary
    if (projectsDownloaded > 0 || geoDataDownloaded > 0) {
      parts.add('Downloaded: $projectsDownloaded projects, $geoDataDownloaded data');
    }

    if (parts.isEmpty) {
      return 'Already in sync';
    }

    return parts.join(' | ');
  }
}
