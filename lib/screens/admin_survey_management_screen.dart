import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_survey_editor_screen.dart';


class _CreateSurveyDialog extends StatefulWidget {
  const _CreateSurveyDialog();

  @override
  State<_CreateSurveyDialog> createState() => _CreateSurveyDialogState();
}

class _CreateSurveyDialogState extends State<_CreateSurveyDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên khảo sát.')),
      );
      return;
    }

    Navigator.of(context).pop({
      'name': name,
      'description': _descriptionController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Tạo bộ khảo sát',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Tên khảo sát *',
                hintText: 'Ví dụ: Khảo sát chuyển đổi số HKD',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              autofocus: false,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Tạo'),
        ),
      ],
    );
  }
}

class AdminSurveyManagementScreen extends StatefulWidget {
  const AdminSurveyManagementScreen({super.key});

  @override
  State<AdminSurveyManagementScreen> createState() =>
      _AdminSurveyManagementScreenState();
}

class _AdminSurveyManagementScreenState
    extends State<AdminSurveyManagementScreen> {
  final _db = FirebaseFirestore.instance;

  static const vnptBlue = Color(0xFF0057B8);
  static const textDark = Color(0xFF172033);
  static const textGrey = Color(0xFF667085);
  static const background = Color(0xFFF6F8FB);

  Future<void> _createSurvey() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      requestFocus: false,
      builder: (_) => const _CreateSurveyDialog(),
    );

    if (result == null || !mounted) return;

    // Cho Dialog/Focus/Overlay kết thúc hoàn toàn trước khi chuyển màn hình.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;

    try {
      final now = FieldValue.serverTimestamp();

      final doc = await _db.collection('survey_templates').add({
        'name': result['name'],
        'description': result['description'] ?? '',
        'status': 'draft',
        'isActive': false,
        'version': 1,
        'sections': <Map<String, dynamic>>[],
        'createdAt': now,
        'updatedAt': now,
      });

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdminSurveyEditorScreen(
            surveyId: doc.id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể tạo bộ khảo sát: $e')),
      );
    }
  }

  Future<void> _applySurvey(
      String surveyId,
      String surveyName,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Áp dụng bộ khảo sát mới?'),
          content: Text(
            '"$surveyName" sẽ được dùng cho các HKD tạo mới từ thời điểm này.\n\n'
                'Các HKD đã nhập trước đó KHÔNG bị thay đổi và vẫn dùng form cũ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Áp dụng form mới'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _db.collection('survey_settings').doc('current').set({
      'mode': 'custom',
      'activeTemplateId': surveyId,
      'activeTemplateName': surveyName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final activeSnapshot = await _db
        .collection('survey_templates')
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _db.batch();

    for (final doc in activeSnapshot.docs) {
      batch.update(doc.reference, {
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(
      _db.collection('survey_templates').doc(surveyId),
      {
        'isActive': true,
        'status': 'published',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã áp dụng "$surveyName" cho HKD tạo mới. HKD cũ không bị ảnh hưởng.',
        ),
      ),
    );

    setState(() {});
  }

  Future<void> _applyDefaultForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Áp dụng form mặc định?'),
        content: const Text(
          'Các HKD tạo mới sẽ dùng form mặc định ban đầu.\n\n'
              'Dữ liệu và form của tất cả HKD đã nhập trước đó vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Áp dụng mặc định'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _db.collection('survey_settings').doc('current').set({
      'mode': 'default',
      'activeTemplateId': null,
      'activeTemplateName': 'Form mặc định',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final activeSnapshot = await _db
        .collection('survey_templates')
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _db.batch();
    for (final doc in activeSnapshot.docs) {
      batch.update(doc.reference, {
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Đã áp dụng form mặc định cho HKD tạo mới. HKD cũ không bị ảnh hưởng.',
        ),
      ),
    );

    setState(() {});
  }


  Future<void> _closeSurvey(
      String surveyId,
      String surveyName,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Đóng bộ khảo sát?'),
          content: Text(
            'Bộ "$surveyName" sẽ không còn là bộ khảo sát đang áp dụng.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _db.collection('survey_templates').doc(surveyId).update({
      'isActive': false,
      'status': 'closed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) setState(() {});
  }

  Future<void> _deleteSurvey(
      String surveyId,
      String surveyName,
      bool isActive,
      ) async {
    if (isActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể xóa form đang áp dụng. Hãy áp dụng form khác hoặc form mặc định trước.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bộ khảo sát?'),
        content: Text(
          'Bạn có chắc muốn xóa "$surveyName"?\n\n'
              'Bộ khảo sát này sẽ bị xóa khỏi danh sách quản lý. '
              'Thao tác này không ảnh hưởng đến dữ liệu HKD đã lưu trước đó.',
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

    if (confirmed != true) return;

    await _db.collection('survey_templates').doc(surveyId).delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa "$surveyName".')),
    );

    setState(() {});
  }

  String _statusText(Map<String, dynamic> data) {
    if (data['isActive'] == true) return 'ĐANG ÁP DỤNG';

    switch (data['status']) {
      case 'published':
        return 'ĐÃ XUẤT BẢN';
      case 'closed':
        return 'ĐÃ ĐÓNG';
      default:
        return 'BẢN NHÁP';
    }
  }

  Color _statusColor(Map<String, dynamic> data) {
    if (data['isActive'] == true) return Colors.green;

    switch (data['status']) {
      case 'published':
        return Colors.blue;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Quản lý bộ khảo sát',
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: textDark),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSurvey,
        backgroundColor: vnptBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tạo khảo sát'),
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('survey_settings')
                .doc('current')
                .snapshots(),
            builder: (context, settingsSnapshot) {
              final settings = settingsSnapshot.data?.data() ?? {};
              final defaultActive = settings['mode'] != 'custom';

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: defaultActive
                      ? const Color(0xFFEAF3FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: defaultActive
                        ? const Color(0xFFBBD8F5)
                        : const Color(0xFFE5EAF0),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.assignment_turned_in_outlined,
                        color: vnptBlue,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Form mặc định ban đầu',
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Dùng cho HKD tạo mới khi không chọn form riêng.',
                            style: TextStyle(
                              color: textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: defaultActive
                          ? null
                          : _applyDefaultForm,
                      style: FilledButton.styleFrom(
                        backgroundColor: vnptBlue,
                        disabledBackgroundColor: Colors.green,
                        disabledForegroundColor: Colors.white,
                      ),
                      child: Text(
                        defaultActive ? 'ĐANG DÙNG' : 'ÁP DỤNG',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('survey_templates')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Không thể tải bộ khảo sát.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Chưa có bộ khảo sát nào.\nBấm "Tạo khảo sát" để bắt đầu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textGrey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final sections = data['sections'] is List
                        ? data['sections'] as List
                        : const [];

                    int questionCount = 0;
                    for (final section in sections) {
                      if (section is Map && section['questions'] is List) {
                        questionCount +=
                            (section['questions'] as List).length;
                      }
                    }

                    final active = data['isActive'] == true;
                    final status = _statusText(data);
                    final statusColor = _statusColor(data);

                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(
                          color: Color(0xFFE5EAF0),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0xFFE9F8EF)
                                        : const Color(0xFFEAF2FF),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    active
                                        ? Icons.check_circle_rounded
                                        : Icons.assignment_outlined,
                                    color: active
                                        ? Colors.green
                                        : vnptBlue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['name']?.toString() ??
                                            'Không có tên',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        data['description']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: textGrey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              AdminSurveyEditorScreen(
                                                surveyId: doc.id,
                                              ),
                                        ),
                                      );
                                      if (mounted) setState(() {});
                                    }

                                    if (value == 'delete') {
                                      await _deleteSurvey(
                                        doc.id,
                                        data['name']?.toString() ??
                                            'bộ khảo sát',
                                        active,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Chỉnh sửa'),
                                    ),
                                    if (!active)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Xóa khảo sát'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(
                                  icon: Icons.layers_outlined,
                                  text: '${sections.length} phần',
                                ),
                                _InfoChip(
                                  icon: Icons.help_outline_rounded,
                                  text: '$questionCount câu hỏi',
                                ),
                                _StatusChip(
                                  text: status,
                                  color: statusColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                if (!active &&
                                    data['status'] != 'closed')
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AdminSurveyEditorScreen(
                                                  surveyId: doc.id,
                                                ),
                                          ),
                                        );
                                        if (mounted) setState(() {});
                                      },
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                      ),
                                      label: const Text('Chỉnh sửa'),
                                    ),
                                  ),
                                if (!active &&
                                    data['status'] != 'closed')
                                  const SizedBox(width: 8),
                                if (!active &&
                                    data['status'] != 'closed')
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _applySurvey(
                                        doc.id,
                                        data['name']?.toString() ??
                                            'bộ khảo sát',
                                      ),
                                      icon: const Icon(
                                        Icons.publish_rounded,
                                      ),
                                      label: const Text('Áp dụng'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: vnptBlue,
                                      ),
                                    ),
                                  ),
                                if (active)
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _closeSurvey(
                                        doc.id,
                                        data['name']?.toString() ??
                                            'bộ khảo sát',
                                      ),
                                      icon: const Icon(
                                        Icons.stop_circle_outlined,
                                      ),
                                      label: const Text('Đóng khảo sát'),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: const Color(0xFF667085),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
