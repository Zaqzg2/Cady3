import 'package:flutter/material.dart';

/// أزرار +/- لضبط الكمية مع إمكانية إدخالها رقميًا مباشرة
class QuantitySelector extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;
  final int min;

  const QuantitySelector({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.min = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundBtn(Icons.remove, () {
          if (quantity > min) onChanged(quantity - 1);
        }),
        SizedBox(
          width: 44,
          child: TextField(
            key: ValueKey(quantity),
            controller: TextEditingController(text: '$quantity'),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= min) onChanged(n);
            },
          ),
        ),
        _roundBtn(Icons.add, () => onChanged(quantity + 1)),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.grey.shade200,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
