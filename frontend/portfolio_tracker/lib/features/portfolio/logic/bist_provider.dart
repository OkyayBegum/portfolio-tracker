import 'package:flutter/material.dart';
import '../models/bist_stock.dart';
import '../data/bist_api_service.dart';

class BistApiProvider extends ChangeNotifier {
  final BistApiService _apiService = BistApiService();
  List<BistStock> _stocks = [];
  bool _isLoading = false;
  String? _error;

  List<BistStock> get stocks => _stocks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchBistData(List<String> symbols) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stocks = await _apiService.fetchCurrentPrices(symbols);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
