import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'package:flutter/material.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() =>
      _AdminManagementScreenState();
}

class _AdminManagementScreenState
    extends State<AdminManagementScreen> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  Stream<QuerySnapshot<Map<String, dynamic>>> get _employees =>
      FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'nhanvien')
          .snapshots();

  Future<void> _setStatus(String uid, String status) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _confirmDelete(
      String uid,
      String name,
      ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: Text(
          'Tài khoản "$name" sẽ bị vô hiệu hóa và không được phép sử dụng ứng dụng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _setStatus(uid, 'deleted');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã xóa/vô hiệu hóa tài khoản nhân viên.'),
      ),
    );
  }

  Future<void> _showAddEmployee() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Thêm nhân viên'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu',
                        hintText: 'Tối thiểu 6 ký tự',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                    final n = name.text.trim();
                    final e = email.text.trim();
                    final p = password.text;

                    if (n.isEmpty ||
                        e.isEmpty ||
                        p.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui lòng nhập đủ thông tin, mật khẩu tối thiểu 6 ký tự.',
                          ),
                        ),
                      );
                      return;
                    }

                    setDialogState(() {
                      saving = true;
                    });

                    FirebaseApp? secondaryApp;
                    FirebaseAuth? secondaryAuth;

                    try {
                      const appName = 'admin_create_employee';

                      try {
                        secondaryApp = Firebase.app(appName);
                      } catch (_) {
                        secondaryApp =
                        await Firebase.initializeApp(
                          name: appName,
                          options:
                          DefaultFirebaseOptions.currentPlatform,
                        );
                      }

                      secondaryAuth =
                          FirebaseAuth.instanceFor(
                            app: secondaryApp,
                          );

                      final credential =
                      await secondaryAuth
                          .createUserWithEmailAndPassword(
                        email: e,
                        password: p,
                      );

                      final user = credential.user!;

                      await user.updateDisplayName(n);

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set({
                        'uid': user.uid,
                        'hoTen': n,
                        'email': e,
                        'provider': 'email',
                        'role': 'nhanvien',
                        'status': 'active',
                        'createdAt':
                        FieldValue.serverTimestamp(),
                        'createdBy':
                        FirebaseAuth.instance.currentUser?.uid,
                      });

                      // Đăng xuất app phụ chỉ là bước dọn dẹp.
                      // Nếu bước này lỗi thì KHÔNG được báo tạo tài khoản thất bại,
                      // vì tài khoản Firebase Auth + Firestore đã tạo thành công.
                      try {
                        await secondaryAuth.signOut();
                      } catch (_) {}

                      if (!mounted) return;
                      Navigator.pop(dialogContext);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã tạo tài khoản nhân viên thành công.',
                          ),
                        ),
                      );
                    } on FirebaseAuthException catch (e) {
                      setDialogState(() {
                        saving = false;
                      });

                      final message =
                      e.code == 'email-already-in-use'
                          ? 'Email này đã tồn tại.'
                          : e.message ??
                          'Không thể tạo tài khoản.';

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message),
                        ),
                      );
                    } catch (e) {
                      setDialogState(() {
                        saving = false;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Không thể tạo tài khoản: $e',
                          ),
                        ),
                      );
                    }
                  },
                  child: saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text('Tạo tài khoản'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    email.dispose();
    password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Quản lý nhân viên',
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showAddEmployee,
            tooltip: 'Thêm nhân viên',
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
              color: vnptBlue,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _employees,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: vnptBlue,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Không tải được danh sách nhân viên.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Chưa có tài khoản nhân viên.',
                style: TextStyle(
                  color: textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return _employeeCard(docs[index]);
            },
          );
        },
      ),
    );
  }

  Widget _employeeCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();
    final name =
    data['hoTen']?.toString().trim().isNotEmpty == true
        ? data['hoTen'].toString().trim()
        : 'Nhân viên';
    final email = data['email']?.toString() ?? '';
    final provider = data['provider']?.toString() ?? 'email';
    final status = data['status']?.toString() ?? 'active';

    final disabled =
        status == 'disabled' || status == 'deleted';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFFE8ECF1),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor:
            disabled
                ? const Color(0xFFFFEBEE)
                : const Color(0xFFEAF3FF),
            child: Icon(
              provider == 'google'
                  ? Icons.g_mobiledata_rounded
                  : Icons.person_rounded,
              color: disabled ? Colors.red : vnptBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  provider == 'google'
                      ? 'Google'
                      : 'Email / Mật khẩu',
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'disable') {
                await _setStatus(doc.id, 'disabled');
              } else if (value == 'enable') {
                await _setStatus(doc.id, 'active');
              } else if (value == 'delete') {
                await _confirmDelete(doc.id, name);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: disabled ? 'enable' : 'disable',
                child: Text(
                  disabled
                      ? 'Mở khóa tài khoản'
                      : 'Khóa tài khoản',
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Xóa tài khoản',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
