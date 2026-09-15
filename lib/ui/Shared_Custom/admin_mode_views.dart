import 'package:flutter/material.dart';
import 'package:primhub/api/admin_view_mode.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class AdminModeViews extends StatefulWidget {
  const AdminModeViews({super.key});

  @override
  State<AdminModeViews> createState() => _AdminModeViewsState();
}

class SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final Color shadowColor;
  final double shadowOpacity;

  SpotlightPainter({
    required this.targetRect,
    required this.shadowColor,
    required this.shadowOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Path background = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(6), // Pequeño margen alrededor del botón
          const Radius.circular(12),
        ),
      );

    final Path result = Path.combine(
      PathOperation.difference,
      background,
      hole,
    );

    final Paint paint = Paint()
      ..color = shadowColor.withOpacity(shadowOpacity)
      ..style = PaintingStyle.fill;

    canvas.drawPath(result, paint);
  }

  @override
  bool shouldRepaint(covariant SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}

class _AdminModeViewsState extends State<AdminModeViews> {
  final GlobalKey modeButtonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  final AdminViewModeManager adminViewModeManager = AdminViewModeManager();

  @override
  void initState() {
    super.initState();
    _checkAndShowTutorial();
  }

  @override
  void dispose() {
    _removeTutorial();
    super.dispose();
  }

  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownTutorial =
        prefs.getBool('hasShownAdminModeTutorial') ?? false;

