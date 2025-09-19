

import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/bist_stock.dart';

class BistApiService {
  Future<double?> fetchCurrentPrice(String symbol) async {
    final url =
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.IS?range=1d&interval=1d';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final result = data['chart']['result'][0]['meta'];
      return result['regularMarketPrice']?.toDouble();
    } else {
      throw Exception('Failed to fetch data');
    }
  }

  Future<List<BistStock>> fetchCurrentPrices(List<String> symbols) async {
    List<BistStock> stocks = [];
    for (final symbol in symbols) {
      try {
        final price = await fetchCurrentPrice(symbol);
        if (price != null) {
          stocks.add(BistStock(symbol: symbol, price: price, change: 0)); // Change is 0 for now
        }
      } catch (_) {
        // Optionally handle errors per symbol
      }
    }
    return stocks;
  }
}
