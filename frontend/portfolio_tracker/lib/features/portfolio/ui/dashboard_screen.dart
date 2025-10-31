import 'package:flutter/material.dart';
import '../data/backend_api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final BackendApiService _backend = BackendApiService();
  List<_StockEntry> _portfolio = [];
  bool _isLoading = false;
  String? _error;
  double? _grandTotal;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }


  Future<void> _addStock() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final symbol = _symbolController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (symbol.isEmpty || amount == 0) {
      setState(() {
        _isLoading = false;
        _error = 'Please enter a valid symbol and amount.';
      });
      return;
    }
    try {
      // Send symbol and lots to backend; backend will fetch current price.
      Map<String, dynamic> created;
      try {
        created = await _backend.addItem(symbol, amount.toInt());
      } catch (e) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to save to backend: ${e.toString()}';
        });
        return;
      }

      final price = (created['price'] as num).toDouble();
      setState(() {
        _portfolio.add(_StockEntry(symbol: symbol, amount: amount, price: price));
        _symbolController.clear();
        _amountController.clear();
        _isLoading = false;
        _calculateGrandTotal();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  // Load portfolio from backend when the screen/app starts
  Future<void> _loadPortfolio() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _backend.getPortfolio();
      final entries = list.map((m) {
        final symbol = (m['symbol'] as String?) ?? '';
        final lotsNum = m['lots'];
        final priceNum = m['price'];
        final amount = (lotsNum is num) ? lotsNum.toDouble() : double.tryParse('$lotsNum') ?? 0.0;
        final price = (priceNum is num) ? priceNum.toDouble() : double.tryParse('$priceNum') ?? 0.0;
        return _StockEntry(symbol: symbol, amount: amount, price: price);
      }).toList();
      setState(() {
        _portfolio = entries;
        _isLoading = false;
      });
      _calculateGrandTotal();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load portfolio: ${e.toString()}';
      });
    }
  }

  Future<void> _deleteStock(int index) async {
    if (index < 0 || index >= _portfolio.length) return;
    final symbol = _portfolio[index].symbol;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _backend.deleteItem(symbol);
      setState(() {
        _portfolio.removeAt(index);
        _isLoading = false;
      });
      _calculateGrandTotal();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to delete: ${e.toString()}';
      });
      // give the user immediate feedback
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
    }
  }

  void _updateAmount(int index, String value) {
    final amount = double.tryParse(value) ?? 0;
    setState(() {
      _portfolio[index] = _portfolio[index].copyWith(amount: amount);
      _calculateGrandTotal();
    });
  }

  void _calculateGrandTotal() {
    _grandTotal = _portfolio.fold<double>(0, (sum, entry) => sum + (entry.price * entry.amount));
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _symbolController,
                    decoration: const InputDecoration(
                      labelText: 'Stock Symbol',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _addStock,
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.builder(
                itemCount: _portfolio.length,
                itemBuilder: (context, index) {
                  final entry = _portfolio[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        dense: true,
                        minVerticalPadding: 0,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        title: Text(entry.symbol, style: const TextStyle(fontSize: 14)),
                        subtitle: Row(
                          children: [
                            const Text('Amount:', style: TextStyle(fontSize: 12)),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                controller: TextEditingController(text: entry.amount.toString()),
                                onChanged: (value) => _updateAmount(index, value),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('₺${entry.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                          onPressed: () => _deleteStock(index),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Grand Total: ₺${(_grandTotal ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockEntry {
  final String symbol;
  final double amount;
  final double price;

  _StockEntry({required this.symbol, required this.amount, required this.price});


  _StockEntry copyWith({String? symbol, double? amount, double? price}) {
    return _StockEntry(
      symbol: symbol ?? this.symbol,
      amount: amount ?? this.amount,
      price: price ?? this.price,
    );
  }
}
