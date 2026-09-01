class InvoiceItem {
  final String productId;
  final String productName;
  final double price;
  int quantity;

  InvoiceItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.quantity = 1,
  });

  double get total => price * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> m) => InvoiceItem(
        productId: m['productId'] as String,
        productName: m['productName'] as String,
        price: (m['price'] as num).toDouble(),
        quantity: (m['quantity'] as num).toInt(),
      );
}
