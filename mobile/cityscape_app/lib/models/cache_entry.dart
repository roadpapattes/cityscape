// lib/models/cache_entry.dart

import 'dart:typed_data';

class CacheEntry {
  final Uint8List body;
  final String? etag;
  final String? contentType;
  final int fetchedAtMs;

  CacheEntry(this.body, this.etag, this.contentType, this.fetchedAtMs);

  Map<String, dynamic> toMap() => {
    'body': body,
    'etag': etag,
    'ct': contentType,
    'at': fetchedAtMs,
  };

  static CacheEntry? fromMap(dynamic m) {
    if (m is! Map) return null;
    final body = m['body'];
    if (body is! Uint8List) return null;
    return CacheEntry(
      body,
      m['etag'] as String?,
      m['ct'] as String?,
      (m['at'] as num?)?.toInt() ?? 0,
    );
  }
}
