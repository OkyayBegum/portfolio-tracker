import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class BackendApiService {
  final String baseUrl;

  BackendApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  static String _defaultBaseUrl() {
    // Default base for development: web -> localhost, native -> Android emulator host
    if (kIsWeb) return 'https://api.gitandroid.com';
    return 'https://api.gitandroid.com';
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

  // Add gold portfolio item. unit: gram, çeyrek, yarım, tam. amount is number of units (can be fractional for grams)
  Future<Map<String, dynamic>> addGold(String unit, double amount) async {
    final uri = Uri.parse('$baseUrl/api/add-gold');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'unit': unit, 'amount': amount}),
    );
    if (res.statusCode != 201) {
      throw Exception('addGold failed: ${res.statusCode} ${res.body}');
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

  // Get manually editable other values (BES, CASH)
  Future<Map<String, double>> getOther() async {
    final uri = Uri.parse('$baseUrl/api/other');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('getOther failed: ${res.statusCode} ${res.body}');
    }
    final Map<String, dynamic> decoded = json.decode(res.body) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  // Update one or more keys in the other map. Payload is a map like {"BES": 1234.56}
  Future<Map<String, double>> updateOther(Map<String, double> updates) async {
    final uri = Uri.parse('$baseUrl/api/other');
    final res = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(updates));
    if (res.statusCode != 200) {
      throw Exception('updateOther failed: ${res.statusCode} ${res.body}');
    }
    final Map<String, dynamic> decoded = json.decode(res.body) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  // Update a portfolio item (symbol, lots, price). Backend expects a full PortfolioItem JSON.
  Future<Map<String, dynamic>> updateItem(String symbol, double lots, double price) async {
    final uri = Uri.parse('$baseUrl/api/update');
    final payload = {'symbol': symbol, 'lots': lots, 'price': price};
    final res = await http.put(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(payload));
    if (res.statusCode != 200) {
      throw Exception('updateItem failed: ${res.statusCode} ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
