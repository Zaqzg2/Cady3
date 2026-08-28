import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';
import '../../models/invoice.dart';
import '../../models/receipt.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'manager_live_activity_screen.dart';

/// ملخّص نشاط مندوب واحد — كله مبني من مستندات Firestore الحقيقية التي
/// كتبها جهاز المندوب فعليًا (نفس مصدر شاشة "نشاط مباشر"). لا يعكس هذا
/// بيانات لم تصل للسحابة بعد؛ فرق مهم عن "كل ما فعله المندوب فعليًا"
class _RepActivity {
  final int invoicesToday;
  final int returnsToday;
  final int receiptsToday;
  final double salesToday;
  final DateTime? lastActivityAt;

  const _RepActivity({
    required this.invoicesToday,
    required this.returnsToday,
    required this.receiptsToday,
    required this.salesToday,
    required this.lastActivityAt,
  });

  static const empty = _RepActivity(
      invoicesToday: 0, returnsToday: 0, receiptsToday: 0, salesToday: 0, lastActivityAt: null);
}

/// المندوبون: نظرة حقيقية على نشاط كل مندوب عبر فايربيس (فواتير/سندات
/// اليوم، آخر عملية وصلت)، مع إبقاء إدارة الحسابات (إضافة/تعديل/إيقاف)
/// بضغطة من نفس البطاقة. لا تدّعي هذه الشاشة معرفة اتصال جهاز المندوب
/// الحي أو عدد عملياته المعلّقة محليًا — هذا غير معروف لجهاز المدير
/// أصلًا حتى يصل ملف أو تُكتب بيانات على فايربيس فعليًا
class ManagerUsersScreen extends StatefulWidget {
  const ManagerUsersScreen({super.key});

  @override
  State<ManagerUsersScreen> createState() => _ManagerUsersScreenState();
}

