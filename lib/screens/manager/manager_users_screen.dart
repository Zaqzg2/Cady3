import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../models/user_account.dart';

/// إدارة حسابات المندوبين (وحسابات المدراء الإضافية إن وُجدت): عرض،
/// إضافة، تعديل، وتفعيل/إيقاف
class ManagerUsersScreen extends StatefulWidget {
  const ManagerUsersScreen({super.key});

  @override
  State<ManagerUsersScreen> createState() => _ManagerUsersScreenState();
}

class _ManagerUsersScreenState extends State<ManagerUsersScreen> {
  List<UserAccount> _users = [];
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = _users[i];
                    final isManager = u.role == UserRole.manager;
                    return Card(
                      child: ListTile(
                        onTap: () => _openForm(existing: u),
                        leading: CircleAvatar(
                          backgroundColor:
                              isManager ? Colors.indigo : Colors.teal,
                          child: Icon(
                              isManager
                                  ? Icons.admin_panel_settings
                                  : Icons.badge_outlined,
                              color: Colors.white,
                              size: 20),
                        ),
                        title: Text(u.displayName),
                        subtitle: Text(isManager
                            ? '@${u.username} • مدير'
                            : '@${u.username} • مندوب${u.repNumber.isNotEmpty ? ' #${u.repNumber}' : ''}'),
                        trailing: Switch(
                          value: u.isActive,
                          onChanged: (_) => _toggleActive(u),
                        ),
                      ),
                    );
                  },
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
        if (_passCtrl.text.length < 4) {
          setState(() {
            _error = '٤ أحرف على الأقل لكلمة المرور';
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
                Text(_error!, style: const TextStyle(color: Colors.red)),
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
