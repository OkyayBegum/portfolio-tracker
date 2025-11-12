
import 'package:flutter/material.dart';
import '../data/backend_api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _goldAmountController = TextEditingController();
  final TextEditingController _besController = TextEditingController();
  final TextEditingController _cashController = TextEditingController();
  final BackendApiService _backend = BackendApiService();
  final GlobalKey _bottomBarKey = GlobalKey();
  double _measuredNavBarHeight = 72.0; // fallback until measured

  // separate lists for stocks and gold
  List<_StockEntry> _stocks = [];
  List<_StockEntry> _golds = [];
  bool _isLoading = false;
  String? _error;
  double _grandTotal = 0.0;

  String _selectedGoldUnit = 'gram';
  final List<String> _goldUnits = ['gram', 'çeyrek', 'yarım', 'tam'];

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
    // measure bottom bar after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottomBar());
  }

  void _measureBottomBar() {
    try {
      final ctx = _bottomBarKey.currentContext;
      if (ctx == null) return;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final h = renderBox.size.height;
      if (h > 0 && h != _measuredNavBarHeight) {
        setState(() {
          _measuredNavBarHeight = h;
        });
      }
    } catch (_) {
      // ignore measurement errors
    }
    // re-measure on next frame to catch keyboard show/hide changes
    WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _amountController.dispose();
    _goldAmountController.dispose();
    _besController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _loadPortfolio() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
  final items = await _backend.getPortfolio();
  if (!mounted) return;
      final List<_StockEntry> stocks = [];
      final List<_StockEntry> golds = [];
      double besVal = 0.0;
      double cashVal = 0.0;

      for (final it in items) {
        final sym = (it['symbol'] ?? '').toString();
        final lots = (it['lots'] is num) ? (it['lots'] as num).toDouble() : double.tryParse(it['lots'].toString()) ?? 0.0;
        final price = (it['price'] is num) ? (it['price'] as num).toDouble() : double.tryParse(it['price'].toString()) ?? 0.0;

        if (sym == 'BES') {
          besVal = price;
        } else if (sym == 'CASH') {
          cashVal = price;
        } else if (['GRAMALTIN', 'CEYREKALTIN', 'YARIMALTIN', 'TAMALTIN'].contains(sym) || sym.startsWith('ALTIN-')) {
          golds.add(_StockEntry(symbol: sym, amount: lots, price: price));
        } else {
          stocks.add(_StockEntry(symbol: sym, amount: lots, price: price));
        }
      }

      setState(() {
        _stocks = stocks;
        _golds = golds;
        _besController.text = besVal == 0.0 ? '' : besVal.toStringAsFixed(2);
        _cashController.text = cashVal == 0.0 ? '' : cashVal.toStringAsFixed(2);
      });
      _calculateGrandTotal();
    } catch (e) {
      setState(() {
        _error = 'Yükleme hatası: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addStock() async {
    final symbol = _symbolController.text.trim().toUpperCase();
    final lotsInt = int.tryParse(_amountController.text) ?? 1;
    if (symbol.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
  final created = await _backend.addItem(symbol, lotsInt);
  if (!mounted) return;
      final s = _StockEntry(
        symbol: created['symbol'].toString(),
        amount: (created['lots'] is num) ? (created['lots'] as num).toDouble() : double.tryParse(created['lots'].toString()) ?? lotsInt.toDouble(),
        price: (created['price'] is num) ? (created['price'] as num).toDouble() : double.tryParse(created['price'].toString()) ?? 0.0,
      );
      setState(() {
        _stocks.insert(0, s);
        _symbolController.clear();
        _amountController.clear();
      });
      _calculateGrandTotal();
    } catch (e) {
      setState(() => _error = 'Ekleme hatası: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error ?? 'Hata')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addGold() async {
    final amt = double.tryParse(_goldAmountController.text.replaceAll(',', '.')) ?? 0.0;
    if (amt <= 0) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
  final created = await _backend.addGold(_selectedGoldUnit, amt);
  if (!mounted) return;
      final g = _StockEntry(
        symbol: created['symbol'].toString(),
        amount: (created['lots'] is num) ? (created['lots'] as num).toDouble() : double.tryParse(created['lots'].toString()) ?? amt,
        price: (created['price'] is num) ? (created['price'] as num).toDouble() : double.tryParse(created['price'].toString()) ?? 0.0,
      );
      setState(() {
        _golds.insert(0, g);
        _goldAmountController.clear();
      });
      _calculateGrandTotal();
    } catch (e) {
      setState(() => _error = 'Altın ekleme hatası: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error ?? 'Hata')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateAmount(int index, String value) {
    final val = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    setState(() {
      _stocks[index] = _stocks[index].copyWith(amount: val);
    });
    _calculateGrandTotal();
  }

  Future<void> _deleteStock(int index) async {
    final sym = _stocks[index].symbol;
    try {
      await _backend.deleteItem(sym);
      if (!mounted) return;
      setState(() {
        _stocks.removeAt(index);
      });
      _calculateGrandTotal();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: ${e.toString()}')));
    }
  }

  Future<void> _deleteGold(int index) async {
    final sym = _golds[index].symbol;
    try {
      await _backend.deleteItem(sym);
      if (!mounted) return;
      setState(() {
        _golds.removeAt(index);
      });
      _calculateGrandTotal();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: ${e.toString()}')));
    }
  }

  void _calculateGrandTotal() {
    double total = 0.0;
    for (final s in _stocks) {
      total += s.price * s.amount;
    }
    for (final g in _golds) {
      total += g.price * g.amount;
    }
    final bes = double.tryParse(_besController.text.replaceAll(',', '.')) ?? 0.0;
    final cash = double.tryParse(_cashController.text.replaceAll(',', '.')) ?? 0.0;
    total += bes + cash;
    setState(() {
      _grandTotal = total;
    });
  }

  Future<void> _saveOtherKey(String key, TextEditingController ctrl) async {
    final val = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final updated = await _backend.updateOther({key: val});
      if (!mounted) return;
      // update controllers to reflect saved (use two decimals)
      setState(() {
        ctrl.text = (updated[key] ?? val).toStringAsFixed(2);
        _isLoading = false;
      });
      // reload portfolio so BES/CASH entries (saved into portfolio.json) are visible and totals update
      await _loadPortfolio();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kaydedildi')));
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Kaydetme hatası: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error ?? 'Hata')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // compute dynamic bottom padding so body content never collides with
    // the bottom navigation bar or the on-screen keyboard. This prevents
    // "Bottom overflowed by X pixels" errors on small screens.
      // Simplified compact layout: smaller fonts, denser rows and normal resize
      // behavior. This avoids complex manual sizing and guarantees fit on small screens.
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottomBar());
      return Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('Portfolio Dashboard')),
        body: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 12.0,
            right: 12.0,
            top: 12.0,
            // ensure content can scroll above bottom bar and keyboard
            bottom: _measuredNavBarHeight + 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 6),
              const Text('Bist Portföyüm', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _symbolController,
                              decoration: const InputDecoration(labelText: 'Stock Symbol', isDense: true),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Amt', isDense: true),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(onPressed: _isLoading ? null : _addStock, child: const Text('Add', style: TextStyle(fontSize: 12))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _stocks.length,
                        itemBuilder: (context, index) {
                          final entry = _stocks[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                title: Row(
                                  children: [
                                    Text(entry.symbol, style: const TextStyle(fontSize: 13)),
                                    const Spacer(),
                                    Text('₺${entry.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    const Text('Amt', style: TextStyle(fontSize: 12)),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 64,
                                      child: TextField(
                                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                                        controller: TextEditingController(text: entry.amount.toString()),
                                        onChanged: (v) => _updateAmount(index, v),
                                        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _deleteStock(index)),
                              ),
                            );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Altın Portföyüm', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _goldAmountController,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Adet / Ağırlık', isDense: true),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: DropdownButtonFormField<String>(
                              value: _selectedGoldUnit,
                              items: _goldUnits.map((u) => DropdownMenuItem(value: u, child: Text(u, style: TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _selectedGoldUnit = v);
                              },
                              decoration: const InputDecoration(labelText: 'Birim', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(onPressed: _isLoading ? null : _addGold, child: const Text('Ekle', style: TextStyle(fontSize: 12))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_golds.isEmpty)
                        const Text('Altın portföyünüz boş', style: TextStyle(fontSize: 12))
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _golds.length,
                          itemBuilder: (context, gindex) {
                            final g = _golds[gindex];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                title: Row(
                                  children: [
                                    Text(g.symbol, style: const TextStyle(fontSize: 13)),
                                    const Spacer(),
                                    Text('₺${g.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    const Text('Amt', style: TextStyle(fontSize: 12)),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 64,
                                      child: TextField(
                                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                                        controller: TextEditingController(text: g.amount.toString()),
                                        onChanged: (v) {
                                          final amt = double.tryParse(v) ?? 0.0;
                                          setState(() => _golds[gindex] = _golds[gindex].copyWith(amount: amt));
                                          _calculateGrandTotal();
                                        },
                                        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _deleteGold(gindex)),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Diğer Portföyüm', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const SizedBox(width: 84, child: Text('BES', style: TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _besController,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'TL', isDense: true),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(onPressed: _isLoading ? null : () => _saveOtherKey('BES', _besController), child: const Text('Kaydet', style: TextStyle(fontSize: 12))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 84, child: Text('Cash', style: TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cashController,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'TL', isDense: true),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(onPressed: _isLoading ? null : () => _saveOtherKey('CASH', _cashController), child: const Text('Kaydet', style: TextStyle(fontSize: 12))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Container(
            key: _bottomBarKey,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                FittedBox(fit: BoxFit.scaleDown, child: Text('₺${formatTurkishCurrency(_grandTotal)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // format number using dot as thousands separator and comma as decimal separator
  String formatTurkishCurrency(double v) {
    final negative = v < 0;
    var val = v.abs();
    var ip = val.floor();
    var frac = ((val - ip) * 100).round();
    if (frac == 100) {
      ip += 1;
      frac = 0;
    }
    var intStr = ip.toString();
    final len = intStr.length;
    final first = (len % 3 == 0) ? 3 : (len % 3);
    final sb = StringBuffer();
    sb.write(intStr.substring(0, first));
    for (var i = first; i < len; i += 3) {
      sb.write('.');
      sb.write(intStr.substring(i, i + 3));
    }
    final fracStr = frac.toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$sb,$fracStr';
  }
}

class _StockEntry {
  final String symbol;
  final double amount;
  final double price;

  _StockEntry({required this.symbol, required this.amount, required this.price});

  _StockEntry copyWith({String? symbol, double? amount, double? price}) {
    return _StockEntry(symbol: symbol ?? this.symbol, amount: amount ?? this.amount, price: price ?? this.price);
  }
}

