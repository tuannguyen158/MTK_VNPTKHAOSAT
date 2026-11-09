



import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'add_business_screen.dart';
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  final TextEditingController searchController =
  TextEditingController();

  String selectedFilter = 'Tất cả';

  // =========================================================
  // BỘ LỌC NÂNG CAO
  // =========================================================

  final Set<String> selectedRevenues = {};
  final Set<String> selectedBanks = {};
  final Set<String> selectedEmployeeRanges = {};
  final Set<String> selectedSuppliers = {};
  String selectedProvince = 'Tất cả';
  String selectedWard = 'Tất cả';

  // =========================================================
  // PHÂN QUYỀN
  // =========================================================

  bool roleLoading = true;
  bool isAdmin = false;

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
        roleLoading = false;
        isAdmin = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role = userDoc.data()?['role']?.toString().toLowerCase();

      if (!mounted) return;

      setState(() {
        isAdmin = role == 'admin';
        roleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isAdmin = false;
        roleLoading = false;
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // FIRESTORE
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> get businessStream {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    final collection = FirebaseFirestore.instance
        .collection('ho_kinh_doanh');

    // ADMIN + NHÂN VIÊN: đều xem toàn bộ dữ liệu khảo sát.
    // Quyền đọc được kiểm soát bởi Firestore Rules.
    return collection.snapshots();
  }

  // =========================================================
  // LẤY GIÁ TRỊ
  // =========================================================

  String valueOf(
      Map<String, dynamic> data,
      List<String> keys, {
        String fallback = 'Chưa có thông tin',
      }) {
    for (final key in keys) {
      final value = data[key];

      if (value != null &&
          value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  // Đọc trạng thái checkbox từ checkboxData.
  // true = Có, false = Không.
  String checkboxValue(
      Map<String, dynamic> data,
      String key, {
        String fallback = 'Chưa có thông tin',
      }) {
    final raw = data['checkboxData'];

    if (raw is Map && raw.containsKey(key)) {
      final value = raw[key];

      if (value is bool) {
        return value ? 'Có' : 'Không';
      }

      final normalized = value.toString().trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'có') {
        return 'Có';
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no' ||
          normalized == 'không') {
        return 'Không';
      }
    }

    return fallback;
  }

  String firstCheckedLabel(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    final raw = data['checkboxData'];

    if (raw is Map) {
      for (final key in keys) {
        if (!raw.containsKey(key)) continue;

        final value = raw[key];
        final checked = value is bool
            ? value
            : ['true', '1', 'yes', 'có']
            .contains(value.toString().trim().toLowerCase());

        if (checked) return key;
      }

      // Có dữ liệu checkbox nhưng không mục nào được chọn.
      if (keys.any(raw.containsKey)) {
        return 'Không';
      }
    }

    return 'Chưa có thông tin';
  }

  String checkedLabels(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    final raw = data['checkboxData'];

    if (raw is Map) {
      final result = <String>[];

      for (final key in keys) {
        if (!raw.containsKey(key)) continue;

        final value = raw[key];
        final checked = value is bool
            ? value
            : ['true', '1', 'yes', 'có']
            .contains(value.toString().trim().toLowerCase());

        if (checked) result.add(key);
      }

      if (result.isNotEmpty) return result.join(', ');

      if (keys.any(raw.containsKey)) return 'Không';
    }

    return 'Chưa có thông tin';
  }

  // =========================================================
  // TÌM KIẾM
  // =========================================================

  bool matchesSearch(
      Map<String, dynamic> data,
      ) {
    final keyword =
    searchController.text.trim().toLowerCase();

    if (keyword.isEmpty) {
      return true;
    }

    final fields = [
      valueOf(
        data,
        [
          'tenHoKinhDoanh',
          'tenHKD',
          'ten',
          'name',
        ],
      ),
      valueOf(
        data,
        [
          'mstCccd',
          'mst',
          'cccd',
        ],
      ),
      valueOf(
        data,
        [
          'chuHoKinhDoanh',
          'chuHo',
          'hoTenChuHo',
        ],
      ),
      valueOf(
        data,
        [
          'soDienThoai',
          'sdt',
          'phone',
        ],
      ),
      valueOf(
        data,
        [
          'diaChi',
          'address',
        ],
      ),
    ];

    return fields.any(
          (value) =>
          value.toLowerCase().contains(keyword),
    );
  }

  // =========================================================
  // XÓA
  // =========================================================

  Future<void> deleteBusiness(
      String id,
      String name,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(22),
          ),
          title: const Text(
            'Xóa hộ kinh doanh?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Bạn có chắc chắn muốn xóa "$name"?\n\n'
                'Dữ liệu sẽ bị xóa khỏi Firestore và '
                'không thể hoàn tác.',
            style: const TextStyle(
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'Xóa',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('ho_kinh_doanh')
          .doc(id)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
          Text('Đã xóa hộ kinh doanh.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Không thể xóa dữ liệu: $e',
          ),
        ),
      );
    }
  }

  // =========================================================
  // CHI TIẾT
  // =========================================================

  void showDetail(
      String id,
      Map<String, dynamic> data,
      ) {
    final name = valueOf(
      data,
      [
        'tenHoKinhDoanh',
        'tenHKD',
        'ten',
        'name',
      ],
      fallback: 'Hộ kinh doanh',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          expand: false,
          builder:
              (context, controller) {
            return Container(
              decoration:
              const BoxDecoration(
                color: background,
                borderRadius:
                BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  Container(
                    width: 45,
                    height: 5,
                    decoration:
                    BoxDecoration(
                      color:
                      const Color(0xFFD0D5DD),
                      borderRadius:
                      BorderRadius.circular(10),
                    ),
                  ),

                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      18,
                      14,
                      8,
                      8,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Chi tiết HKD',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight:
                              FontWeight.w800,
                              color: textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(
                              sheetContext,
                            );
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      controller: controller,
                      padding:
                      const EdgeInsets.fromLTRB(
                        16,
                        5,
                        16,
                        30,
                      ),
                      children: [
                        // =========================
                        // HEADER
                        // =========================

                        Container(
                          padding:
                          const EdgeInsets.all(
                            16,
                          ),
                          decoration:
                          BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                            BorderRadius.circular(
                              18,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 55,
                                height: 55,
                                decoration:
                                const BoxDecoration(
                                  color:
                                  vnptLightBlue,
                                  shape:
                                  BoxShape.circle,
                                ),
                                child:
                                const Icon(
                                  Icons
                                      .storefront_rounded,
                                  color:
                                  vnptBlue,
                                  size: 29,
                                ),
                              ),
                              const SizedBox(
                                width: 13,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 2,
                                      overflow:
                                      TextOverflow
                                          .ellipsis,
                                      style:
                                      const TextStyle(
                                        fontSize: 17,
                                        fontWeight:
                                        FontWeight
                                            .w800,
                                        color:
                                        textDark,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 6,
                                    ),
                                    _statusBadge(
                                      isSurveyed(data),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 14,
                        ),

                        _buildSurveyDetails(data),

                        const SizedBox(
                          height: 14,
                        ),

                        _detailSection(
                          'IV. VỊ TRÍ',
                          [
                            _detailRow(
                              Icons.location_city_outlined,
                              'Tỉnh / Thành phố',
                              valueOf(
                                data,
                                [
                                  'tinhThanh',
                                ],
                              ),
                            ),
                            _detailRow(
                              Icons.location_on_outlined,
                              'Phường / Xã',
                              valueOf(
                                data,
                                [
                                  'phuongXa',
                                ],
                              ),
                            ),
                            _detailRow(
                              Icons.gps_fixed_rounded,
                              'Latitude',
                              valueOf(
                                data,
                                [
                                  'latitude',
                                  'lat',
                                ],
                              ),
                            ),
                            _detailRow(
                              Icons.gps_fixed_rounded,
                              'Longitude',
                              valueOf(
                                data,
                                [
                                  'longitude',
                                  'lng',
                                  'lon',
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 22,
                        ),

                        // =========================
                        // SỬA
                        // =========================

                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child:
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddBusinessScreen(
                                    documentId: id,
                                    existingData: data,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.edit_rounded,
                            ),
                            label: const Text(
                              'SỬA THÔNG TIN',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.w800,
                              ),
                            ),
                            style:
                            ElevatedButton
                                .styleFrom(
                              backgroundColor:
                              vnptBlue,
                              foregroundColor:
                              Colors.white,
                              elevation: 0,
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        // =========================
                        // XÓA
                        // =========================

                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child:
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(
                                sheetContext,
                              );

                              deleteBusiness(
                                id,
                                name,
                              );
                            },
                            icon: const Icon(
                              Icons
                                  .delete_outline_rounded,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'XÓA HỘ KINH DOANH',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight:
                                FontWeight.w800,
                              ),
                            ),
                            style:
                            OutlinedButton
                                .styleFrom(
                              side:
                              const BorderSide(
                                color: Color(
                                  0xFFFFCDD2,
                                ),
                              ),
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor:
        Colors.transparent,
        elevation: 0,

        title: Row(
          children: [
            const Text(
              'Khảo Sát',
              style: TextStyle(
                color: textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            if (!roleLoading)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? const Color(0xFFFFF4D6)
                      : vnptLightBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAdmin ? 'ADMIN' : 'NHÂN VIÊN',
                  style: TextStyle(
                    color: isAdmin
                        ? const Color(0xFF9A6700)
                        : vnptBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),

        actions: [
          IconButton(
            onPressed: () {
              setState(() {});
            },
            icon: const Icon(
              Icons.refresh_rounded,
              color: textDark,
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // =================================================
          // SEARCH
          // =================================================

          Container(
            color: Colors.white,
            padding:
            const EdgeInsets.fromLTRB(
              16,
              4,
              16,
              14,
            ),
            child: TextField(
              controller:
              searchController,
              onChanged: (_) {
                setState(() {});
              },
              decoration:
              InputDecoration(
                hintText:
                'Tìm tên HKD, MST, SĐT...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: vnptBlue,
                ),
                suffixIcon:
                searchController.text
                    .isNotEmpty
                    ? IconButton(
                  onPressed: () {
                    searchController
                        .clear();
                    setState(() {});
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                  ),
                )
                    : null,
                filled: true,
                fillColor:
                background,
                border:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                  borderSide:
                  BorderSide.none,
                ),
              ),
            ),
          ),

          // =================================================
          // FILTER
          // =================================================

          Container(
            color: Colors.white,
            height: 58,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('Tất cả'),
                _filterChip('Hôm nay'),
                _advancedFilterChip(),
                _addBusinessChip(),
              ],
            ),
          ),

          if (hasAdvancedFilters)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Đang áp dụng $activeFilterCount bộ lọc',
                      style: const TextStyle(
                        color: vnptBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearAdvancedFilters,
                    child: const Text('Xóa bộ lọc'),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // =================================================
          // FIRESTORE LIST
          // =================================================

          Expanded(
            child: roleLoading
                ? const Center(
              child: CircularProgressIndicator(
                color: vnptBlue,
              ),
            )
                : StreamBuilder<
                QuerySnapshot<
                    Map<String, dynamic>>>(
              stream: businessStream,
              builder:
                  (context, snapshot) {
                if (snapshot.hasError) {
                  return _errorView(
                    snapshot.error.toString(),
                  );
                }

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child:
                    CircularProgressIndicator(
                      color: vnptBlue,
                    ),
                  );
                }

                final docs =
                    snapshot.data?.docs ?? [];

                final filtered =
                docs.where((doc) {
                  return matchesSearch(
                    doc.data(),
                  ) &&
                      matchesFilter(
                        doc.data(),
                      );
                }).toList();

                if (filtered.isEmpty) {
                  return _emptyView();
                }

                return ListView.builder(
                  physics:
                  const BouncingScrollPhysics(),
                  padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    25,
                  ),
                  itemCount:
                  filtered.length,
                  itemBuilder:
                      (context, index) {
                    final doc =
                    filtered[index];

                    return _businessCard(
                      doc.id,
                      doc.data(),
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

  bool _isToday(dynamic rawDate) {
    if (rawDate == null) return false;

    DateTime? date;
    if (rawDate is Timestamp) {
      date = rawDate.toDate();
    } else if (rawDate is DateTime) {
      date = rawDate;
    } else if (rawDate is String) {
      date = DateTime.tryParse(rawDate);
    }

    if (date == null) return false;

    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _matchesAnyCheckbox(
      Map<String, dynamic> data,
      Set<String> selected,
      List<String> keys,
      ) {
    if (selected.isEmpty) return true;

    final raw = data['checkboxData'];
    final checked = <String>{};

    if (raw is Map) {
      for (final key in keys) {
        if (!raw.containsKey(key)) continue;

        final value = raw[key];
        final isChecked = value is bool
            ? value
            : ['true', '1', 'yes', 'có'].contains(
          value.toString().trim().toLowerCase(),
        );

        if (isChecked) checked.add(key);
      }
    }

    return selected.any(checked.contains);
  }

  bool matchesFilter(Map<String, dynamic> data) {
    // Lọc nhanh theo ngày khảo sát.
    if (selectedFilter == 'Hôm nay') {
      final date = data['surveyedAt'] ?? data['createdAt'];
      if (!_isToday(date)) return false;
    }

    // Doanh thu.
    if (selectedRevenues.isNotEmpty) {
      final revenue = firstCheckedLabel(
        data,
        [
          'Dưới 1 tỷ/năm',
          'Từ 1 - 3 tỷ/năm',
          'Trên 3 tỷ/năm',
        ],
      );

      if (!selectedRevenues.contains(revenue)) return false;
    }

    // Ngân hàng.
    if (selectedBanks.isNotEmpty) {
      final bank = _canonicalBank(
        data['nganHang']?.toString() ?? '',
      );

      if (!selectedBanks.contains(bank)) return false;
    }

    // Số người.
    if (selectedEmployeeRanges.isNotEmpty) {
      final employees = firstCheckedLabel(
        data,
        [
          'Dưới 10 người',
          'Từ 10 đến 49 người',
          'Từ 50 đến 199 người',
          'Trên 200 người',
        ],
      );

      if (!selectedEmployeeRanges.contains(employees)) {
        return false;
      }
    }

    // Nhà cung cấp.
    if (selectedSuppliers.isNotEmpty) {
      if (!_matchesAnyCheckbox(
        data,
        selectedSuppliers,
        [
          'Dùng VNPT',
          'Dùng Viettel',
          'Dùng MISA',
          'Dùng SoftDream',
          'Nhà cung cấp khác',
        ],
      )) {
        return false;
      }
    }

    // Khu vực: dùng cả trường tỉnh/phường và địa chỉ HKD.
    if (selectedProvince != 'Tất cả' &&
        !_locationContains(data, selectedProvince)) {
      return false;
    }

    if (selectedWard != 'Tất cả' &&
        !_locationContains(data, selectedWard)) {
      return false;
    }

    return true;
  }

  // =========================================================
  // KHU VỰC: TỈNH / THÀNH PHỐ + PHƯỜNG / XÃ
  // =========================================================

  // =========================================================
  // KHU VỰC: CHUẨN HÓA VÀ GOM NHÓM
  // =========================================================

  String _normalizeLocation(String raw) {
    var value = raw.trim().toLowerCase();

    const accent = {
      'à':'a','á':'a','ạ':'a','ả':'a','ã':'a',
      'â':'a','ầ':'a','ấ':'a','ậ':'a','ẩ':'a','ẫ':'a',
      'ă':'a','ằ':'a','ắ':'a','ặ':'a','ẳ':'a','ẵ':'a',
      'è':'e','é':'e','ẹ':'e','ẻ':'e','ẽ':'e',
      'ê':'e','ề':'e','ế':'e','ệ':'e','ể':'e','ễ':'e',
      'ì':'i','í':'i','ị':'i','ỉ':'i','ĩ':'i',
      'ò':'o','ó':'o','ọ':'o','ỏ':'o','õ':'o',
      'ô':'o','ồ':'o','ố':'o','ộ':'o','ổ':'o','ỗ':'o',
      'ơ':'o','ờ':'o','ớ':'o','ợ':'o','ở':'o','ỡ':'o',
      'ù':'u','ú':'u','ụ':'u','ủ':'u','ũ':'u',
      'ư':'u','ừ':'u','ứ':'u','ự':'u','ử':'u','ữ':'u',
      'ỳ':'y','ý':'y','ỵ':'y','ỷ':'y','ỹ':'y',
      'đ':'d',
    };

    accent.forEach((from, to) {
      value = value.replaceAll(from, to);
    });

    return value
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _canonicalProvince(String raw) {
    final n = _normalizeLocation(raw);
    if (n.isEmpty) return '';

    const aliases = <String, List<String>>{
      'Đồng Nai': [
        'dong nai', 'dongnai', 'dnai', 'd nai', 'dn',
      ],
      'Bình Dương': ['binh duong', 'binhduong', 'bd'],
      'TP. Hồ Chí Minh': [
        'ho chi minh', 'hochiminh', 'hcm', 'tphcm', 'tp hcm',
        'sai gon', 'saigon',
      ],
      'Bà Rịa - Vũng Tàu': [
        'ba ria vung tau', 'ba ria', 'vung tau', 'brvt',
      ],
      'Bình Phước': ['binh phuoc', 'binhphuoc', 'bp'],
      'Tây Ninh': ['tay ninh', 'tayninh'],
      'Long An': ['long an', 'longan'],
      'Tiền Giang': ['tien giang', 'tiengiang'],
      'Bến Tre': ['ben tre', 'bentre'],
      'Vĩnh Long': ['vinh long', 'vinhlong'],
      'Trà Vinh': ['tra vinh', 'travinh'],
      'Đồng Tháp': ['dong thap', 'dongthap'],
      'An Giang': ['an giang', 'angiang'],
      'Kiên Giang': ['kien giang', 'kiengiang'],
      'Cần Thơ': ['can tho', 'cantho', 'ct'],
      'Hậu Giang': ['hau giang', 'haugiang'],
      'Sóc Trăng': ['soc trang', 'soctrang'],
      'Bạc Liêu': ['bac lieu', 'baclieu'],
      'Cà Mau': ['ca mau', 'camau'],
      'Hà Nội': ['ha noi', 'hanoi', 'hn'],
      'Hải Phòng': ['hai phong', 'haiphong', 'hp'],
      'Đà Nẵng': ['da nang', 'danang'],
      'Huế': ['hue', 'thua thien hue'],
      'Quảng Nam': ['quang nam', 'quangnam'],
      'Quảng Ngãi': ['quang ngai', 'quangngai'],
      'Bình Định': ['binh dinh', 'binhdinh'],
      'Phú Yên': ['phu yen', 'phuyen'],
      'Khánh Hòa': ['khanh hoa', 'khanhhoa'],
      'Ninh Thuận': ['ninh thuan', 'ninhthuan'],
      'Lâm Đồng': ['lam dong', 'lamdong'],
      'Đắk Lắk': ['dak lak', 'daklak'],
      'Đắk Nông': ['dak nong', 'daknong'],
      'Gia Lai': ['gia lai', 'gialai'],
      'Kon Tum': ['kon tum', 'kontum'],
      'Quảng Bình': ['quang binh', 'quangbinh'],
      'Quảng Trị': ['quang tri', 'quangtri'],
      'Hà Tĩnh': ['ha tinh', 'hatinh'],
      'Nghệ An': ['nghe an', 'nghean'],
      'Thanh Hóa': ['thanh hoa', 'thanhhoa'],
      'Ninh Bình': ['ninh binh', 'ninhbinh'],
      'Nam Định': ['nam dinh', 'namdinh'],
      'Thái Bình': ['thai binh', 'thaibinh'],
      'Hòa Bình': ['hoa binh', 'hoabinh'],
      'Phú Thọ': ['phu tho', 'phutho'],
      'Vĩnh Phúc': ['vinh phuc', 'vinhphuc'],
      'Bắc Ninh': ['bac ninh', 'bacninh'],
      'Bắc Giang': ['bac giang', 'bacgiang'],
      'Hưng Yên': ['hung yen', 'hungyen'],
      'Hải Dương': ['hai duong', 'haiduong'],
      'Thái Nguyên': ['thai nguyen', 'thainguyen'],
      'Bắc Kạn': ['bac kan', 'backan'],
      'Lạng Sơn': ['lang son', 'langson'],
      'Cao Bằng': ['cao bang', 'caobang'],
      'Tuyên Quang': ['tuyen quang', 'tuyenquang'],
      'Yên Bái': ['yen bai', 'yenbai'],
      'Lào Cai': ['lao cai', 'laocai'],
      'Điện Biên': ['dien bien', 'dienbien'],
      'Lai Châu': ['lai chau', 'laichau'],
      'Sơn La': ['son la', 'sonla'],
      'Hà Giang': ['ha giang', 'hagiang'],
    };

    for (final entry in aliases.entries) {
      if (entry.value.contains(n)) return entry.key;
    }

    return '';
  }

  String _canonicalWard(String raw) {
    var value = raw.trim();

    // Loại tiền tố hành chính.
    value = value.replaceFirst(
      RegExp(
        r'^(phường|phuong|p\.|xã|xa|thị trấn|thi tran|tt\.)\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();

    // Cắt phần tỉnh/thành phố nằm sau tên Phường/Xã.
    value = value.split(
      RegExp(
        r'\s+(?:tỉnh|tinh|thành phố|thanh pho|tp\.?)\s+',
        caseSensitive: false,
      ),
    ).first.trim();

    // Cắt sau dấu phân cách khi địa chỉ ghi "Hố Nai - Đồng Nai".
    value = value.split(RegExp(r'\s*[-|;,]\s*')).first.trim();

    // Hố Nai 1 / Hố Nai 2 / Hố Nai 3 -> Hố Nai.
    value = value.replaceFirst(
      RegExp(r'^(hố nai|ho nai)\s*[123]\s*$', caseSensitive: false),
      'Hố Nai',
    );

    final n = _normalizeLocation(value);
    if (n.isEmpty) return '';

    // Tỉnh/Thành phố tuyệt đối không được xuất hiện trong danh sách
    // Phường/Xã. Ví dụ "Đồng Nai" phải bị loại khỏi Phường/Xã.
    if (_canonicalProvince(value).isNotEmpty) {
      return '';
    }

    const aliases = <String, List<String>>{
      'Hố Nai': ['ho nai', 'honai'],
      'Long Bình': ['long binh'],
      'Long Bình Tân': ['long binh tan'],
      'Trảng Bom': ['trang bom', 'trangbom'],
      'Tân Hiệp': ['tan hiep'],
      'Tam Hiệp': ['tam hiep'],
      'Tam Phước': ['tam phuoc'],
      'An Bình': ['an binh'],
      'Hóa An': ['hoa an'],
      'Bửu Long': ['buu long'],
      'Biên Hòa': ['bien hoa'],
    };

    for (final entry in aliases.entries) {
      if (entry.value.contains(n)) return entry.key;
    }

    // Với dữ liệu Phường/Xã hợp lệ nhưng chưa nằm trong alias:
    // trả về tên đã làm sạch, không trả về cả câu địa chỉ.
    if (n.length <= 40 &&
        !n.contains('duong ') &&
        !n.contains(' so ') &&
        !n.contains(' khu dan cu ') &&
        !n.contains(' thon ') &&
        !n.contains(' ap ') &&
        !n.contains(' kiot ') &&
        !n.contains('cho moi') &&
        !n.contains('dia chi')) {
      return value;
    }

    return '';
  }

  String _locationText(Map<String, dynamic> data) {
    final parts = <String>[
      data['tinhThanh']?.toString() ?? '',
      data['phuongXa']?.toString() ?? '',
      data['diaChi']?.toString() ?? '',
      data['address']?.toString() ?? '',
      data['diaChiKinhDoanh']?.toString() ?? '',
      data['diaChiHoKinhDoanh']?.toString() ?? '',
      data['diaChiHoKD']?.toString() ?? '',
    ];

    return parts
        .where((e) => e.trim().isNotEmpty)
        .join(' | ');
  }

  bool _locationContains(
      Map<String, dynamic> data,
      String selected,
      ) {
    if (selected == 'Tất cả') return true;

    final wanted = _normalizeLocation(selected);
    if (wanted.isEmpty) return true;

    final source = _normalizeLocation(_locationText(data));

    if (source.contains(wanted)) return true;

    final wantedWords = wanted
        .split(' ')
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (wantedWords.length > 1) {
      return wantedWords.every(source.contains);
    }

    return false;
  }

  List<String> _locationValues(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String key,
      ) {
    final grouped = <String, String>{};

    void addProvince(String raw) {
      final canonical = _canonicalProvince(raw);
      if (canonical.isEmpty) return;

      final normalized = _normalizeLocation(canonical);
      grouped.putIfAbsent(normalized, () => canonical);
    }

    void addWard(String raw) {
      final canonical = _canonicalWard(raw);

      // Không cho phép tỉnh/thành phố lọt xuống danh sách Phường/Xã.
      if (canonical.isEmpty || _canonicalProvince(canonical).isNotEmpty) {
        return;
      }

      final normalized = _normalizeLocation(canonical);
      if (normalized.isEmpty) return;

      grouped.putIfAbsent(normalized, () => canonical);
    }

    for (final doc in docs) {
      final data = doc.data();

      if (key == 'tinhThanh') {
        // Chỉ nhận tỉnh/thành phố đã được canonical hóa.
        addProvince(data['tinhThanh']?.toString() ?? '');

        // Bổ sung từ địa chỉ, nhưng chỉ lấy tỉnh/thành phố hợp lệ.
        final address = [
          data['diaChi']?.toString() ?? '',
          data['address']?.toString() ?? '',
          data['diaChiKinhDoanh']?.toString() ?? '',
          data['diaChiHoKinhDoanh']?.toString() ?? '',
          data['diaChiHoKD']?.toString() ?? '',
        ].join(' ');

        final explicitProvinceMatches = RegExp(
          r'(?:tỉnh|tinh|thành phố|thanh pho|tp\.?)\s+([^,;|]+)',
          caseSensitive: false,
        ).allMatches(address);

        for (final match in explicitProvinceMatches) {
          addProvince(match.group(1) ?? '');
        }

        // Trường hợp địa chỉ kết thúc bằng "... , Đồng Nai".
        final chunks = address
            .split(RegExp(r'\s*,\s*|\s*\|\s*|\s*;\s*'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);

        for (final chunk in chunks) {
          addProvince(chunk);
        }
      } else {
        // Phường/Xã: chỉ lấy trường phuongXa hoặc các cụm có từ khóa
        // phường / xã / thị trấn trong địa chỉ. Không lấy mảnh địa chỉ
        // cuối làm Phường/Xã nữa.
        addWard(data['phuongXa']?.toString() ?? '');

        final address = [
          data['diaChi']?.toString() ?? '',
          data['address']?.toString() ?? '',
          data['diaChiKinhDoanh']?.toString() ?? '',
          data['diaChiHoKinhDoanh']?.toString() ?? '',
          data['diaChiHoKD']?.toString() ?? '',
        ].join(' ');

        final explicitWardMatches = RegExp(
          r'(?:phường|phuong|p\.|xã|xa|thị trấn|thi tran|tt\.?)\s+([^,;|]+)',
          caseSensitive: false,
        ).allMatches(address);

        for (final match in explicitWardMatches) {
          addWard(match.group(1) ?? '');
        }

        // Bổ sung các tên Phường/Xã đã biết nếu xuất hiện trực tiếp
        // trong địa chỉ, ví dụ "Hố Nai - Đồng Nai".
        const knownWards = [
          'Hố Nai',
          'Long Bình',
          'Long Bình Tân',
          'Trảng Bom',
          'Tân Hiệp',
          'Tam Hiệp',
          'Tam Phước',
          'An Bình',
          'Hóa An',
          'Bửu Long',
        ];

        final normalizedAddress = _normalizeLocation(address);
        for (final ward in knownWards) {
          if (normalizedAddress.contains(_normalizeLocation(ward))) {
            addWard(ward);
          }
        }
      }
    }

    final result = grouped.values.toList()
      ..sort(
            (a, b) => _normalizeLocation(a)
            .compareTo(_normalizeLocation(b)),
      );

    return result;
  }


  Widget _businessCard(
      String id,
      Map<String, dynamic> data,
      ) {
    final name = valueOf(
      data,
      ['tenHoKinhDoanh', 'tenHKD', 'ten', 'name'],
      fallback: 'Hộ kinh doanh',
    );

    final owner = valueOf(
      data,
      ['chuHoKinhDoanh', 'chuHo', 'hoTenChuHo'],
      fallback: 'Chưa có chủ hộ',
    );

    final ward = valueOf(
      data,
      ['phuongXa'],
      fallback: 'Chưa có Phường/Xã',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => showDetail(id, data),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: vnptLightBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: vnptBlue,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        owner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Người nhập: ${valueOf(
                          data,
                          ['createdByName', 'createdByEmail'],
                          fallback: 'Không xác định',
                        )}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF00897B),
                            size: 14,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              ward,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF00897B),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9AA3AF),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get activeFilterCount {
    int count = 0;
    if (selectedRevenues.isNotEmpty) count++;
    if (selectedBanks.isNotEmpty) count++;
    if (selectedEmployeeRanges.isNotEmpty) count++;
    if (selectedSuppliers.isNotEmpty) count++;
    if (selectedProvince != 'Tất cả') count++;
    if (selectedWard != 'Tất cả') count++;
    return count;
  }

  bool get hasAdvancedFilters => activeFilterCount > 0;

  String _canonicalBank(String raw) {
    final v = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[._-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (v.isEmpty) return 'Chưa có thông tin';

    if (RegExp(
      r'^(mb|mb bank|mbbank|m b|ngan hang mb|ngan hang quan doi)$',
    ).hasMatch(v)) {
      return 'MB Bank';
    }

    if (RegExp(
      r'^(vcb|vietcom|vietcombank|vietcom bank|ngan hang vietcombank|ngan hang ngoai thuong)$',
    ).hasMatch(v)) {
      return 'Vietcombank';
    }

    if (RegExp(
      r'^(bidv|bi dv|ngan hang bidv)$',
    ).hasMatch(v)) {
      return 'BIDV';
    }

    if (RegExp(
      r'^(vietin|vietinbank|vietin bank|ctg|ngan hang vietinbank)$',
    ).hasMatch(v)) {
      return 'VietinBank';
    }

    if (RegExp(
      r'^(agribank|agri bank|agri|ngan hang agribank)$',
    ).hasMatch(v)) {
      return 'Agribank';
    }

    if (RegExp(
      r'^(acb|a cb|acb bank|ngan hang acb)$',
    ).hasMatch(v)) {
      return 'ACB';
    }

    if (RegExp(
      r'^(techcom|techcombank|techcom bank|tcb|ngan hang techcombank)$',
    ).hasMatch(v)) {
      return 'Techcombank';
    }

    if (RegExp(
      r'^(vpbank|vp bank|ngan hang vpbank)$',
    ).hasMatch(v)) {
      return 'VPBank';
    }

    if (RegExp(
      r'^(tpbank|tp bank|ngan hang tpbank)$',
    ).hasMatch(v)) {
      return 'TPBank';
    }

    if (RegExp(
      r'^(sacombank|sacom bank|sacom|stb|ngan hang sacombank)$',
    ).hasMatch(v)) {
      return 'Sacombank';
    }

    return raw.trim();
  }

  List<String> _uniqueValues(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String key,
      ) {
    final values = <String>{};
    for (final doc in docs) {
      final value = doc.data()[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        values.add(key == 'nganHang' ? _canonicalBank(value) : value);
      }
    }
    final result = values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  void _clearAdvancedFilters() {
    setState(() {
      selectedRevenues.clear();
      selectedBanks.clear();
      selectedEmployeeRanges.clear();
      selectedSuppliers.clear();
      selectedProvince = 'Tất cả';
      selectedWard = 'Tất cả';
    });
  }

  Future<void> _showAdvancedFilters() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('ho_kinh_doanh')
        .get();
    if (!mounted) return;

    final docs = snapshot.docs;
    final banks = _uniqueValues(docs, 'nganHang');
    final provinces = _locationValues(docs, 'tinhThanh');
    final wards = _locationValues(docs, 'phuongXa');

    final tempRevenues = {...selectedRevenues};
    final tempBanks = {...selectedBanks};
    final tempEmployees = {...selectedEmployeeRanges};
    final tempSuppliers = {...selectedSuppliers};
    var tempProvince = selectedProvince;
    var tempWard = selectedWard;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.88,
              minChildSize: 0.60,
              maxChildSize: 0.96,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Bộ lọc nâng cao',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: textDark,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          children: [
                            _filterSectionTitle('💰 Doanh thu'),
                            ...[
                              'Dưới 1 tỷ/năm',
                              'Từ 1 - 3 tỷ/năm',
                              'Trên 3 tỷ/năm',
                            ].map((item) => CheckboxListTile(
                              value: tempRevenues.contains(item),
                              title: Text(item),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: vnptBlue,
                              onChanged: (value) => setSheetState(() {
                                value == true ? tempRevenues.add(item) : tempRevenues.remove(item);
                              }),
                            )),

                            _filterSectionTitle('🏦 Ngân hàng'),
                            if (banks.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text('Chưa có dữ liệu ngân hàng.'),
                              )
                            else
                              ...banks.map((item) => CheckboxListTile(
                                value: tempBanks.contains(item),
                                title: Text(item),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                activeColor: vnptBlue,
                                onChanged: (value) => setSheetState(() {
                                  value == true ? tempBanks.add(item) : tempBanks.remove(item);
                                }),
                              )),

                            _filterSectionTitle('👥 Số người'),
                            ...[
                              'Dưới 10 người',
                              'Từ 10 đến 49 người',
                              'Từ 50 đến 199 người',
                              'Trên 200 người',
                            ].map((item) => CheckboxListTile(
                              value: tempEmployees.contains(item),
                              title: Text(item),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: vnptBlue,
                              onChanged: (value) => setSheetState(() {
                                value == true ? tempEmployees.add(item) : tempEmployees.remove(item);
                              }),
                            )),

                            _filterSectionTitle('📡 Nhà cung cấp'),
                            ...[
                              'Dùng VNPT',
                              'Dùng Viettel',
                              'Dùng MISA',
                              'Dùng SoftDream',
                              'Nhà cung cấp khác',
                            ].map((item) => CheckboxListTile(
                              value: tempSuppliers.contains(item),
                              title: Text(item),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: vnptBlue,
                              onChanged: (value) => setSheetState(() {
                                value == true ? tempSuppliers.add(item) : tempSuppliers.remove(item);
                              }),
                            )),

                            _filterSectionTitle('📍 Khu vực'),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: tempProvince,
                              decoration: _filterDropdownDecoration('Tỉnh / Thành phố'),
                              items: ['Tất cả', ...provinces].map((item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )).toList(),
                              onChanged: (value) => setSheetState(() {
                                tempProvince = value ?? 'Tất cả';
                                tempWard = 'Tất cả';
                              }),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: tempWard,
                              decoration: _filterDropdownDecoration('Phường / Xã'),
                              items: ['Tất cả', ...wards].map((item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )).toList(),
                              onChanged: (value) => setSheetState(() => tempWard = value ?? 'Tất cả'),
                            ),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      tempRevenues.clear();
                                      tempBanks.clear();
                                      tempEmployees.clear();
                                      tempSuppliers.clear();
                                      tempProvince = 'Tất cả';
                                      tempWard = 'Tất cả';
                                    });
                                  },
                                  child: const Text('Xóa tất cả'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedRevenues
                                        ..clear()
                                        ..addAll(tempRevenues);
                                      selectedBanks
                                        ..clear()
                                        ..addAll(tempBanks);
                                      selectedEmployeeRanges
                                        ..clear()
                                        ..addAll(tempEmployees);
                                      selectedSuppliers
                                        ..clear()
                                        ..addAll(tempSuppliers);
                                      selectedProvince = tempProvince;
                                      selectedWard = tempWard;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: vnptBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text(
                                    'Áp dụng bộ lọc',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _filterSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 5),
      child: Text(
        title,
        style: const TextStyle(
          color: textDark,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  InputDecoration _filterDropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E6EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E6EB)),
      ),
    );
  }

  Widget _addBusinessChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(Icons.add_business_rounded, size: 18, color: Colors.white),
        label: const Text('Thêm HKD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        backgroundColor: vnptBlue,
        side: BorderSide.none,
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBusinessScreen()));
        },
      ),
    );
  }

  Widget _advancedFilterChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(Icons.tune_rounded, size: 18, color: hasAdvancedFilters ? vnptBlue : textDark),
        label: Text(
          hasAdvancedFilters ? 'Bộ lọc nâng cao • $activeFilterCount' : 'Bộ lọc',
          style: TextStyle(color: hasAdvancedFilters ? vnptBlue : textDark, fontWeight: FontWeight.w700, fontSize: 12),
        ),
        backgroundColor: hasAdvancedFilters ? vnptLightBlue : Colors.white,
        side: BorderSide(color: hasAdvancedFilters ? vnptBlue : const Color(0xFFE2E6EB)),
        onPressed: _showAdvancedFilters,
      ),
    );
  }

  Widget _filterChip(String title) {
    final selected = selectedFilter == title;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(title),
        selected: selected,
        onSelected: (_) => setState(() => selectedFilter = title),
        selectedColor: vnptLightBlue,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? vnptBlue : const Color(0xFFE2E6EB),
        ),
        labelStyle: TextStyle(
          color: selected ? vnptBlue : textGrey,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  // =========================================================
  // TRẠNG THÁI KHẢO SÁT
  // =========================================================

  bool isSurveyed(Map<String, dynamic> data) {
    final raw = data['daKhaoSat'];

    if (raw is bool) {
      return raw;
    }

    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true' || value == 'đã khảo sát' || value == 'da khao sat') {
        return true;
      }
    }

    // Hỗ trợ dữ liệu cũ có surveyedAt nhưng chưa có daKhaoSat.
    final surveyedAt = data['surveyedAt'];
    if (surveyedAt != null) {
      return true;
    }

    return false;
  }

  Widget _statusBadge(bool surveyed) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: surveyed
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        surveyed ? 'ĐÃ KHẢO SÁT' : 'CHƯA KHẢO SÁT',
        style: TextStyle(
          color: surveyed
              ? const Color(0xFF2E7D32)
              : const Color(0xFFE65100),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // =========================================================
  // DETAIL SECTION
  // =========================================================


  Widget _buildSurveyDetails(Map<String, dynamic> data) {
    // Dữ liệu cũ không có surveyMode (hoặc mode != custom)
    // luôn hiển thị bằng FORM MẶC ĐỊNH ban đầu.
    if (data['surveyMode']?.toString() != 'custom') {
      return _buildDefaultSurveyDetails(data);
    }

    return _buildDynamicSurveyDetails(data);
  }

  Widget _buildDefaultSurveyDetails(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailSection(
          'I. THÔNG TIN HỘ KINH DOANH',
          [
            _detailRow(
              Icons.person_outline,
              'Họ tên',
              valueOf(data, ['tenHoKinhDoanh', 'tenHKD', 'ten']),
            ),
            _detailRow(
              Icons.badge_outlined,
              'MST / CCCD',
              valueOf(data, ['mstCccd', 'mst', 'cccd']),
            ),
            _detailRow(
              Icons.person_outline,
              'Chủ hộ kinh doanh',
              valueOf(data, ['chuHoKinhDoanh', 'tenChuHo']),
            ),
            _detailRow(
              Icons.category_outlined,
              'Mặt hàng kinh doanh',
              valueOf(data, ['matHangKinhDoanh', 'matHang']),
            ),
            _detailRow(
              Icons.phone_outlined,
              'Số điện thoại',
              valueOf(data, ['soDienThoai', 'sdt', 'phone']),
            ),
            _detailRow(
              Icons.home_outlined,
              'Địa chỉ chi tiết',
              valueOf(data, ['diaChi', 'address']),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _detailSection(
          'II. THÔNG TIN QUY MÔ & CHUYỂN ĐỔI SỐ',
          [
            _detailRow(
              Icons.payments_outlined,
              'Doanh thu',
              firstCheckedLabel(
                data,
                [
                  'Dưới 1 tỷ/năm',
                  'Từ 1 - 3 tỷ/năm',
                  'Trên 3 tỷ/năm',
                ],
              ),
            ),
            _detailRow(
              Icons.receipt_long_outlined,
              'Dịch vụ đang sử dụng',
              _legacyCheckedLabels(
                data,
                [
                  'Hóa đơn điện tử',
                  'Chữ ký số',
                  'Phần mềm bán hàng',
                  'Chưa sử dụng',
                ],
              ),
            ),
            _detailRow(
              Icons.business_outlined,
              'Nhà cung cấp',
              _legacyCheckedLabels(
                data,
                [
                  'Dùng VNPT',
                  'Dùng Viettel',
                  'Dùng Misa',
                  'Dùng MISA',
                  'Dùng Softdream',
                  'Dùng SoftDream',
                  'Nhà cung cấp khác',
                ],
              ),
            ),
            _detailRow(
              Icons.people_outline,
              'Số người',
              firstCheckedLabel(
                data,
                [
                  'Dưới 10 người',
                  'Từ 10 đến 49 người',
                  'Từ 50 đến 199 người',
                  'Trên 200 người',
                ],
              ),
            ),
            _detailRow(
              Icons.account_balance_outlined,
              'Ngân hàng',
              valueOf(data, ['nganHang']),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _detailSection(
          'III. CÔNG CỤ SỐ',
          [
            _detailRow(
              Icons.point_of_sale,
              'Máy POS',
              checkboxValue(
                data,
                'Máy POS',
                fallback: valueOf(data, ['mayPOS']),
              ),
            ),
            _detailRow(
              Icons.qr_code_scanner,
              'Máy quét mã',
              checkboxValue(
                data,
                'Máy quét mã',
                fallback: valueOf(data, ['mayQuetMa']),
              ),
            ),
            _detailRow(
              Icons.print_outlined,
              'Máy in hóa đơn',
              checkboxValue(
                data,
                'Máy in hóa đơn',
                fallback: valueOf(data, ['mayInHoaDon']),
              ),
            ),
            _detailRow(
              Icons.payments_outlined,
              'Thanh toán không tiền mặt',
              checkboxValue(
                data,
                'Thanh toán không dùng tiền mặt',
                fallback: valueOf(
                  data,
                  ['thanhToanKhongTienMat'],
                ),
              ),
            ),
            _detailRow(
              Icons.language_outlined,
              'Website đặt hàng',
              checkboxValue(
                data,
                'Website đặt hàng',
                fallback: valueOf(data, ['websiteDatHang']),
              ),
            ),
            _detailRow(
              Icons.inventory_2_outlined,
              'Quản lý tồn kho',
              checkboxValue(
                data,
                'Quản lý tồn kho',
                fallback: valueOf(data, ['quanLyTonKho']),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _legacyCheckedLabels(
      Map<String, dynamic> data,
      List<String> keys,
      ) {
    final result = <String>[];

    for (final key in keys) {
      if (checkboxValue(data, key, fallback: '') == 'Có') {
        result.add(_legacyDisplayLabel(key));
      }
    }

    if (result.isEmpty) {
      return 'Chưa có thông tin';
    }

    return result.toSet().join(', ');
  }

  String _legacyDisplayLabel(String key) {
    switch (key) {
      case 'Dùng VNPT':
        return 'VNPT';
      case 'Dùng Viettel':
        return 'Viettel';
      case 'Dùng Misa':
      case 'Dùng MISA':
        return 'MISA';
      case 'Dùng Softdream':
      case 'Dùng SoftDream':
        return 'SoftDream';
      case 'Nhà cung cấp khác':
        return 'Khác';
      default:
        return key;
    }
  }


  Widget _buildDynamicSurveyDetails(
      Map<String, dynamic> data,
      ) {
    final templateId = data['surveyTemplateId']?.toString().trim();

    if (templateId == null || templateId.isEmpty) {
      return _detailSection(
        'THÔNG TIN KHẢO SÁT',
        [
          _detailRow(
            Icons.info_outline,
            'Trạng thái',
            'Dữ liệu này chưa có bộ khảo sát động.',
          ),
        ],
      );
    }

    return FutureBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('survey_templates')
          .doc(templateId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _detailSection(
            'THÔNG TIN KHẢO SÁT',
            [
              _detailRow(
                Icons.error_outline,
                'Lỗi',
                'Không thể tải bộ câu hỏi của khảo sát.',
              ),
            ],
          );
        }

        final template = snapshot.data!.data();
        if (template == null) {
          return _detailSection(
            'THÔNG TIN KHẢO SÁT',
            [
              _detailRow(
                Icons.info_outline,
                'Trạng thái',
                'Bộ khảo sát không còn tồn tại.',
              ),
            ],
          );
        }

        final sections = template['sections'];
        final answers = data['surveyAnswers'] is Map
            ? Map<String, dynamic>.from(data['surveyAnswers'] as Map)
            : <String, dynamic>{};

        if (sections is! List || sections.isEmpty) {
          return _detailSection(
            template['name']?.toString() ?? 'THÔNG TIN KHẢO SÁT',
            [
              _detailRow(
                Icons.info_outline,
                'Trạng thái',
                'Bộ khảo sát chưa có câu hỏi.',
              ),
            ],
          );
        }

        final widgets = <Widget>[];

        for (final rawSection in sections) {
          if (rawSection is! Map) continue;

          final section = Map<String, dynamic>.from(rawSection);
          final title =
              section['title']?.toString() ?? 'Phần khảo sát';

          final rows = <Widget>[];
          final questions = section['questions'];

          if (questions is List) {
            for (final rawQuestion in questions) {
              if (rawQuestion is! Map) continue;

              final question =
              Map<String, dynamic>.from(rawQuestion);

              final key = question['key']?.toString() ??
                  question['id']?.toString() ??
                  '';

              final questionTitle =
                  question['title']?.toString() ??
                      question['question']?.toString() ??
                      'Câu hỏi';

              final displayTitle =
                  '${rows.length + 1}. $questionTitle';

              final answer = answers[key];

              rows.add(
                _dynamicQuestionCard(
                  questionNumber: rows.length + 1,
                  questionTitle: questionTitle,
                  questionType: question['type'],
                  answer: answer,
                ),
              );
            }
          }

          if (rows.isNotEmpty) {
            widgets.add(
              _detailSection(title, rows),
            );
            widgets.add(
              const SizedBox(height: 14),
            );
          }
        }

        if (widgets.isEmpty) {
          return _detailSection(
            template['name']?.toString() ?? 'THÔNG TIN KHẢO SÁT',
            [
              _detailRow(
                Icons.info_outline,
                'Trạng thái',
                'Chưa có câu trả lời.',
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        );
      },
    );
  }

  Widget _dynamicQuestionCard({
    required int questionNumber,
    required String questionTitle,
    required dynamic questionType,
    required dynamic answer,
  }) {
    final answerText = _formatDynamicAnswer(answer);

    // Giữ khoảng 40% cho câu hỏi và 60% cho câu trả lời.
    // Cách này giúp câu hỏi dài xuống dòng đẹp mà không làm
    // cột trả lời bị bóp quá nhỏ.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Số thứ tự
          SizedBox(
            width: 30,
            child: Container(
              width: 27,
              height: 27,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$questionNumber',
                style: const TextStyle(
                  color: vnptBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // CÂU HỎI
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                questionTitle
                    .replaceFirst(
                  RegExp(r'^\s*\d+\s*[.)\-:]\s*'),
                  '',
                )
                    .trim(),
                softWrap: true,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(width: 18),

          // CÂU TRẢ LỜI
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                answerText,
                softWrap: true,
                style: TextStyle(
                  color: answerText == 'Chưa có thông tin'
                      ? textGrey
                      : textDark,
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  IconData _iconForQuestionType(dynamic rawType) {
    final type = rawType?.toString().toLowerCase();

    switch (type) {
      case 'number':
      case 'numeric':
        return Icons.numbers_rounded;
      case 'single':
      case 'single_choice':
      case 'radio':
      case 'choice':
        return Icons.radio_button_checked_rounded;
      case 'multiple':
      case 'multi_choice':
      case 'checkbox':
      case 'multiple_choice':
        return Icons.check_box_rounded;
      default:
        return Icons.short_text_rounded;
    }
  }

  String _formatDynamicAnswer(dynamic value) {
    if (value == null) return 'Chưa có thông tin';

    if (value is List) {
      final values = value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();

      return values.isEmpty
          ? 'Chưa có thông tin'
          : values.join(', ');
    }

    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');
    }

    final text = value.toString().trim();
    return text.isEmpty ? 'Chưa có thông tin' : text;
  }

  Widget _detailSection(
      String title,
      List<Widget> children,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(15),
      decoration:
      BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
            const TextStyle(
              color: vnptBlue,
              fontSize: 12,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          ...children,
        ],
      ),
    );
  }

  // =========================================================
  // DETAIL ROW
  // =========================================================

  IconData _detailIconForTitle(
      String title,
      IconData fallback,
      ) {
    final value = title
        .toLowerCase()
        .replaceAll(RegExp(r'^\s*\d+\s*[.)\-:]\s*'), '')
        .trim();

    if (value.contains('họ tên') ||
        value.contains('họ và tên') ||
        value.contains('tên hộ') ||
        value.contains('chủ hộ')) {
      return Icons.person_outline_rounded;
    }
    if (value.contains('mst') ||
        value.contains('cccd') ||
        value.contains('mã số thuế')) {
      return Icons.badge_outlined;
    }
    if (value.contains('số điện thoại') ||
        value == 'sdt' ||
        value.contains('điện thoại')) {
      return Icons.phone_outlined;
    }
    if (value.contains('địa chỉ')) {
      return Icons.home_outlined;
    }
    if (value.contains('mặt hàng') ||
        value.contains('ngành nghề')) {
      return Icons.storefront_outlined;
    }
    if (value.contains('tỉnh') ||
        value.contains('thành phố')) {
      return Icons.location_city_outlined;
    }
    if (value.contains('phường') ||
        value.contains('xã')) {
      return Icons.location_on_outlined;
    }
    if (value.contains('gps') ||
        value.contains('latitude') ||
        value.contains('longitude')) {
      return Icons.gps_fixed_rounded;
    }

    return fallback;
  }

  Widget _detailRow(
      IconData icon,
      String title,
      String value,
      ) {
    final displayIcon = _detailIconForTitle(title, icon);

    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: Center(
              child: Icon(
                displayIcon,
                color: vnptBlue,
                size: 18,
              ),
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          SizedBox(
            width: 125,
            child: Text(
              title,
              style:
              const TextStyle(
                color: textGrey,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
              const TextStyle(
                color: textDark,
                fontSize: 12.5,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // EMPTY
  // =========================================================

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(25),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration:
              const BoxDecoration(
                color: vnptLightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: vnptBlue,
                size: 35,
              ),
            ),
            const SizedBox(
              height: 15,
            ),
            const Text(
              'Không tìm thấy HKD',
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight:
                FontWeight.w800,
              ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              searchController.text
                  .trim()
                  .isEmpty
                  ? 'Chưa có dữ liệu khảo sát.'
                  : 'Không có HKD phù hợp với tìm kiếm.',
              textAlign:
              TextAlign.center,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ERROR
  // =========================================================

  Widget _errorView(
      String error,
      ) {
    return Center(
      child: Padding(
        padding:
        const EdgeInsets.all(25),
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(
              height: 12,
            ),
            const Text(
              'Không thể tải dữ liệu',
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight:
                FontWeight.w800,
              ),
            ),
            const SizedBox(
              height: 7,
            ),
            Text(
              error,
              textAlign:
              TextAlign.center,
              style: const TextStyle(
                color: textGrey,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
