import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminSurveyEditorScreen extends StatefulWidget {
  final String surveyId;

  const AdminSurveyEditorScreen({
    super.key,
    required this.surveyId,
  });

  @override
  State<AdminSurveyEditorScreen> createState() =>
      _AdminSurveyEditorScreenState();
}

class _AdminSurveyEditorScreenState extends State<AdminSurveyEditorScreen> {
  final _db = FirebaseFirestore.instance;

  static const vnptBlue = Color(0xFF0057B8);
  static const textDark = Color(0xFF172033);
  static const textGrey = Color(0xFF667085);
  static const background = Color(0xFFF6F8FB);

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSurvey();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadSurvey() async {
    try {
      final doc =
      await _db.collection('survey_templates').doc(widget.surveyId).get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy bộ khảo sát.')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final data = doc.data() ?? {};
      _nameController.text = data['name']?.toString() ?? '';
      _descriptionController.text =
          data['description']?.toString() ?? '';

      final rawSections = data['sections'];
      if (rawSections is List) {
        _sections = rawSections
            .whereType<Map>()
            .map(
              (section) => Map<String, dynamic>.from(section),
        )
            .toList();
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tải khảo sát: $e')),
        );
      }
    }
  }

  Future<void> _save({bool publish = false}) async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên khảo sát.')),
      );
      return;
    }

    if (_sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng tạo ít nhất một phần.')),
      );
      return;
    }

    final hasEmptyQuestion = _sections.any((section) {
      final questions = section['questions'];
      if (questions is! List) return false;

      return questions.any(
            (raw) =>
        raw is Map &&
            (raw['title']?.toString().trim().isEmpty ?? true),
      );
    });

    if (hasEmptyQuestion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Có câu hỏi chưa nhập nội dung.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final ref = _db.collection('survey_templates').doc(widget.surveyId);
      final current = await ref.get();
      final currentData = current.data() ?? {};
      final currentVersion =
          (currentData['version'] as num?)?.toInt() ?? 1;

      await ref.update({
        'name': name,
        'description': _descriptionController.text.trim(),
        'sections': _sections,
        'version': publish ? currentVersion + 1 : currentVersion,
        'status': publish ? 'published' : 'draft',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish
                ? 'Đã xuất bản bộ khảo sát.'
                : 'Đã lưu bản nháp.',
          ),
        ),
      );

      if (publish) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lưu khảo sát thất bại: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addSection() async {
    final title = await showDialog<String>(
      context: context,
      requestFocus: false,
      builder: (_) => const _SectionNameDialog(),
    );

    if (title == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;

    setState(() {
      _sections.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'title': title,
        'questions': <Map<String, dynamic>>[],
      });
    });
  }

  Future<void> _editSection(int index) async {
    final title = await showDialog<String>(
      context: context,
      requestFocus: false,
      builder: (_) => _SectionNameDialog(
        initialValue: _sections[index]['title']?.toString() ?? '',
        title: 'Sửa tên phần',
      ),
    );

    if (title == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;

    setState(() => _sections[index]['title'] = title);
  }

  Future<void> _deleteSection(int index) async {
    final ok = await _confirm(
      title: 'Xóa phần khảo sát?',
      message:
      'Các câu hỏi bên trong phần này cũng sẽ bị xóa khỏi bản nháp.',
    );

    if (ok) {
      setState(() => _sections.removeAt(index));
    }
  }

  Future<void> _addQuestion(int sectionIndex) async {
    final question = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuestionEditorSheet(),
    );

    if (question == null) return;

    setState(() {
      final questions =
      List<Map<String, dynamic>>.from(
        (_sections[sectionIndex]['questions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );

      questions.add(question);
      _sections[sectionIndex]['questions'] = questions;
    });
  }

  Future<void> _editQuestion(
      int sectionIndex,
      int questionIndex,
      ) async {
    final questions =
    List<Map<String, dynamic>>.from(
      (_sections[sectionIndex]['questions'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );

    final edited = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuestionEditorSheet(
        initialQuestion: questions[questionIndex],
      ),
    );

    if (edited == null) return;

    setState(() {
      questions[questionIndex] = edited;
      _sections[sectionIndex]['questions'] = questions;
    });
  }

  Future<void> _deleteQuestion(
      int sectionIndex,
      int questionIndex,
      ) async {
    final ok = await _confirm(
      title: 'Xóa câu hỏi?',
      message: 'Câu hỏi này sẽ bị xóa khỏi bản nháp.',
    );

    if (!ok) return;

    setState(() {
      final questions =
      List<Map<String, dynamic>>.from(
        (_sections[sectionIndex]['questions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );

      questions.removeAt(questionIndex);
      _sections[sectionIndex]['questions'] = questions;
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    ) ??
        false;
  }

  void _moveSection(int index, int direction) {
    final newIndex = index + direction;

    if (newIndex < 0 || newIndex >= _sections.length) return;

    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(newIndex, item);
    });
  }

  void _moveQuestion(
      int sectionIndex,
      int questionIndex,
      int direction,
      ) {
    final questions =
    List<Map<String, dynamic>>.from(
      (_sections[sectionIndex]['questions'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );

    final newIndex = questionIndex + direction;
    if (newIndex < 0 || newIndex >= questions.length) return;

    setState(() {
      final item = questions.removeAt(questionIndex);
      questions.insert(newIndex, item);
      _sections[sectionIndex]['questions'] = questions;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: textDark),
        title: const Text(
          'Thiết kế bộ khảo sát',
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: const Text('LƯU NHÁP'),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _saving ? null : () => _save(publish: true),
              style: FilledButton.styleFrom(
                backgroundColor: vnptBlue,
              ),
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('XUẤT BẢN'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addSection,
        backgroundColor: vnptBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm phần'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        children: [
          _buildBasicInfo(),
          const SizedBox(height: 16),
          if (_sections.isEmpty)
            _buildEmptyState()
          else
            ..._sections.asMap().entries.map(
                  (entry) => _buildSectionCard(
                entry.key,
                entry.value,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thông tin bộ khảo sát',
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên khảo sát *',
                prefixIcon: Icon(Icons.assignment_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(
              Icons.library_add_outlined,
              size: 52,
              color: vnptBlue,
            ),
            const SizedBox(height: 12),
            const Text(
              'Chưa có phần khảo sát',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bấm "Thêm phần" để tạo Phần I, Phần II...',
              textAlign: TextAlign.center,
              style: TextStyle(color: textGrey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addSection,
              icon: const Icon(Icons.add),
              label: const Text('Thêm phần đầu tiên'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
      int sectionIndex,
      Map<String, dynamic> section,
      ) {
    final questions =
    (section['questions'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.layers_outlined,
                    color: vnptBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section['title']?.toString() ?? 'Phần',
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Lên',
                  onPressed: sectionIndex == 0
                      ? null
                      : () => _moveSection(sectionIndex, -1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Xuống',
                  onPressed: sectionIndex == _sections.length - 1
                      ? null
                      : () => _moveSection(sectionIndex, 1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _editSection(sectionIndex);
                    if (value == 'delete') _deleteSection(sectionIndex);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Sửa tên phần'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa phần'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            if (questions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Phần này chưa có câu hỏi.',
                  style: TextStyle(color: textGrey),
                ),
              ),
            ...questions.asMap().entries.map(
                  (entry) => _buildQuestionCard(
                sectionIndex,
                entry.key,
                entry.value,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _addQuestion(sectionIndex),
                icon: const Icon(Icons.add),
                label: const Text('Thêm câu hỏi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
      int sectionIndex,
      int questionIndex,
      Map<String, dynamic> question,
      ) {
    final type = question['type']?.toString() ?? 'text';
    final typeName = _typeName(type);
    final options = (question['options'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    final currentQuestions =
    (_sections[sectionIndex]['questions'] as List? ?? []);

    final isLastQuestion =
        questionIndex >= currentQuestions.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFEAF2FF),
            child: Text(
              '${questionIndex + 1}',
              style: const TextStyle(
                color: vnptBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${questionIndex + 1}. ${question['title']?.toString() ?? ''}',
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniChip(text: typeName),
                    if (question['required'] == true)
                      const _MiniChip(text: 'Bắt buộc'),
                  ],
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Lựa chọn: ${options.join(' • ')}',
                    style: const TextStyle(
                      color: textGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Lên',
            onPressed: questionIndex == 0
                ? null
                : () => _moveQuestion(
              sectionIndex,
              questionIndex,
              -1,
            ),
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: 'Xuống',
            onPressed: isLastQuestion
                ? null
                : () => _moveQuestion(
              sectionIndex,
              questionIndex,
              1,
            ),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _editQuestion(sectionIndex, questionIndex);
              }
              if (value == 'delete') {
                _deleteQuestion(sectionIndex, questionIndex);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text('Sửa câu hỏi'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Xóa câu hỏi'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeName(String type) {
    switch (type) {
      case 'number':
        return 'Nhập số';
      case 'single':
        return 'Chọn một';
      case 'multiple':
        return 'Chọn nhiều';
      default:
        return 'Văn bản';
    }
  }
}


class _SectionNameDialog extends StatefulWidget {
  final String initialValue;
  final String title;

  const _SectionNameDialog({
    this.initialValue = '',
    this.title = 'Thêm phần khảo sát',
  });

  @override
  State<_SectionNameDialog> createState() => _SectionNameDialogState();
}

class _SectionNameDialogState extends State<_SectionNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên phần.')),
      );
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: TextField(
        controller: _controller,
        autofocus: false,
        decoration: const InputDecoration(
          labelText: 'Tên phần *',
          hintText: 'Ví dụ: I. THÔNG TIN HỘ KINH DOANH',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;

  const _MiniChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0057B8),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuestionEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? initialQuestion;

  const _QuestionEditorSheet({
    this.initialQuestion,
  });

  @override
  State<_QuestionEditorSheet> createState() => _QuestionEditorSheetState();
}

class _QuestionEditorSheetState extends State<_QuestionEditorSheet> {
  static const vnptBlue = Color(0xFF0057B8);

  late final TextEditingController _titleController;
  late String _type;
  late bool _required;
  late List<TextEditingController> _optionControllers;

  bool get _needsOptions =>
      _type == 'single' || _type == 'multiple';

  @override
  void initState() {
    super.initState();

    final q = widget.initialQuestion ?? {};

    _titleController = TextEditingController(
      text: q['title']?.toString() ?? '',
    );

    _type = q['type']?.toString() ?? 'text';
    _required = q['required'] == true;

    final options = (q['options'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    _optionControllers = options
        .map((option) => TextEditingController(text: option))
        .toList();

    if (_needsOptions && _optionControllers.isEmpty) {
      _optionControllers.add(TextEditingController());
      _optionControllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changeType(String? value) {
    if (value == null) return;

    setState(() {
      _type = value;

      if (_type == 'single' || _type == 'multiple') {
        if (_optionControllers.isEmpty) {
          _optionControllers.add(TextEditingController());
          _optionControllers.add(TextEditingController());
        }
      }
    });
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 1) return;

    final controller = _optionControllers.removeAt(index);
    controller.dispose();

    setState(() {});
  }

  void _submit() {
    // Admin chỉ nhập nội dung câu hỏi. Số thứ tự sẽ được app tự động
    // hiển thị theo vị trí của câu hỏi trong từng phần.
    var title = _titleController.text.trim();
    title = title.replaceFirst(
      RegExp(r'^\s*\d+\s*[\.)\-:]\s*'),
      '',
    ).trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung câu hỏi.')),
      );
      return;
    }

    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (_needsOptions && options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Câu hỏi lựa chọn cần ít nhất 2 đáp án.'),
        ),
      );
      return;
    }

    Navigator.pop<Map<String, dynamic>>(
      context,
      {
        'id': widget.initialQuestion?['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        'title': title,
        'type': _type,
        'required': _required,
        'options': _needsOptions ? options : <String>[],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Câu hỏi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nội dung câu hỏi *',
                  hintText: 'Ví dụ: Doanh thu trung bình mỗi tháng? (không cần nhập số)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Loại câu trả lời',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'text',
                    child: Text('Văn bản'),
                  ),
                  DropdownMenuItem(
                    value: 'number',
                    child: Text('Nhập số'),
                  ),
                  DropdownMenuItem(
                    value: 'single',
                    child: Text('Chọn một'),
                  ),
                  DropdownMenuItem(
                    value: 'multiple',
                    child: Text('Chọn nhiều / Checkbox'),
                  ),
                ],
                onChanged: _changeType,
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Bắt buộc trả lời',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                value: _required,
                activeColor: vnptBlue,
                onChanged: (value) {
                  setState(() => _required = value);
                },
              ),
              if (_needsOptions) ...[
                const SizedBox(height: 8),
                const Text(
                  'Các lựa chọn',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ..._optionControllers.asMap().entries.map(
                      (entry) {
                    final index = entry.key;
                    final controller = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Lựa chọn ${index + 1}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeOption(index),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm lựa chọn'),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: vnptBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    widget.initialQuestion == null
                        ? 'Thêm câu hỏi'
                        : 'Lưu câu hỏi',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