class _ManagerUsersScreenState extends State<ManagerUsersScreen> {
  List<UserAccount> _users = [];
  bool _loading = true;
  final Map<String, _RepActivity> _activity = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await context.read<AppProvider>().getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
    for (final u in users.where((u) => u.role == UserRole.rep)) {
      _loadRepActivity(u.id);
    }
  }

  Future<void> _loadRepActivity(String repId) async {
    try {
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('ownerUid', isEqualTo: repId)
          .orderBy('date', descending: true)
          .limit(50)
          .get();
      final receiptsSnap = await FirebaseFirestore.instance
          .collection('receipts')
          .where('ownerUid', isEqualTo: repId)
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      final invoices = invoicesSnap.docs.map((d) => Invoice.fromMap(d.data())).toList();
      final receipts = receiptsSnap.docs.map((d) => Receipt.fromMap(d.data())).toList();

      final now = DateTime.now();
      bool isToday(DateTime d) =>
          d.year == now.year && d.month == now.month && d.day == now.day;

      final todayInvoices = invoices.where((i) => isToday(i.createdAt));
      final salesInvoices = todayInvoices.where((i) => i.kind != InvoiceKind.saleReturn);
      final returnInvoices = todayInvoices.where((i) => i.kind == InvoiceKind.saleReturn);
      final todayReceipts = receipts.where((r) => isToday(r.createdAt));

      DateTime? last;
      for (final i in invoices) {
        if (last == null || i.createdAt.isAfter(last)) last = i.createdAt;
      }
      for (final r in receipts) {
        if (last == null || r.createdAt.isAfter(last)) last = r.createdAt;
      }

      if (!mounted) return;
      setState(() {
        _activity[repId] = _RepActivity(
          invoicesToday: salesInvoices.length,
          returnsToday: returnInvoices.length,
          receiptsToday: todayReceipts.length,
          salesToday: salesInvoices.fold(0.0, (s, i) => s + i.grandTotal),
          lastActivityAt: last,
        );
      });
    } catch (_) {
      // تجاهل بصمت لهذا المندوب فقط (مثال: فهرس Firestore غير جاهز) —
      // باقي الشاشة (الحسابات) تبقى تعمل رغم ذلك
    }
  }

  Future<void> _toggleActive(UserAccount u) async {
    await context.read<AppProvider>().toggleUserActive(u);
    _load();
  }

  Future<void> _openForm({UserAccount? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserFormSheet(existing: existing),
    );
    if (saved == true) _load();
  }

  String _relativeTime(DateTime? d) {
    if (d == null) return 'لا يوجد نشاط بعد';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'آخر نشاط: الآن';
    if (diff.inMinutes < 60) return 'آخر نشاط: قبل ${diff.inMinutes} دقيقة';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) {
      final t = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      return 'آخر نشاط: اليوم $t';
    }
    if (diff.inDays < 2) return 'آخر نشاط: أمس';
    if (diff.inDays < 30) return 'آخر نشاط: قبل ${diff.inDays} يوم';
    return 'آخر نشاط: قبل فترة طويلة';
  }

  Color _activityColor(DateTime? d) {
    if (d == null) return Colors.grey.shade400;
    final hours = DateTime.now().difference(d).inHours;
    if (hours < 6) return AppTheme.syncSuccess;
    if (hours < 48) return AppTheme.syncPending;
    return AppTheme.syncError;
  }

  void _openRepDetail(UserAccount u) {
    final activity = _activity[u.id] ?? _RepActivity.empty;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RepDetailSheet(
        user: u,
        activity: activity,
        relativeTime: _relativeTime,
        dotColor: _activityColor(activity.lastActivityAt),
        onEdit: () {
          Navigator.pop(ctx);
          _openForm(existing: u);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reps = _users.where((u) => u.role == UserRole.rep).toList();
    final managers = _users.where((u) => u.role == UserRole.manager).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('المندوبون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('إضافة مندوب'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('لا يوجد مستخدمون بعد'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: [
                      for (final u in reps) ...[
                        _RepCard(
                          user: u,
                          activity: _activity[u.id],
                          relativeLabel: _relativeTime(_activity[u.id]?.lastActivityAt),
                          dotColor: _activityColor(_activity[u.id]?.lastActivityAt),
                          onTap: () => _openRepDetail(u),
                          onToggleActive: () => _toggleActive(u),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (managers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('المدراء', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 8),
                        for (final u in managers) ...[
                          Card(
                            child: ListTile(
                              onTap: () => _openForm(existing: u),
                              leading: const CircleAvatar(
                                backgroundColor: Colors.indigo,
                                child: Icon(Icons.admin_panel_settings,
                                    color: Colors.white, size: 20),
                              ),
                              title: Text(u.displayName),
                              subtitle: Text('@${u.username} • مدير'),
                              trailing: Switch(
                                value: u.isActive,
                                onChanged: (_) => _toggleActive(u),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _RepCard extends StatelessWidget {
  final UserAccount user;
  final _RepActivity? activity;
  final String relativeLabel;
  final Color dotColor;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  const _RepCard({
    required this.user,
    required this.activity,
    required this.relativeLabel,
    required this.dotColor,
    required this.onTap,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final hasOps = a != null && (a.invoicesToday + a.returnsToday + a.receiptsToday) > 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.syncSuccessSoft,
                    child: Text(
                      user.displayName.isNotEmpty ? user.displayName.substring(0, 1) : '؟',
                      style: TextStyle(
                          color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        border: Border.all(color: Theme.of(context).cardColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(relativeLabel,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    if (hasOps) ...[
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (a.invoicesToday > 0) '${a.invoicesToday} فاتورة',
                          if (a.receiptsToday > 0) '${a.receiptsToday} سند',
                          if (a.returnsToday > 0) '${a.returnsToday} مرتجع',
                        ].join(' + '),
                        style: TextStyle(
                            color: AppTheme.syncSuccess, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(value: user.isActive, onChanged: (_) => onToggleActive()),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepDetailSheet extends StatelessWidget {
  final UserAccount user;
  final _RepActivity activity;
  final String Function(DateTime?) relativeTime;
  final Color dotColor;
  final VoidCallback onEdit;

  const _RepDetailSheet({
    required this.user,
    required this.activity,
    required this.relativeTime,
    required this.dotColor,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.syncSuccessSoft,
                  child: Text(
                    user.displayName.isNotEmpty ? user.displayName.substring(0, 1) : '؟',
                    style: TextStyle(
                        color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                          ),
                          const SizedBox(width: 6),
                          Text(relativeTime(activity.lastActivityAt),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('اليوم (حسب آخر ما وصل عبر فايربيس)',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                _MiniStat(icon: Icons.receipt_long_outlined, label: 'فواتير', value: '${activity.invoicesToday}'),
                _MiniStat(icon: Icons.payments_outlined, label: 'سندات', value: '${activity.receiptsToday}'),
                _MiniStat(icon: Icons.undo, label: 'مرتجع', value: '${activity.returnsToday}'),
              ],
            ),
            if (activity.salesToday > 0) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.syncSuccessSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Text('إجمالي المبيعات اليوم', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(Formatters.money(activity.salesToday),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerLiveActivityScreen(initialRepId: user.id),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('عرض في النشاط المباشر'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل الحساب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ],
      ),
    );
  }
}

class _UserFormSheet extends StatefulWidget {
  final UserAccount? existing;
  const _UserFormSheet({this.existing});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _repNumberCtrl;
  final _passCtrl = TextEditingController();
  UserRole _role = UserRole.rep;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.displayName ?? '');
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _repNumberCtrl = TextEditingController(text: e?.repNumber ?? '');
    _role = e?.role ?? UserRole.rep;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _repNumberCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final app = context.read<AppProvider>();
    try {
      final taken = await app.isUsernameTaken(_userCtrl.text,
          excludingId: widget.existing?.id);
      if (taken) {
        setState(() {
          _error = 'اسم المستخدم مستخدم بالفعل';
          _saving = false;
        });
        return;
      }
      if (_isEdit) {
        final u = widget.existing!;
        u.displayName = _nameCtrl.text.trim();
        u.username = _userCtrl.text.trim();
        u.repNumber = _repNumberCtrl.text.trim();
        await app.updateUserAccount(u);
        if (_passCtrl.text.isNotEmpty) {
          await app.setUserPassword(u, _passCtrl.text);
        }
      } else {
        if (_passCtrl.text.length < 6) {
          setState(() {
            _error = '٦ أحرف على الأقل لكلمة المرور';
            _saving = false;
          });
          return;
        }
        await app.addUser(
          username: _userCtrl.text,
          rawPassword: _passCtrl.text,
          displayName: _nameCtrl.text,
          role: _role,
          repNumber: _repNumberCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'تعديل الحساب' : 'إضافة مستخدم جديد',
                  style:
                      const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                      value: UserRole.rep,
                      label: Text('مندوب'),
                      icon: Icon(Icons.badge_outlined)),
                  ButtonSegment(
                      value: UserRole.manager,
                      label: Text('مدير'),
                      icon: Icon(Icons.admin_panel_settings)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'الاسم', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              if (_role == UserRole.rep) ...[
                TextFormField(
                  controller: _repNumberCtrl,
                  decoration: const InputDecoration(
                      labelText: 'رقم المندوب', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'كلمة مرور جديدة (اتركها فارغة لعدم التغيير)'
                      : 'كلمة المرور',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppTheme.syncError)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء الحساب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
