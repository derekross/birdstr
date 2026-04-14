import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches bird info (summary + image) from Wikipedia's REST API.
///
/// Uses the Wikipedia API v1 summary endpoint which returns
/// a short extract and a thumbnail — no API key needed.
class WikipediaService {
  WikipediaService._();
  static final instance = WikipediaService._();

  /// Cache to avoid re-fetching the same species.
  final _cache = <String, BirdWikiInfo?>{};

  /// Fetch Wikipedia info for a bird by its common name.
  /// Falls back to scientific name if the common name has no article.
  Future<BirdWikiInfo?> fetchBirdInfo({
    required String commonName,
    required String scientificName,
  }) async {
    // Check cache.
    final cacheKey = scientificName.toLowerCase();
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    // Try common name first (usually has better articles).
    var info = await _fetchSummary(commonName);

    // Fall back to scientific name.
    if (info == null && scientificName.isNotEmpty) {
      info = await _fetchSummary(scientificName);
    }

    _cache[cacheKey] = info;
    return info;
  }

  Future<BirdWikiInfo?> _fetchSummary(String title) async {
    try {
      // Wikipedia REST API summary endpoint.
      final encoded = Uri.encodeComponent(title.replaceAll(' ', '_'));
      final url = 'https://en.wikipedia.org/api/rest_v1/page/summary/$encoded';

      final response = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Check that we got an actual article (not a disambiguation page).
      final type = data['type'] as String?;
      if (type == 'disambiguation' || type == 'not_found') return null;

      final extract = data['extract'] as String? ?? '';
      if (extract.isEmpty) return null;

      // Get thumbnail image.
      String? imageUrl;
      final thumbnail = data['thumbnail'] as Map<String, dynamic>?;
      if (thumbnail != null) {
        imageUrl = thumbnail['source'] as String?;
      }

      // Get higher-res image from originalimage if available.
      String? fullImageUrl;
      final original = data['originalimage'] as Map<String, dynamic>?;
      if (original != null) {
        fullImageUrl = original['source'] as String?;
      }

      final pageUrl =
          data['content_urls']?['desktop']?['page'] as String? ??
          'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title)}';

      return BirdWikiInfo(
        title: data['title'] as String? ?? title,
        extract: extract,
        thumbnailUrl: imageUrl,
        fullImageUrl: fullImageUrl,
        pageUrl: pageUrl,
      );
    } catch (e) {
      debugPrint('[WikipediaService] error fetching "$title": $e');
      return null;
    }
  }
}

/// Wikipedia summary data for a bird species.
class BirdWikiInfo {
  const BirdWikiInfo({
    required this.title,
    required this.extract,
    this.thumbnailUrl,
    this.fullImageUrl,
    this.pageUrl,
  });

  final String title;

  /// Short plain-text extract (1-3 paragraphs).
  final String extract;

  /// Thumbnail image URL (~320px).
  final String? thumbnailUrl;

  /// Full-resolution image URL.
  final String? fullImageUrl;

  /// Link to the full Wikipedia article.
  final String? pageUrl;
}
