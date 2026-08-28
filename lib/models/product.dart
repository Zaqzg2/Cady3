import 'sync_status.dart';

class Product {
  final String id;
  String name;
  double price;
  String unit; // وحدة القياس: قطعة/كرتون/عبوة ...
  String? imagePath;
  SyncStatus syncStatus;
  DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.unit = 'قطعة',
    this.imagePath,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'unit': unit,
        'imagePath': imagePath,
        'syncStatus': syncStatus.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        unit: m['unit'] as String? ?? 'قطعة',
        imagePath: m['imagePath'] as String?,
        syncStatus: m['syncStatus'] != null
            ? SyncStatus.values.firstWhere((s) => s.name == m['syncStatus'],
                orElse: () => SyncStatus.synced)
            : SyncStatus.synced,
        updatedAt: m['updatedAt'] != null
            ? DateTime.parse(m['updatedAt'] as String)
            : DateTime.now(),
      );
}

