import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

/// صندوق الصادر والوارد الحقيقي: كل ملف صُدِّر أو استُقبل سابقًا محفوظ
/// هنا محليًا وقابل للتصفّح — بدل ما يتذكّر التطبيق آخر عملية فقط.
/// المشاركة الفعلية للملف تبقى عبر واجهة النظام (واتساب/بلوتوث/بريد)،
/// لأن هذا هو المتاح على أندرويد لنقل ملف بين جهازين؛ الفرق أن تاريخ كل
/// ما أُرسل أو استُقبل صار مرئيًا ومتاحًا داخل التطبيق دائمًا
class SyncOutboxInboxScreen extends StatefulWidget {
  const SyncOutboxInboxScreen({super.key});

  @override
  State<SyncOutboxInboxScreen> createState() => _SyncOutboxInboxScreenState();
}

class _SyncOutboxInboxScreenState extends State<SyncOutboxInboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<OutboxRecord>> _outboxFuture;
  late Future<List<InboxRecord>> _inboxFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    final app = context.read<AppProvider>();
    setState(() {
      _outboxFuture = app.listSyncOutbox();
      _inboxFuture = app.listSyncInbox();
    });
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'اليوم $time';
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
    if (wasYesterday) return 'أمس $time';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} $time';
  }

  Future<void> _reShare(OutboxRecord r) async {
    await context.read<AppProvider>().reShareOutboxRecord(r);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('فُتحت واجهة المشاركة')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصادر والوارد'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'صادر'),
            Tab(text: 'وارد'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _OutboxList(future: _outboxFuture, onRefresh: _refresh, onReShare: _reShare, formatDate: _formatDate),
          _InboxList(future: _inboxFuture, onRefresh: _refresh, formatDate: _formatDate),
        ],
      ),
    );
  }
}

class _OutboxList extends StatelessWidget {
  final Future<List<OutboxRecord>> future;
  final VoidCallback onRefresh;
  final void Function(OutboxRecord) onReShare;
  final String Function(DateTime) formatDate;

  const _OutboxList({
    required this.future,
    required this.onRefresh,
    required this.onReShare,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        onRefresh();
      },
      child: FutureBuilder<List<OutboxRecord>>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snap.data!;
          if (records.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('لا توجد عمليات تصدير سابقة بعد')),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, i) {
              final r = records[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Slidable(
                  key: ValueKey(r.id),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.32,
                    children: [
                      SlidableAction(
                        onPressed: (_) => onReShare(r),
                        backgroundColor: AppTheme.syncSuccess,
                        foregroundColor: Colors.white,
                        icon: Icons.share_outlined,
                        label: 'إعادة إرسال',
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ],
                  ),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.syncSuccessSoft,
                        child: Icon(Icons.upload_outlined, color: AppTheme.syncSuccess, size: 20),
                      ),
                      title: Text(
                        '${r.invoicesCount} فاتورة، ${r.receiptsCount} سند'
                        '${r.customersCount > 0 ? '، ${r.customersCount} عميل' : ''}'
                        '${r.productsCount > 0 ? '، ${r.productsCount} منتج' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${formatDate(r.createdAt)} · ${r.fileName}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () => onReShare(r),
                        tooltip: 'إعادة إرسال',
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  final Future<List<InboxRecord>> future;
  final VoidCallback onRefresh;
  final String Function(DateTime) formatDate;

  const _InboxList({required this.future, required this.onRefresh, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        onRefresh();
      },
      child: FutureBuilder<List<InboxRecord>>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snap.data!;
          if (records.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('لا توجد ملفات واردة عُولجت بعد')),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, i) {
              final r = records[i];
              final isAck = r.type == 'sync_ack';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isAck ? AppTheme.syncSuccessSoft : AppTheme.syncPendingSoft,
                      child: Icon(
                        isAck ? Icons.verified_outlined : Icons.inventory_2_outlined,
                        color: isAck ? AppTheme.syncSuccess : AppTheme.syncPending,
                        size: 20,
                      ),
                    ),
                    title: Text(r.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatDate(r.receivedAt)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
