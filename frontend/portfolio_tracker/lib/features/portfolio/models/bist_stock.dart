class BistStock {
  final String symbol;
  final double price;
  final double change;

  BistStock({
    required this.symbol,
    required this.price,
    required this.change,
  });

  factory BistStock.fromJson(Map<String, dynamic> json) {
    return BistStock(
      symbol: json['symbol'],
      price: json['price'].toDouble(),
      change: json['change'].toDouble(),
    );
  }
}
