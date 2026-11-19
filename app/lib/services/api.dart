import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models.dart';

/// Thin wrapper around Firebase: Firestore paths + Cloud Function calls.
class Api {
  Api._();
  static final instance = Api._();

  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
  final _storage = FirebaseStorage.instance;

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data, {Duration? timeout}) async {
    try {
      final res = await _fn
          .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout ?? const Duration(minutes: 5)))
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      throw ApiException(e.message ?? 'Something went wrong (${e.code}).');
    }
  }

  // ---- user / workspace ----
  Stream<String?> defaultWorkspaceId() =>
      _db.doc('users/$uid').snapshots().map((s) => s.data()?['defaultWorkspaceId'] as String?);

  Future<({String workspaceId, String brandId})> createWorkspace(
      {required String workspaceName, required String brandName, required String industry}) async {
    final r = await _call('createWorkspace',
        {'workspaceName': workspaceName, 'brandName': brandName, 'industry': industry});
    return (workspaceId: r['workspaceId'] as String, brandId: r['brandId'] as String);
  }

  Future<String> createBrand(String workspaceId, {required String name, required String industry}) async {
    final r = await _call('createBrand', {'workspaceId': workspaceId, 'name': name, 'industry': industry});
    return r['brandId'] as String;
  }

  Stream<Map<String, dynamic>?> workspace(String wid) => _db.doc('workspaces/$wid').snapshots().map((s) => s.data());

  Stream<Map<String, dynamic>?> usageThisMonth(String wid) {
    final month = DateTime.now().toUtc().toIso8601String().substring(0, 7);
    return _db.doc('workspaces/$wid/usage/$month').snapshots().map((s) => s.data());
  }

  // ---- brands ----
  Stream<List<Brand>> brands(String wid) => _db
      .collection('workspaces/$wid/brands')
      .orderBy('createdAt')
      .snapshots()
      .map((q) => q.docs.map((d) => Brand.fromDoc(d.id, d.data())).toList());

  Stream<Brand?> brand(String wid, String bid) => _db
      .doc('workspaces/$wid/brands/$bid')
      .snapshots()
      .map((s) => s.exists ? Brand.fromDoc(s.id, s.data()!) : null);

  Future<void> updateBrand(String wid, String bid, Map<String, dynamic> fields) =>
      _db.doc('workspaces/$wid/brands/$bid').update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<String> uploadLogo(String wid, String bid, Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'jpg' ? 'jpeg' : extension.toLowerCase();
    final path = 'workspaces/$wid/brands/$bid/logo.$ext';
    await _storage.ref(path).putData(bytes, SettableMetadata(contentType: 'image/$ext'));
    await updateBrand(wid, bid, {'logoPath': path});
    return path;
  }

  Future<({List<String> palette, BrandColors suggested})> extractBrandColors(String wid, String bid) async {
    final r = await _call('extractBrandColors', {'workspaceId': wid, 'brandId': bid});
    return (
      palette: (r['palette'] as List).map((e) => (e as Map)['hex'] as String).toList(),
      suggested: BrandColors.fromMap(Map<String, dynamic>.from(r['suggested'] as Map)),
    );
  }

  Future<String> downloadUrl(String path) => _storage.ref(path).getDownloadURL();
  Future<Uint8List?> downloadBytes(String path) => _storage.ref(path).getData(15 * 1024 * 1024);

  // ---- ideas & posts ----
  Future<({String ideaSetId, List<Idea> ideas})> generateIdeas(String wid, String bid,
      {required String topic, required Platform platform, int count = 6}) async {
    final r = await _call('generateIdeas',
        {'workspaceId': wid, 'brandId': bid, 'topic': topic, 'platform': platform.name, 'count': count});
    return (
      ideaSetId: r['ideaSetId'] as String,
      ideas: (r['ideas'] as List).map((e) => Idea.fromMap(e as Map)).toList(),
    );
  }

  Future<String> generatePost(String wid, String bid,
      {required String ideaSetId, required int ideaIndex, String? format, String layout = 'band', String? headline}) async {
    final r = await _call('generatePost', {
      'workspaceId': wid,
      'brandId': bid,
      'ideaSetId': ideaSetId,
      'ideaIndex': ideaIndex,
      'layout': layout,
      'format': ?format,
      if (headline != null && headline.isNotEmpty) 'headline': headline,
    });
    return r['postId'] as String;
  }

  Future<void> relayoutPost(String wid, String bid, String postId, {String? layout, String? headline, String? subline}) =>
      _call('relayoutPost', {
        'workspaceId': wid,
        'brandId': bid,
        'postId': postId,
        'layout': ?layout,
        'headline': ?headline,
        'subline': ?subline,
      }, timeout: const Duration(minutes: 1));

  Stream<List<Post>> posts(String wid, String bid) => _db
      .collection('workspaces/$wid/brands/$bid/posts')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((q) => q.docs.map((d) => Post.fromDoc(d.id, d.data())).toList());

  Stream<Post?> post(String wid, String bid, String pid) => _db
      .doc('workspaces/$wid/brands/$bid/posts/$pid')
      .snapshots()
      .map((s) => s.exists ? Post.fromDoc(s.id, s.data()!) : null);

  Future<void> deletePost(String wid, String bid, String pid) =>
      _db.doc('workspaces/$wid/brands/$bid/posts/$pid').delete();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
