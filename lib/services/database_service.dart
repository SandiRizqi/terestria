import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/project_model.dart';
import '../models/geo_data_model.dart';
import '../models/form_field_model.dart';
import '../models/notification_model.dart';
import '../utils/app_logger.dart';
import 'tracking/session_repository.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static const int _databaseVersion = 5;

  /// Versi skema DB (dicantumkan di info log diagnostik).
  static const int schemaVersion = _databaseVersion;
  static const String _databaseName = 'geoform.db';

  /// Nama berkas DB utama (reset logout menghapus `geoform.db*`).
  static const String databaseName = _databaseName;

  /// Tutup koneksi (reset logout) — akses berikutnya membuka/membuat DB baru.
  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Projects Table
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        geometryType TEXT NOT NULL,
        formFields TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        isSynced INTEGER DEFAULT 0,
        syncedAt INTEGER,
        createdBy TEXT,
        collectors TEXT DEFAULT '[]'
      )
    ''');

    // GeoData Table
    await db.execute('''
      CREATE TABLE geo_data (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL,
        formData TEXT NOT NULL,
        points TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        isSynced INTEGER DEFAULT 0,
        syncedAt INTEGER,
        collectedBy TEXT NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('''
      CREATE INDEX idx_geo_data_projectId ON geo_data(projectId)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_geo_data_createdAt ON geo_data(createdAt)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_geo_data_isSynced ON geo_data(isSynced)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_projects_isSynced ON projects(isSynced)
    ''');

    // Notifications Table
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        data TEXT,
        receivedAt INTEGER NOT NULL,
        isRead INTEGER DEFAULT 0
      )
    ''');

    // Create index for notifications
    await db.execute('''
      CREATE INDEX idx_notifications_receivedAt ON notifications(receivedAt)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_notifications_isRead ON notifications(isRead)
    ''');

    // Tracking sessions (multi-project concurrent tracking)
    await _createTrackingTables(db);
  }

  /// Tabel persistensi sesi tracking (recovery setelah crash/kill). Idempoten
  /// (IF NOT EXISTS) agar aman dipanggil di _onCreate maupun _onUpgrade.
  Future<void> _createTrackingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tracking_sessions (
        projectId TEXT PRIMARY KEY,
        projectJson TEXT NOT NULL,
        startedAt INTEGER NOT NULL,
        paused INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL,
        provider TEXT NOT NULL DEFAULT 'phone'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tracking_session_points (
        projectId TEXT NOT NULL,
        seq INTEGER NOT NULL,
        point TEXT NOT NULL,
        PRIMARY KEY (projectId, seq)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tsp_project_seq
        ON tracking_session_points(projectId, seq)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
    if (oldVersion < 2) {
      // Add notifications table
      await db.execute('''
        CREATE TABLE notifications (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          data TEXT,
          receivedAt INTEGER NOT NULL,
          isRead INTEGER DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_notifications_receivedAt ON notifications(receivedAt)
      ''');

      await db.execute('''
        CREATE INDEX idx_notifications_isRead ON notifications(isRead)
      ''');
    }

    if (oldVersion < 3) {
      // Add collectors column to existing projects table
      await db.execute('''
        ALTER TABLE projects ADD COLUMN collectors TEXT DEFAULT '[]'
      ''');
    }

    if (oldVersion < 4) {
      // Tabel persistensi sesi tracking (multi-project concurrent tracking)
      await _createTrackingTables(db);
    }

    if (oldVersion < 5) {
      // Sumber GPS per sesi (phone/emlid). Tabel dari v<4 sudah dibuat dengan
      // kolom ini di atas → cek dulu agar ALTER tak gagal (idempoten).
      final info = await db.rawQuery('PRAGMA table_info(tracking_sessions)');
      if (SessionRepository.needsProviderColumn(info)) {
        await db.execute(
            "ALTER TABLE tracking_sessions ADD COLUMN provider TEXT NOT NULL DEFAULT 'phone'");
      }
    }
  }

  // ==================== PROJECT OPERATIONS ====================

  Future<void> saveProject(Project project) async {
    final db = await database;
    
    final projectMap = {
      'id': project.id,
      'name': project.name,
      'description': project.description,
      'geometryType': project.geometryType.toString().split('.').last,
      'formFields': jsonEncode(project.formFields.map((f) => f.toJson()).toList()),
      'createdAt': project.createdAt.millisecondsSinceEpoch,
      'updatedAt': project.updatedAt.millisecondsSinceEpoch,
      'isSynced': project.isSynced ? 1 : 0,
      'syncedAt': project.syncedAt?.millisecondsSinceEpoch,
      'createdBy': project.createdBy,
      'collectors': jsonEncode(project.collectors),
    };

    await db.insert(
      'projects',
      projectMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Project>> loadProjects() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'projects',
      orderBy: 'updatedAt DESC',
    );

    return _mapRows(maps, _projectFromMap, 'project');
  }

  Future<Project?> getProjectById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return _projectFromMap(maps.first);
  }

  Future<void> deleteProject(String projectId) async {
    final db = await database;
    
    // Delete project (CASCADE will delete related geo_data)
    await db.delete(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
    );
    
    // Manually delete geo_data (in case CASCADE doesn't work on some devices)
    await db.delete(
      'geo_data',
      where: 'projectId = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateProjectSyncStatus(String projectId, bool isSynced, {DateTime? syncedAt}) async {
    final db = await database;
    await db.update(
      'projects',
      {
        'isSynced': isSynced ? 1 : 0,
        'syncedAt': (syncedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<List<Project>> getUnsyncedProjects() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'projects',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'updatedAt DESC',
    );

    return _mapRows(maps, _projectFromMap, 'project');
  }

  Future<int> getUnsyncedProjectCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM projects WHERE isSynced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== GEO DATA OPERATIONS ====================

  Future<void> saveGeoData(GeoData geoData) async {
    final db = await database;
    await db.insert(
      'geo_data',
      geoDataToRow(geoData),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Tulis [geoData] HANYA bila record di DB masih ber-`updatedAt`
  /// [expectedUpdatedAt] (belum diedit sejak snapshot diambil). Dipakai setelah
  /// upload: edit user selama upload tidak tertimpa & tak ikut ditandai synced.
  /// Mengembalikan false bila record sudah berubah (atau terhapus).
  Future<bool> saveGeoDataIfUnchanged(
    GeoData geoData, {
    required DateTime expectedUpdatedAt,
  }) async {
    final db = await database;
    final row = geoDataToRow(geoData)..remove('id');
    final count = await db.update(
      'geo_data',
      row,
      where: 'id = ? AND updatedAt = ?',
      whereArgs: [geoData.id, expectedUpdatedAt.millisecondsSinceEpoch],
    );
    return count > 0;
  }

  /// Baris SQLite untuk [geoData]. `collectedBy` kosong disimpan sebagai ''
  /// karena kolomnya NOT NULL (skema lama) — data server boleh tanpa kolektor.
  static Map<String, Object?> geoDataToRow(GeoData geoData) => {
        'id': geoData.id,
        'projectId': geoData.projectId,
        'formData': jsonEncode(geoData.formData),
        'points': jsonEncode(geoData.points.map((p) => p.toJson()).toList()),
        'createdAt': geoData.createdAt.millisecondsSinceEpoch,
        'updatedAt': geoData.updatedAt.millisecondsSinceEpoch,
        'isSynced': geoData.isSynced ? 1 : 0,
        'syncedAt': geoData.syncedAt?.millisecondsSinceEpoch,
        'collectedBy': geoData.collectedBy ?? '',
      };

  Future<List<GeoData>> loadGeoData(String projectId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'geo_data',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'createdAt DESC',
    );

    return _mapRows(maps, _geoDataFromMap, 'geo data');
  }

  Future<GeoData?> getGeoDataById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'geo_data',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return _geoDataFromMap(maps.first);
  }

  Future<void> deleteGeoData(String geoDataId) async {
    final db = await database;
    await db.delete(
      'geo_data',
      where: 'id = ?',
      whereArgs: [geoDataId],
    );
  }

  Future<void> updateGeoDataSyncStatus(String geoDataId, bool isSynced, {DateTime? syncedAt}) async {
    final db = await database;
    await db.update(
      'geo_data',
      {
        'isSynced': isSynced ? 1 : 0,
        'syncedAt': (syncedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [geoDataId],
    );
  }

  Future<List<GeoData>> getUnsyncedGeoData({String? projectId}) async {
    final db = await database;
    
    String whereClause = 'isSynced = ?';
    List<dynamic> whereArgs = [0];
    
    if (projectId != null) {
      whereClause += ' AND projectId = ?';
      whereArgs.add(projectId);
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'geo_data',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return _mapRows(maps, _geoDataFromMap, 'geo data');
  }

  Future<List<GeoData>> getSyncedGeoData({String? projectId}) async {
    final db = await database;

    String whereClause = 'isSynced = ?';
    List<dynamic> whereArgs = [1];

    if (projectId != null) {
      whereClause += ' AND projectId = ?';
      whereArgs.add(projectId);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'geo_data',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    return _mapRows(maps, _geoDataFromMap, 'geo data');
  }

  Future<int> getGeoDataCount(String projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM geo_data WHERE projectId = ?',
      [projectId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getUnsyncedGeoDataCount({String? projectId}) async {
    final db = await database;
    
    String query = 'SELECT COUNT(*) as count FROM geo_data WHERE isSynced = ?';
    List<dynamic> args = [0];
    
    if (projectId != null) {
      query += ' AND projectId = ?';
      args.add(projectId);
    }
    
    final result = await db.rawQuery(query, args);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== EXPORT & CLEAR ====================

  Future<Map<String, dynamic>> exportProject(String projectId) async {
    final project = await getProjectById(projectId);
    final geoDataList = await loadGeoData(projectId);
    
    if (project == null) {
      throw Exception('Project not found');
    }
    
    return {
      'project': project.toJson(),
      'data': geoDataList.map((d) => d.toJson()).toList(),
    };
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('geo_data');
    await db.delete('projects');
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ==================== HELPER METHODS ====================

  /// Petakan baris → model satu per satu. Baris rusak DILEWATI dan dicatat di
  /// log (bukan menggagalkan seluruh daftar: dulu satu baris korup membuat
  /// daftar project/data kosong). Baris tetap ada di DB untuk diperiksa.
  static List<T> _mapRows<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) convert,
    String what,
  ) {
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(convert(row));
      } catch (e, st) {
        logError('Skipping unreadable $what row id=${row['id']}',
            tag: 'DB', error: e, stack: st);
      }
    }
    return out;
  }

  Project _projectFromMap(Map<String, dynamic> map) {
    final formFieldsList = jsonDecode(map['formFields']) as List;

    // Parse collectors: stored as JSON string, fallback ke empty list
    List<String> collectors = const [];
    try {
      final raw = map['collectors'];
      if (raw != null && raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          collectors = decoded.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {
      collectors = const [];
    }

    return Project(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      geometryType: geometryTypeFromName(map['geometryType']),
      formFields: formFieldsList
          .map((f) => FormFieldModel.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
      isSynced: map['isSynced'] == 1,
      syncedAt: map['syncedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['syncedAt'])
          : null,
      createdBy: map['createdBy'],
      collectors: collectors,
    );
  }

  GeoData _geoDataFromMap(Map<String, dynamic> map) {
    final formData = jsonDecode(map['formData']) as Map<String, dynamic>;
    final pointsList = jsonDecode(map['points']) as List;
    final collectedBy = map['collectedBy'] as String?;

    return GeoData(
      id: map['id'],
      projectId: map['projectId'],
      formData: formData,
      points: pointsList
          .map((p) => GeoPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
      isSynced: map['isSynced'] == 1,
      syncedAt: map['syncedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['syncedAt'])
          : null,
      collectedBy:
          (collectedBy == null || collectedBy.isEmpty) ? null : collectedBy,
    );
  }

  // ==================== NOTIFICATION OPERATIONS ====================

  Future<void> saveNotification(NotificationModel notification) async {
    final db = await database;
    
    final notificationMap = {
      'id': notification.id,
      'title': notification.title,
      'body': notification.body,
      'data': notification.data != null ? jsonEncode(notification.data) : null,
      'receivedAt': notification.receivedAt.millisecondsSinceEpoch,
      'isRead': notification.isRead ? 1 : 0,
    };

    await db.insert(
      'notifications',
      notificationMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationModel>> loadNotifications() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notifications',
      orderBy: 'receivedAt DESC',
    );

    return maps.map((map) => _notificationFromMap(map)).toList();
  }

  Future<List<NotificationModel>> loadUnreadNotifications() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notifications',
      where: 'isRead = ?',
      whereArgs: [0],
      orderBy: 'receivedAt DESC',
    );

    return maps.map((map) => _notificationFromMap(map)).toList();
  }

  Future<int> getUnreadNotificationCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notifications WHERE isRead = ?',
      [0],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final db = await database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
  }

  Future<void> markAllNotificationsAsRead() async {
    final db = await database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'isRead = ?',
      whereArgs: [0],
    );
  }

  Future<void> deleteNotification(String notificationId) async {
    final db = await database;
    await db.delete(
      'notifications',
      where: 'id = ?',
      whereArgs: [notificationId],
    );
  }

  Future<void> deleteAllNotifications() async {
    final db = await database;
    await db.delete('notifications');
  }

  NotificationModel _notificationFromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'],
      title: map['title'],
      body: map['body'],
      data: map['data'] != null ? jsonDecode(map['data']) as Map<String, dynamic> : null,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(map['receivedAt']),
      isRead: map['isRead'] == 1,
    );
  }
}
