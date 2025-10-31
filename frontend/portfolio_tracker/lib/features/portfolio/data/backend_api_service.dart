import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class BackendApiService {
  final String baseUrl;

  BackendApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  static String _defaultBaseUrl() {
    // Default base for development: web -> localhost, native -> Android emulator host
    if (kIsWeb) return 'http://localhost:8080';
    return 'http://10.0.2.2:8080';
  }

  // Sends symbol and lots to backend. Backend will fetch current price.
  // Returns the created item as decoded JSON (map with symbol, lots, price).
  Future<Map<String, dynamic>> addItem(String symbol, int lots) async {
    final uri = Uri.parse('$baseUrl/api/add');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'symbol': symbol, 'lots': lots}),
    );
    if (res.statusCode != 201) {
      throw Exception('addItem failed: ${res.statusCode} ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  // Fetch the entire portfolio from the backend
  Future<List<Map<String, dynamic>>> getPortfolio() async {
    final uri = Uri.parse('$baseUrl/api/portfolio');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('getPortfolio failed: ${res.statusCode} ${res.body}');
    }
    final List<dynamic> decoded = json.decode(res.body) as List<dynamic>;
    return decoded.map((e) => e as Map<String, dynamic>).toList();
  }

  // Delete an item by symbol on the backend. Backend returns 200 on success.
  Future<void> deleteItem(String symbol) async {
    final uri = Uri.parse('$baseUrl/api/delete/$symbol');
    final res = await http.delete(uri);
    if (res.statusCode != 200) {
      throw Exception('deleteItem failed: ${res.statusCode} ${res.body}');
    }
  }
}
