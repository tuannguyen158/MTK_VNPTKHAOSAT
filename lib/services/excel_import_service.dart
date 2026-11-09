

import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

/// Kết quả import Excel.
class ExcelImportResult {
  final int totalRows;
  final int imported;
  final int updated;
  final int skipped;
  final int invalid;
  final List<String> errors;

  const ExcelImportResult({
    required this.totalRows,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.invalid,
    required this.errors,
  });
}


/// Kết quả quét Excel trước khi ghi Firebase.
class ExcelPreviewResult {
  final List<String> allSheets;
  final List<String> dataSheets;
  final int totalRows;
  final int validRows;
  final int skippedRows;
  final List<Map<String, dynamic>> sampleRows;

  const ExcelPreviewResult({
    required this.allSheets,
    required this.dataSheets,
    required this.totalRows,
    required this.validRows,
    required this.skippedRows,
    required this.sampleRows,
  });
}

/// Service dùng cho ADMIN:
/// Excel Sheet "Trang tính 2" -> Firestore collection "ho_kinh_doanh".
///
/// Sheet 2 hiện có các nhóm cột:
/// - Thông tin HKD
/// - Doanh thu
/// - Dịch vụ đang sử dụng
/// - Nhà cung cấp
/// - Số người
/// - Công cụ số
/// - Ngân hàng
///
/// GPS của dữ liệu Excel cũ chưa có nên latitude/longitude = null.
/// Dữ liệu import được đánh dấu daKhaoSat = true vì đây là danh sách
/// HKD đã được khảo sát bằng phiếu giấy trước đó.
class ExcelImportService {
  ExcelImportService._();

  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  static final CollectionReference<Map<String, dynamic>> _businessRef =
  _firestore.collection('ho_kinh_doanh');

  static const String sheetName = 'Trang tính 2';

  /// Mở hộp chọn file .xlsx.
  static Future<PlatformFile?> pickExcelFile() async {
    // file_picker 12.x: pickFile() trả trực tiếp PlatformFile?
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    return file;
  }

  /// Quét file nhưng CHƯA ghi gì vào Firestore.
  /// Dùng cho màn hình Preview của Admin.
  static Future<ExcelPreviewResult> previewExcel({
    required PlatformFile file,
    required String currentAdminUid,
  }) async {
    final bytes = await _readFileBytes(file);
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('File Excel không có sheet nào.');
    }

    final allSheets = excel.tables.keys.toList();
    final dataSheets = <String>[];
    final samples = <Map<String, dynamic>>[];

    int totalRows = 0;
    int validRows = 0;
    int skippedRows = 0;

    final now = Timestamp.now();

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final sheet = entry.value;

      if (sheet.rows.isEmpty) continue;

      final headerIndex = _findHeaderRow(sheet.rows);
      if (headerIndex == -1) continue;

      final headers = sheet.rows[headerIndex]
          .map((cell) => _normalizeHeader(cell?.value?.toString()))
          .toList();

      if (_findColumn(headers, 'Tên Hộ Kinh Doanh') == -1 &&
          _findColumn(headers, 'Tên HKD') == -1) {
        continue;
      }

      dataSheets.add(sheetName);

