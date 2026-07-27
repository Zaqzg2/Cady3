class Customer {
  final String id;
  String name;
  String phone;
  String address;
  double openingBalance; // رصيد افتتاحي (مديونية سابقة)

  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.openingBalance = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
      );
}
