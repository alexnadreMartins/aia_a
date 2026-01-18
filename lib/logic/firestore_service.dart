import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/company_model.dart';
import '../models/project_model.dart';
import '../models/event_config.dart';
import 'metadata_helper.dart';
import 'dart:io';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  // Debug / Test Connection
  Future<String> testConnection() async {
     final db = _db;
     if (db == null) return "Firestore is NOT initialized locally.";
     
     try {
       final user = FirebaseAuth.instance.currentUser;
       if (user == null) return "Error: User NOT Logged in (FirebaseAuth is null).";

       final testId = "test_conn_${DateTime.now().millisecondsSinceEpoch}";
       // Try write
       await db.collection('debug_connection').doc(testId).set({
         'timestamp': FieldValue.serverTimestamp(),
         'msg': 'Hello from ${user.uid}'
       });
       // Try read
       final doc = await db.collection('debug_connection').doc(testId).get();
       if (!doc.exists) return "Write success but Read failed (Doc not found).";
       
       // Cleanup
       await db.collection('debug_connection').doc(testId).delete();
       
       return "Success: Database Connected & Authorized.\nUser: ${user.uid}";
     } catch (e) {
       return "Connection Failed: $e";
     }
  }

  bool _isInitialized = false;

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    try {
      if (Firebase.apps.isEmpty) {
         // This usually implies main.dart hasn't called initializeApp with options yet.
         // We can't do much here without options.
         // We assume main.dart will call it.
         // If it failed there, we stay uninitialized.
      } else {
        _isInitialized = true;
      }
    } catch (e) {
      debugPrint("FirestoreService: Firebase not initialized: $e");
    }
  }

  FirebaseFirestore? get _db {
    if (!_isInitialized && Firebase.apps.isNotEmpty) _isInitialized = true;
    if (!_isInitialized) return null;
    return FirebaseFirestore.instance;
  }

  // --- Event Config ---

  Future<void> saveEventConfig(EventConfig config) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection('config').doc('events').set(config.toJson());
    } catch (e) {
      debugPrint("Error saving event config: $e");
    }
  }

  Future<EventConfig> getEventConfig() async {
    final db = _db;
    if (db == null) return EventConfig.defaultConfig();
    try {
      final doc = await db.collection('config').doc('events').get();
      if (doc.exists && doc.data() != null) {
        return EventConfig.fromJson(doc.data()!);
      }
    } catch (e) {
      debugPrint("Error loading event config: $e");
    }
    return EventConfig.defaultConfig();
  }

  // --- Advanced Stats Generation ---

  Future<void> saveProjectStats(Project project, {Map<String, PhotoMetadata>? metadataCache}) async {
    // Force init if needed
    if (_db == null) await ensureInitialized();
    final db = _db;
    
    if (db == null) {
       debugPrint("FIREBASE ERROR: Database not initialized after attempt. Aborting save.");
       return;
    }

    try {
      debugPrint("FIREBASE: Starting Save for ${project.id}");
      
      // 1. Resolve User & Company from Active Session (Critical for Attribution)
      String company = project.company;
      String lastUser = project.lastUser;
      String userCategory = project.userCategory;
      
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
          debugPrint("Resolving User from Session: ${fbUser.email}");
          try {
             // Block and fetch real profile
             final userDoc = await db.collection('users').doc(fbUser.uid).get();
             if (userDoc.exists && userDoc.data() != null) {
                final data = userDoc.data()!;
                company = data['company'] ?? "Default";
                lastUser = data['name'] ?? fbUser.displayName ?? "Usuário";
                userCategory = data['role'] ?? "Editor";
                debugPrint("User Resolved: $lastUser ($company)");
             } else {
                // Fallback if doc missing but Auth valid
                lastUser = fbUser.displayName ?? fbUser.email ?? "Editor";
                company = "Unknown";
             }
          } catch (e) {
             debugPrint("Error fetching user profile during save: $e");
          }
      } else {
          debugPrint("WARNING: No Active Session found during save.");
          if (lastUser.isEmpty) {
             lastUser = "Editor (Offline)"; 
             company = "Default";
          }
      }
      
      final mappings = await getPhotographerMappings();
      final eventConfig = await getEventConfig();

      // 2. Extract Photo Paths (Unique)
      final Set<String> uniquePaths = {};
      for (var page in project.pages) {
         for (var photo in page.photos) {
            if (photo.path.isNotEmpty) {
               uniquePaths.add(photo.path);
            }
         }
      }
      final List<String> pathList = uniquePaths.toList();
      
      // 3. Extract Metadata (Cached + Blocking Wait)
      debugPrint("ANALYTICS: Extracting metadata for ${pathList.length} photos...");
      
      List<PhotoMetadata> metas = [];
      if (pathList.isNotEmpty) {
           // Use Cache if available
           final List<String> missingPaths = [];
           final Map<String, PhotoMetadata> solvedMetas = {};

           if (metadataCache != null) {
               for (var path in pathList) {
                   if (metadataCache.containsKey(path)) {
                       solvedMetas[path] = metadataCache[path]!;
                   } else {
                       missingPaths.add(path);
                   }
               }
           } else {
               missingPaths.addAll(pathList);
           }
           
           if (missingPaths.isNotEmpty) {
               debugPrint("ANALYTICS: Cache miss for ${missingPaths.length} photos. Fetching...");
               try {
                  final fetched = await MetadataHelper.getMetadataBatch(missingPaths);
                  for (int i=0; i<missingPaths.length; i++) {
                      solvedMetas[missingPaths[i]] = fetched[i];
                  }
               } catch (e) {
                  debugPrint("Warning: Metadata fetch failed: $e");
               }
           }
           
           // Reconstruct List in order
           metas = pathList.map((p) => solvedMetas[p] ?? PhotoMetadata()).toList();
           debugPrint("METADATA: Final Count: ${metas.length} (Cached: ${pathList.length - missingPaths.length})");

      } else {
         debugPrint("METADATA: No photos to process.");
      }

      // 4. Compute Counts & Stats
      int totalPhotos = 0;
      final cameraCounts = <String, int>{}; // Serial -> Count
      final photographerData = <String, Map<String, dynamic>>{}; // Name -> Data
      final cameraDetails = <String, Map<String, String>>{}; // Serial -> Details

      for (int i = 0; i < pathList.length; i++) {
         final path = pathList[i];
         PhotoMetadata? meta;
         if (i < metas.length) meta = metas[i];
         
         // Identify Camera
         String serial = meta?.cameraSerial ?? "";
         if (serial.isEmpty && meta?.cameraModel != null) {
              serial = "Model_${meta!.cameraModel}";
         } else if (serial.isEmpty) {
              serial = "Unknown_Device";
         }
         
         // Store Details
         if (!cameraDetails.containsKey(serial)) {
            cameraDetails[serial] = {
               'model': meta?.cameraModel ?? "Unknown",
               'artist': meta?.artist ?? "",
               'serial': serial
            };
         }
         
         // Identify Photographer Name (The logic user liked)
         String pName = "Desconhecido";
         if (mappings.containsKey(serial)) {
             pName = mappings[serial]!;
         } else {
             // Fallback Logic: "Author (Serial)"
             if (meta?.artist != null && meta!.artist!.isNotEmpty) {
                pName = "${meta!.artist} (Serial: ${meta!.cameraSerial ?? 'N/A'})"; 
             } else if (serial.startsWith("Model_")) {
                pName = meta?.cameraModel ?? "Câmera Genérica";
             } else if (!serial.startsWith("Unknown_")) {
                pName = "Câmera $serial";
             }
         }

         // Update Counts
         totalPhotos++;
         cameraCounts[serial] = (cameraCounts[serial] ?? 0) + 1;
         
         // Event Logic
         final filename = path.split(Platform.pathSeparator).last;
         String eventName = "Outros";
         int eventId = 0;
         final prefixMatch = RegExp(r'^(\d+)[_\s-]').firstMatch(filename);
         if (prefixMatch != null) {
            eventId = int.parse(prefixMatch.group(1)!);
            eventName = eventConfig.eventMap[eventId] ?? "Evento $eventId";
         }
         
         if (!photographerData.containsKey(pName)) {
             photographerData[pName] = {
                 'totalUsed': 0,
                 'events': <int>{}, 
                 'breakdown': <String, int>{},
             };
         }
         
         photographerData[pName]!['totalUsed'] = (photographerData[pName]!['totalUsed'] as int) + 1;
         (photographerData[pName]!['events'] as Set<int>).add(eventId);
         
         final breakdown = photographerData[pName]!['breakdown'] as Map<String, int>;
         breakdown[eventName] = (breakdown[eventName] ?? 0) + 1;
      }
      
      // Post-Process Stats
      final finalPhotographerStats = photographerData.map((key, value) {
         return MapEntry(key, {
            ...value,
            'events': (value['events'] as Set<int>).toList(),
         });
      });

      // 5. Save to Firestore
      final projectRef = db.collection('projects').doc(project.id);
      
      await projectRef.set({
        'name': project.name,
        'path': project.id, // Using Path as ID (Reverted)
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastUser': project.lastUser,
        'userCategory': project.userCategory,
        'company': company,
        'contractNumber': project.contractNumber,
        'totalEditingTime': project.totalEditingTime.inSeconds,
        'totalEditingTimeSeconds': project.totalEditingTime.inSeconds,
        'pageCount': project.pages.length,
        
        // Expanded Analytics Headers
        'totalPhotosUsed': totalPhotos,
        'cameraCount': cameraCounts.length,
        'totalPhotosSource': _sumValues(project.sourcePhotoCounts),
        
        // Detailed Data
        'usedPhotoCounts': cameraCounts,
        'photographerStats': finalPhotographerStats,
        'cameras': cameraDetails.map((k, v) => MapEntry(k, v)),
        
      }, SetOptions(merge: true));

      debugPrint("FIREBASE: Project Stats Saved. Photos: $totalPhotos, Cameras: ${cameraCounts.length}");

    } catch (e) {
      debugPrint("FIREBASE ERROR: Failed to save stats: $e");
    }
  }

  int _sumValues(Map<String, int> map) => map.values.fold(0, (a, b) => a + b);


      

  // --- Users ---

  Future<AiaUser?> getUser(String uid) async {
    final db = _db;
    if (db == null) return null;
    try {
      final doc = await db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return AiaUser.fromJson(doc.data()!);
      }
    } catch (e) {
      debugPrint("Error fetching user $uid: $e");
    }
    return null;
  }

  Future<void> saveUser(AiaUser user) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection('users').doc(user.id).set(user.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving user: $e");
    }
  }
  
  Future<void> deleteUser(String userId) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection('users').doc(userId).delete();
    } catch (e) {
      debugPrint("Error deleting user: $e");
    }
  }

  Future<List<AiaUser>> getUsers() async {
    final db = _db;
    if (db == null) return [];
    try {
      final snap = await db.collection('users').get();
      return snap.docs.map((d) => AiaUser.fromJson(d.data())).toList();
    } catch (e) {
      debugPrint("Error getting users: $e");
      return [];
    }
  }

  // Uses a secondary app to create a user without logging out the current admin
  Future<String?> createAuthUser(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
      // 1. Initialize a secondary app with same options
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );
      
      // 2. Create user on that app
      final cred = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(email: email, password: password);
          
      return cred.user?.uid;
    } catch (e) {
      debugPrint("Error creating auth user: $e");
      rethrow;
    } finally {
      // 3. Delete the app to free resources
      await secondaryApp?.delete();
    }
  }
  
  // --- Photographer Mappings ---
  
  // --- Companies ---

  Future<void> saveCompany(Company company) async {
    final db = _db;
    if (db == null) throw Exception("Firebase não inicializado. Verifique a configuração.");
    try {
      await db.collection('companies').doc(company.id).set(company.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving company: $e");
      rethrow;
    }
  }

  Future<void> deleteCompany(String companyId) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection('companies').doc(companyId).delete();
    } catch (e) {
      debugPrint("Error deleting company: $e");
    }
  }

  Future<List<Company>> getCompanies() async {
    final db = _db;
    if (db == null) return [];
    try {
      final snapshot = await db.collection('companies').get();
      return snapshot.docs.map((doc) => Company.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint("Error loading companies: $e");
      return [];
    }
  }
  
  // --- Mappings ---

  Future<void> saveMapping(String serial, String photographerName) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection('mappings').doc(serial).set({
        'serial': serial,
        'photographer': photographerName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error saving mapping: $e");
    }
  }

  Future<Map<String, String>> getPhotographerMappings() async {
    final db = _db;
    if (db == null) return {};
    try {
      final snap = await db.collection('mappings').get();
      final map = <String, String>{};
      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['serial'] != null && data['photographer'] != null) {
           map[data['serial']] = data['photographer'];
        }
      }
      return map;
    } catch (e) {
      debugPrint("Error getting mappings: $e");
      return {};
    }
  }

  // --- Analytics Query Helpers ---
  
  Future<List<Map<String, dynamic>>> getProjectsSince(DateTime date) async {
     final db = _db;
     if (db == null) return [];
     try {
       final snap = await db.collection('projects')
           .where('lastUpdated', isGreaterThan: date)
           .get();
       return snap.docs.map((d) => d.data()).toList();
     } catch (e) {
       return [];
     }
  }
  
  Future<List<Map<String, dynamic>>> getProjectsInRange(DateTime start, DateTime end) async {
    final db = _db;
    if (db == null) return [];
    try {
      final snapshot = await db.collection('projects')
          .where('lastUpdated', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('lastUpdated', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint("Error loading projects range: $e");
      return [];
    }
  }
}

