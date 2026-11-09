
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/biometric_service.dart';

import 'dart:convert';
import 'dart:io';
import 'map_screen.dart';
import 'package:cross_file/cross_file.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'add_business_screen.dart';
import 'survey_screen.dart';
import 'login_screen.dart';
import 'admin_management_screen.dart';
import 'admin_excel_import_screen.dart';
import 'admin_survey_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // =========================================================
  // MÀU SẮC VNPT
  // =========================================================

  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);

  static const Color background = Color(0xFFF5F7FA);

  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);
  static const Color textLightGrey = Color(0xFF8A94A3);

  // =========================================================
  // BOTTOM NAVIGATION
  // =========================================================

  int _selectedIndex = 0;

  // =========================================================
  // TÌM KIẾM
  // =========================================================

  final TextEditingController _searchController =
  TextEditingController();

  String _searchText = '';

  bool _searching = false;

  // =========================================================
  // PHÂN QUYỀN ADMIN / NHÂN VIÊN
  // =========================================================

  bool _roleLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _roleLoading = false;
        _isAdmin = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      setState(() {
        _isAdmin =
            snapshot.data()?['role']?.toString().toLowerCase() == 'admin';
        _roleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _roleLoading = false;
      });
    }
  }

  // =========================================================
  // FIRESTORE
  // =========================================================

  // Admin + Nhân viên đều xem TOÀN BỘ HKD.
  // Firestore Rules kiểm soát quyền đọc bằng loggedIn().
  Query<Map<String, dynamic>> get _businessQuery {
    return FirebaseFirestore.instance
        .collection('ho_kinh_doanh');
  }

  // =========================================================
  // XUẤT EXCEL - CHỈ ADMIN
  // =========================================================

  Future<void> _exportExcel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
      ) async {
    if (!_isAdmin) {
      _showMessageDialog(
        'Không có quyền',
        'Chỉ tài khoản Admin mới được xuất dữ liệu Excel.',
      );
      return;
    }

    if (documents.isEmpty) {
      _showMessageDialog(
        'Xuất Excel',
        'Hiện chưa có dữ liệu khảo sát để xuất.',
      );
      return;
    }

    // =========================================================
    // BƯỚC 1: CHỌN KIỂU XUẤT
    // =========================================================

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Xuất dữ liệu Excel',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Chọn phạm vi dữ liệu muốn xuất.',
                  style: TextStyle(
                    color: textGrey,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),

                _buildExcelChoice(
                  icon: Icons.all_inclusive_rounded,
                  title: 'Xuất toàn bộ dữ liệu HKD',
                  subtitle:
                  'Xuất tất cả hộ kinh doanh của mọi Form.',
                  onTap: () => Navigator.pop(context, 'all'),
                ),

                const SizedBox(height: 10),

                _buildExcelChoice(
                  icon: Icons.assignment_rounded,
                  title: 'Xuất theo Form',
                  subtitle:
                  'Chọn một Form và chỉ xuất dữ liệu của Form đó.',
                  onTap: () => Navigator.pop(context, 'form'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;

    // =========================================================
    // 1. XUẤT TOÀN BỘ
    // =========================================================

    if (choice == 'all') {
      await _exportAllBusinessExcel(documents);
      return;
    }

    // =========================================================
    // 2. XUẤT THEO FORM
    // =========================================================

    final templatesSnapshot = await FirebaseFirestore.instance
        .collection('survey_templates')
        .orderBy('createdAt', descending: true)
        .get();

    if (!mounted) return;

    final formId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chọn Form để xuất',
                      style: TextStyle(
                        color: textDark,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      20,
                    ),
                    children: [
                      _buildFormChoice(
                        icon: Icons.restore_rounded,
                        title: 'Form mặc định',
                        subtitle:
                        'Các HKD đang sử dụng Form ban đầu.',
                        onTap: () =>
                            Navigator.pop(context, '__default__'),
                      ),

                      const SizedBox(height: 10),

                      ...templatesSnapshot.docs.map((doc) {
                        final data = doc.data();

                        final name =
                            data['name']?.toString().trim() ?? '';

                        final status =
                            data['status']?.toString() ?? 'draft';

                        return Padding(
                          padding:
                          const EdgeInsets.only(bottom: 10),
                          child: _buildFormChoice(
                            icon: Icons.assignment_outlined,
                            title: name.isEmpty
                                ? 'Form không tên'
                                : name,
                            subtitle: status == 'published'
                                ? 'Đã xuất bản'
                                : 'Bản nháp',
                            onTap: () =>
                                Navigator.pop(context, doc.id),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (formId == null) return;

    // =========================================================
    // FORM MẶC ĐỊNH
    // =========================================================

    if (formId == '__default__') {
      final defaultDocuments = documents.where((doc) {
        final data = doc.data();

        // HKD cũ từ hệ thống trước khi có Form động
        // hoặc HKD không có surveyTemplateId đều thuộc Form mặc định.
        final templateId =
            data['surveyTemplateId']?.toString().trim() ?? '';

        final mode =
            data['surveyMode']?.toString().trim().toLowerCase() ?? '';

        return templateId.isEmpty && mode != 'custom';
      }).toList();

      await _exportDefaultFormExcel(defaultDocuments);
      return;
    }

    // =========================================================
    // FORM ĐỘNG
    // =========================================================

    QueryDocumentSnapshot<Map<String, dynamic>>? selectedTemplate;

    for (final doc in templatesSnapshot.docs) {
      if (doc.id == formId) {
        selectedTemplate = doc;
        break;
      }
    }

    if (selectedTemplate == null) {
      if (!mounted) return;
      _showMessageDialog(
        'Xuất Excel',
        'Không tìm thấy Form đã chọn.',
      );
      return;
    }

    final selectedData = selectedTemplate.data();

    final formName =
    selectedData['name']?.toString().trim().isNotEmpty == true
        ? selectedData['name'].toString().trim()
        : 'Form khảo sát';

    final formDocuments = documents.where((doc) {
      final data = doc.data();

      return data['surveyTemplateId']?.toString().trim() == formId;
    }).toList();

    await _exportCustomFormExcel(
      formDocuments,
      selectedData,
      formId,
      formName,
    );
  }

  Widget _buildExcelChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: vnptLightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: vnptBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: textGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: textGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: vnptLightBlue,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                color: vnptBlue,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: textGrey,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: textGrey,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAllBusinessExcel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
      ) async {
    await _createAndShareExcel(
      documents: documents,
      filePrefix: 'VNPT_KhaoSat_ToanBo',
      shareTitle: 'Xuất toàn bộ dữ liệu VNPT',
      sheetName: 'Toàn bộ HKD',
    );
  }

  Future<void> _exportDefaultFormExcel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
      ) async {
    if (documents.isEmpty) {
      _showMessageDialog(
        'Form mặc định',
        'Không có HKD nào thuộc Form mặc định.',
      );
      return;
    }

    await _createAndShareExcel(
      documents: documents,
      filePrefix: 'VNPT_KhaoSat_FormMacDinh',
      shareTitle: 'Dữ liệu Form mặc định',
      sheetName: 'Form mặc định',
    );
  }

  Future<void> _exportCustomFormExcel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
      Map<String, dynamic> template,
      String templateId,
      String formName,
      ) async {
    if (documents.isEmpty) {
      _showMessageDialog(
        'Xuất theo Form',
        'Không có HKD nào thuộc "$formName".',
      );
      return;
    }

    try {
      final excel = Excel.createExcel();

      excel.rename(
        'Sheet1',
        'Dữ liệu khảo sát',
      );

      final sheet = excel['Dữ liệu khảo sát'];

      // ---------------------------------------------------------
      // Các cột thông tin HKD luôn có.
      // ---------------------------------------------------------

      final headers = <String>[
        'Tên Hộ Kinh Doanh',
        'MST / CCCD',
        'Số điện thoại',
        'Địa chỉ',
        'Tỉnh / Thành phố',
        'Phường / Xã',
        'Latitude',
        'Longitude',
      ];

      // ---------------------------------------------------------
      // Lấy câu hỏi trực tiếp từ Form đã chọn.
      // ---------------------------------------------------------

      final questionColumns =
      <Map<String, String>>[];

      final sections = template['sections'];

      if (sections is List) {
        for (final rawSection in sections) {
          if (rawSection is! Map) continue;

          final questions = rawSection['questions'];

          if (questions is! List) continue;

          for (final rawQuestion in questions) {
            if (rawQuestion is! Map) continue;

            final questionId =
                rawQuestion['id']?.toString() ??
                    rawQuestion['key']?.toString() ??
                    '';

            if (questionId.isEmpty) continue;

            final questionTitle =
                rawQuestion['title']?.toString().trim() ??
                    rawQuestion['question']?.toString().trim() ??
                    'Câu hỏi';

            if (questionColumns.any(
                  (item) => item['id'] == questionId,
            )) {
              continue;
            }

            questionColumns.add({
              'id': questionId,
              'title': questionTitle,
            });

            headers.add(
              '${questionColumns.length}. $questionTitle',
            );
          }
        }
      }

      // Thông tin truy vết Form.
      headers.add('surveyTemplateId');
      headers.add('surveyName');
      headers.add('documentId');

      sheet.appendRow(
        headers.map(
              (header) => TextCellValue(header),
        ).toList(),
      );

      // ---------------------------------------------------------
      // Ghi từng HKD.
      // ---------------------------------------------------------

      for (final doc in documents) {
        final data = doc.data();

        final rawAnswers =
        data['surveyAnswers'];

        final answers =
        rawAnswers is Map
            ? Map<String, dynamic>.from(rawAnswers)
            : <String, dynamic>{};

        final row = <String>[
          data['tenHoKinhDoanh']?.toString() ??
              data['tenHKD']?.toString() ??
              data['ten']?.toString() ??
              '',
          data['mstCccd']?.toString() ?? '',
          data['soDienThoai']?.toString() ?? '',
          data['diaChi']?.toString() ?? '',
          data['tinhThanh']?.toString() ?? '',
          data['phuongXa']?.toString() ?? '',
          _excelValue(data['latitude']),
          _excelValue(data['longitude']),
        ];

        for (final question in questionColumns) {
          final id = question['id']!;

          row.add(
            _excelValue(
              answers[id],
            ),
          );
        }

        row.add(
          data['surveyTemplateId']?.toString() ??
              templateId,
        );

        row.add(
          data['surveyName']?.toString() ??
              formName,
        );

        row.add(doc.id);

        sheet.appendRow(
          row.map(
                (value) => TextCellValue(value),
          ).toList(),
        );
      }

      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(
          i,
          i < 8 ? 20 : 25,
        );
      }

      final bytes = excel.save();

      if (bytes == null || bytes.isEmpty) {
        throw Exception(
          'Không thể tạo file Excel.',
        );
      }

      await _saveAndShareExcel(
        bytes,
        'VNPT_KhaoSat_${_safeExcelFileName(formName)}',
        'Dữ liệu khảo sát - $formName',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessageDialog(
        'Xuất Excel thất bại',
        'Không thể xuất dữ liệu của Form "$formName".\n\n$e',
      );
    }
  }

  Future<void> _createAndShareExcel({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    required String filePrefix,
    required String shareTitle,
    required String sheetName,
  }) async {
    try {
      final keySet = <String>{};

      for (final doc in documents) {
        keySet.addAll(doc.data().keys);
      }

      const priorityKeys = <String>[
        'tenHoKinhDoanh',
        'tenHKD',
        'ten',
        'mstCccd',
        'chuHoKinhDoanh',
        'matHangKinhDoanh',
        'soDienThoai',
        'diaChi',
        'tinhThanh',
        'tinhThanhCode',
        'phuongXa',
        'phuongXaCode',
        'latitude',
        'longitude',
        'doanhThu',
        'soNguoi',
        'dichVuDangSuDung',
        'nhaCungCap',
        'congCuSo',
        'checkboxData',
        'surveyMode',
        'surveyTemplateId',
        'surveyName',
        'surveyVersion',
        'surveyAnswers',
        'daKhaoSat',
        'createdBy',
        'createdByUid',
        'createdAt',
        'updatedAt',
        'surveyedAt',
      ];

      final headers = <String>[
        ...priorityKeys.where(keySet.contains),
        ...keySet
            .where(
              (key) => !priorityKeys.contains(key),
        )
            .toList()
          ..sort(),
        'documentId',
      ];

      final excel = Excel.createExcel();

      excel.rename(
        'Sheet1',
        sheetName,
      );

      final sheet = excel[sheetName];

      sheet.appendRow(
        headers.map(
              (header) => TextCellValue(header),
        ).toList(),
      );

      for (final doc in documents) {
        final data = doc.data();

        final row = headers.map(
              (header) {
            if (header == 'documentId') {
              return TextCellValue(doc.id);
            }

            return TextCellValue(
              _excelValue(data[header]),
            );
          },
        ).toList();

        sheet.appendRow(row);
      }

      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 20);
      }

      final bytes = excel.save();

      if (bytes == null || bytes.isEmpty) {
        throw Exception(
          'Không thể tạo file Excel.',
        );
      }

      await _saveAndShareExcel(
        bytes,
        filePrefix,
        shareTitle,
      );
    } catch (e) {
      if (!mounted) return;

      _showMessageDialog(
        'Xuất Excel thất bại',
        'Không thể tạo file Excel.\n\nChi tiết: $e',
      );
    }
  }

  Future<void> _saveAndShareExcel(
      List<int> bytes,
      String fileNamePrefix,
      String title,
      ) async {
    final downloadsDir =
    await getDownloadsDirectory();

    final Directory targetDir =
        downloadsDir ??
            await getApplicationDocumentsDirectory();

    if (!await targetDir.exists()) {
      await targetDir.create(
        recursive: true,
      );
    }

    final now = DateTime.now();

    final fileName =
        '${fileNamePrefix}_'
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}.xlsx';

    final file = File(
      '${targetDir.path}/$fileName',
    );

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    if (!mounted) return;

    await SharePlus.instance.share(
      ShareParams(
        title: title,
        text: title,
        files: [
          XFile(
            file.path,
            mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã tạo file Excel: $fileName',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _safeExcelFileName(String value) {
    final result = value
        .replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    )
        .trim();

    return result.isEmpty ? 'Form' : result;
  }

  String _excelValue(dynamic value) {
    if (value == null) return '';

    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}:'
          '${date.second.toString().padLeft(2, '0')}';
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is List || value is Map) {
      return jsonEncode(value);
    }

    return value.toString();
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomePage(),
          const SurveyScreen(),
          _buildMapPage(),
          _buildProfilePage(),
        ],
      ),

      // =====================================================
      // BOTTOM NAVIGATION
      // =====================================================

      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
                (states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: vnptBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                );
              }
              return const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              );
            },
          ),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
                (states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(
                  color: vnptBlue,
                  size: 24,
                );
              }
              return const IconThemeData(
                color: Colors.white,
                size: 24,
              );
            },
          ),
        ),
        child: NavigationBar(
          height: 72,
          backgroundColor: vnptBlue,
          elevation: 8,

          selectedIndex: _selectedIndex,

          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },

          indicatorColor: Colors.white,

          labelBehavior:
          NavigationDestinationLabelBehavior.alwaysShow,

          destinations: const [
            NavigationDestination(
              icon: Icon(
                Icons.home_outlined,
                color: Colors.white,
              ),
              selectedIcon: Icon(
                Icons.home_rounded,
                color: vnptBlue,
              ),
              label: 'Trang chủ',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.assignment_outlined,
                color: Colors.white,
              ),
              selectedIcon: Icon(
                Icons.assignment_rounded,
                color: vnptBlue,
              ),
              label: 'Khảo sát',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.map_outlined,
                color: Colors.white,
              ),
              selectedIcon: Icon(
                Icons.map_rounded,
                color: vnptBlue,
              ),
              label: 'Bản đồ',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.person_outline_rounded,
                color: Colors.white,
              ),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: vnptBlue,
              ),
              label: 'Cá nhân',
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // HOME PAGE
  // =========================================================

  Widget _buildHomePage() {
    final User? user =
        FirebaseAuth.instance.currentUser;

    final String displayName =
    user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email ?? 'Tài khoản');

    return Stack(
      children: [
        // =================================================
        // HÌNH NỀN HOME
        // =================================================
        Positioned.fill(
          child: Image.asset(
            'assets/images/back.jpg',
            fit: BoxFit.cover,
          ),
        ),

        // Lớp phủ trắng nhẹ để chữ/card vẫn dễ nhìn.
        Positioned.fill(
          child: Container(
            color: Colors.white.withOpacity(0.72),
          ),
        ),

        // =================================================
        // NỘI DUNG HOME
        // =================================================
        SafeArea(
          child: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              _buildHeader(displayName),

              // =================================================
              // DATA FIRESTORE
              // =================================================

              Expanded(
                child: StreamBuilder<
                    QuerySnapshot<Map<String, dynamic>>>(
                  stream: _businessQuery.snapshots(),

                  builder: (context, snapshot) {
                    // -------------------------------------------
                    // ĐANG TẢI
                    // -------------------------------------------

                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: vnptBlue,
                        ),
                      );
                    }

                    // -------------------------------------------
                    // LỖI
                    // -------------------------------------------

                    if (snapshot.hasError) {
                      return _buildFirestoreError(
                        snapshot.error.toString(),
                      );
                    }

                    // -------------------------------------------
                    // DỮ LIỆU
                    // -------------------------------------------

                    final documents =
                        snapshot.data?.docs ?? [];

                    if (_roleLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: vnptBlue,
                        ),
                      );
                    }

                    return _isAdmin
                        ? _buildAdminHomeContent(documents)
                        : _buildHomeContent(documents);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(
      String displayName,
      ) {
    return Container(
      height: 76,

      padding: const EdgeInsets.fromLTRB(
        14,
        8,
        8,
        8,
      ),

      // Header hòa chung với background back.jpg.
      color: Colors.transparent,

      child: Row(
        children: [
          // =================================================
          // AVATAR - XANH VNPT
          // =================================================

          Container(
            width: 40,
            height: 40,

            decoration: const BoxDecoration(
              color: vnptBlue,
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(width: 9),

          // =================================================
          // TÊN TÀI KHOẢN - HÒA VỚI BACKGROUND
          // =================================================

          if (!_searching)
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                mainAxisAlignment:
                MainAxisAlignment.center,

                children: [
                  const Text(
                    'Xin chào!',

                    style: TextStyle(
                      color: textDark,
                      fontSize: 10.5,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    displayName,

                    maxLines: 1,

                    overflow:
                    TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: textDark,
                      fontSize: 13.5,
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

          // =================================================
          // THANH TÌM KIẾM KHI BẤM ICON
          // =================================================

          if (_searching)
            Expanded(
              child: Container(
                height: 43,

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),

                  borderRadius:
                  BorderRadius.circular(13),
                ),

                child: TextField(
                  controller:
                  _searchController,

                  autofocus: true,

                  onChanged: (value) {
                    setState(() {
                      _searchText =
                          value.trim().toLowerCase();
                    });
                  },

                  textInputAction:
                  TextInputAction.search,

                  style: const TextStyle(
                    fontSize: 13,
                    color: textDark,
                  ),

                  decoration:
                  const InputDecoration(
                    hintText:
                    'Tìm kiếm hộ kinh doanh...',

                    hintStyle:
                    TextStyle(
                      color:
                      Color(0xFF9AA3AF),
                      fontSize: 12,
                    ),

                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: vnptBlue,
                      size: 21,
                    ),

                    border:
                    InputBorder.none,

                    contentPadding:
                    EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(width: 4),

          // =================================================
          // ICON TÌM KIẾM - TRẮNG
          // =================================================

          if (!_searching)
            IconButton(
              tooltip: 'Tìm kiếm',

              onPressed: () {
                setState(() {
                  _searching = true;
                });
              },

              icon: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: vnptBlue,
                  size: 22,
                ),
              ),
            ),

          // =================================================
          // ICON ĐÓNG TÌM KIẾM - TRẮNG
          // =================================================

          if (_searching)
            IconButton(
              tooltip: 'Đóng tìm kiếm',

              onPressed: () {
                _searchController.clear();

                setState(() {
                  _searchText = '';
                  _searching = false;
                });
              },

              icon: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: vnptBlue,
                  size: 21,
                ),
              ),
            ),

          // =================================================
          // THÔNG BÁO - TRẮNG
          // =================================================

          IconButton(
            tooltip: 'Thông báo',

            onPressed: () {
              _showMessageDialog(
                'Thông báo',
                'Hiện tại bạn chưa có thông báo mới.',
              );
            },

            icon: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: vnptBlue,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ADMIN HOME CONTENT
  // =========================================================

  Widget _buildAdminHomeContent(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
      ) {
    final total = documents.length;
    final today = _countToday(documents);
    final week = _countThisWeek(documents);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 21, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.bar_chart_rounded,
            'TỔNG QUAN',
          ),
          const SizedBox(height: 11),

          _overviewCard(total, today, week),

          const SizedBox(height: 25),

          _sectionTitle(
            Icons.manage_accounts_rounded,
            'QUẢN LÝ NHÂN VIÊN',
          ),
          const SizedBox(height: 11),

          _wideFunctionCard(
            icon: Icons.manage_accounts_rounded,
            title: 'Quản lý nhân viên',
            subtitle: 'Thêm, xem, khóa và xóa tài khoản nhân viên',
            color: vnptBlue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminManagementScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 25),

          _sectionTitle(
            Icons.assignment_rounded,
            'QUẢN LÝ BỘ KHẢO SÁT',
          ),
          const SizedBox(height: 11),

          _wideFunctionCard(
            icon: Icons.assignment_rounded,
            title: 'Quản lý bộ khảo sát',
            subtitle:
            'Tạo, chỉnh sửa, xuất bản và áp dụng bộ câu hỏi cho nhân viên',
            color: vnptBlue,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                  const AdminSurveyManagementScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 25),

          _sectionTitle(
            Icons.edit_note_rounded,
            'NHẬP HỘ KINH DOANH',
          ),
          const SizedBox(height: 11),

          _wideFunctionCard(
            icon: Icons.edit_note_rounded,
            title: 'Nhập HKD',
            subtitle: 'Thêm hộ kinh doanh mới',
            color: vnptBlue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddBusinessScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          _wideFunctionCard(
            icon: Icons.table_chart_rounded,
            title: 'Xuất Excel',
            subtitle: 'Xuất toàn bộ dữ liệu khảo sát',
            color: vnptBlue,
            onTap: () => _exportExcel(documents),
          ),

          const SizedBox(height: 12),

          _wideFunctionCard(
            icon: Icons.file_upload_rounded,
            title: 'Nhập Excel',
            subtitle: 'Đọc tất cả sheet và nhập HKD vào Firebase',
            color: vnptBlue,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminExcelImportScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }



  // =========================================================
  // HOME CONTENT
  // =========================================================

  Widget _buildHomeContent(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    // =======================================================
    // LỌC TÌM KIẾM
    // =======================================================

    final List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    filteredDocuments =
    documents.where((doc) {
      if (_searchText.isEmpty) {
        return true;
      }

      final data = doc.data();

      final String name =
          data['tenHoKinhDoanh']
              ?.toString()
              .toLowerCase() ??
              '';

      final String tenHKD =
          data['tenHKD']
              ?.toString()
              .toLowerCase() ??
              '';

      final String ten =
          data['ten']
              ?.toString()
              .toLowerCase() ??
              '';

      final String address =
          data['diaChi']
              ?.toString()
              .toLowerCase() ??
              '';

      return name.contains(_searchText) ||
          tenHKD.contains(_searchText) ||
          ten.contains(_searchText) ||
          address.contains(_searchText);
    }).toList();

    // =======================================================
    // TỔNG QUAN
    // =======================================================

    final int total =
        filteredDocuments.length;

    final int today =
    _countToday(
      filteredDocuments,
    );

    final int week =
    _countThisWeek(
      filteredDocuments,
    );

    // =======================================================
    // BIỂU ĐỒ
    // =======================================================

    final List<int> chartData =
    _getSevenDayData(
      filteredDocuments,
    );

    // =======================================================
    // KHẢO SÁT GẦN ĐÂY
    // =======================================================

    final List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    recent =
    _getRecentDocuments(
      filteredDocuments,
    );

    // =======================================================
    // GIAO DIỆN
    // =======================================================

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // =================================================
          // TIÊU ĐỀ
          // =================================================

          Center(
            child: Column(
              children: [
                const Text(
                  'QUẢN LÝ HỘ KINH DOANH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: vnptBlue,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Theo dõi và quản lý dữ liệu khảo sát',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // =================================================
          // BIỂU ĐỒ - ĐƯA LÊN NGAY SAU HEADER
          // =================================================

          _sectionTitle(
            Icons.show_chart_rounded,
            'TIẾN ĐỘ KHẢO SÁT',
          ),

          const SizedBox(height: 10),

          _chartCard(chartData),

          const SizedBox(height: 22),

          // =================================================
          // TỔNG QUAN
          // =================================================

          _sectionTitle(
            Icons.bar_chart_rounded,
            'TỔNG QUAN',
          ),

          const SizedBox(height: 10),

          _overviewCard(
            total,
            today,
            week,
          ),

          const SizedBox(height: 22),

          // =================================================
          // CHỨC NĂNG
          // =================================================

          _sectionTitle(
            Icons.apps_rounded,
            'CHỨC NĂNG',
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _functionCard(
                  icon: Icons.edit_note_rounded,
                  title: 'Nhập HKD',
                  subtitle: 'Thêm hộ kinh doanh',
                  color: vnptBlue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddBusinessScreen(),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _functionCard(
                  icon: Icons.map_rounded,
                  title: 'Bản đồ HKD',
                  subtitle: 'Xem vị trí HKD',
                  color: vnptBlue,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 2;
                    });
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // =================================================
          // KHẢO SÁT GẦN ĐÂY
          // =================================================

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle(
                Icons.assignment_rounded,
                'KHẢO SÁT GẦN ĐÂY',
              ),

              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedIndex = 1;
                  });
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: vnptBlue,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          _recentSurveyCard(recent),
        ],
      ),
    );
  }

  // =========================================================
  // SECTION TITLE
  // =========================================================

  Widget _sectionTitle(
      IconData icon,
      String title,
      ) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,

          decoration:
          BoxDecoration(
            color: vnptLightBlue,

            borderRadius:
            BorderRadius.circular(9),
          ),

          child: Icon(
            icon,
            color: vnptBlue,
            size: 18,
          ),
        ),

        const SizedBox(width: 9),

        Text(
          title,

          style:
          const TextStyle(
            color: vnptBlue,
            fontSize: 15,
            fontWeight:
            FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // OVERVIEW CARD
  // =========================================================

  Widget _overviewCard(
      int total,
      int today,
      int week,
      ) {
    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 5,
      ),

      decoration:
      BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(19),

        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.035),

            blurRadius: 14,

            offset:
            const Offset(0, 5),
          ),
        ],
      ),

      child: Row(
        children: [
          Expanded(
            child: _overviewItem(
              total.toString(),
              'Tổng HKD',
              Icons.storefront_rounded,
            ),
          ),

          _verticalDivider(),

          Expanded(
            child: _overviewItem(
              today.toString(),
              'Hôm nay',
              Icons.today_rounded,
            ),
          ),

          _verticalDivider(),

          Expanded(
            child: _overviewItem(
              week.toString(),
              'Tuần này',
              Icons.date_range_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // OVERVIEW ITEM
  // =========================================================

  Widget _overviewItem(
      String value,
      String title,
      IconData icon,
      ) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,

          decoration:
          BoxDecoration(
            color: vnptLightBlue,

            borderRadius:
            BorderRadius.circular(10),
          ),

          child: Icon(
            icon,
            color: vnptBlue,
            size: 18,
          ),
        ),

        const SizedBox(height: 7),

        Text(
          value,

          style:
          const TextStyle(
            color: textDark,
            fontSize: 22,
            fontWeight:
            FontWeight.w800,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          title,

          style:
          const TextStyle(
            color: textLightGrey,
            fontSize: 11.5,
            fontWeight:
            FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // VERTICAL DIVIDER
  // =========================================================

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 68,

      color:
      const Color(0xFFE7EBF0),
    );
  }

  // =========================================================
  // FUNCTION CARD
  // =========================================================

  Widget _functionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        borderRadius:
        BorderRadius.circular(18),

        child: Ink(
          height: 132,

          decoration:
          BoxDecoration(
            color: Colors.white,

            borderRadius:
            BorderRadius.circular(18),

            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.035),

                blurRadius: 12,

                offset:
                const Offset(0, 4),
              ),
            ],
          ),

          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,

            children: [
              Container(
                width: 52,
                height: 52,

                decoration:
                BoxDecoration(
                  color:
                  color.withOpacity(
                    0.10,
                  ),

                  shape:
                  BoxShape.circle,
                ),

                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                title,

                style:
                const TextStyle(
                  color: textDark,
                  fontSize: 14,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,

                style:
                const TextStyle(
                  color:
                  textLightGrey,
                  fontSize: 10.5,
                  fontWeight:
                  FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // WIDE FUNCTION CARD
  // =========================================================

  Widget _wideFunctionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,

        borderRadius:
        BorderRadius.circular(18),

        child: Ink(
          width: double.infinity,

          height: 72,

          decoration:
          BoxDecoration(
            color: Colors.white,

            borderRadius:
            BorderRadius.circular(18),

            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.03),

                blurRadius: 10,

                offset:
                const Offset(0, 3),
              ),
            ],
          ),

          child: Row(
            children: [
              const SizedBox(width: 15),

              Container(
                width: 45,
                height: 45,

                decoration:
                BoxDecoration(
                  color:
                  color.withOpacity(
                    0.10,
                  ),

                  shape:
                  BoxShape.circle,
                ),

                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [
                    Text(
                      title,

                      style:
                      const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      subtitle,

                      style:
                      const TextStyle(
                        color:
                        textLightGrey,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons
                    .chevron_right_rounded,

                color: vnptBlue,

                size: 24,
              ),

              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // BIỂU ĐỒ 7 NGÀY
  // =========================================================

  Widget _chartCard(
      List<int> values,
      ) {
    int maxValue = 1;

    for (final value in values) {
      if (value > maxValue) {
        maxValue = value;
      }
    }

    final DateTime now =
    DateTime.now();

    final List<String> labels = [];

    for (int i = 6; i >= 0; i--) {
      final DateTime date =
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(
        Duration(days: i),
      );

      labels.add(
        '${date.day}/${date.month}',
      );
    }

    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.fromLTRB(
        15,
        16,
        15,
        13,
      ),

      decoration:
      BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(19),

        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.035),

            blurRadius: 14,

            offset:
            const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Số HKD được khảo sát',

                  style:
                  TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w500,
                  ),
                ),
              ),

              Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),

                decoration:
                BoxDecoration(
                  color: vnptLightBlue,

                  borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
                ),

                child: const Text(
                  '7 ngày',

                  style:
                  TextStyle(
                    color: vnptBlue,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 155,

            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.end,

              children:
              List.generate(
                7,
                    (index) {
                  final int value =
                  values[index];

                  final double barHeight =
                  value == 0
                      ? 4
                      : 100 *
                      value /
                      maxValue;

                  return Expanded(
                    child: Padding(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 3,
                      ),

                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment
                            .end,

                        children: [
                          Text(
                            value.toString(),

                            style:
                            const TextStyle(
                              color: textGrey,
                              fontSize: 10,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),

                          const SizedBox(
                            height: 4,
                          ),

                          AnimatedContainer(
                            duration:
                            const Duration(
                              milliseconds: 400,
                            ),

                            height:
                            barHeight,

                            width:
                            double.infinity,

                            decoration:
                            BoxDecoration(
                              color: vnptBlue,

                              borderRadius:
                              BorderRadius
                                  .circular(
                                7,
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 7,
                          ),

                          Text(
                            labels[index],

                            style:
                            const TextStyle(
                              color:
                              textLightGrey,
                              fontSize: 9,
                              fontWeight:
                              FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // KHẢO SÁT GẦN ĐÂY
  // =========================================================

  Widget _recentSurveyCard(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    if (documents.isEmpty) {
      return Container(
        width: double.infinity,

        padding:
        const EdgeInsets.symmetric(
          vertical: 28,
          horizontal: 20,
        ),

        decoration:
        BoxDecoration(
          color: Colors.white,

          borderRadius:
          BorderRadius.circular(19),
        ),

        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,

              decoration:
              const BoxDecoration(
                color: vnptLightBlue,
                shape:
                BoxShape.circle,
              ),

              child: const Icon(
                Icons.assignment_outlined,
                color: vnptBlue,
                size: 27,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Chưa có dữ liệu khảo sát',

              style:
              TextStyle(
                color: textGrey,
                fontSize: 13,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 6,
      ),

      decoration:
      BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(19),

        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.025),

            blurRadius: 10,

            offset:
            const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        children: List.generate(
          documents.length,
              (index) {
            final data =
            documents[index].data();

            final String name =
                data['tenHoKinhDoanh']
                    ?.toString() ??
                    data['tenHKD']
                        ?.toString() ??
                    data['ten']
                        ?.toString() ??
                    'Hộ kinh doanh';

            final String address =
                data['diaChi']
                    ?.toString() ??
                    'Đã khảo sát';

            final Timestamp? timestamp =
            data['createdAt']
            as Timestamp?;

            String time = '--:--';

            if (timestamp != null) {
              final DateTime date =
              timestamp.toDate();

              time =
              '${date.hour.toString().padLeft(2, '0')}:'
                  '${date.minute.toString().padLeft(2, '0')}';
            }

            return Column(
              children: [
                _surveyItem(
                  name,
                  address,
                  time,
                ),

                if (index <
                    documents.length - 1)
                  const Divider(
                    height: 1,
                    color:
                    Color(0xFFF0F2F5),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // =========================================================
  // SURVEY ITEM
  // =========================================================

  String _displayBusinessName(Map<String, dynamic> data) {
    final legacy = [
      data['tenHoKinhDoanh'],
      data['tenHKD'],
      data['ten'],
      data['name'],
    ];

    for (final value in legacy) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }

    final answers = data['surveyAnswers'];
    if (answers is Map) {
      for (final entry in answers.entries) {
        final text = entry.value?.toString().trim() ?? '';
        if (text.isNotEmpty && text != 'null') {
          return text;
        }
      }
    }

    return 'Hộ kinh doanh';
  }

  Widget _surveyItem(
      String name,
      String address,
      String time,
      ) {
    return SizedBox(
      height: 68,

      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,

            decoration:
            const BoxDecoration(
              color: vnptLightBlue,
              shape:
              BoxShape.circle,
            ),

            child: const Icon(
              Icons.storefront_rounded,
              color: vnptBlue,
              size: 20,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              mainAxisAlignment:
              MainAxisAlignment.center,

              children: [
                Text(
                  name,

                  maxLines: 1,

                  overflow:
                  TextOverflow.ellipsis,

                  style:
                  const TextStyle(
                    color: textDark,
                    fontSize: 13.5,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  address,

                  maxLines: 1,

                  overflow:
                  TextOverflow.ellipsis,

                  style:
                  const TextStyle(
                    color:
                    textLightGrey,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Text(
            time,

            style:
            const TextStyle(
              color:
              textLightGrey,
              fontSize: 11,
              fontWeight:
              FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ĐẾM HÔM NAY
  // =========================================================

  int _countToday(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    final DateTime now =
    DateTime.now();

    int count = 0;

    for (final doc in documents) {
      final Timestamp? timestamp =
      doc.data()['createdAt']
      as Timestamp?;

      if (timestamp == null) {
        continue;
      }

      final DateTime date =
      timestamp.toDate();

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        count++;
      }
    }

    return count;
  }

  // =========================================================
  // ĐẾM TUẦN NÀY
  // =========================================================

  int _countThisWeek(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    final DateTime now =
    DateTime.now();

    final DateTime startOfWeek =
    DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(
      Duration(
        days: now.weekday - 1,
      ),
    );

    int count = 0;

    for (final doc in documents) {
      final Timestamp? timestamp =
      doc.data()['createdAt']
      as Timestamp?;

      if (timestamp == null) {
        continue;
      }

      final DateTime date =
      timestamp.toDate();

      if (!date.isBefore(
        startOfWeek,
      )) {
        count++;
      }
    }

    return count;
  }

  // =========================================================
  // DỮ LIỆU BIỂU ĐỒ 7 NGÀY
  // =========================================================

  List<int> _getSevenDayData(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    final DateTime now =
    DateTime.now();

    final List<int> result = [];

    for (int i = 6; i >= 0; i--) {
      final DateTime target =
      DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(
        Duration(days: i),
      );

      int count = 0;

      for (final doc in documents) {
        final Timestamp? timestamp =
        doc.data()['createdAt']
        as Timestamp?;

        if (timestamp == null) {
          continue;
        }

        final DateTime date =
        timestamp.toDate();

        if (date.year ==
            target.year &&
            date.month ==
                target.month &&
            date.day ==
                target.day) {
          count++;
        }
      }

      result.add(count);
    }

    return result;
  }

  // =========================================================
  // LẤY KHẢO SÁT GẦN ĐÂY
  // =========================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _getRecentDocuments(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
      documents,
      ) {
    final List<
        QueryDocumentSnapshot<
            Map<String, dynamic>>>
    result =
    [...documents];

    result.sort(
          (a, b) {
        final Timestamp? timeA =
        a.data()['createdAt']
        as Timestamp?;

        final Timestamp? timeB =
        b.data()['createdAt']
        as Timestamp?;

        if (timeA == null &&
            timeB == null) {
          return 0;
        }

        if (timeA == null) {
          return 1;
        }

        if (timeB == null) {
          return -1;
        }

        return timeB.compareTo(
          timeA,
        );
      },
    );

    return result
        .take(4)
        .toList();
  }

  // =========================================================
  // TRANG KHẢO SÁT
  // =========================================================

  Widget _buildSurveyPage() {
    return SafeArea(
      child: Column(
        children: [
          _buildSimplePageHeader(
            'KHẢO SÁT',
            Icons.assignment_rounded,
          ),

          Expanded(
            child: StreamBuilder<
                QuerySnapshot<
                    Map<String, dynamic>>>(
              stream:
              _businessQuery.snapshots(),

              builder:
                  (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child:
                    CircularProgressIndicator(
                      color: vnptBlue,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildFirestoreError(
                    snapshot.error.toString(),
                  );
                }

                final docs =
                    snapshot.data?.docs ??
                        [];

                if (docs.isEmpty) {
                  return _emptyPage(
                    Icons.assignment_outlined,
                    'Chưa có khảo sát',
                    'Các hộ kinh doanh sau khi được lưu sẽ hiển thị tại đây.',
                  );
                }

                final recent =
                _getRecentDocuments(
                  docs,
                );

                return ListView.separated(
                  padding:
                  const EdgeInsets.all(
                    16,
                  ),

                  itemCount:
                  recent.length,

                  separatorBuilder:
                      (_, __) =>
                  const SizedBox(
                    height: 10,
                  ),

                  itemBuilder:
                      (context, index) {
                    final data =
                    recent[index]
                        .data();

                    final String name =
                        data['tenHoKinhDoanh']
                            ?.toString() ??
                            data['tenHKD']
                                ?.toString() ??
                            data['ten']
                                ?.toString() ??
                            'Hộ kinh doanh';

                    final String address =
                        data['diaChi']
                            ?.toString() ??
                            'Chưa có địa chỉ';

                    return _surveyListCard(
                      name,
                      address,
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

  // =========================================================
  // TRANG BẢN ĐỒ
  // =========================================================

  Widget _buildMapPage() {
    return const MapScreen();
  }

  // =========================================================
  // HEADER TRANG CON
  // =========================================================

  Widget _buildSimplePageHeader(
      String title,
      IconData icon,
      ) {
    return Container(
      height: 68,

      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
      ),

      decoration:
      const BoxDecoration(
        color: Colors.white,

      ),

      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,

            decoration:
            const BoxDecoration(
              color: vnptLightBlue,
              shape:
              BoxShape.circle,
            ),

            child: Icon(
              icon,
              color: vnptBlue,
              size: 21,
            ),
          ),

          const SizedBox(width: 11),

          Text(
            title,

            style:
            const TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight:
              FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TRANG CÁ NHÂN
  // =========================================================

  Widget _buildProfilePage() {
    final User? user = FirebaseAuth.instance.currentUser;

    final String name =
    user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Tài khoản';

    final String email = user?.email ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 30),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: vnptLightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: vnptBlue,
                size: 50,
              ),
            ),

            const SizedBox(height: 13),

            Text(
              name,
              style: const TextStyle(
                color: textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              email,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 30),

            _profileItem(
              Icons.manage_accounts_rounded,
              'Thông tin tài khoản',
              _showAccountInfo,
            ),

            const SizedBox(height: 10),

            _profileItem(
              Icons.lock_reset_rounded,
              'Đổi mật khẩu',
              _showChangePassword,
            ),

            const SizedBox(height: 10),

            _profileItem(
              Icons.settings_rounded,
              'Cài đặt',
              _showSettings,
            ),

            const SizedBox(height: 10),

            _profileItem(
              Icons.logout_rounded,
              'Đăng xuất',
              _showLogoutDialog,
              isLogout: true,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // PROFILE ITEM
  // Không dùng dấu > theo yêu cầu.
  // =========================================================

  Widget _profileItem(
      IconData icon,
      String title,
      VoidCallback onTap, {
        bool isLogout = false,
      }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: vnptLightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: vnptBlue,
                  size: 21,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isLogout ? vnptBlue : textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // THÔNG TIN TÀI KHOẢN
  // =========================================================

  void _showAccountInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AccountInfoPage(
          onSaved: () {
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }

  // =========================================================
  // ĐỔI MẬT KHẨU
  // =========================================================

  void _showChangePassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _ChangePasswordPage(),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: vnptBlue,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: textGrey,
          ),
        ),
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD9DEE7),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // =========================================================
  // CÀI ĐẶT
  // =========================================================

  void _showSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _SettingsPage(),
      ),
    );
  }

  Widget _settingsItem(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
      ) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: vnptLightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: vnptBlue,
                  size: 21,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: textLightGrey,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // SURVEY LIST CARD
  // =========================================================

  Widget _surveyListCard(
      String name,
      String address,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(15),

      decoration:
      BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(17),
      ),

      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,

            decoration:
            const BoxDecoration(
              color: vnptLightBlue,
              shape:
              BoxShape.circle,
            ),

            child: const Icon(
              Icons.storefront_rounded,
              color: vnptBlue,
              size: 23,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  name,

                  maxLines: 1,

                  overflow:
                  TextOverflow.ellipsis,

                  style:
                  const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  address,

                  maxLines: 1,

                  overflow:
                  TextOverflow.ellipsis,

                  style:
                  const TextStyle(
                    color:
                    textLightGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.chevron_right_rounded,
            color:
            Color(0xFFB0B8C4),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // EMPTY PAGE
  // =========================================================

  Widget _emptyPage(
      IconData icon,
      String title,
      String message,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [
            Container(
              width: 82,
              height: 82,

              decoration:
              const BoxDecoration(
                color: vnptLightBlue,
                shape:
                BoxShape.circle,
              ),

              child: Icon(
                icon,
                color: vnptBlue,
                size: 42,
              ),
            ),

            const SizedBox(
              height: 17,
            ),

            Text(
              title,

              textAlign:
              TextAlign.center,

              style:
              const TextStyle(
                color: textDark,
                fontSize: 19,
                fontWeight:
                FontWeight.w800,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              message,

              textAlign:
              TextAlign.center,

              style:
              const TextStyle(
                color: textGrey,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // FIRESTORE ERROR
  // =========================================================

  Widget _buildFirestoreError(
      String error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(25),

        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [
            Container(
              width: 70,
              height: 70,

              decoration:
              BoxDecoration(
                color:
                Colors.red.withOpacity(
                  0.08,
                ),

                shape:
                BoxShape.circle,
              ),

              child: const Icon(
                Icons.cloud_off_rounded,
                size: 35,
                color: vnptBlue,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            const Text(
              'Không thể tải dữ liệu',

              textAlign:
              TextAlign.center,

              style:
              TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              error,

              textAlign:
              TextAlign.center,

              style:
              const TextStyle(
                color: textGrey,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // MESSAGE DIALOG
  // =========================================================

  void _showMessageDialog(
      String title,
      String message,
      ) {
    showDialog(
      context: context,

      builder: (context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(20),
          ),

          title: Text(
            title,

            style:
            const TextStyle(
              color: textDark,
              fontSize: 20,
              fontWeight:
              FontWeight.w700,
            ),
          ),

          content: Text(
            message,

            style:
            const TextStyle(
              color: textGrey,
              fontSize: 14,
              height: 1.45,
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                );
              },

              child: const Text(
                'Đóng',

                style:
                TextStyle(
                  color: vnptBlue,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  void _showLogoutDialog() {
    showDialog(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(24),
          ),

          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration:
                BoxDecoration(
                  color:
                  Colors.red.withOpacity(
                    0.10,
                  ),

                  shape:
                  BoxShape.circle,
                ),

                child: const Icon(
                  Icons.logout_rounded,
                  color: vnptBlue,
                ),
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Text(
                  'Đăng xuất',

                  style:
                  TextStyle(
                    fontSize: 20,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          content: const Text(
            'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này?',

            style:
            TextStyle(
              fontSize: 14,
              height: 1.4,
              color: textGrey,
            ),
          ),

          actionsPadding:
          const EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18,
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },

              child: const Text(
                'Hủy',

                style:
                TextStyle(
                  color: Colors.grey,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ),

            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth
                    .instance
                    .signOut();

                if (!mounted) {
                  return;
                }

                Navigator.of(context)
                    .pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) =>
                    const LoginScreen(),
                  ),
                      (route) => false,
                );
              },

              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                Colors.red,

                foregroundColor:
                Colors.white,

                elevation: 0,

                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              child: const Text(
                'Đăng xuất',

                style:
                TextStyle(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================
// TRANG THÔNG TIN TÀI KHOẢN
// Dùng route riêng, không dùng BottomSheet/Overlay.
// =============================================================

class _AccountInfoPage extends StatefulWidget {
  final VoidCallback? onSaved;

  const _AccountInfoPage({this.onSaved});

  @override
  State<_AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<_AccountInfoPage> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(
      text: user?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    if (name.isEmpty) {
      _message('Vui lòng nhập tên tài khoản.');
      return;
    }

    setState(() => _saving = true);

    try {
      // Cập nhật Firebase Authentication.
      await user.updateDisplayName(name);
      await user.reload();

      // Đồng bộ tên vào Firestore nhưng giữ nguyên role.
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final currentDoc = await userDoc.get();
      final currentData = currentDoc.data() ?? <String, dynamic>{};

      await userDoc.set(
        {
          'displayName': name,
          'email': user.email,
          'role': currentData['role'] ?? 'employee',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      widget.onSaved?.call();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật thông tin tài khoản.'),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(
        e.code == 'permission-denied'
            ? 'Không có quyền cập nhật thông tin tài khoản.'
            : 'Không thể cập nhật thông tin: ${e.message ?? e.code}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message('Không thể cập nhật thông tin: $e');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        title: const Text(
          'Thông tin tài khoản',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  color: vnptLightBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: vnptBlue,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Tên tài khoản',
              style: TextStyle(
                color: textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),

            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.person_outline_rounded,
                  color: vnptBlue,
                ),
                hintText: 'Nhập tên tài khoản',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Email',
              style: TextStyle(
                color: textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.email_outlined,
                    color: vnptBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user?.email ?? 'Chưa có email',
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: vnptBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  'Lưu thay đổi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// =============================================================
// TRANG ĐỔI MẬT KHẨU
// Không dùng BottomSheet.
// =============================================================

class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage();

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentController.text;
    final newPassword = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      _message('Vui lòng nhập đầy đủ thông tin.');
      return;
    }

    if (newPassword.length < 6) {
      _message('Mật khẩu mới phải có ít nhất 6 ký tự.');
      return;
    }

    if (newPassword != confirm) {
      _message('Mật khẩu xác nhận không khớp.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) {
      _message('Không tìm thấy tài khoản đang đăng nhập.');
      return;
    }

    setState(() => _saving = true);

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đổi mật khẩu thành công.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      String message = 'Không thể đổi mật khẩu.';

      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Mật khẩu hiện tại không đúng.';
          break;
        case 'weak-password':
          message = 'Mật khẩu mới quá yếu.';
          break;
        case 'requires-recent-login':
          message =
          'Phiên đăng nhập đã cũ. Vui lòng đăng nhập lại rồi thử lại.';
          break;
        case 'user-mismatch':
          message = 'Tài khoản xác thực không khớp.';
          break;
      }

      _message(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message('Lỗi: $e');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: vnptBlue,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: textGrey,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        title: const Text(
          'Đổi mật khẩu',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),

            _passwordField(
              controller: _currentController,
              label: 'Mật khẩu hiện tại',
              obscure: _obscureCurrent,
              onToggle: () {
                setState(() => _obscureCurrent = !_obscureCurrent);
              },
            ),

            const SizedBox(height: 14),

            _passwordField(
              controller: _newController,
              label: 'Mật khẩu mới',
              obscure: _obscureNew,
              onToggle: () {
                setState(() => _obscureNew = !_obscureNew);
              },
            ),

            const SizedBox(height: 14),

            _passwordField(
              controller: _confirmController,
              label: 'Xác nhận mật khẩu mới',
              obscure: _obscureConfirm,
              onToggle: () {
                setState(() => _obscureConfirm = !_obscureConfirm);
              },
            ),

            const SizedBox(height: 26),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: vnptBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  'Đổi mật khẩu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// =============================================================
// TRANG CÀI ĐẶT
// =============================================================

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textLightGrey = Color(0xFF8A94A3);

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _loading = true;
  bool _processing = false;
  String _biometricName = 'Sinh trắc học';

  @override
  void initState() {
    super.initState();
    _loadBiometricStatus();
  }

  Future<void> _loadBiometricStatus() async {
    try {
      final available = await BiometricService.isAvailable();
      final enabled = await BiometricService.isEnabled();
      final name = await BiometricService.getBiometricName();

      if (!mounted) return;
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricName = name;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Biometric settings error: $e');
      if (!mounted) return;
      setState(() {
        _biometricAvailable = false;
        _biometricEnabled = false;
        _loading = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_processing) return;

    if (!_biometricAvailable) {
      _showMessage('Thiết bị không hỗ trợ Face ID hoặc vân tay.', error: true);
      return;
    }

    setState(() => _processing = true);

    try {
      final authenticated = await BiometricService.authenticate();

      if (!authenticated) {
        if (mounted) {
          _showMessage(
            value
                ? 'Xác thực không thành công. Sinh trắc học chưa được bật.'
                : 'Cần xác thực $_biometricName để tắt tính năng này.',
            error: true,
          );
        }
        return;
      }

      if (value) {
        await BiometricService.enable();
      } else {
        await BiometricService.disable();
      }

      if (!mounted) return;
      setState(() => _biometricEnabled = value);
      _showMessage(value ? 'Đã bật $_biometricName.' : 'Đã tắt $_biometricName.');
    } catch (e) {
      debugPrint('Toggle biometric error: $e');
      if (mounted) {
        _showMessage('Không thể thay đổi cài đặt sinh trắc học.', error: true);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : vnptBlue,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget _item(
      BuildContext context,
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
      ) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: vnptLightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: vnptBlue, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: textLightGrey,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: textLightGrey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _biometricItem() {
    final icon = _biometricName == 'Face ID'
        ? Icons.face_rounded
        : Icons.fingerprint_rounded;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: vnptLightBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: vnptBlue, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Xác thực sinh trắc học',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _biometricAvailable
                        ? 'Đăng nhập nhanh bằng $_biometricName'
                        : 'Thiết bị không hỗ trợ sinh trắc học',
                    style: const TextStyle(
                      color: textLightGrey,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_loading || _processing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: vnptBlue,
                ),
              )
            else
              Switch.adaptive(
                value: _biometricEnabled,
                onChanged: _biometricAvailable ? _toggleBiometric : null,
                activeColor: vnptBlue,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        title: const Text(
          'Cài đặt',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _item(
              context,
              Icons.notifications_none_rounded,
              'Thông báo',
              'Quản lý thông báo ứng dụng',
                  () => _showMessage('Tùy chọn thông báo sẽ được bổ sung sau.'),
            ),
            const SizedBox(height: 10),
            _biometricItem(),
            const SizedBox(height: 10),
            _item(
              context,
              Icons.info_outline_rounded,
              'Thông tin ứng dụng',
              'VNPT Khảo Sát Hộ Kinh Doanh',
                  () {
                showAboutDialog(
                  context: context,
                  applicationName: 'VNPT Khảo Sát Hộ Kinh Doanh',
                  applicationVersion: '1.0.0',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
