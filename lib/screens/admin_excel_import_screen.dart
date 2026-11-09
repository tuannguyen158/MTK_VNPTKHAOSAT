import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/excel_import_service.dart';

class AdminExcelImportScreen extends StatefulWidget {
  const AdminExcelImportScreen({super.key});

  @override
  State<AdminExcelImportScreen> createState() =>
      _AdminExcelImportScreenState();
}

class _AdminExcelImportScreenState extends State<AdminExcelImportScreen> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  PlatformFile? _file;
  ExcelPreviewResult? _preview;
  bool _loading = false;
  bool _importing = false;

  Future<void> _pickFile() async {
    try {
      final file = await ExcelImportService.pickExcelFile();
      if (file == null) return;

      setState(() {
        _file = file;
        _preview = null;
        _loading = true;
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('Không tìm thấy tài khoản Admin.');
      }

      final preview = await ExcelImportService.previewExcel(
        file: file,
        currentAdminUid: uid,
      );

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Không thể đọc Excel', '$e');
    }
  }

  Future<void> _import() async {
    final file = _file;
    final preview = _preview;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (file == null || preview == null || uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận Import'),
        content: Text(
          'App sẽ nhập ${preview.validRows} dòng HKD vào Firebase.\n\n'
              'Các dòng trùng MST/CCCD sẽ được cập nhật, '
              'dòng mới sẽ được tạo.\n\n'
              'Bạn có muốn tiếp tục không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: vnptBlue),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _importing = true);

    try {
      final result = await ExcelImportService.importAllBusinessSheets(
        file: file,
        currentAdminUid: uid,
      );

      if (!mounted) return;

      setState(() => _importing = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import hoàn tất'),
          content: Text(
            'Tổng dòng: ${result.totalRows}\n'
                'HKD mới: ${result.imported}\n'
                'HKD cập nhật: ${result.updated}\n'
                'Bỏ qua: ${result.skipped}\n'
                'Lỗi: ${result.invalid}',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: vnptBlue),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _message('Import thất bại', '$e');
    }
  }

  void _message(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: vnptBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Nhập dữ liệu Excel',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _importing
          ? const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: vnptBlue),
            SizedBox(height: 14),
            Text('Đang Import vào Firebase...'),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _fileCard(),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(35),
              child: Center(
                child: CircularProgressIndicator(color: vnptBlue),
              ),
            ),
          if (preview != null) ...[
            _summary(preview),
            const SizedBox(height: 14),
            _sheetCard(preview),
            const SizedBox(height: 14),
            _sampleCard(preview),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: vnptBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed:
                preview.validRows == 0 ? null : _import,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  'IMPORT ${preview.validRows} HKD VÀO FIREBASE',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fileCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: vnptLightBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: vnptBlue,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'File Excel khảo sát',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _file?.name ?? 'Chưa chọn file .xlsx',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: vnptBlue,
            ),
            onPressed: _loading || _importing ? null : _pickFile,
            child: const Text('Chọn file'),
          ),
        ],
      ),
    );
  }

  Widget _summary(ExcelPreviewResult p) {
    return Row(
      children: [
        Expanded(
          child: _stat(
            '${p.allSheets.length}',
            'Tổng sheet',
            Icons.layers_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(
            '${p.dataSheets.length}',
            'Sheet HKD',
            Icons.fact_check_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(
            '${p.validRows}',
            'Dòng hợp lệ',
            Icons.storefront_rounded,
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 15,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: vnptBlue, size: 21),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: textDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textGrey,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetCard(ExcelPreviewResult p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Các sheet được phát hiện',
            style: TextStyle(
              color: textDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...p.allSheets.map(
                (name) {
              final isData = p.dataSheets.contains(name);
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(
                      isData
                          ? Icons.check_circle_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 18,
                      color: isData ? vnptBlue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isData ? textDark : textGrey,
                          fontSize: 12.5,
                          fontWeight:
                          isData ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      isData ? 'Dữ liệu HKD' : 'Bỏ qua',
                      style: TextStyle(
                        color: isData ? vnptBlue : textGrey,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sampleCard(ExcelPreviewResult p) {
    if (p.sampleRows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Xem trước dữ liệu',
            style: TextStyle(
              color: textDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '10 dòng đầu tiên. Toàn bộ cột Excel vẫn được lưu vào excelData.',
            style: TextStyle(
              color: textGrey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ...p.sampleRows.asMap().entries.map(
                (entry) {
              final index = entry.key + 1;
              final data = entry.value;
              final raw = data['excelData'];
              final excelData =
              raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$index. ${data['tenHoKinhDoanh'] ?? 'Hộ kinh doanh'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'MST/CCCD: ${data['mstCccd'] ?? '—'}',
                      style: const TextStyle(
                        color: textGrey,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Địa chỉ: ${data['diaChi'] ?? '—'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textGrey,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toàn bộ cột Excel: ${excelData.length} trường',
                      style: const TextStyle(
                        color: vnptBlue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
