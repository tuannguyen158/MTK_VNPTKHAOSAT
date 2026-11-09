import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static const String _enabledKey = 'biometric_enabled';

  /// Kiểm tra thiết bị có hỗ trợ sinh trắc học không
  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();

      if (!supported) {
        return false;
      }

      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra người dùng đã bật sinh trắc học chưa
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Bật sinh trắc học
  static Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_enabledKey, true);
  }

  /// Tắt sinh trắc học
  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_enabledKey, false);
  }

  /// Xác thực Face ID / Touch ID / Vân tay
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason:
        'Xác thực sinh trắc học để đăng nhập VNPT Khảo Sát',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Lấy danh sách sinh trắc học khả dụng
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Lấy tên sinh trắc học để hiển thị
  static Future<String> getBiometricName() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.contains(BiometricType.face)) {
      return 'Face ID';
    }

    if (biometrics.contains(BiometricType.fingerprint)) {
      return 'Vân tay';
    }

    if (biometrics.contains(BiometricType.iris)) {
      return 'Quét mống mắt';
    }

    if (biometrics.contains(BiometricType.strong)) {
      return 'Sinh trắc học';
    }

    return 'Sinh trắc học';
  }
}