class Product {
  final String id;
  String name;
  double price;
  String unit; // وحدة القياس: قطعة/كرتون/عبوة ...
  String? imagePath;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.unit = 'قطعة',
    this.imagePath,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'unit': unit,
        'imagePath': imagePath,
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        unit: m['unit'] as String? ?? 'قطعة',
        imagePath: m['imagePath'] as String?,
      );
}
