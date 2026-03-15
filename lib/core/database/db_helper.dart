import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'DirXplore', 'app_database.db');

    // Ensure directory exists
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        url TEXT,
        savePath TEXT,
        fileName TEXT,
        status TEXT,
        progress REAL,
        speed INTEGER,
        totalBytes INTEGER,
        downloadedBytes INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE proxies (
        id TEXT PRIMARY KEY,
        name TEXT,
        host TEXT,
        port INTEGER,
        type TEXT,
        username TEXT,
        password TEXT,
        isActive INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE proxies ADD COLUMN name TEXT');
      await db.execute('ALTER TABLE proxies ADD COLUMN username TEXT');
      await db.execute('ALTER TABLE proxies ADD COLUMN password TEXT');
    }
  }
}
