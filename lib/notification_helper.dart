import 'package:flutter/material.dart';

enum NotificationType {
  success,
  error,
  warning,
  info,
}

void showAppNotification(
    BuildContext context,
    String title,
    String message, {
      NotificationType type = NotificationType.info,
    }) {
  final overlay = Overlay.of(context);

  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => _AppNotification(
      title: title,
      message: message,
      type: type,
      onClose: () {
        if (entry.mounted) {
          entry.remove();
        }
      },
    ),
  );

  overlay.insert(entry);

  Future.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) {
      entry.remove();
    }
  });
}

class _AppNotification extends StatefulWidget {
  final String title;
  final String message;
  final NotificationType type;
  final VoidCallback onClose;

  const _AppNotification({
    required this.title,
    required this.message,
    required this.type,
    required this.onClose,
  });

  @override
  State<_AppNotification> createState() => _AppNotificationState();
}

class _AppNotificationState extends State<_AppNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<Offset> slide;
  late Animation<double> fade;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    slide = Tween<Offset>(
      begin: const Offset(0, -1.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutBack,
      ),
    );

    fade = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
    );

    controller.forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Color get mainColor {
    switch (widget.type) {
      case NotificationType.success:
        return const Color(0xFF16A34A);

      case NotificationType.error:
        return const Color(0xFFDC2626);

      case NotificationType.warning:
        return const Color(0xFFF59E0B);

      case NotificationType.info:
        return const Color(0xFF2563EB);
    }
  }

  IconData get icon {
    switch (widget.type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;

      case NotificationType.error:
        return Icons.error_rounded;

      case NotificationType.warning:
        return Icons.warning_rounded;

      case NotificationType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: mainColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: mainColor,
                      size: 27,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          widget.message,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF6B7280),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF9CA3AF),
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