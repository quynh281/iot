import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('iot.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // ===== TABLE: sensor =====
    await db.execute('''
      CREATE TABLE sensor(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        temp REAL,
        hum REAL,
        soil1 INTEGER,
        soil2 INTEGER,
        soil3 INTEGER,
        time TEXT
      )
    ''');

    // ===== TABLE: pump_log =====
    await db.execute('''
      CREATE TABLE pump_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pump INTEGER,
        start TEXT,
        end TEXT
      )
    ''');

    // ===== TABLE: schedule =====
    await db.execute('''
      CREATE TABLE schedule(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pump INTEGER,
        hour INTEGER,
        minute INTEGER,
        duration INTEGER,
        is_enabled INTEGER DEFAULT 1
      )
    ''');

    // ===== TABLE: config =====
    await db.execute('''
      CREATE TABLE config(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        min REAL,
        max REAL,
        notify INTEGER
      )
    ''');

    // ===== TABLE: sensor_pump_map (✅ CHỈ TẠO 1 LẦN) =====
    await db.execute('''
      CREATE TABLE sensor_pump_map(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensor_id TEXT NOT NULL,
        pump INTEGER NOT NULL,
        threshold INTEGER NOT NULL
      )
    ''');

    // ===== TABLE: notification =====
    await db.execute('''
      CREATE TABLE notification(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        time TEXT
      )
    ''');

    // ===== TABLE: sensor_config =====
    await db.execute('''
      CREATE TABLE sensor_config(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        created_at TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // ✅ FIX: Kiểm tra table tồn tại trước khi tạo
    if (oldVersion < 2) {
      // Kiểm tra xem column có tồn tại không
      final columns = await db.rawQuery("PRAGMA table_info(schedule)");
      final hasIsEnabled = columns.any((col) => col['name'] == 'is_enabled');
      
      if (!hasIsEnabled) {
        await db.execute(
          'ALTER TABLE schedule ADD COLUMN is_enabled INTEGER DEFAULT 1',
        );
      }
    }

    if (oldVersion < 3) {
      // ===== Tạo sensor_config =====
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sensor_config'",
      );
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE sensor_config(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            created_at TEXT
          )
        ''');
      }

      // ===== Tạo sensor_pump_map =====
      final mapTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sensor_pump_map'",
      );
      if (mapTables.isEmpty) {
        await db.execute('''
          CREATE TABLE sensor_pump_map(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sensor_id TEXT NOT NULL,
            pump INTEGER NOT NULL,
            threshold INTEGER NOT NULL
          )
        ''');
      }
    }
  }

  // ===== DỌN DỮ LIỆU CŨ (giữ 7 ngày) =====
  Future<void> cleanupOldData() async {
    final db = await database;

    final cutoff =
        DateTime.now().subtract(const Duration(days: 7)).toIso8601String();

    await db.delete("sensor", where: "time < ?", whereArgs: [cutoff]);
    await db.delete("notification", where: "time < ?", whereArgs: [cutoff]);

    // pump_log: xóa log đã kết thúc và cũ hơn 7 ngày
    await db.delete(
      "pump_log",
      where: "end IS NOT NULL AND end < ?",
      whereArgs: [cutoff],
    );
  }
}