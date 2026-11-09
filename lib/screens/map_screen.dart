import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'add_business_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // =========================================================
  // MÀU VNPT
  // =========================================================

  static const Color vnptBlue = Color(0xFF0057B8);
  static const Color vnptLightBlue = Color(0xFFEAF3FF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF172033);
  static const Color textGrey = Color(0xFF667085);

  // =========================================================
  // MAP
  // =========================================================

  final MapController _mapController = MapController();

  final CollectionReference<Map<String, dynamic>> _businessRef =
  FirebaseFirestore.instance.collection('ho_kinh_doanh');

  bool _didFitInitialMarkers = false;
  bool _isGettingLocation = false;

  // VỊ TRÍ HIỆN TẠI CỦA THIẾT BỊ
  LatLng? _currentLocation;
  double? _currentAccuracy;

  // CHỈ ĐƯỜNG TRONG APP
  StreamSubscription<Position>? _positionSubscription;
  _BusinessLocation? _navigationTarget;
  List<LatLng> _routePoints = [];
  bool _isNavigating = false;
  bool _isLoadingRoute = false;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  // Chống gọi OSRM liên tục + bỏ qua kết quả cũ
  int _routeRequestId = 0;
  DateTime? _lastRouteFetchAt;

  // true  = camera tự bám theo người dùng khi đang chỉ đường
  // false = người dùng đã tự kéo/zoom bản đồ, không giật camera nữa
  bool _followUser = true;

  // Chỉ mục dữ liệu (tính 1 lần cho mỗi lần Firestore đổi dữ liệu)
  QuerySnapshot<Map<String, dynamic>>? _indexedSnapshot;
  List<_IndexedLocation> _index = [];

  // =========================================================
  // TÌM KIẾM / LỌC HKD
  // =========================================================

  final TextEditingController _searchController =
  TextEditingController();

  String _searchQuery = '';
  String _provinceFilter = '';
  String _wardFilter = '';

  bool get _hasFilters =>
      _provinceFilter.trim().isNotEmpty ||
          _wardFilter.trim().isNotEmpty;

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // ĐỔI GIÁ TRỊ SANG DOUBLE
  // =========================================================

  double? _toDouble(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString().replaceAll(',', '.').trim(),
    );
  }

  // =========================================================
  // LẤY TEXT AN TOÀN
  // =========================================================

  String _valueOf(
      Map<String, dynamic> data,
      List<String> keys, {
        String fallback = 'Chưa có thông tin',
      }) {
    for (final key in keys) {
      final value = data[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  // =========================================================
  // LẤY THỜI GIAN
  // =========================================================

  DateTime? _getDate(Map<String, dynamic> data) {
    final value = data['createdAt'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Chưa có ngày';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // =========================================================
  // ĐƯA MAP VỀ TOÀN BỘ MARKER
  // =========================================================

  void _fitAllMarkers(
      List<_BusinessLocation> locations, {
        bool force = false,
      }) {
    if (locations.isEmpty) return;

    if (_didFitInitialMarkers && !force) {
      return;
    }

    _didFitInitialMarkers = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Chỉ có 1 HKD
      if (locations.length == 1) {
        _mapController.move(
          LatLng(
            locations.first.latitude,
            locations.first.longitude,
          ),
          16,
        );
        return;
      }

      final points = locations
          .map(
            (item) => LatLng(
          item.latitude,
          item.longitude,
        ),
      )
          .toList();

      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(75),
          maxZoom: 17,
        ),
      );
    });
  }

  // =========================================================
  // CHỌN KIỂU CHỈ ĐƯỜNG
  // =========================================================

  Future<void> _showDirectionsChoice(_BusinessLocation item) async {
    // Đang chỉ đường mà chọn HKD khác -> dừng tuyến cũ rồi cho chọn lại.
    if (_isNavigating) {
      await _stopInAppNavigation();
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Chọn cách chỉ đường',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _startInAppNavigation(item);
                    },
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text(
                      'CHỈ ĐƯỜNG TRONG APP',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vnptBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openGoogleMapsDirections(item);
                    },
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      color: vnptBlue,
                    ),
                    label: const Text(
                      'MỞ GOOGLE MAPS',
                      style: TextStyle(
                        color: vnptBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFBBD5F5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // ROUTING TRONG APP - OSRM / OPENSTREETMAP
  // =========================================================

  Future<void> _fetchRoute(
    LatLng from,
    LatLng to, {
    bool clearOld = true,
  }) async {
    if (!mounted) return;

    final requestId = ++_routeRequestId;
    _lastRouteFetchAt = DateTime.now();

    setState(() {
      _isLoadingRoute = true;
      // Khi cập nhật tuyến lúc đang đi thì giữ đường cũ, tránh bị nhấp nháy.
      if (clearOld) _routePoints = [];
    });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
            '${from.longitude},${from.latitude};'
            '${to.longitude},${to.latitude}'
            '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http.get(
        url,
        headers: const {
          'User-Agent': 'VNPT-Khao-Sat/1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Máy chủ chỉ đường trả về ${response.statusCode}.');
      }

      final json = jsonDecode(response.body);

      if (json['code'] != 'Ok' ||
          json['routes'] is! List ||
          (json['routes'] as List).isEmpty) {
        throw Exception('Không tìm thấy tuyến đường.');
      }

      final route = (json['routes'] as List).first;
      final geometry = route['geometry'];
      final coordinates = geometry?['coordinates'];

      if (coordinates is! List || coordinates.isEmpty) {
        throw Exception('Tuyến đường không có dữ liệu hình học.');
      }

      final points = coordinates
          .whereType<List>()
          .where((pair) => pair.length >= 2)
          .map(
            (pair) => LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        ),
      )
          .toList();

      // Có yêu cầu mới hơn (hoặc đã dừng chỉ đường) -> bỏ kết quả này.
      if (!mounted ||
          requestId != _routeRequestId ||
          !_isNavigating) {
        return;
      }

      setState(() {
        _routePoints = points;
        _routeDistanceMeters =
            (route['distance'] as num?)?.toDouble();
        _routeDurationSeconds =
            (route['duration'] as num?)?.toDouble();
      });
    } catch (e) {
      if (!mounted || requestId != _routeRequestId) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể lấy tuyến đường: $e'),
        ),
      );
    } finally {
      if (mounted && requestId == _routeRequestId) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  // Khoảng cách (mét) từ vị trí hiện tại tới điểm gần nhất trên tuyến.
  double _distanceToRoute(LatLng current) {
    if (_routePoints.isEmpty) return double.infinity;

    const distance = Distance();
    var best = double.infinity;

    for (final point in _routePoints) {
      final d = distance.as(LengthUnit.Meter, current, point);
      if (d < best) best = d;
    }

    return best;
  }

  Future<void> _startInAppNavigation(
      _BusinessLocation item,
      ) async {
    try {
      if (!await _ensureLocationPermission()) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final start = LatLng(
        position.latitude,
        position.longitude,
      );
      final target = LatLng(
        item.latitude,
        item.longitude,
      );

      if (!mounted) return;

      setState(() {
        _navigationTarget = item;
        _currentLocation = start;
        _currentAccuracy = position.accuracy;
        _isNavigating = true;
        _followUser = true;
      });

      _mapController.move(start, 17);

      await _fetchRoute(start, target);

      await _positionSubscription?.cancel();

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
                (position) async {
              if (!mounted || !_isNavigating) return;

              final current = LatLng(
                position.latitude,
                position.longitude,
              );

              setState(() {
                _currentLocation = current;
                _currentAccuracy = position.accuracy;
              });

              // Chỉ bám camera khi người dùng chưa tự kéo bản đồ,
              // và giữ nguyên mức zoom họ đang dùng.
              if (_followUser) {
                _mapController.move(
                  current,
                  math.max(_mapController.camera.zoom, 15),
                );
              }

              final target = _navigationTarget;
              if (target == null) return;

              final targetPoint = LatLng(
                target.latitude,
                target.longitude,
              );

              // Đã đến nơi (cách điểm đến <= 30m).
              final toTarget = const Distance().as(
                LengthUnit.Meter,
                current,
                targetPoint,
              );

              if (toTarget <= 30) {
                final name = target.name;
                await _stopInAppNavigation();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Bạn đã đến "$name".'),
                  ),
                );
                return;
              }

              // Chỉ tính lại tuyến khi đi chệch khỏi tuyến > 50m,
              // không có yêu cầu nào đang chạy và cách lần trước >= 10 giây.
              // (Server OSRM công cộng giới hạn tần suất gọi.)
              if (_isLoadingRoute) return;

              final last = _lastRouteFetchAt;
              final tooSoon = last != null &&
                  DateTime.now().difference(last) <
                      const Duration(seconds: 10);

              if (!tooSoon && _distanceToRoute(current) > 50) {
                await _fetchRoute(
                  current,
                  targetPoint,
                  clearOld: false,
                );
              }
            },
            onError: (Object error) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Mất tín hiệu GPS: $error'),
                ),
              );
            },
          );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isNavigating = false;
        _navigationTarget = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể bắt đầu chỉ đường: $e'),
        ),
      );
    }
  }

  Future<void> _stopInAppNavigation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    // Vô hiệu hóa mọi yêu cầu tuyến đường đang chờ.
    _routeRequestId++;

    if (!mounted) return;

    setState(() {
      _isNavigating = false;
      _navigationTarget = null;
      _routePoints = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _isLoadingRoute = false;
      _followUser = true;
    });
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '--';

    if (meters < 1000) {
      return '${meters.round()} m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '--';

    final minutes = (seconds / 60).round();

    if (minutes < 60) {
      return '$minutes phút';
    }

    final hours = minutes ~/ 60;
    final remain = minutes % 60;

    return remain == 0
        ? '$hours giờ'
        : '$hours giờ $remain phút';
  }

  // =========================================================
  // VỊ TRÍ HIỆN TẠI CỦA THIẾT BỊ
  // =========================================================

  // Kiểm tra GPS đang bật + quyền vị trí. Trả về true nếu dùng được.
  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'GPS đang tắt. Vui lòng bật vị trí trên thiết bị.',
          ),
          action: SnackBarAction(
            label: 'MỞ',
            onPressed: () {
              Geolocator.openLocationSettings();
            },
          ),
        ),
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn đã từ chối quyền truy cập vị trí.'),
        ),
      );
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Quyền vị trí đã bị từ chối vĩnh viễn.',
          ),
          action: SnackBarAction(
            label: 'CÀI ĐẶT',
            onPressed: () {
              Geolocator.openAppSettings();
            },
          ),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _goToCurrentLocation() async {
    try {
      if (!await _ensureLocationPermission()) return;

      if (!mounted) return;

      setState(() {
        _isGettingLocation = true;
        _followUser = true; // bấm nút này = bám theo vị trí lại
      });

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;

      final here = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _currentLocation = here;
        _currentAccuracy = position.accuracy;
      });

      _mapController.move(here, 17);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể lấy vị trí hiện tại: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  // =========================================================
  // TÌM KIẾM / LỌC
  // =========================================================

  // =========================================================
  // CHUẨN HÓA TEXT CHO TÌM KIẾM / LỌC
  // =========================================================
  // Ví dụ:
  //   Đồng Nai  -> dong nai
  //   ĐỒNG NAI  -> dong nai
  //   Xã Hưng Thịnh -> xa hung thinh
  // Nhờ vậy người dùng có thể gõ có/không dấu đều tìm được.
  String _normalizeText(dynamic value) {
    if (value == null) return '';

    var text = value.toString().trim().toLowerCase();

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
      text = text.replaceAll(from, to);
    });

    // Đổi dấu câu thành khoảng trắng để "phuong/xa" và
    // "phuong - xa" đều được xử lý ổn định.
    text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeLocationFilter(dynamic value) {
    var text = _normalizeText(value);

    const prefixes = <String>[
      'thanh pho ',
      'tinh ',
      'quan ',
      'huyen ',
      'thi xa ',
      'thi tran ',
      'phuong ',
      'xa ',
    ];

    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }

    return text;
  }

  String _locationFieldText(
      _BusinessLocation item, {
        required bool province,
      }) {
    final data = item.data;
    final values = <dynamic>[];

    // 1. Các field chuẩn của app.
    final directKeys = province
        ? const [
      'tinhThanh',
      'tinhThanhCode',
      'tinhThanhPho',
      'province',
      'provinceName',
      'provinceCode',
      'tinh',
      'city',
      'state',
    ]
        : const [
      'phuongXa',
      'phuongXaCode',
      'phuongXaName',
      'ward',
      'wardName',
      'commune',
      'phuong',
      'xa',
      'district',
    ];

    for (final key in directKeys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        values.add(value);
      }
    }

    // 2. Địa chỉ đầy đủ luôn được dùng làm fallback.
    values.add(item.address);

    // 3. Dữ liệu import Excel.
    //
    // Excel có thể đặt tên cột khác nhau:
    // "Tỉnh/Thành phố", "Tỉnh - TP", "Xã/Phường", "Phường/Xã",
    // "Địa bàn", "Tỉnh", "Xã"... nên không cố định một tên cột.
    final excelData = data['excelData'];
    if (excelData is Map) {
      for (final entry in excelData.entries) {
        final header = _normalizeText(entry.key);
        final headerNoSpace = header.replaceAll(' ', '');

        bool isProvinceHeader = false;
        bool isWardHeader = false;

        if (headerNoSpace.contains('tinh') ||
            headerNoSpace.contains('province') ||
            headerNoSpace.contains('city')) {
          isProvinceHeader = true;
        }

        if (headerNoSpace.contains('phuong') ||
            headerNoSpace.contains('xa') ||
            headerNoSpace.contains('ward') ||
            headerNoSpace.contains('commune')) {
          isWardHeader = true;
        }

        if ((province && isProvinceHeader) ||
            (!province && isWardHeader)) {
          final value = entry.value;
          if (value != null && value.toString().trim().isNotEmpty) {
            values.add(value);
          }
        }
      }

      // Nếu Excel đặt tên cột không chuẩn, vẫn cho phép tìm trong
      // toàn bộ giá trị Excel. Điều này đặc biệt hữu ích với file giấy
      // cũ đã nhập trước khi app có field tinhThanh/phuongXa.
      values.addAll(excelData.values);
    }

    return values
        .where((value) => value != null)
        .map(_normalizeText)
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  String _searchableText(_BusinessLocation item) {
    final data = item.data;

    final values = <dynamic>[
      item.name,
      item.owner,
      item.phone,
      item.address,
      data['mstCccd'],
      data['matHangKinhDoanh'],
      data['doanhThu'],
      data['soNguoi'],
      data['tinhThanh'],
      data['phuongXa'],
    ];

    final excelData = data['excelData'];
    if (excelData is Map) {
      values.addAll(excelData.values);
      values.addAll(excelData.keys);
    }

    return values
        .where((value) => value != null)
        .map(_normalizeText)
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  // Tính sẵn text tìm kiếm / lọc cho từng HKD. Chỉ tính lại khi
  // Firestore trả dữ liệu mới, KHÔNG tính lại mỗi lần GPS cập nhật vị trí.
  List<_IndexedLocation> _indexFor(
      QuerySnapshot<Map<String, dynamic>> snapshot,
      ) {
    if (identical(snapshot, _indexedSnapshot)) return _index;

    _index = _locationsFromDocs(snapshot.docs)
        .map(
          (item) => _IndexedLocation(
        item: item,
        searchText: _searchableText(item),
        provinceText: _locationFieldText(item, province: true),
        wardText: _locationFieldText(item, province: false),
      ),
    )
        .toList();
    _indexedSnapshot = snapshot;

    return _index;
  }

  List<_BusinessLocation> _applyFilters(
      List<_IndexedLocation> indexed,
      ) {
    final query = _normalizeText(_searchQuery);
    final province = _normalizeLocationFilter(_provinceFilter);
    final ward = _normalizeLocationFilter(_wardFilter);

    return indexed
        .where((entry) {
      final matchSearch =
          query.isEmpty || entry.searchText.contains(query);

      final matchProvince =
          province.isEmpty || entry.provinceText.contains(province);

      final matchWard =
          ward.isEmpty || entry.wardText.contains(ward);

      return matchSearch && matchProvince && matchWard;
    })
        .map((entry) => entry.item)
        .toList();
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _FilterDialogContent(
          initialProvince: _provinceFilter,
          initialWard: _wardFilter,
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _provinceFilter = result['province'] ?? '';
      _wardFilter = result['ward'] ?? '';
      _didFitInitialMarkers = false;
    });
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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(
              Icons.map_rounded,
              color: vnptBlue,
              size: 23,
            ),
            SizedBox(width: 9),
            Text(
              'Bản đồ HKD',
              style: TextStyle(
                color: textDark,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: () {
              setState(() {
                _didFitInitialMarkers = false;
              });
            },
            icon: const Icon(
              Icons.refresh_rounded,
              color: textDark,
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _businessRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _errorView(snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: vnptBlue,
              ),
            );
          }

          // Chuyển dữ liệu Firestore thành danh sách marker (có cache).
          final indexed = snapshot.data == null
              ? <_IndexedLocation>[]
              : _indexFor(snapshot.data!);

          final allLocations = indexed;
          final safeLocations = _applyFilters(indexed);

          _fitAllMarkers(safeLocations);

          return Stack(
            children: [
              // ===================================================
              // MAP
              // ===================================================

              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(
                    10.957,
                    106.842,
                  ),
                  initialZoom: 12,
                  minZoom: 5,
                  maxZoom: 19,
                  // Người dùng tự kéo/zoom bản đồ -> ngừng tự bám camera.
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _isNavigating && _followUser) {
                      setState(() {
                        _followUser = false;
                      });
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                    'com.example.untitled',
                  ),

                  // =================================================
                  // MARKER
                  // =================================================

                  MarkerLayer(
                    markers: safeLocations.map((item) {
                      return Marker(
                        point: LatLng(
                          item.latitude,
                          item.longitude,
                        ),
                        width: 52,
                        height: 52,
                        child: GestureDetector(
                          onTap: () {
                            _showBusinessDetail(item);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: vnptBlue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // =================================================
                  // TUYẾN ĐƯỜNG ĐANG CHỈ TRONG APP
                  // =================================================

                  if (_routePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          strokeWidth: 6,
                          color: vnptBlue,
                        ),
                      ],
                    ),

                  // =================================================
                  // VỊ TRÍ HIỆN TẠI CỦA THIẾT BỊ
                  // =================================================

                  if (_currentLocation != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _currentLocation!,
                          radius: (_currentAccuracy ?? 25)
                              .clamp(12, 120)
                              .toDouble(),
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderColor:
                          Colors.blue.withValues(alpha: 0.35),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),

                  if (_currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLocation!,
                          width: 42,
                          height: 42,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 5,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                      ),
                    ],
                  ),
                ],
              ),

              // ===================================================
              // TÌM KIẾM NHANH
              // ===================================================

              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: textGrey,
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          // TUYỆT ĐỐI không setState() ở onChanged.
                          // Nếu rebuild MapScreen ở mỗi ký tự, TextField sẽ
                          // mất focus và người dùng phải bấm lại liên tục.
                          onChanged: (_) {},
                          onSubmitted: (value) {
                            if (!mounted) return;
                            setState(() {
                              _searchQuery = value.trim();
                              _didFitInitialMarkers = false;
                            });
                          },
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText:
                            'Tìm tên HKD, MST, SĐT, địa chỉ...',
                            hintStyle: TextStyle(
                              color: textGrey,
                              fontSize: 12,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () {
                            _searchController.clear();
                            if (!mounted) return;
                            setState(() {
                              _searchQuery = '';
                              _didFitInitialMarkers = false;
                            });
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: textGrey,
                            size: 20,
                          ),
                        ),
                      Container(
                        width: 1,
                        height: 28,
                        color: const Color(0xFFE4E7EC),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'Lọc HKD',
                            onPressed: _showFilterDialog,
                            icon: const Icon(
                              Icons.tune_rounded,
                              color: vnptBlue,
                            ),
                          ),
                          if (_hasFilters)
                            Positioned(
                              right: 5,
                              top: 7,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ===================================================
              // HIỂN THỊ BỘ LỌC ĐANG DÙNG
              // ===================================================

              if (_hasFilters)
                Positioned(
                  top: 78,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: [
                      if (_provinceFilter.isNotEmpty)
                        _activeFilterChip(
                          Icons.location_city_rounded,
                          _provinceFilter,
                        ),
                      if (_wardFilter.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _activeFilterChip(
                            Icons.location_on_outlined,
                            _wardFilter,
                          ),
                        ),
                    ],
                  ),
                ),

              // ===================================================
              // THÔNG TIN CHỈ ĐƯỜNG TRONG APP
              // ===================================================

              if (_isNavigating)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 88,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(
                      14,
                      12,
                      8,
                      12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
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
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: vnptBlue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                _navigationTarget?.name ??
                                    'Đang chỉ đường',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _isLoadingRoute
                                    ? 'Đang tính tuyến đường...'
                                    : '${_formatDistance(_routeDistanceMeters)}'
                                    ' • ${_formatDuration(_routeDurationSeconds)}',
                                style: const TextStyle(
                                  color: textGrey,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dừng chỉ đường',
                          onPressed: _stopInAppNavigation,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ===================================================
              // NÚT VỊ TRÍ HIỆN TẠI
              // ===================================================

              Positioned(
                right: 16,
                bottom: 28,
                child: FloatingActionButton(
                  heroTag: 'map_current_location',
                  backgroundColor: Colors.white,
                  foregroundColor: vnptBlue,
                  elevation: 5,
                  onPressed: _isGettingLocation
                      ? null
                      : _goToCurrentLocation,
                  child: _isGettingLocation
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: vnptBlue,
                    ),
                  )
                      : const Icon(
                    Icons.my_location_rounded,
                  ),
                ),
              ),

              // ===================================================
              // KHÔNG CÓ MARKER
              // ===================================================

              if (safeLocations.isEmpty)
                Positioned(
                  left: 25,
                  right: 25,
                  top: _hasFilters || _searchQuery.isNotEmpty
                      ? 180
                      : 150,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            allLocations.isEmpty
                                ? Icons.location_off_rounded
                                : Icons.search_off_rounded,
                            color: vnptBlue,
                            size: 42,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            allLocations.isEmpty
                                ? 'Chưa có HKD có GPS'
                                : 'Không tìm thấy HKD',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            allLocations.isEmpty
                                ? 'Các hộ kinh doanh sau khi lấy GPS '
                                'và lưu dữ liệu sẽ tự động xuất hiện '
                                'trên bản đồ.'
                                : 'Thử đổi từ khóa tìm kiếm hoặc '
                                'bộ lọc tỉnh/thành phố, phường/xã.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // CHUYỂN DOCS -> LOCATIONS
  // =========================================================

  List<_BusinessLocation> _locationsFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final List<_BusinessLocation> result = [];

    for (final doc in docs) {
      final data = doc.data();

      final latitude = _toDouble(data['latitude']);
      final longitude = _toDouble(data['longitude']);

      if (latitude == null || longitude == null) {
        continue;
      }

      if (latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }

      result.add(
        _BusinessLocation(
          id: doc.id,
          name: _valueOf(
            data,
            [
              'tenHoKinhDoanh',
              'tenHKD',
              'ten',
              'name',
            ],
            fallback: 'Hộ kinh doanh',
          ),
          owner: _valueOf(
            data,
            [
              'chuHoKinhDoanh',
              'chuHo',
              'hoTenChuHo',
            ],
            fallback: 'Chưa có chủ hộ',
          ),
          phone: _valueOf(
            data,
            [
              'soDienThoai',
              'sdt',
              'phone',
            ],
            fallback: 'Chưa có SĐT',
          ),
          address: _valueOf(
            data,
            [
              'diaChi',
              'address',
            ],
            fallback: 'Chưa có địa chỉ',
          ),
          latitude: latitude,
          longitude: longitude,
          data: data,
        ),
      );
    }

    return result;
  }

  Widget _activeFilterChip(IconData icon, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 175),
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 7,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: vnptBlue, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textDark,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CHI TIẾT HKD
  // =========================================================

  Future<void> _openGoogleMapsDirections(
      _BusinessLocation item,
      ) async {
    final uri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'destination': '${item.latitude},${item.longitude}',
        'travelmode': 'driving',
        'dir_action': 'navigate',
      },
    );

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể mở Google Maps hoặc trình duyệt.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể mở Google Maps: $e'),
        ),
      );
    }
  }

  void _showBusinessDetail(
      _BusinessLocation item,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0D5DD),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 17),

                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: vnptLightBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: vnptBlue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  _detailRow(
                    Icons.person_outline_rounded,
                    'Chủ hộ',
                    item.owner,
                  ),

                  _detailRow(
                    Icons.phone_outlined,
                    'SĐT',
                    item.phone,
                  ),

                  _detailRow(
                    Icons.location_on_outlined,
                    'Địa chỉ',
                    item.address,
                  ),

                  _detailRow(
                    Icons.gps_fixed_rounded,
                    'GPS',
                    '${item.latitude.toStringAsFixed(6)}, '
                        '${item.longitude.toStringAsFixed(6)}',
                  ),

                  _detailRow(
                    Icons.calendar_today_outlined,
                    'Ngày nhập',
                    _formatDate(
                      _getDate(item.data),
                    ),
                  ),

                  const SizedBox(height: 13),

                  // =================================================
                  // CHỈ ĐƯỜNG - GOOGLE MAPS
                  // =================================================

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showDirectionsChoice(item);
                      },
                      icon: const Icon(
                        Icons.navigation_rounded,
                      ),
                      label: const Text(
                        'CHỈ ĐƯỜNG',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vnptBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 9),

                  // =================================================
                  // XEM VỊ TRÍ
                  // =================================================

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);

                        _mapController.move(
                          LatLng(
                            item.latitude,
                            item.longitude,
                          ),
                          18,
                        );
                      },
                      icon: const Icon(
                        Icons.my_location_rounded,
                      ),
                      label: const Text(
                        'XEM VỊ TRÍ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vnptBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 9),

                  // =================================================
                  // SỬA
                  // =================================================

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);

                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddBusinessScreen(
                              documentId: item.id,
                              existingData:
                              Map<String, dynamic>.from(item.data),
                            ),
                          ),
                        );

                        if (!mounted) return;

                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: vnptBlue,
                      ),
                      label: const Text(
                        'SỬA THÔNG TIN',
                        style: TextStyle(
                          color: vnptBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFBBD5F5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 9),

                  // =================================================
                  // XÓA
                  // =================================================

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);

                        await _deleteBusiness(
                          item,
                        );
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'XÓA HỘ KINH DOANH',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFFFCDD2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // XÓA HKD
  // =========================================================

  Future<void> _deleteBusiness(
      _BusinessLocation item,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Xóa hộ kinh doanh?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Bạn có chắc muốn xóa "${item.name}"?\n\n'
                'Dữ liệu sẽ bị xóa khỏi Firestore và '
                'không thể hoàn tác.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      if (_navigationTarget?.id == item.id) {
        await _stopInAppNavigation();
      }

      await _businessRef.doc(item.id).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã xóa hộ kinh doanh.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể xóa: $e',
          ),
        ),
      );
    }
  }

  // =========================================================
  // DETAIL ROW
  // =========================================================

  Widget _detailRow(
      IconData icon,
      String title,
      String value,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: vnptBlue,
            size: 18,
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 70,
            child: Text(
              title,
              style: const TextStyle(
                color: textGrey,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ERROR
  // =========================================================

  Widget _errorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.red,
              size: 45,
            ),
            const SizedBox(height: 12),
            const Text(
              'Không thể tải bản đồ',
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              error,
              textAlign: TextAlign.center,
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

class _FilterDialogContent extends StatefulWidget {
  final String initialProvince;
  final String initialWard;

  const _FilterDialogContent({
    required this.initialProvince,
    required this.initialWard,
  });

  @override
  State<_FilterDialogContent> createState() => _FilterDialogContentState();
}

class _FilterDialogContentState extends State<_FilterDialogContent> {
  late final TextEditingController _provinceController;
  late final TextEditingController _wardController;

  @override
  void initState() {
    super.initState();
    _provinceController =
        TextEditingController(text: widget.initialProvince);
    _wardController = TextEditingController(text: widget.initialWard);
  }

  @override
  void dispose() {
    _provinceController.dispose();
    _wardController.dispose();
    super.dispose();
  }

  void _closeWithResult({
    required String province,
    required String ward,
  }) {
    // Đóng bàn phím trước khi đóng Dialog để tránh lỗi
    // "_dependents.isEmpty" trên một số phiên bản Flutter.
    FocusScope.of(context).unfocus();

    Navigator.of(context).pop(<String, String>{
      'province': province,
      'ward': ward,
    });
  }

  Widget _field({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          color: _MapScreenState.vnptBlue,
          size: 21,
        ),
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: Color(0xFFE4E7EC),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: _MapScreenState.vnptBlue,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      title: const Row(
        children: [
          Icon(
            Icons.filter_alt_rounded,
            color: _MapScreenState.vnptBlue,
          ),
          SizedBox(width: 9),
          Text(
            'Lọc hộ kinh doanh',
            style: TextStyle(
              color: _MapScreenState.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              controller: _provinceController,
              icon: Icons.location_city_rounded,
              label: 'Tỉnh / Thành phố',
              hint: 'Ví dụ: Đồng Nai',
            ),
            const SizedBox(height: 11),
            _field(
              controller: _wardController,
              icon: Icons.location_on_outlined,
              label: 'Phường / Xã',
              hint: 'Ví dụ: Long Bình',
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            _closeWithResult(province: '', ward: '');
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: _MapScreenState.vnptBlue,
            side: const BorderSide(
              color: Color(0xFFBBD5F5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'XÓA BỘ LỌC',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            _closeWithResult(
              province: _provinceController.text.trim(),
              ward: _wardController.text.trim(),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _MapScreenState.vnptBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'ÁP DỤNG',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================
// MODEL
// =============================================================

// Dữ liệu HKD + text đã chuẩn hóa sẵn để tìm kiếm/lọc nhanh.
class _IndexedLocation {
  final _BusinessLocation item;
  final String searchText;
  final String provinceText;
  final String wardText;

  const _IndexedLocation({
    required this.item,
    required this.searchText,
    required this.provinceText,
    required this.wardText,
  });
}

class _BusinessLocation {
  final String id;
  final String name;
  final String owner;
  final String phone;
  final String address;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> data;

  const _BusinessLocation({
    required this.id,
    required this.name,
    required this.owner,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.data,
  });
}