      for (int rowIndex = headerIndex + 1;
      rowIndex < sheet.rows.length;
      rowIndex++) {
        final row = sheet.rows[rowIndex];
        if (_isEmptyRow(row)) continue;

        totalRows++;

        try {
          final data = _mapSheetRow(
            row: row,
            headers: headers,
            sheetName: sheetName,
            rowNumber: rowIndex + 1,
            adminUid: currentAdminUid,
            now: now,
          );

          if (data == null ||
              _cleanValue(data['tenHoKinhDoanh']) == null) {
            skippedRows++;
            continue;
          }

          validRows++;

          if (samples.length < 10) {
            samples.add(data);
          }
        } catch (_) {
          skippedRows++;
        }
      }
    }

    return ExcelPreviewResult(
      allSheets: allSheets,
      dataSheets: dataSheets,
      totalRows: totalRows,
      validRows: validRows,
      skippedRows: skippedRows,
      sampleRows: samples,
    );
  }

  /// Quét và import tất cả các sheet có cấu trúc dữ liệu HKD.
  ///
  /// Sheet nào có ít nhất một trong các cột nhận diện:
  /// - Tên Hộ Kinh Doanh
  /// - MST (Số CCCD)
  /// - Số điện thoại
  /// - Địa chỉ
  ///
  /// sẽ được coi là sheet dữ liệu HKD.
  /// Các sheet báo cáo/tổng hợp/ghi chú sẽ được bỏ qua.
  static Future<ExcelImportResult> importAllBusinessSheets({
    required PlatformFile file,
    required String currentAdminUid,
  }) async {
    final bytes = await _readFileBytes(file);
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('File Excel không có sheet nào.');
    }

    final existingSnapshot = await _businessRef.get();
    final existingByMst = <String, String>{};

    for (final doc in existingSnapshot.docs) {
      final mst = _cleanValue(doc.data()['mstCccd']);
      if (_isUsableMst(mst)) {
        existingByMst[_normalizeKey(mst!)] = doc.id;
      }
    }

    final now = Timestamp.now();

    int totalRows = 0;
    int imported = 0;
    int updated = 0;
    int skipped = 0;
    int invalid = 0;

    final errors = <String>[];

    WriteBatch batch = _firestore.batch();
    int batchOperations = 0;

    Future<void> commitBatch() async {
      if (batchOperations == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      batchOperations = 0;
    }

    for (final entry in excel.tables.entries) {
      final currentSheetName = entry.key;
      final sheet = entry.value;

      if (sheet.rows.isEmpty) {
        continue;
      }

      final headerIndex = _findHeaderRow(sheet.rows);

      // Không có cấu trúc HKD -> bỏ qua sheet.
      if (headerIndex == -1) {
        continue;
      }

      final headers = sheet.rows[headerIndex]
          .map((cell) => _normalizeHeader(cell?.value?.toString()))
          .toList();

      final tenHkdIndex =
      _findColumn(headers, 'Tên Hộ Kinh Doanh');

      if (tenHkdIndex == -1) {
        continue;
      }

      for (int rowIndex = headerIndex + 1;
      rowIndex < sheet.rows.length;
      rowIndex++) {
        final row = sheet.rows[rowIndex];

        if (_isEmptyRow(row)) {
          continue;
        }

        totalRows++;
        final excelRowNumber = rowIndex + 1;

        try {
          final data = _mapSheetRow(
            row: row,
            headers: headers,
            sheetName: currentSheetName,
            rowNumber: excelRowNumber,
            adminUid: currentAdminUid,
            now: now,
          );

          if (data == null) {
            skipped++;
            continue;
          }

          final tenHkd = _cleanValue(data['tenHoKinhDoanh']);

          if (tenHkd == null || tenHkd.isEmpty) {
            invalid++;
            errors.add(
              'Sheet "$currentSheetName", dòng $excelRowNumber: '
                  'thiếu Tên Hộ Kinh Doanh.',
            );
            continue;
          }

          final mst = _cleanValue(data['mstCccd']);

          final existingDocId = _isUsableMst(mst)
              ? existingByMst[_normalizeKey(mst!)]
              : null;

          if (existingDocId != null) {
            batch.set(
              _businessRef.doc(existingDocId),
              {
                ...data,
                'updatedAt': now,
                'updatedBy': currentAdminUid,
              },
              SetOptions(merge: true),
            );
            updated++;
          } else {
            final newRef = _businessRef.doc();
            batch.set(newRef, data);

            if (_isUsableMst(mst)) {
              existingByMst[_normalizeKey(mst!)] = newRef.id;
            }

            imported++;
          }

          batchOperations++;

          if (batchOperations >= 450) {
            await commitBatch();
          }
        } catch (e) {
          invalid++;
          errors.add(
            'Sheet "$currentSheetName", dòng $excelRowNumber: $e',
          );
        }
      }
    }

    await commitBatch();

    return ExcelImportResult(
      totalRows: totalRows,
      imported: imported,
      updated: updated,
      skipped: skipped,
      invalid: invalid,
      errors: errors,
    );
  }

  /// Alias ngắn để dùng ở UI Admin.
  static Future<ExcelImportResult> importExcel({
    required PlatformFile file,
    required String currentAdminUid,
  }) {
    return importAllBusinessSheets(
      file: file,
      currentAdminUid: currentAdminUid,
    );
  }

  /// Map một dòng của bất kỳ sheet HKD nào.
  /// Tên cột được normalize nên khác biệt hoa/thường và khoảng trắng
  /// không làm import thất bại.
  static Map<String, dynamic>? _mapSheetRow({
    required List<Data?> row,
    required List<String> headers,
    required String sheetName,
    required int rowNumber,
    required String adminUid,
    required Timestamp now,
  }) {
    String? valueAny(List<String> names) {
      for (final name in names) {
        final index = _findColumn(headers, name);
        if (index != -1 && index < row.length) {
          final value = _cleanValue(row[index]?.value?.toString());
          if (value != null) return value;
        }
      }
      return null;
    }

    bool checkedAny(List<String> names) {
      for (final name in names) {
        final index = _findColumn(headers, name);
        if (index != -1 && index < row.length) {
          if (_isChecked(row[index]?.value)) return true;
        }
      }
      return false;
    }

    final tenHkd = valueAny([
      'Tên Hộ Kinh Doanh',
      'Tên HKD',
      'Tên hộ kinh doanh',
    ]);

    if (tenHkd == null) return null;

    final mst = valueAny([
      'MST (Số CCCD)',
      'MST/CCCD',
      'MST',
      'CCCD',
    ]);

    final matHang = valueAny([
      'Mặt Hàng Kinh Doanh',
      'Mặt hàng kinh doanh',
      'Mặt hàng',
    ]);

    final chuHo = valueAny([
      'Chủ hộ kinh doanh',
      'Chủ hộ',
      'Tên chủ hộ',
    ]);

    final soDienThoai = valueAny([
      'Số điện thoại',
      'SDT',
      'SĐT',
      'Điện thoại',
    ]);

    final diaChi = valueAny([
      'Địa chỉ',
      'Dia chi',
    ]);

    final doanhThu = _firstCheckedLabel([
      ('Dưới 1 tỷ/năm', 'Dưới 1 tỷ/năm'),
      ('Dưới 1 tỷ / năm', 'Dưới 1 tỷ/năm'),
      ('Từ 1 - 3 tỷ/năm', 'Từ 1 - 3 tỷ/năm'),
      ('Từ 1–3 tỷ/năm', 'Từ 1–3 tỷ/năm'),
      ('Trên 3 tỷ/năm', 'Trên 3 tỷ/năm'),
    ], (header) => checkedAny([header]));

    final dichVuDangSuDung = <String>[];

    final serviceColumns = <List<String>, String>{
      ['Hóa đơn điện tử']: 'Hóa đơn điện tử',
      ['Chữ ký số']: 'Chữ ký số',
      ['Phần mềm bán hàng']: 'Phần mềm bán hàng',
      ['Chưa sử dụng']: 'Chưa sử dụng',
    };

    serviceColumns.forEach((names, label) {
      if (checkedAny(names)) dichVuDangSuDung.add(label);
    });

    final nhaCungCap = <String>[];

    final providerColumns = <List<String>, String>{
      ['Dùng VNPT', 'VNPT']: 'VNPT',
      ['Dùng Viettel', 'Viettel']: 'Viettel',
      ['Dùng Misa', 'Misa']: 'Misa',
      ['Dùng Sofdream', 'Sofdream']: 'Sofdream',
    };

    providerColumns.forEach((names, label) {
      if (checkedAny(names)) nhaCungCap.add(label);
    });

    final nhaCungCapKhac = valueAny([
      'Nhà cung cấp khác',
      'NCC khác',
    ]);

    if (nhaCungCapKhac != null &&
        !_isEmptyLike(nhaCungCapKhac)) {
      nhaCungCap.add(nhaCungCapKhac);
    }

    final soNguoi = _firstCheckedLabel([
      ('Dưới 10 người', 'Dưới 10 người'),
      ('Từ 10 đến 49 người', 'Từ 10 đến 49 người'),
      ('Từ 50 đến 199 người', 'Từ 50 đến 199 người'),
      ('Trên 200 người', 'Trên 200 người'),
    ], (header) => checkedAny([header]));

    final congCuSo = <String>[];

    final digitalColumns = <List<String>, String>{
      ['Máy POS', 'POS']: 'Máy POS',
      ['Máy quét mã']: 'Máy quét mã',
      ['Máy in hóa đơn']: 'Máy in hóa đơn',
      ['Thanh toán không dùng tiền mặt']: 'Thanh toán không dùng tiền mặt',
      ['Website đặt hàng']: 'Website đặt hàng',
      ['Quản lý tồn kho']: 'Quản lý tồn kho',
    };

    digitalColumns.forEach((names, label) {
      if (checkedAny(names)) congCuSo.add(label);
    });

    // =========================================================
    // NGÂN HÀNG - CỘT TEXT, KHÔNG PHẢI CHECKBOX
    // =========================================================
    // Tìm cột ngân hàng linh hoạt vì tên header Excel có thể là:
    // "Ngân hàng", "Tên ngân hàng", "Tên NH", "NH", "Bank",
    // "Ngân hàng đang sử dụng", ... hoặc có thêm số thứ tự/ký hiệu.
    String? nganHang;

    int bankIndex = -1;

    // 1. Ưu tiên các tên cột rõ ràng.
    const bankHeaders = <String>[
      'Ngân hàng',
      'Tên ngân hàng',
      'Ngân Hàng',
      'NGÂN HÀNG',
      'Tên NH',
      'NH',
      'Bank',
      'Ngân hàng sử dụng',
      'HKD sử dụng ngân hàng nào',
    ];

    for (final wanted in bankHeaders) {
      final index = _findColumn(headers, wanted);
      if (index != -1) {
        bankIndex = index;
        break;
      }
    }

    // 2. Nếu không khớp chính xác, dò theo nội dung header.
    if (bankIndex == -1) {
      for (int i = 0; i < headers.length; i++) {
        final header = _normalizeHeader(headers[i]);

        if (header.contains('ngân hàng') ||
            header.contains('ngan hang') ||
            header.contains('tên ngân hàng') ||
            header.contains('ten ngan hang') ||
            header == 'nh' ||
            header.startsWith('nh ') ||
            header.contains(' bank') ||
            header.startsWith('bank ')) {
          bankIndex = i;
          break;
        }
      }
    }

    if (bankIndex != -1 && bankIndex < row.length) {
      nganHang = _cleanValue(
        row[bankIndex]?.value?.toString(),
      );
    }

    // 3. Fallback cuối: nếu header bị đặt tên hoàn toàn khác,
    // nhận diện một số tên ngân hàng phổ biến từ chính ô dữ liệu.
    if (nganHang == null) {
      const knownBanks = <String>[
        'BIDV',
        'Vietcombank',
        'VietinBank',
        'Agribank',
        'MB Bank',
        'MBBank',
        'ACB',
        'Techcombank',
        'VPBank',
        'TPBank',
        'Sacombank',
        'HDBank',
        'SHB',
        'VIB',
        'OCB',
        'Eximbank',
        'SeABank',
        'MSB',
        'Nam A Bank',
        'Bac A Bank',
      ];

      for (int i = 0; i < row.length; i++) {
        final value = _cleanValue(row[i]?.value?.toString());
        if (value == null) continue;

        final normalizedValue = value.toLowerCase();

        final looksLikeBank = knownBanks.any(
              (bank) => normalizedValue == bank.toLowerCase(),
        );

        if (looksLikeBank) {
          nganHang = value;
          break;
        }
      }
    }

    // =========================================================
    // GIỮ TOÀN BỘ DỮ LIỆU GỐC CỦA EXCEL
    // =========================================================
    //
    // Ngoài các field chuẩn của app, mọi cột khác trong Excel
    // cũng được lưu lại vào "excelData". Như vậy nếu sau này
    // Excel có thêm cột mới (doanh thu chi tiết, số lao động,
    // loại hình, ghi chú, ...), dữ liệu vẫn không bị mất.
    final excelData = <String, dynamic>{};

    for (int i = 0; i < headers.length; i++) {
      if (i >= row.length) continue;

      final originalHeader =
      row.length > i
          ? _cleanValue(
        // headers đã normalize nên tìm tên gốc từ header cell
        // sẽ không khả thi ở đây; dùng header normalized làm key.
        headers[i],
      )
          : null;

      if (originalHeader == null || originalHeader.isEmpty) {
        continue;
      }

      final rawValue = row[i]?.value;
      final convertedValue = _excelCellToFirestoreValue(rawValue);

      if (convertedValue != null) {
        excelData[originalHeader] = convertedValue;
      }
    }

    // =========================================================
    // GIỮ TRẠNG THÁI TẤT CẢ CHECKBOX CỦA EXCEL
    // =========================================================
    // Excel checkbox có thể được thư viện đọc thành true/false,
    // hoặc thành 1/0, X, ✓, Có/Không.
    // Lưu nguyên trạng thái vào checkboxData để màn hình Chi tiết
    // có thể phân biệt:
    //   true  = Có
    //   false = Không
    //   không có key = Chưa có thông tin.
    final checkboxData = <String, dynamic>{};

    const checkboxColumns = <String>[
      'Dưới 1 tỷ/năm',
      'Từ 1 - 3 tỷ/năm',
      'Trên 3 tỷ/năm',
      'Hóa đơn điện tử',
      'Chữ ký số',
      'Phần mềm bán hàng',
      'Chưa sử dụng',
      'Dùng VNPT',
      'Dùng Viettel',
      'Dùng Misa',
      'Dùng Sofdream',
      'Nhà cung cấp khác',
      'Dưới 10 người',
      'Từ 10 đến 49 người',
      'Từ 50 đến 199 người',
      'Trên 200 người',
      'Máy POS',
      'Máy quét mã',
      'Máy in hóa đơn',
      'Thanh toán không dùng tiền mặt',
      'Website đặt hàng',
      'Quản lý tồn kho',
    ];

    for (final column in checkboxColumns) {
      final index = _findColumn(headers, column);

      if (index != -1 && index < row.length) {
        final raw = row[index]?.value;

        if (raw != null) {
          if (raw is bool) {
            checkboxData[column] = raw;
          } else {
            final normalized = raw.toString().trim().toLowerCase();

            if (normalized == 'true' ||
                normalized == 'false' ||
                normalized == '1' ||
                normalized == '0' ||
                normalized == 'x' ||
                normalized == '✓' ||
                normalized == 'yes' ||
                normalized == 'no' ||
                normalized == 'có' ||
                normalized == 'không') {
              checkboxData[column] = _isChecked(raw);
            }
          }
        }
      }
    }

    // Hỗ trợ header có tên hơi khác bằng cách dò theo nội dung.
    for (int i = 0; i < headers.length; i++) {
      if (i >= row.length) continue;

      final header = headers[i].trim();
      final lower = header.toLowerCase();

      final isKnownCheckbox =
      checkboxColumns.any((name) =>
      _normalizeHeader(name) == _normalizeHeader(header));

      if (isKnownCheckbox) continue;

      final looksLikeCheckbox =
          lower.contains('dưới 1 tỷ') ||
              lower.contains('từ 1 - 3 tỷ') ||
              lower.contains('trên 3 tỷ') ||
              lower.contains('hóa đơn điện tử') ||
              lower.contains('chữ ký số') ||
              lower.contains('phần mềm bán hàng') ||
              lower.contains('dùng vnpt') ||
              lower.contains('dùng viettel') ||
              lower.contains('dùng misa') ||
              lower.contains('dùng sofdream') ||
              lower.contains('dưới 10 người') ||
              lower.contains('từ 10 đến 49 người') ||
              lower.contains('từ 50 đến 199 người') ||
              lower.contains('trên 200 người') ||
              lower.contains('máy pos') ||
              lower.contains('máy quét mã') ||
              lower.contains('máy in hóa đơn') ||
              lower.contains('website đặt hàng') ||
              lower.contains('quản lý tồn kho') ||
              lower.contains('thanh toán không dùng tiền mặt');

      if (looksLikeCheckbox && row[i]?.value != null) {
        final raw = row[i]!.value;
        final normalized = raw.toString().trim().toLowerCase();

        if (raw is bool ||
            normalized == 'true' ||
            normalized == 'false' ||
            normalized == '1' ||
            normalized == '0' ||
            normalized == 'x' ||
            normalized == '✓' ||
            normalized == 'yes' ||
            normalized == 'no' ||
            normalized == 'có' ||
            normalized == 'không') {
          checkboxData[header] = _isChecked(raw);
        }
      }
    }

    return {
      'checkboxData': checkboxData,
      'sttExcel': valueAny(['STT']),
      'tenHoKinhDoanh': tenHkd,
      'mstCccd': mst,
      'matHangKinhDoanh': matHang,
      'chuHoKinhDoanh': chuHo,
      'soDienThoai': soDienThoai,
      'diaChi': diaChi,

      // Excel hiện tại chưa có GPS.
      'latitude': null,
      'longitude': null,

      'doanhThu': doanhThu,
      'soNguoi': soNguoi,

      'dichVuDangSuDung': dichVuDangSuDung,
      'nhaCungCap': nhaCungCap,
      'nhaCungCapKhac': nhaCungCapKhac,
      'congCuSo': congCuSo,
      'nganHang': nganHang,

      // Dữ liệu Excel là dữ liệu khảo sát giấy đã có.
      'daKhaoSat': true,

      'dataSource': 'excel',
      'importedFromExcel': true,
      'importedSheet': sheetName,

      // Toàn bộ cột/dữ liệu gốc của dòng Excel.
      'excelData': excelData,

      'createdBy': adminUid,
      'createdAt': now,
      'surveyedAt': now,
      'updatedAt': now,
    };
  }

  /// Đọc bytes:
  /// - Windows/Android/iOS: thường có path.
  /// - Web hoặc trường hợp FilePicker trả bytes: dùng bytes.
  static Future<Uint8List> _readFileBytes(
      PlatformFile file,
      ) async {
    final path = file.path;

    if (path != null && path.isNotEmpty) {
      return File(path).readAsBytes();
    }

    throw Exception(
      'Không thể đọc đường dẫn file Excel. '
          'Vui lòng chọn lại file.',
    );
  }

  /// Tìm dòng chứa tên cột chuẩn.
  static int _findHeaderRow(
      List<List<Data?>> rows,
      ) {
    for (int i = 0; i < rows.length; i++) {
      final headers = rows[i]
          .map((cell) => _normalizeHeader(cell?.value?.toString()))
          .toList();

      if (_findColumn(headers, 'Tên Hộ Kinh Doanh') != -1 ||
          _findColumn(headers, 'Tên HKD') != -1 ||
          _findColumn(headers, 'MST') != -1 ||
          _findColumn(headers, 'MST/CCCD') != -1) {
        return i;
      }
    }

    return -1;
  }

  static dynamic _excelCellToFirestoreValue(dynamic value) {
    if (value == null) return null;

    if (value is bool) return value;

    if (value is num) return value;

    final stringValue = value.toString().trim();

    if (stringValue.isEmpty) return null;

    // Các giá trị đánh dấu thường gặp trong Excel.
    if (stringValue.toLowerCase() == 'true') return true;
    if (stringValue.toLowerCase() == 'false') return false;

    return stringValue;
  }

  static String? _firstCheckedLabel(
      List<(String header, String label)> options,
      bool Function(String header) checked,
      ) {
    for (final option in options) {
      if (checked(option.$1)) {
        return option.$2;
      }
    }

    return null;
  }

  static int _findColumn(
      List<String> headers,
      String wanted,
      ) {
    final normalizedWanted =
    _normalizeHeader(wanted);

    for (int i = 0; i < headers.length; i++) {
      if (headers[i] == normalizedWanted) {
        return i;
      }
    }

    return -1;
  }

  static String _normalizeHeader(String? value) {
    if (value == null) return '';

    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  static String? _cleanValue(String? value) {
    if (value == null) return null;

    var result = value
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (_isEmptyLike(result)) {
      return null;
    }

    // Excel cũ có các giá trị kiểu:
    // " Trống ", "Không có".
    // Không xóa "Không có" vì một số trường dùng nó như dữ liệu thực tế.
    result = result.replaceAll(RegExp(r'^"+|"+$'), '').trim();

    if (_isEmptyLike(result)) {
      return null;
    }

    return result;
  }

  static bool _isEmptyLike(String value) {
    final normalized = value
        .trim()
        .toLowerCase();

    return normalized.isEmpty ||
        normalized == 'trống' ||
        normalized == '"trống"' ||
        normalized == 'null' ||
        normalized == 'n/a' ||
        normalized == '-';
  }

  static bool _isUsableMst(String? mst) {
    if (mst == null || mst.trim().isEmpty) {
      return false;
    }

    return !_isEmptyLike(mst);
  }

  static String _normalizeKey(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\s\-.]'), '')
        .toLowerCase();
  }

  static bool _isChecked(dynamic value) {
    if (value == null) return false;

    if (value is bool) {
      return value;
    }

    final normalized = value
        .toString()
        .trim()
        .toLowerCase();

    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'x' ||
        normalized == '✓' ||
        normalized == 'yes' ||
        normalized == 'có';
  }

  static bool _isEmptyRow(List<Data?> row) {
    for (final cell in row) {
      final value = cell?.value;

      if (value != null &&
          value.toString().trim().isNotEmpty) {
        return false;
      }
    }

    return true;
  }
}

