import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vietnam_provinces/vietnam_provinces.dart';

import '../notification_helper.dart';

/// Màn hình nhập HKD.
///
/// Từ phiên bản này, phần câu hỏi không còn hard-code theo tháng.
/// App tự lấy MỘT bộ khảo sát đang được Admin áp dụng trong collection
/// `survey_templates` với `isActive == true`.
///
/// Cấu trúc template dự kiến:
/// survey_templates/{templateId}
/// {
///   name: 'Khảo sát A',
///   version: 1,
///   isActive: true,
///   status: 'published',
///   sections: [
///     {
///       id: 'section_1',
///       title: 'I. THÔNG TIN HKD',
///       questions: [
///         {
///           id: 'q_1',
///           key: 'tenHoKinhDoanh',
///           title: 'Tên Hộ Kinh Doanh',
///           type: 'text',
///           required: true,
///           options: []
///         }
///       ]
///     }
///   ]
/// }
class AddBusinessScreen extends StatefulWidget {
  final String? documentId;
  final Map<String, dynamic>? existingData;

  const AddBusinessScreen({
    super.key,
    this.documentId,
    this.existingData,
  });

  bool get isEdit => documentId != null;

  @override
  State<AddBusinessScreen> createState() => _AddBusinessScreenState();
}

class _AddBusinessScreenState extends State<AddBusinessScreen> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, dynamic> _answers = {};

  Province? selectedProvince;
  Ward? selectedWard;

  bool loadingTemplate = true;
  bool templateMissing = false;
  String? templateError;
  bool saving = false;
  bool gettingLocation = false;

  double? latitude;
  double? longitude;
  bool gpsReady = false;

  String surveyMode = 'default'; // default | custom
  String? surveyTemplateId;
  int surveyVersion = 1;
  String surveyName = '';
  List<Map<String, dynamic>> sections = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (widget.isEdit && widget.existingData != null) {
      _loadExistingLocation(widget.existingData!);
    }

    await _loadSurveyForCurrentRecord();

    if (!mounted) return;
    setState(() {
      loadingTemplate = false;
    });
  }

  Future<void> _loadSurveyForCurrentRecord() async {
    // HKD cũ không có surveyMode => luôn được coi là FORM MẶC ĐỊNH.
    if (widget.isEdit && widget.existingData != null) {
      final data = widget.existingData!;
      final mode = data['surveyMode']?.toString();

      if (mode != 'custom') {
        surveyMode = 'default';
        _loadLegacyFallbackTemplate();
        _loadExistingAnswers(data);
        return;
      }

      final templateId = data['surveyTemplateId']?.toString().trim();
      if (templateId == null || templateId.isEmpty) {
        surveyMode = 'default';
        _loadLegacyFallbackTemplate();
        _loadExistingAnswers(data);
        return;
      }

      await _loadSurveyTemplateById(templateId);
      if (templateMissing) {
        // Không để mất dữ liệu nếu template cũ bị xóa.
        surveyMode = 'default';
        _loadLegacyFallbackTemplate();
        _loadExistingAnswers(data);
      } else {
        _loadExistingAnswers(data);
      }
      return;
    }

    // HKD mới: đọc cấu hình Admin hiện tại.
    await _loadCurrentSurveyMode();
  }

  Future<void> _loadCurrentSurveyMode() async {
    try {
      final settings = await FirebaseFirestore.instance
          .collection('survey_settings')
          .doc('current')
          .get();

      final data = settings.data();
      final mode = data?['mode']?.toString() ?? 'default';

      if (mode != 'custom') {
        surveyMode = 'default';
        _loadLegacyFallbackTemplate();
        return;
      }

      final templateId = data?['activeTemplateId']?.toString().trim();
      if (templateId == null || templateId.isEmpty) {
        surveyMode = 'default';
        _loadLegacyFallbackTemplate();
        return;
      }

      await _loadSurveyTemplateById(templateId);

      if (templateMissing) {
        // Admin đã chọn FORM MỚI nhưng template lỗi/mất:
        // không âm thầm chuyển về form mặc định.
        surveyMode = 'custom';
        sections = [];
        templateError =
        'Form mới đang được áp dụng nhưng không tải được. '
            'Vui lòng kiểm tra bộ khảo sát Admin đã áp dụng.';
      }
    } catch (e, stackTrace) {
      debugPrint('❌ LỖI TẢI CẤU HÌNH KHẢO SÁT: $e');
      debugPrintStack(stackTrace: stackTrace);
      // Không có cấu hình => dùng form mặc định.
      surveyMode = 'default';
      _loadLegacyFallbackTemplate();
      templateMissing = false;
      templateError = null;
    }
  }

  Future<void> _loadSurveyTemplateById(String templateId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('survey_templates')
          .doc(templateId)
          .get();

      if (!doc.exists) {
        throw Exception('Không tìm thấy bộ khảo sát $templateId.');
      }

      final data = doc.data()!;
      final normalized = _normalizeSections(data['sections']);

      if (normalized.isEmpty) {
        throw Exception(
          'Bộ khảo sát "${data['name'] ?? 'Không tên'}" chưa có câu hỏi.',
        );
      }

      surveyMode = 'custom';
      surveyTemplateId = doc.id;
      surveyName = data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : 'Khảo sát';
      surveyVersion = _toInt(data['version']) ?? 1;
      sections = normalized;
      templateMissing = false;
      templateError = null;
    } catch (e, stackTrace) {
      debugPrint('❌ LỖI TẢI TEMPLATE $templateId: $e');
      debugPrintStack(stackTrace: stackTrace);
      surveyTemplateId = null;
      surveyName = '';
      sections = [];
      templateMissing = true;
      templateError = e.toString();
    }
  }

  void _loadExistingLocation(Map<String, dynamic> data) {
    final provinces = VietnamProvinces.getProvinces();
    final provinceCode = data['tinhThanhCode']?.toString();

    if (provinceCode != null && provinceCode.isNotEmpty) {
      for (final province in provinces) {
        if (province.code.toString() == provinceCode) {
          selectedProvince = province;
          break;
        }
      }
    }

    if (selectedProvince != null) {
      final wards = VietnamProvinces.getWards(
        provinceCode: selectedProvince!.code,
      );
      final wardCode = data['phuongXaCode']?.toString();
      if (wardCode != null && wardCode.isNotEmpty) {
        for (final ward in wards) {
          if (ward.code.toString() == wardCode) {
            selectedWard = ward;
            break;
          }
        }
      }
    }

    final lat = data['latitude'];
    final lng = data['longitude'];
    if (lat is num && lng is num) {
      latitude = lat.toDouble();
      longitude = lng.toDouble();
      gpsReady = true;
    }
  }

  Future<void> _loadActiveSurvey() async {
    await _loadCurrentSurveyMode();
  }

  void _loadLegacyFallbackTemplate() {
    surveyMode = 'default';
    surveyTemplateId = null;
    surveyVersion = _toInt(widget.existingData?['surveyVersion']) ?? 1;
    surveyName = 'Khảo sát hiện tại';

    sections = [
      {
        'id': 'legacy_section_1',
        'title': 'I. THÔNG TIN CHÍNH',
        'questions': [
          _q('tenHoKinhDoanh', 'Tên Hộ Kinh Doanh', 'text', true),
          _q('mstCccd', 'MST / CCCD', 'text', true),
          _q('chuHoKinhDoanh', 'Chủ Hộ Kinh Doanh', 'text', true),
          _q('matHangKinhDoanh', 'Mặt hàng kinh doanh', 'text', true),
          _q('soDienThoai', 'Số điện thoại', 'text', true),
          _q('diaChi', 'Địa chỉ chi tiết', 'text', true),
        ],
      },
      {
        'id': 'legacy_section_2',
        'title': 'II. THÔNG TIN QUY MÔ & CHUYỂN ĐỔI SỐ',
        'questions': [
          _q(
            'doanhThu',
            '1. Doanh thu bình quân',
            'single_choice',
            false,
            options: [
              'Dưới 1 tỷ / năm',
              'Từ 1 - 3 tỷ / năm',
              'Trên 3 tỷ / năm',
            ],
          ),
          _q(
            'dichVuDangSuDung',
            '2. HKD có đang sử dụng các dịch vụ nào sau đây?',
            'multi_choice',
            false,
            options: [
              'Hóa đơn điện tử',
              'Chữ ký số',
              'Phần mềm bán hàng',
              'Chưa sử dụng',
            ],
          ),
          _q(
            'nhaCungCap',
            '3. HKD đang sử dụng dịch vụ của nhà cung cấp nào?',
            'multi_choice',
            false,
            options: [
              'VNPT',
              'Viettel',
              'MISA',
              'SoftDream',
              'Khác',
            ],
          ),
          _q(
            'soNguoi',
            '4. HKD hiện có bao nhiêu người?',
            'single_choice',
            false,
            options: [
              'Dưới 10 người',
              'Từ 10 đến 49 người',
              'Từ 50 đến 199 người',
              'Trên 200 người',
            ],
          ),
          _q(
            'congCuSo',
            '5. HKD đang sử dụng công cụ số nào sau đây?',
            'multi_choice',
            false,
            options: [
              'Máy POS',
              'Máy quét mã',
              'Máy in hóa đơn',
              'Thanh toán không dùng tiền mặt',
              'Website đặt hàng',
              'Quản lý tồn kho',
            ],
          ),
          _q('nganHang', '6. HKD đang sử dụng ngân hàng nào?', 'text', false),
        ],
      },
    ];

    if (widget.isEdit && widget.existingData != null) {
      _loadExistingAnswers(widget.existingData!);
    }
  }

  Map<String, dynamic> _q(
      String key,
      String title,
      String type,
      bool required, {
        List<String> options = const [],
      }) {
    return {
      'id': key,
      'key': key,
      'title': title,
      'type': type,
      'required': required,
      'options': options,
    };
  }

  List<Map<String, dynamic>> _normalizeSections(dynamic raw) {
    if (raw is! List) return [];

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;

      final questions = <Map<String, dynamic>>[];
      final rawQuestions = item['questions'];
      if (rawQuestions is List) {
        for (var qIndex = 0; qIndex < rawQuestions.length; qIndex++) {
          final rawQuestion = rawQuestions[qIndex];
          if (rawQuestion is! Map) continue;

          final q = <String, dynamic>{
            'id': rawQuestion['id']?.toString() ?? 'q_${i}_$qIndex',
            'key': rawQuestion['key']?.toString() ??
                rawQuestion['id']?.toString() ??
                'q_${i}_$qIndex',
            'title': rawQuestion['title']?.toString() ??
                rawQuestion['question']?.toString() ??
                'Câu hỏi',
            'type': _normalizeQuestionType(rawQuestion['type']),
            'required': rawQuestion['required'] == true,
            'options': _stringList(rawQuestion['options']),
            'hint': rawQuestion['hint']?.toString(),
            'placeholder': rawQuestion['placeholder']?.toString(),
            'maxLines': _toInt(rawQuestion['maxLines']) ?? 1,
          };
          questions.add(q);
        }
      }

      result.add({
        'id': item['id']?.toString() ?? 'section_$i',
        'title': item['title']?.toString() ?? 'Phần ${i + 1}',
        'questions': questions,
      });
    }

    return result;
  }

  String _normalizeQuestionType(dynamic raw) {
    final type = raw?.toString().trim().toLowerCase() ?? 'text';
    switch (type) {
      case 'text':
      case 'short_text':
      case 'long_text':
        return 'text';
      case 'number':
      case 'numeric':
        return 'number';
      case 'single':
      case 'single_choice':
      case 'radio':
      case 'choice':
        return 'single_choice';
      case 'multiple':
      case 'multi_choice':
      case 'checkbox':
      case 'multiple_choice':
        return 'multi_choice';
      default:
        return 'text';
    }
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  void _loadExistingAnswers(Map<String, dynamic> data) {
    _answers.clear();

    final rawAnswers = data['surveyAnswers'];
    if (rawAnswers is Map) {
      rawAnswers.forEach((key, value) {
        _answers[key.toString()] = value;
      });
    }

    // Tương thích dữ liệu cũ: map các field cũ vào key của template.
    for (final section in sections) {
      final questions = section['questions'];
      if (questions is! List) continue;
      for (final rawQuestion in questions) {
        if (rawQuestion is! Map) continue;
        final key = rawQuestion['key']?.toString();
        if (key == null || key.isEmpty) continue;
        if (_answers.containsKey(key)) continue;
        if (data.containsKey(key)) {
          _answers[key] = data[key];
        }
      }
    }

    _answers.forEach((key, value) {
      if (value is String && _isTextQuestion(key)) {
        _textController(key).text = value;
      }
    });
  }

  bool _isTextQuestion(String key) {
    for (final section in sections) {
      final questions = section['questions'];
      if (questions is! List) continue;
      for (final rawQuestion in questions) {
        if (rawQuestion is Map && rawQuestion['key']?.toString() == key) {
          final type = _normalizeQuestionType(rawQuestion['type']);
          return type == 'text' || type == 'number';
        }
      }
    }
    return false;
  }

  TextEditingController _textController(String key) {
    return _textControllers.putIfAbsent(key, () {
      final controller = TextEditingController();
      final value = _answers[key];
      if (value != null) controller.text = value.toString();
      return controller;
    });
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void showNotification(
      String title,
      String message,
      NotificationType type,
      ) {
    if (!mounted) return;
    showAppNotification(
      context,
      title,
      message,
      type: type,
    );
  }

  Future<void> getCurrentLocation() async {
    if (gettingLocation) return;

    setState(() => gettingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5));
      if (!serviceEnabled) {
        showNotification(
          'Chưa bật vị trí',
          'Vui lòng bật GPS/vị trí trên thiết bị.',
          NotificationType.warning,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showNotification(
          'Chưa cấp quyền vị trí',
          'Ứng dụng cần quyền vị trí để ghi nhận tọa độ HKD.',
          NotificationType.warning,
        );
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 0,
          ),
        ).timeout(const Duration(seconds: 12));
      } on Exception {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        throw Exception('Không lấy được vị trí hiện tại.');
      }

      if (!mounted) return;
      setState(() {
        latitude = position!.latitude;
        longitude = position.longitude;
        gpsReady = true;
      });

      showNotification(
        'GPS đã sẵn sàng',
        'Đã lấy tọa độ: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        NotificationType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showNotification(
        'Không lấy được vị trí',
        'Vui lòng kiểm tra GPS và quyền vị trí rồi thử lại.',
        NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => gettingLocation = false);
    }
  }

  bool validateForm() {
    if (selectedProvince == null) {
      showNotification(
        'Thiếu khu vực',
        'Vui lòng chọn Tỉnh/Thành phố.',
        NotificationType.warning,
      );
      return false;
    }

    if (selectedWard == null) {
      showNotification(
        'Thiếu khu vực',
        'Vui lòng chọn Phường/Xã.',
        NotificationType.warning,
      );
      return false;
    }

    if (!widget.isEdit &&
        (!gpsReady || latitude == null || longitude == null)) {
      showNotification(
        'Chưa có GPS',
        'Vui lòng bật vị trí và lấy GPS trước khi lưu.',
        NotificationType.warning,
      );
      return false;
    }

    if (widget.isEdit && (latitude == null || longitude == null)) {
      showNotification(
        'Thiếu tọa độ',
        'HKD này chưa có tọa độ GPS để giữ lại.',
        NotificationType.warning,
      );
      return false;
    }

    for (final section in sections) {
      final questions = section['questions'];
      if (questions is! List) continue;

      for (final rawQuestion in questions) {
        if (rawQuestion is! Map) continue;
        final key = rawQuestion['key']?.toString();
        if (key == null || key.isEmpty) continue;
        if (rawQuestion['required'] != true) continue;

        final value = _currentAnswer(key);
        final empty = value == null ||
            (value is String && value.trim().isEmpty) ||
            (value is List && value.isEmpty);

        if (empty) {
          final title = rawQuestion['title']?.toString() ?? 'Câu hỏi';
          showNotification(
            'Thiếu thông tin',
            'Vui lòng trả lời: $title',
            NotificationType.warning,
          );
          return false;
        }
      }
    }

    return true;
  }

  dynamic _currentAnswer(String key) {
    final controller = _textControllers[key];
    if (controller != null) {
      final value = controller.text.trim();
      _answers[key] = value;
      return value;
    }
    return _answers[key];
  }

  Future<void> saveBusiness() async {
    if (saving) return;
    if (!validateForm()) return;

    setState(() => saving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Vui lòng đăng nhập lại.');
      }

      // Đồng bộ dữ liệu từ TextField vào answers trước khi lưu.
      for (final entry in _textControllers.entries) {
        _answers[entry.key] = entry.value.text.trim();
      }

      final currentUserName = (user.displayName?.trim().isNotEmpty == true)
          ? user.displayName!.trim()
          : (user.email ?? 'Nhân viên');

      final businessData = <String, dynamic>{
        'tinhThanh': selectedProvince?.name ?? widget.existingData?['tinhThanh'],
        'tinhThanhCode': selectedProvince?.code ??
            widget.existingData?['tinhThanhCode'],
        'phuongXa': selectedWard?.name ?? widget.existingData?['phuongXa'],
        'phuongXaCode': selectedWard?.code ??
            widget.existingData?['phuongXaCode'],
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (surveyMode == 'custom' && surveyTemplateId != null) {
        // Chỉ HKD dùng FORM MỚI mới lưu snapshot câu trả lời động.
        businessData.addAll({
          'surveyMode': 'custom',
          'surveyTemplateId': surveyTemplateId,
          'surveyVersion': surveyVersion,
          'surveyName': surveyName,
          'surveyAnswers': Map<String, dynamic>.from(_answers),
        });
      } else {
        // FORM MẶC ĐỊNH: giữ nguyên cấu trúc dữ liệu cũ.
        // Không gắn template mới vào các HKD cũ.
        if (!widget.isEdit) {
          businessData['surveyMode'] = 'default';
        }

        // FORM MẶC ĐỊNH phải giữ đúng cấu trúc dữ liệu cũ.
        // Đặc biệt checkboxData là nơi form cũ lưu trạng thái
        // Có/Không của Doanh thu, dịch vụ, nhà cung cấp, công cụ số...
        _copyLegacyFields(businessData);
        businessData['checkboxData'] =
            _buildLegacyCheckboxDataFromAnswers();
      }

      final ref = FirebaseFirestore.instance.collection('ho_kinh_doanh');

      if (widget.isEdit && widget.documentId != null) {
        businessData['updatedByUid'] = user.uid;
        businessData['updatedByEmail'] = user.email;
        businessData['updatedByName'] = currentUserName;

        final docRef = ref.doc(widget.documentId!);
        final snapshot = await docRef.get();
        if (!snapshot.exists) {
          throw Exception(
            'Không tìm thấy HKD cần sửa trong Firestore.\n'
                'Document ID: ${widget.documentId}',
          );
        }

        await docRef.set(businessData, SetOptions(merge: true));
      } else {
        businessData['createdAt'] = FieldValue.serverTimestamp();
        businessData['createdBy'] = user.uid;
        businessData['createdByUid'] = user.uid;
        businessData['createdByEmail'] = user.email;
        businessData['createdByName'] = currentUserName;
        businessData['daKhaoSat'] = true;
        businessData['surveyedAt'] = FieldValue.serverTimestamp();

        await ref.add(businessData);
      }

      if (!mounted) return;
      showNotification(
        'Lưu thành công',
        'Hộ kinh doanh đã được lưu cùng bộ khảo sát "$surveyName".',
        NotificationType.success,
      );

      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ LỖI LƯU HKD: $e');
      if (mounted) {
        showNotification(
          'Không thể lưu',
          e.toString(),
          NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Map<String, bool> _buildLegacyCheckboxDataFromAnswers() {
    final result = <String, bool>{};

    bool selected(dynamic value, String option) {
      if (value is List) {
        return value
            .map((e) => e?.toString().trim())
            .contains(option);
      }

      return value?.toString().trim() == option;
    }

    final doanhThu = _answers['doanhThu'];
    result['Dưới 1 tỷ/năm'] =
        doanhThu?.toString().trim() == 'Dưới 1 tỷ / năm';
    result['Từ 1 - 3 tỷ/năm'] =
        doanhThu?.toString().trim() == 'Từ 1 - 3 tỷ / năm';
    result['Trên 3 tỷ/năm'] =
        doanhThu?.toString().trim() == 'Trên 3 tỷ / năm';

    final dichVu = _answers['dichVuDangSuDung'];
    result['Hóa đơn điện tử'] = selected(dichVu, 'Hóa đơn điện tử');
    result['Chữ ký số'] = selected(dichVu, 'Chữ ký số');
    result['Phần mềm bán hàng'] =
        selected(dichVu, 'Phần mềm bán hàng');
    result['Chưa sử dụng'] = selected(dichVu, 'Chưa sử dụng');

    final nhaCungCap = _answers['nhaCungCap'];
    result['Dùng VNPT'] = selected(nhaCungCap, 'VNPT');
    result['Dùng Viettel'] = selected(nhaCungCap, 'Viettel');
    result['Dùng Misa'] = selected(nhaCungCap, 'MISA');
    result['Dùng Softdream'] =
        selected(nhaCungCap, 'SoftDream');
    result['Nhà cung cấp khác'] =
        selected(nhaCungCap, 'Khác');

    final soNguoi = _answers['soNguoi'];
    result['Dưới 10 người'] =
        soNguoi?.toString().trim() == 'Dưới 10 người';
    result['Từ 10 đến 49 người'] =
        soNguoi?.toString().trim() == 'Từ 10 đến 49 người';
    result['Từ 50 đến 199 người'] =
        soNguoi?.toString().trim() == 'Từ 50 đến 199 người';
    result['Trên 200 người'] =
        soNguoi?.toString().trim() == 'Trên 200 người';

    final congCu = _answers['congCuSo'];
    result['Máy POS'] = selected(congCu, 'Máy POS');
    result['Máy quét mã'] = selected(congCu, 'Máy quét mã');
    result['Máy in hóa đơn'] =
        selected(congCu, 'Máy in hóa đơn');
    result['Thanh toán không dùng tiền mặt'] =
        selected(congCu, 'Thanh toán không dùng tiền mặt');
    result['Website đặt hàng'] =
        selected(congCu, 'Website đặt hàng');
    result['Quản lý tồn kho'] =
        selected(congCu, 'Quản lý tồn kho');

    return result;
  }

  void _copyLegacyFields(Map<String, dynamic> target) {
    final mapped = <String, dynamic>{};

    // 1) Ưu tiên key chuẩn do template cung cấp.
    const knownKeys = <String>[
      'tenHoKinhDoanh',
      'mstCccd',
      'chuHoKinhDoanh',
      'matHangKinhDoanh',
      'soDienThoai',
      'diaChi',
      'doanhThu',
      'dichVuDangSuDung',
      'nhaCungCap',
      'nhaCungCapKhac',
      'soNguoi',
      'congCuSo',
      'nganHang',
    ];

    for (final key in knownKeys) {
      if (_answers.containsKey(key)) {
        mapped[key] = _answers[key];
      }
    }

    // 2) Template cũ được tạo trước khi có field "key":
    // tự nhận diện các câu hỏi quen thuộc bằng tiêu đề.
    for (final section in sections) {
      final questions = section['questions'];
      if (questions is! List) continue;

      for (final raw in questions) {
        if (raw is! Map) continue;

        final key = raw['key']?.toString() ?? '';
        final title = raw['title']?.toString().trim() ?? '';
        final answer = _answers[key];

        if (answer == null) continue;

        final normalized = _normalizeLabel(title);

        if (normalized.contains('tenhokinhdoanh') ||
            normalized.contains('tenhkd')) {
          mapped['tenHoKinhDoanh'] = answer;
        } else if (normalized.contains('mst') ||
            normalized.contains('cccd')) {
          mapped['mstCccd'] = answer;
        } else if (normalized.contains('chuho') ||
            normalized.contains('chuhokinhdoanh')) {
          mapped['chuHoKinhDoanh'] = answer;
        } else if (normalized.contains('mathang')) {
          mapped['matHangKinhDoanh'] = answer;
        } else if (normalized.contains('sodienthoai') ||
            normalized == 'sdt') {
          mapped['soDienThoai'] = answer;
        } else if (normalized == 'diachi' ||
            normalized.contains('diachikinhdoanh')) {
          mapped['diaChi'] = answer;
        } else if (normalized.contains('doanhthu')) {
          mapped['doanhThu'] = answer;
        } else if (normalized.contains('songuoi') ||
            normalized.contains('soluongnguoi')) {
          mapped['soNguoi'] = answer;
        } else if (normalized.contains('nganhang')) {
          mapped['nganHang'] = answer;
        }
      }
    }

    target.addAll(mapped);
  }

  String _normalizeLabel(String value) {
    var result = value.trim().toLowerCase();

    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };

    replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });

    return result.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Widget _buildTemplateError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.assignment_late_outlined,
              size: 64,
              color: Color(0xFF0057B8),
            ),
            const SizedBox(height: 14),
            const Text(
              'Chưa có bộ khảo sát áp dụng',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              templateError ??
                  'Vui lòng báo Admin kiểm tra bộ khảo sát đang áp dụng.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textGrey,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                setState(() {
                  loadingTemplate = true;
                  templateMissing = false;
                  templateError = null;
                });
                await _loadActiveSurvey();
                if (!mounted) return;
                setState(() => loadingTemplate = false);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tải lại'),
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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: textDark),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEdit ? 'Sửa Hộ Kinh Doanh' : 'Nhập Hộ Kinh Doanh',
              style: const TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (surveyName.isNotEmpty)
              Text(
                surveyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: loadingTemplate
          ? const Center(
        child: CircularProgressIndicator(color: vnptBlue),
      )
          : templateMissing
          ? _buildTemplateError()
          : SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (templateMissing) _templateWarning(),
            sectionHeader(
              Icons.location_city_rounded,
              'KHU VỰC KHẢO SÁT',
            ),
            const SizedBox(height: 10),
            locationAreaCard(),
            const SizedBox(height: 25),
            sectionHeader(
              Icons.gps_fixed_rounded,
              'VỊ TRÍ HỘ KINH DOANH',
            ),
            const SizedBox(height: 10),
            gpsCard(),
            const SizedBox(height: 27),
            ..._buildDynamicSurvey(),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: saving ? null : saveBusiness,
                icon: saving
                    ? const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  saving ? 'ĐANG LƯU...' : 'LƯU HỘ KINH DOANH',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: vnptBlue,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '* Thông tin bắt buộc',
                style: TextStyle(
                  color: Color(0xFF9AA3AF),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templateWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE1A6)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chưa có bộ khảo sát Admin áp dụng. App đang dùng mẫu cũ tạm thời. Khi Admin tạo và áp dụng bộ khảo sát mới, form này sẽ tự chuyển sang bộ đó.',
              style: TextStyle(
                color: Color(0xFF7A5600),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDynamicSurvey() {
    final widgets = <Widget>[];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final title = section['title']?.toString() ?? 'Phần ${sectionIndex + 1}';

      widgets.add(
        sectionHeader(Icons.article_outlined, title),
      );
      widgets.add(const SizedBox(height: 12));

      final questions = section['questions'];
      if (questions is List) {
        for (final rawQuestion in questions) {
          if (rawQuestion is! Map) continue;

          final question = Map<String, dynamic>.from(rawQuestion);

          widgets.add(_buildQuestion(question));
          widgets.add(const SizedBox(height: 16));
        }
      }

      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  Widget _buildQuestion(Map<String, dynamic> question) {
    final key = question['key']?.toString() ?? question['id'].toString();
    final title = question['title']?.toString() ?? 'Câu hỏi';
    final type = _normalizeQuestionType(question['type']);
    final required = question['required'] == true;
    final options = _stringList(question['options']);

    switch (type) {
      case 'single_choice':
        return _singleChoiceQuestion(
          key: key,
          title: title,
          options: options,
          required: required,
        );
      case 'multi_choice':
        return _multiChoiceQuestion(
          key: key,
          title: title,
          options: options,
          required: required,
        );
      case 'number':
        return _dynamicTextQuestion(
          key: key,
          title: title,
          required: required,
          keyboardType: TextInputType.number,
          maxLines: 1,
          hint: question['placeholder']?.toString(),
        );
      case 'text':
      default:
        return _dynamicTextQuestion(
          key: key,
          title: title,
          required: required,
          keyboardType: TextInputType.text,
          maxLines: _toInt(question['maxLines']) ?? 1,
          hint: question['placeholder']?.toString(),
        );
    }
  }

  Widget _dynamicTextQuestion({
    required String key,
    required String title,
    required bool required,
    required TextInputType keyboardType,
    required int maxLines,
    String? hint,
  }) {
    final controller = _textController(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        questionTitle('$title${required ? ' *' : ''}'),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines < 1 ? 1 : maxLines,
          onChanged: (value) => _answers[key] = value,
          style: const TextStyle(color: textDark, fontSize: 13.5),
          decoration: _inputDecoration(hint ?? title),
        ),
      ],
    );
  }

  Widget _singleChoiceQuestion({
    required String key,
    required String title,
    required List<String> options,
    required bool required,
  }) {
    final selected = _answers[key]?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        questionTitle('$title${required ? ' *' : ''}'),
        ...options.map(
              (option) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _answers[key] = option),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Radio<String>(
                    value: option,
                    groupValue: selected,
                    onChanged: (value) {
                      setState(() => _answers[key] = value);
                    },
                    activeColor: vnptBlue,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Expanded(
                    child: Text(
                      option,
                      style: const TextStyle(color: textGrey, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _multiChoiceQuestion({
    required String key,
    required String title,
    required List<String> options,
    required bool required,
  }) {
    final selected = _answers[key] is List
        ? List<String>.from(
      (_answers[key] as List).map((e) => e.toString()),
    )
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        questionTitle('$title${required ? ' *' : ''}'),
        ...options.map(
              (option) {
            final checked = selected.contains(option);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _toggleMultiChoice(key, option),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (_) => _toggleMultiChoice(key, option),
                      activeColor: vnptBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Expanded(
                      child: Text(
                        option,
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _toggleMultiChoice(String key, String option) {
    final current = _answers[key] is List
        ? List<String>.from(
      (_answers[key] as List).map((e) => e.toString()),
    )
        : <String>[];

    setState(() {
      if (current.contains(option)) {
        current.remove(option);
      } else {
        current.add(option);
      }
      _answers[key] = current;
    });
  }

  Widget locationAreaCard() {
    final provinces = VietnamProvinces.getProvinces();
    final wards = selectedProvince == null
        ? <Ward>[]
        : VietnamProvinces.getWards(
      provinceCode: selectedProvince!.code,
    );

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9EF)),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<Province>(
            value: selectedProvince,
            isExpanded: true,
            decoration: dropdownDecoration(
              'Tỉnh / Thành phố',
              Icons.location_city_rounded,
            ),
            items: provinces.map((province) {
              return DropdownMenuItem<Province>(
                value: province,
                child: Text(
                  province.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: textDark),
                ),
              );
            }).toList(),
            onChanged: (province) {
              setState(() {
                selectedProvince = province;
                selectedWard = null;
              });
            },
          ),
          const SizedBox(height: 13),
          DropdownButtonFormField<Ward>(
            value: selectedWard,
            isExpanded: true,
            decoration: dropdownDecoration(
              'Phường / Xã',
              Icons.location_on_outlined,
            ),
            hint: Text(
              selectedProvince == null
                  ? 'Chọn Tỉnh/Thành phố trước'
                  : 'Chọn Phường/Xã',
              style: const TextStyle(color: Color(0xFF9AA3AF), fontSize: 13),
            ),
            items: wards.map((ward) {
              return DropdownMenuItem<Ward>(
                value: ward,
                child: Text(
                  ward.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: textDark),
                ),
              );
            }).toList(),
            onChanged: selectedProvince == null
                ? null
                : (ward) {
              setState(() => selectedWard = ward);
            },
          ),
        ],
      ),
    );
  }

  Widget gpsCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: gpsReady ? const Color(0xFFBBE7CE) : const Color(0xFFE4E9EF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: gpsReady ? const Color(0xFFE9F8EF) : vnptLightBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              gpsReady
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              color: gpsReady ? const Color(0xFF16A34A) : vnptBlue,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gpsReady ? 'GPS đã sẵn sàng' : 'Chưa có GPS',
                  style: TextStyle(
                    color: gpsReady ? const Color(0xFF15803D) : textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  gpsReady && latitude != null && longitude != null
                      ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                      : 'Bật vị trí để ghi nhận tọa độ HKD',
                  style: const TextStyle(color: textGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: gettingLocation ? null : getCurrentLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: vnptBlue,
                side: const BorderSide(color: vnptBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: gettingLocation
                  ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Text(
                gpsReady ? 'Lấy lại' : 'Lấy GPS',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: vnptLightBlue,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: vnptBlue, size: 18),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget questionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        title,
        style: const TextStyle(
          color: textDark,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE3E8EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE3E8EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: vnptBlue, width: 1.8),
      ),
      labelStyle: const TextStyle(color: textGrey, fontSize: 13),
      floatingLabelStyle: const TextStyle(
        color: vnptBlue,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration dropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: vnptBlue, size: 21),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE3E8EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE3E8EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: vnptBlue, width: 1.8),
      ),
      labelStyle: const TextStyle(color: textGrey, fontSize: 13),
      floatingLabelStyle: const TextStyle(
        color: vnptBlue,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
