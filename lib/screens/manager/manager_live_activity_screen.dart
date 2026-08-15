import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../models/receipt.dart';
import '../../models/user_account.dart';
import '../../services/account_service.dart';
import '../../utils/formatters.dart';

/// عرض مباشر (Live) لفواتير وسندات كل المندوبين من Firestore مباشرة —
/// بديل فوري لا يحتاج انتظار تصدير/استيراد JSON يدوي. يعتمد على صلاحية
/// المدير بقواعد الحماية (isManager يقرأ كل شي بغض النظر عن ownerUid).
/// يتحدّث تلقائيًا (StreamBuilder) لحظة ما يوصل أي مستند جديد من أي جهاز
/// مندوب متصل بالإنترنت — بدون أي زر "تحديث" يدوي.
class ManagerLiveActivityScreen extends StatefulWidget {
  const ManagerLiveActivityScreen({super.key});

  @override
  State<ManagerLiveActivityScreen> createState() =>
      _ManagerLiveActivityScreenState();
}

class _ManagerLiveActivityScreenState extends State<ManagerLiveActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<UserAccount> _reps = [];
  String? _selectedRepId; // null = كل المندوبين

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadReps();
  }

  Future<void> _loadReps() async {
    final users = await AccountService.instance.getUsers();
    if (!mounted) return;
    setState(() {
      _reps = users.where((u) => u.role == UserRole.rep).toList();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _queryFor(String collection) {
    final col = FirebaseFirestore.instance.collection(collection);
    Query<Map<String, dynamic>> q = col.orderBy('date', descending: true);
    if (_selectedRepId != null) {
      q = col
          .where('ownerUid', isEqualTo: _selectedRepId)
          .orderBy('date', descending: true);
    }
    return q.limit(150);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نشاط مباشر'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'الفواتير'), Tab(text: 'السندات')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String?>(
              value: _selectedRepId,
              decoration: const InputDecoration(
                labelText: 'المندوب',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('كل المندوبين')),
                for (final r in _reps)
                  DropdownMenuItem<String?>(
                    value: r.id,
                    child: Text(
                        r.displayName.isNotEmpty ? r.displayName : r.username),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedRepId = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _InvoicesStream(query: _queryFor('invoices')),
                _ReceiptsStream(query: _queryFor('receipts')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicesStream extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _InvoicesStream({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox(error: snap.error.toString());
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('ما فيه فواتير بعد'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final inv = Invoice.fromMap(docs[i].data());
            final isReturn = inv.kind == InvoiceKind.saleReturn;
            final color = isReturn ? Colors.orange : Colors.green;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(
                    isReturn ? Icons.undo : Icons.receipt_long_outlined,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(inv.customerName),
                subtitle: Text(
                    '${inv.repName} • ${Formatters.d(inv.date)} • ${isReturn ? "مرتجع" : "بيع"}'),
                trailing: Text(
                  Formatters.money(inv.grandTotal),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReceiptsStream extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _ReceiptsStream({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox(error: snap.error.toString());
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('ما فيه سندات بعد'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = Receipt.fromMap(docs[i].data());
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.withOpacity(0.12),
                  child: const Icon(Icons.payments_outlined,
                      color: Colors.indigo, size: 18),
                ),
                title: Text(r.customerName),
                subtitle: Text('${r.repName} • ${Formatters.d(r.date)}'),
                trailing: Text(
                  Formatters.money(r.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// لو Firestore يحتاج فهرس مركّب (شائع مع فلتر + ترتيب معًا)، رسالة
/// الخطأ نفسها من Firebase تجيب رابط جاهز لإنشائه بضغطة وحدة
class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});

  @override
  Widget build(BuildContext context) {
    final needsIndex =
        error.contains('index') || error.contains('FAILED_PRECONDITION');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              needsIndex
                  ? 'Firestore يحتاج فهرس (index) لهذا الفلتر — افتح الرابط اللي بنص الخطأ تحت بالمتصفح واضغط Create Index، وبعد دقيقة أو دقيقتين ارجع لهذي الشاشة'
                  : 'تعذّر تحميل البيانات من Firestore',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
