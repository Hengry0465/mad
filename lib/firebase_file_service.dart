import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class FirebaseFileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get the current user ID or return null if not logged in
  String? get currentUserId => _auth.currentUser?.uid;

  // Get reference to the files collection for the current user
  CollectionReference<Map<String, dynamic>> get _filesCollection {
    if (currentUserId == null) {
      throw Exception('User is not logged in');
    }
    return _firestore.collection('users').doc(currentUserId).collection('files');
  }

  // Upload a file to Firestore
  Future<String> uploadFile(File file, String fileName, {bool isPasswordProtected = false}) async {
    if (currentUserId == null) {
      throw Exception('User is not logged in');
    }

    try {
      // Read file as bytes
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;

      // For larger files, we need to split them into chunks
      // Firestore has a 1MB document size limit
      const int maxChunkSize = 500 * 1024; // 500KB per chunk
      final int totalChunks = (fileSize / maxChunkSize).ceil();

      // Create the file document first
      final fileDoc = await _filesCollection.add({
        'name': fileName,
        'size': fileSize,
        'dateAdded': FieldValue.serverTimestamp(),
        'isEncrypted': true, // We'll encrypt all files
        'isPasswordProtected': isPasswordProtected,
        'fileExtension': fileName.contains('.') ? fileName.split('.').last : '',
        'totalChunks': totalChunks,
      });

      // Upload chunks
      for (int i = 0; i < totalChunks; i++) {
        final int start = i * maxChunkSize;
        final int end = (i + 1) * maxChunkSize > fileSize ? fileSize : (i + 1) * maxChunkSize;
        final Uint8List chunkBytes = fileBytes.sublist(start, end);

        // Encrypt the chunk (simple XOR with a key for demo purposes)
        final encryptedBytes = _encryptBytes(chunkBytes, "mySecretKey123");

        // Convert to base64 for storage in Firestore
        final String base64Data = base64Encode(encryptedBytes);

        // Store the chunk
        await fileDoc.collection('chunks').doc(i.toString()).set({
          'data': base64Data,
          'index': i,
        });
      }

      return fileDoc.id;
    } catch (e) {
      print('Error uploading file: $e');
      throw Exception('Failed to upload file: $e');
    }
  }

  // Get all files for the current user
  Future<List<FirebaseFileInfo>> getFiles() async {
    if (currentUserId == null) {
      return [];
    }

    try {
      final snapshot = await _filesCollection.orderBy('dateAdded', descending: true).get();
      return snapshot.docs.map((doc) {
        final data = doc.data();

        // Parse the timestamp safely
        Timestamp? timestamp = data['dateAdded'] as Timestamp?;
        DateTime dateAdded = timestamp?.toDate() ?? DateTime.now();

        return FirebaseFileInfo(
          id: doc.id,
          name: data['name'] ?? '',
          size: data['size'] ?? 0,
          dateAdded: dateAdded,
          isEncrypted: data['isEncrypted'] ?? true,
          isPasswordProtected: data['isPasswordProtected'] ?? false,
          fileExtension: data['fileExtension'] ?? '',
          totalChunks: data['totalChunks'] ?? 1,
        );
      }).toList();
    } catch (e) {
      print('Error getting files: $e');
      return [];
    }
  }

  // Download a file from Firestore
  Future<Uint8List> downloadFile(String fileId, {String password = "mySecretKey123"}) async {
    if (currentUserId == null) {
      throw Exception('User is not logged in');
    }

    try {
      // Get file metadata
      final fileDoc = await _filesCollection.doc(fileId).get();
      final data = fileDoc.data()!;
      final int totalChunks = data['totalChunks'] ?? 1;

      // Create a buffer to hold the complete file
      final List<int> fileData = [];

      // Download each chunk
      for (int i = 0; i < totalChunks; i++) {
        final chunkDoc = await _filesCollection.doc(fileId).collection('chunks').doc(i.toString()).get();
        final chunkData = chunkDoc.data()!;

        // Decode from base64
        final Uint8List encryptedBytes = base64Decode(chunkData['data']);

        // Decrypt the chunk
        final decryptedBytes = _decryptBytes(encryptedBytes, password);

        // Add to the buffer
        fileData.addAll(decryptedBytes);
      }

      return Uint8List.fromList(fileData);
    } catch (e) {
      print('Error downloading file: $e');
      throw Exception('Failed to download file: $e');
    }
  }

  // Delete a file from Firestore
  Future<void> deleteFile(String fileId) async {
    if (currentUserId == null) {
      throw Exception('User is not logged in');
    }

    try {
      // Get the total chunks
      final fileDoc = await _filesCollection.doc(fileId).get();
      final data = fileDoc.data()!;
      final int totalChunks = data['totalChunks'] ?? 1;

      // Delete all chunks first
      for (int i = 0; i < totalChunks; i++) {
        await _filesCollection.doc(fileId).collection('chunks').doc(i.toString()).delete();
      }

      // Delete the file document
      await _filesCollection.doc(fileId).delete();
    } catch (e) {
      print('Error deleting file: $e');
      throw Exception('Failed to delete file: $e');
    }
  }

  // Simple encryption (XOR) - you should use a more secure method in production
  Uint8List _encryptBytes(Uint8List bytes, String password) {
    final List<int> keyBytes = utf8.encode(password);
    final List<int> result = List<int>.filled(bytes.length, 0);

    for (var i = 0; i < bytes.length; i++) {
      final keyByte = keyBytes[i % keyBytes.length];
      result[i] = bytes[i] ^ keyByte;
    }

    return Uint8List.fromList(result);
  }

  // Simple decryption (XOR)
  Uint8List _decryptBytes(Uint8List bytes, String password) {
    // For XOR, encryption and decryption are the same
    return _encryptBytes(bytes, password);
  }

  // Save a file to disk after downloading
  Future<String> saveFileToDisk(Uint8List fileData, String fileName) async {
    try {
      // Use path_provider to get a directory
      final directory = Directory.systemTemp;
      final filePath = '${directory.path}/$fileName';

      // Write the file
      final file = File(filePath);
      await file.writeAsBytes(fileData);

      return filePath;
    } catch (e) {
      print('Error saving file: $e');
      throw Exception('Failed to save file: $e');
    }
  }
}

// Model class for Firebase file info
class FirebaseFileInfo {
  final String id;
  final String name;
  final int size;
  final DateTime dateAdded;
  final bool isEncrypted;
  final bool isPasswordProtected;
  final String fileExtension;
  final int totalChunks;

  FirebaseFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.dateAdded,
    this.isEncrypted = true,
    this.isPasswordProtected = false,
    this.fileExtension = '',
    this.totalChunks = 1,
  });

  // Format file size
  String get formattedSize {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = this.size.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Format date
  String get formattedDate {
    return DateFormat('dd/MM/yyyy HH:mm').format(dateAdded);
  }
}