import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notification_helper.dart';
import '../services/biometric_service.dart';
import 'register_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode passwordFocusNode = FocusNode();

  static const Color vnptBlue = Color(0xFF0149CF);

  bool showPassword = false;
  bool loading = false;
  bool rememberLogin = false;
  bool checkingSavedLogin = true;

  bool biometricAvailable = false;
  bool biometricEnabled = false;
  bool biometricChecking = false;

  late final Future<void> _googleInitialization;

  @override
  void initState() {
    super.initState();

    _googleInitialization = GoogleSignIn.instance.initialize();

    passwordFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _loadLoginState();
  }

  // =========================================================
  // KIỂM TRA ĐỊNH DẠNG EMAIL
  // =========================================================

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  // =========================================================
  // KIỂM TRA TRẠNG THÁI ĐĂNG NHẬP
  // =========================================================

  Future<void> _loadLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedRemember = prefs.getBool('remember_login') ?? false;

      final savedEmail = prefs.getString('saved_email') ?? '';

      final available = await BiometricService.isAvailable();

      final enabled = await BiometricService.isEnabled();

      if (!mounted) return;

      setState(() {
        rememberLogin = savedRemember;
        emailController.text = savedEmail;

        biometricAvailable = available;
        biometricEnabled = enabled;

        checkingSavedLogin = false;
      });

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null && savedRemember && enabled && available) {
        await _authenticateBiometric();
        return;
      }

      if (currentUser != null && savedRemember && !enabled) {
        _goToHome();
      }
    } catch (e) {
      debugPrint('Load login state error: $e');

      if (!mounted) return;

      setState(() {
        checkingSavedLogin = false;
      });
    }
  }

  // =========================================================
  // XÁC THỰC SINH TRẮC HỌC
  // =========================================================

  Future<void> _authenticateBiometric() async {
    if (!mounted) return;

    setState(() {
      biometricChecking = true;
    });

    final success = await BiometricService.authenticate();

    if (!mounted) return;

    setState(() {
      biometricChecking = false;
    });

    if (success) {
      _goToHome();
      return;
    }

    showAppNotification(
      context,
      'Xác thực chưa thành công',
      'Bạn có thể đăng nhập bằng email và mật khẩu.',
      type: NotificationType.warning,
    );
  }

  // =========================================================
  // HỎI CÓ BẬT SINH TRẮC HỌC KHÔNG
  // =========================================================

  Future<void> _askEnableBiometric() async {
    if (!biometricAvailable) {
      _goToHome();
      return;
    }

    final biometricName = await BiometricService.getBiometricName();

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: vnptBlue,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Đăng nhập nhanh',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            'Bạn có muốn sử dụng '
            '$biometricName để đăng nhập nhanh '
            'vào VNPT Khảo Sát ở những lần sau không?',
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text(
                'Bỏ qua',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: vnptBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: const Text(
                'Bật ngay',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (result != true) {
      _goToHome();
      return;
    }

    final authenticated = await BiometricService.authenticate();

    if (!mounted) return;

    if (authenticated) {
      await BiometricService.enable();

      if (!mounted) return;

      setState(() {
        biometricEnabled = true;
      });

      showAppNotification(
        context,
        'Đã bật sinh trắc học',
        'Lần sau bạn có thể dùng '
            '$biometricName để đăng nhập nhanh.',
        type: NotificationType.success,
      );
    }

    _goToHome();
  }

  // =========================================================
  // LƯU ĐĂNG NHẬP
  // =========================================================

  Future<void> _saveRememberedLogin() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('remember_login', rememberLogin);

    if (rememberLogin) {
      await prefs.setString('saved_email', emailController.text.trim());
    } else {
      await prefs.remove('saved_email');
    }
  }

  // =========================================================
  // ĐI TỚI HOME
  // =========================================================

  void _goToHome() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  // =========================================================
  // ĐĂNG NHẬP EMAIL / PASSWORD
  // =========================================================

  Future<void> login() async {
    if (loading) return;

    final email = emailController.text.trim();

    final password = passwordController.text;

    if (email.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập địa chỉ email.',
        type: NotificationType.warning,
      );
      return;
    }

    // Kiểm tra định dạng email trước khi đăng nhập.
    if (!_isValidEmail(email)) {
      showAppNotification(
        context,
        'Email không hợp lệ',
        'Vui lòng nhập đúng định dạng email.',
        type: NotificationType.warning,
      );
      return;
    }

    if (password.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập mật khẩu.',
        type: NotificationType.warning,
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      // =====================================================
      // KIỂM TRA TRẠNG THÁI TÀI KHOẢN
      // =====================================================

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final data = userDoc.data();

        final status = data?['status']?.toString().toLowerCase() ?? 'active';

        if (status == 'disabled' || status == 'deleted') {
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;

          showAppNotification(
            context,
            'Tài khoản bị khóa',
            'Tài khoản này đã bị Admin khóa '
                'hoặc xóa khỏi ứng dụng.',
            type: NotificationType.warning,
          );

          return;
        }
      }

      // =====================================================
      // LƯU ĐĂNG NHẬP
      // =====================================================

      try {
        await _saveRememberedLogin();
      } catch (e) {
        debugPrint('SharedPreferences error: $e');
      }

      if (!mounted) return;

      if (biometricAvailable && !biometricEnabled) {
        await _askEnableBiometric();
        return;
      }

      _goToHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = 'Không thể đăng nhập.';

      switch (e.code) {
        case 'user-not-found':
          message = 'Tài khoản này chưa được đăng ký.';
          break;

        case 'wrong-password':
          message = 'Mật khẩu không chính xác.';
          break;

        case 'invalid-credential':
          message = 'Email hoặc mật khẩu không chính xác.';
          break;

        case 'invalid-email':
          message = 'Địa chỉ email không hợp lệ.';
          break;

        case 'user-disabled':
          message = 'Tài khoản này đã bị vô hiệu hóa.';
          break;
      }

      showAppNotification(
        context,
        'Đăng nhập thất bại',
        message,
        type: NotificationType.error,
      );
    } catch (e) {
      debugPrint('Email login error: $e');

      if (!mounted) return;

      showAppNotification(
        context,
        'Có lỗi xảy ra',
        'Không thể thực hiện đăng nhập. '
            'Hãy kiểm tra Firebase hoặc thử lại.',
        type: NotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // =========================================================
  // ĐĂNG NHẬP GOOGLE
  // =========================================================

  Future<void> loginWithGoogle() async {
    if (loading) return;

    setState(() {
      loading = true;
    });

    try {
      await _googleInitialization;

      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCredential.user;

      if (user == null) {
        throw Exception('Không lấy được thông tin tài khoản Google.');
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final userSnapshot = await userRef.get();

      if (userSnapshot.exists) {
        final data = userSnapshot.data();

        final status = data?['status']?.toString().toLowerCase() ?? 'active';

        if (status == 'disabled' || status == 'deleted') {
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;

          showAppNotification(
            context,
            'Tài khoản bị khóa',
            'Tài khoản này đã bị Admin khóa '
                'hoặc xóa khỏi ứng dụng.',
            type: NotificationType.warning,
          );

          return;
        }

        // Không ghi đè role.
        await userRef.set({
          'uid': user.uid,
          'hoTen': user.displayName ?? 'Người dùng Google',
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'provider': 'google',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Google mới mặc định Nhân viên.
        await userRef.set({
          'uid': user.uid,
          'hoTen': user.displayName ?? 'Người dùng Google',
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'provider': 'google',
          'role': 'nhanvien',
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // =====================================================
      // LƯU ĐĂNG NHẬP
      // =====================================================

      try {
        await _saveRememberedLogin();
      } catch (e) {
        debugPrint('SharedPreferences error: $e');
      }

      if (!mounted) return;

      showAppNotification(
        context,
        'Đăng nhập thành công',
        'Chào mừng ${user.displayName ?? 'bạn'}!',
        type: NotificationType.success,
      );

      await Future.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;

      if (biometricAvailable && !biometricEnabled) {
        await _askEnableBiometric();
        return;
      }

      _goToHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = 'Không thể đăng nhập bằng Google.';

      if (e.code == 'account-exists-with-different-credential') {
        message =
            'Email này đang thuộc một tài khoản '
            'đăng nhập khác.';
      } else if (e.code == 'operation-not-allowed') {
        message =
            'Bạn chưa bật đăng nhập Google '
            'trong Firebase Authentication.';
      }

      showAppNotification(
        context,
        'Đăng nhập Google thất bại',
        message,
        type: NotificationType.error,
      );
    } catch (e) {
      debugPrint('Google login error: $e');

      if (!mounted) return;

      showAppNotification(
        context,
        'Đăng nhập Google thất bại',
        'Google Sign-In gặp lỗi. '
            'Kiểm tra cấu hình Google/Firebase rồi thử lại.',
        type: NotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // =========================================================
  // QUÊN MẬT KHẨU
  // =========================================================

  Future<void> forgotPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      showAppNotification(
        context,
        'Quên mật khẩu',
        'Vui lòng nhập email trước.',
        type: NotificationType.warning,
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      showAppNotification(
        context,
        'Đã gửi email',
        'Hãy kiểm tra hộp thư để đặt lại mật khẩu.',
        type: NotificationType.success,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = 'Không thể gửi email đặt lại mật khẩu.';

      if (e.code == 'user-not-found') {
        message = 'Không tìm thấy tài khoản với email này.';
      } else if (e.code == 'invalid-email') {
        message = 'Địa chỉ email không hợp lệ.';
      }

      showAppNotification(
        context,
        'Không thể gửi email',
        message,
        type: NotificationType.error,
      );
    } catch (_) {
      if (!mounted) return;

      showAppNotification(
        context,
        'Có lỗi xảy ra',
        'Không thể thực hiện yêu cầu.',
        type: NotificationType.error,
      );
    }
  }

  // =========================================================
  // STYLE Ô NHẬP
  // =========================================================

  InputDecoration inputDecoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: vnptBlue, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF5FBFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: vnptBlue, width: 1.5),
      ),
      floatingLabelStyle: const TextStyle(
        color: vnptBlue,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    passwordFocusNode.dispose();

    super.dispose();
  }

  // =========================================================
  // GIAO DIỆN
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    final compact = height < 700;

    if (checkingSavedLogin || biometricChecking) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: vnptBlue),
              const SizedBox(height: 18),
              if (biometricChecking)
                const Text(
                  'Xác thực sinh trắc học...',
                  style: TextStyle(
                    color: vnptBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0072CE), Color(0xFF00AEEF), Color(0xFFEAF6FF)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 22,
                vertical: compact ? 8 : 14,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // LOGO

                    Image.asset(
                      'assets/images/123.png',
                      height: compact ? 150 : 206,
                      fit: BoxFit.contain,
                    ),

                    SizedBox(height: compact ? 4 : 7),

                    const Text(
                      'VNPT ĐỒNG HÀNH CÙNG BẠN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 3),

                    const Text(
                      'Hệ thống khảo sát khách hàng',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    SizedBox(height: compact ? 11 : 14),

                    // KHUNG LOGIN
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        compact ? 18 : 21,
                        compact ? 18 : 21,
                        compact ? 18 : 21,
                        compact ? 14 : 17,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(21),
                        border: Border.all(color: const Color(0xFFE4E8EF)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.055),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Đăng nhập',
                            style: TextStyle(
                              color: vnptBlue,
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 2),

                          const Text(
                            'Đăng nhập để tiếp tục sử dụng hệ thống',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF7A8493),
                              fontSize: 13,
                            ),
                          ),

                          SizedBox(height: compact ? 14 : 17),

                          // EMAIL
                          SizedBox(
                            height: 54,
                            child: TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: inputDecoration(
                                'Email',
                                Icons.email_outlined,
                              ),
                            ),
                          ),

                          const SizedBox(height: 9),

                          // MẬT KHẨU
                          SizedBox(
                            height: 54,
                            child: TextField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: !showPassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!loading) {
                                  login();
                                }
                              },
                              decoration: inputDecoration(
                                'Mật khẩu',
                                Icons.lock_outline_rounded,
                                suffixIcon: passwordFocusNode.hasFocus
                                    ? IconButton(
                                        tooltip: showPassword
                                            ? 'Ẩn mật khẩu'
                                            : 'Hiện mật khẩu',
                                        onPressed: () {
                                          setState(() {
                                            showPassword = !showPassword;
                                          });
                                        },
                                        icon: Icon(
                                          showPassword
                                              ? Icons.visibility_rounded
                                              : Icons.visibility_off_rounded,
                                          color: vnptBlue,
                                          size: 20,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),

                          const SizedBox(height: 2),

                          // LƯU ĐĂNG NHẬP + QUÊN MẬT KHẨU
                          SizedBox(
                            height: 39,
                            child: Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: loading
                                      ? null
                                      : () {
                                          setState(() {
                                            rememberLogin = !rememberLogin;
                                          });
                                        },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Checkbox(
                                        value: rememberLogin,
                                        activeColor: vnptBlue,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: loading
                                            ? null
                                            : (value) {
                                                setState(() {
                                                  rememberLogin =
                                                      value ?? false;
                                                });
                                              },
                                      ),
                                      const Text(
                                        'Lưu đăng nhập',
                                        style: TextStyle(
                                          color: Color(0xFF4B5563),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Spacer(),

                                TextButton(
                                  onPressed: loading ? null : forgotPassword,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Quên mật khẩu?',
                                    style: TextStyle(
                                      color: vnptBlue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 4),

                          // ĐĂNG NHẬP
                          SizedBox(
                            width: double.infinity,
                            height: 51,
                            child: ElevatedButton(
                              onPressed: loading ? null : login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: vnptBlue,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 21,
                                      height: 21,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'ĐĂNG NHẬP',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // HOẶC
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  height: 1,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 9),
                                child: Text(
                                  'HOẶC',
                                  style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // GOOGLE
                          SizedBox(
                            width: double.infinity,
                            height: 51,
                            child: OutlinedButton.icon(
                              onPressed: loading ? null : loginWithGoogle,
                              icon: const Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              label: const Text(
                                'ĐĂNG NHẬP BẰNG GOOGLE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF172033),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFFD0D5DD),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 5),

                          // ĐĂNG KÝ
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Chưa có tài khoản?',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 13,
                                ),
                              ),
                              TextButton(
                                onPressed: loading
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RegisterScreen(),
                                          ),
                                        );
                                      },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.only(
                                    left: 5,
                                    right: 5,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Đăng ký ngay',
                                  style: TextStyle(
                                    color: vnptBlue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: compact ? 4 : 7),

                    const Text(
                      '© VNPT Tập Đoàn Viễn Thông Việt Nam',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8A93A1), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
