
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../notification_helper.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController =
      TextEditingController();

  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool showPassword = false;
  bool showConfirmPassword = false;
  bool loading = false;
  bool passwordFocused = false;
  bool confirmPasswordFocused = false;

  static const Color vnptBlue = Color(0xFF0057B8);

  // =========================
  // ĐĂNG KÝ
  // =========================

  Future<void> register() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    // Tránh đăng ký nhiều lần
    if (loading) return;

    // Kiểm tra họ tên
    if (name.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập họ và tên.',
        type: NotificationType.warning,
      );
      return;
    }

    // Kiểm tra email
    if (email.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập email.',
        type: NotificationType.warning,
      );
      return;
    }

    // Kiểm tra mật khẩu
    if (password.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập mật khẩu.',
        type: NotificationType.warning,
      );
      return;
    }

    if (password.length < 6) {
      showAppNotification(
        context,
        'Mật khẩu quá ngắn',
        'Mật khẩu phải có ít nhất 6 ký tự.',
        type: NotificationType.warning,
      );
      return;
    }

    // Kiểm tra nhập lại mật khẩu
    if (confirmPassword.isEmpty) {
      showAppNotification(
        context,
        'Thiếu thông tin',
        'Vui lòng nhập lại mật khẩu.',
        type: NotificationType.warning,
      );
      return;
    }

    if (password != confirmPassword) {
      showAppNotification(
        context,
        'Mật khẩu không khớp',
        'Hai mật khẩu bạn nhập không giống nhau.',
        type: NotificationType.error,
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      // =========================
      // TẠO TÀI KHOẢN FIREBASE
      // =========================

      final UserCredential credential =
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;

      if (user == null) {
        throw Exception(
          'Không thể tạo tài khoản người dùng.',
        );
      }

      // Lưu tên vào Firebase Authentication
      await user.updateDisplayName(name);

      // =========================
      // LƯU THÔNG TIN USER
      // FIRESTORE
      // =========================

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'hoTen': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // =========================
      // THÔNG BÁO THÀNH CÔNG
      // =========================

      showAppNotification(
        context,
        'Đăng ký thành công',
        'Tài khoản của bạn đã được tạo.',
        type: NotificationType.success,
      );

      // =========================
      // VÀO HOME
      // =========================

      Future.delayed(
        const Duration(milliseconds: 700),
        () {
          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const HomeScreen(),
            ),
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String title = 'Đăng ký thất bại';
      String message = 'Không thể tạo tài khoản.';

      if (e.code == 'email-already-in-use') {
        title = 'Email đã tồn tại';
        message =
            'Email này đã được sử dụng cho một tài khoản khác.';
      } else if (e.code == 'invalid-email') {
        title = 'Email không hợp lệ';
        message =
            'Vui lòng kiểm tra lại địa chỉ email.';
      } else if (e.code == 'weak-password') {
        title = 'Mật khẩu quá yếu';
        message =
            'Vui lòng sử dụng mật khẩu mạnh hơn.';
      } else if (e.code == 'operation-not-allowed') {
        title = 'Chưa bật đăng ký';
        message =
            'Phương thức đăng nhập Email/Password chưa được bật trên Firebase.';
      }

      showAppNotification(
        context,
        title,
        message,
        type: NotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;

      showAppNotification(
        context,
        'Có lỗi xảy ra',
        'Không thể tạo tài khoản. Vui lòng thử lại.',
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

  // =========================
  // STYLE Ô NHẬP
  // =========================

  InputDecoration inputDecoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: vnptBlue,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: vnptBlue,
          width: 2,
        ),
      ),
      floatingLabelStyle: const TextStyle(
        color: vnptBlue,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // =========================
  // GIAO DIỆN
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 25,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 440,
              ),
              child: Column(
                children: [
                  // =====================
                  // NÚT QUAY LẠI
                  // =====================

                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: vnptBlue,
                        size: 28,
                      ),
                    ),
                  ),

                  const SizedBox(height: 5),

                  // =====================
                  // LOGO VNPT
                  // =====================

                  Image.asset(
                    'assets/images/vnpt1.jpg',
                    height: 75,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 18),

                  // =====================
                  // TIÊU ĐỀ
                  // =====================

                  const Text(
                    'VNPT ĐỒNG HÀNH CÙNG BẠN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: vnptBlue,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Tạo tài khoản để bắt đầu',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =====================
                  // KHUNG ĐĂNG KÝ
                  // =====================

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // =====================
                        // TIÊU ĐỀ FORM
                        // =====================

                        const Text(
                          'Tạo tài khoản',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: vnptBlue,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Nhập thông tin của bạn để đăng ký',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 25),

                        // =====================
                        // HỌ TÊN
                        // =====================

                        TextField(
                          controller: nameController,
                          textCapitalization:
                              TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: inputDecoration(
                            'Họ và tên',
                            Icons.person_outline_rounded,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // =====================
                        // EMAIL
                        // =====================

                        TextField(
                          controller: emailController,
                          keyboardType:
                              TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: inputDecoration(
                            'Email',
                            Icons.email_outlined,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // =====================
                        // MẬT KHẨU
                        // =====================

                        Focus(
                          onFocusChange: (hasFocus) {
                            if (!mounted) return;

                            setState(() {
                              passwordFocused = hasFocus;
                            });
                          },
                          child: TextField(
                            controller: passwordController,
                            obscureText: !showPassword,
                            textInputAction: TextInputAction.next,
                            decoration: inputDecoration(
                              'Mật khẩu',
                              Icons.lock_outline_rounded,
                              suffixIcon: passwordFocused
                                  ? IconButton(
                                      onPressed: () {
                                        setState(() {
                                          showPassword =
                                              !showPassword;
                                        });
                                      },
                                      icon: Icon(
                                        showPassword
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        color: vnptBlue,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        // =====================
                        // NHẬP LẠI MẬT KHẨU
                        // =====================

                        Focus(
                          onFocusChange: (hasFocus) {
                            if (!mounted) return;

                            setState(() {
                              confirmPasswordFocused = hasFocus;
                            });
                          },
                          child: TextField(
                            controller:
                                confirmPasswordController,
                            obscureText: !showConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!loading) {
                                register();
                              }
                            },
                            decoration: inputDecoration(
                              'Nhập lại mật khẩu',
                              Icons.lock_outline_rounded,
                              suffixIcon: confirmPasswordFocused
                                  ? IconButton(
                                      onPressed: () {
                                        setState(() {
                                          showConfirmPassword =
                                              !showConfirmPassword;
                                        });
                                      },
                                      icon: Icon(
                                        showConfirmPassword
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        color: vnptBlue,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // =====================
                        // NÚT ĐĂNG KÝ
                        // =====================

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: loading ? null : register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: vnptBlue,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),
                            child: loading
                                ? const SizedBox(
                                    width: 23,
                                    height: 23,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'ĐĂNG KÝ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // =====================
                        // ĐÃ CÓ TÀI KHOẢN
                        // =====================

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Đã có tài khoản?',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Đăng nhập',
                                style: TextStyle(
                                  color: vnptBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    '© VNPT Tập Đoàn Viễn Thông Việt Nam',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