    if (!hasShownTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTutorial();
      });
      await prefs.setBool('hasShownAdminModeTutorial', true);
    }
  }

  void _showTutorial() {
    if (_overlayEntry != null) return;

    final renderBox =
        modeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final targetRect = position & size;

    final modeName = _modeLabel(context, adminViewModeManager.currentMode);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        final colorScheme = Theme.of(context).colorScheme;

        return Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _removeTutorial(),
            child: Stack(
              children: [
                // Custom Spotlight Background
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: SpotlightPainter(
                        targetRect: targetRect,
                        shadowColor: colorScheme.primary,
                        shadowOpacity: 0.7,
                      ),
                    ),
                  ),
                ),
                // Tooltip Positioned
                Positioned(
                  top: position.dy + size.height + 12,
                  right: screenSize.width - (position.dx + size.width),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppLocale.viewMode.getString(context),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocale.viewModeTutorial
                                    .getStringWithVariables(context, {
                                      'mode': modeName,
                                    }),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
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

    Overlay.of(context).insert(_overlayEntry!);

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) _removeTutorial();
    });
  }

  void _removeTutorial() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return ListenableBuilder(
      listenable: adminViewModeManager,
      builder: (context, child) {
        if (isMobile) {
          return _buildMobileMenu(context, adminViewModeManager);
        }
        return _buildAdminModePopupMenu(context, adminViewModeManager);
      },
    );
  }

  void _confirmAdminModeChange(
    BuildContext context,
    AdminViewMode mode,
    AdminViewModeManager manager,
  ) {
    if (manager.currentMode == mode) return;

    String modeName = '';
    String description = '';
    Color modeColor = Colors.blue;

    switch (mode) {
      case AdminViewMode.mixed:
        modeName = AppLocale.mixedMode.getString(context);
        modeColor = Colors.blueAccent;
        description = AppLocale.mixedModeDescription.getString(context);
        break;
      case AdminViewMode.support:
        modeName = AppLocale.supportMode.getString(context);
        modeColor = Colors.orange;
        description = AppLocale.supportModeDescription.getString(context);
        break;
      case AdminViewMode.project:
        modeName = AppLocale.projectMode.getString(context);
        modeColor = Colors.teal;
        description = AppLocale.projectModeDescription.getString(context);
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => CustomModal(
        title: AppLocale.changeToMode.getStringWithVariables(context, {'mode': modeName}),
        width: 450,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            Text(
              AppLocale.modeChangeNote.getString(context),
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          CustomButton(
            text: AppLocale.cancel.getString(context),
            backgroundColor: Colors.grey.shade400,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CustomButton(
            text: AppLocale.accept.getString(context),
            backgroundColor: modeColor,
            onPressed: () {
              manager.saveMode(mode);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  Color _getModeColor(AdminViewMode mode) {
    switch (mode) {
      case AdminViewMode.mixed:
        return Colors.blueAccent;
      case AdminViewMode.support:
        return Colors.orange;
      case AdminViewMode.project:
        return Colors.teal;
    }
  }

  void _showAdminModeSelectionDialog(
    BuildContext context,
    AdminViewModeManager manager,
  ) {
    final current = manager.currentMode;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return CustomModal(
          title: AppLocale.viewMode.getString(context),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.layers,
                  color: _getModeColor(AdminViewMode.mixed),
                ),
                title: Text(
                  AppLocale.mixedMode.getString(context),
                  style: TextStyle(color: _getModeColor(AdminViewMode.mixed)),
                ),
                trailing: current == AdminViewMode.mixed
                    ? Icon(
                        Icons.check,
                        color: _getModeColor(AdminViewMode.mixed),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _confirmAdminModeChange(
                    context,
                    AdminViewMode.mixed,
                    manager,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.support_agent,
                  color: _getModeColor(AdminViewMode.support),
                ),
                title: Text(
                  AppLocale.supportMode.getString(context),
                  style: TextStyle(color: _getModeColor(AdminViewMode.support)),
                ),
                trailing: current == AdminViewMode.support
                    ? Icon(
                        Icons.check,
                        color: _getModeColor(AdminViewMode.support),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _confirmAdminModeChange(
                    context,
                    AdminViewMode.support,
                    manager,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.account_tree,
                  color: _getModeColor(AdminViewMode.project),
                ),
                title: Text(
                  AppLocale.projectMode.getString(context),
                  style: TextStyle(color: _getModeColor(AdminViewMode.project)),
                ),
                trailing: current == AdminViewMode.project
                    ? Icon(
                        Icons.check,
                        color: _getModeColor(AdminViewMode.project),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _confirmAdminModeChange(
                    context,
                    AdminViewMode.project,
                    manager,
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocale.close.getString(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileMenu(BuildContext context, AdminViewModeManager manager) {
    return PopupMenuButton<String>(
      key: modeButtonKey,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'admin_mode') {
          _showAdminModeSelectionDialog(context, manager);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'admin_mode',
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: Text(
              '${AppLocale.viewMode.getString(context)}: ${_modeLabel(context, manager.currentMode)}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminModePopupMenu(
    BuildContext context,
    AdminViewModeManager manager,
  ) {
    final currentMode = manager.currentMode;
    final currentColor = _getModeColor(currentMode);

    return PopupMenuButton<AdminViewMode>(
      key: modeButtonKey,
      tooltip: AppLocale.viewMode.getString(context),
      onSelected: (AdminViewMode mode) {
        _confirmAdminModeChange(context, mode, manager);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: currentColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: currentColor.withOpacity(0.8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                currentMode == AdminViewMode.support
                    ? AppLocale.supportMode.getString(context)
                    : (currentMode == AdminViewMode.project
                          ? AppLocale.projectMode.getString(context)
                          : AppLocale.mixedMode.getString(context)),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
      itemBuilder: (BuildContext context) {
        PopupMenuItem<AdminViewMode> buildItem(
          AdminViewMode mode,
          String text,
        ) {
          final isSelected = currentMode == mode;
          final modeColor = _getModeColor(mode);

          return PopupMenuItem<AdminViewMode>(
            value: mode,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isSelected
                    ? modeColor.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    mode == AdminViewMode.mixed
                        ? Icons.layers
                        : (mode == AdminViewMode.support
                              ? Icons.support_agent
                              : Icons.account_tree),
                    color: modeColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: modeColor,
                    ),
                  ),
                  if (isSelected) const Spacer(),
                  if (isSelected) Icon(Icons.check, size: 18, color: modeColor),
                ],
              ),
            ),
          );
        }

        return [
          buildItem(
            AdminViewMode.mixed,
            AppLocale.mixedMode.getString(context),
          ),
          buildItem(
            AdminViewMode.support,
            AppLocale.supportMode.getString(context),
          ),
          buildItem(
            AdminViewMode.project,
            AppLocale.projectMode.getString(context),
          ),
        ];
      },
    );
  }

  String _modeLabel(BuildContext context, AdminViewMode mode) {
    return switch (mode) {
      AdminViewMode.mixed => AppLocale.mixedMode.getString(context),
      AdminViewMode.support => AppLocale.supportMode.getString(context),
      AdminViewMode.project => AppLocale.projectMode.getString(context),
    };
  }
}
