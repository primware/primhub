import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage>
    with TickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animationController;
  late AnimationController _borderAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();

    _borderAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _borderAnimationController.dispose();
    _userController.dispose();
    super.dispose();
  }

  void _resetPassword() async {
    if (_userController.text.trim().isEmpty) {
      ToastMessage.show(
        context: context,
        message: AppLocale.enterUserOrEmail.getString(context),
        type: ToastType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Simular llamada al API
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      ToastMessage.show(
        context: context,
        message: AppLocale.instructionsSent.getString(context),
        type: ToastType.success,
      );
      context.pop(); // Regresa al login
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Animated Border
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _borderAnimationController,
                            builder: (context, child) {
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: SweepGradient(
                                    center: Alignment.center,
                                    colors: [
                                      theme.colorScheme.primary.withOpacity(
                                        0.0,
                                      ),
                                      theme.colorScheme.primary.withOpacity(
                                        0.8,
                                      ),
                                      theme.colorScheme.primaryContainer
                                          .withOpacity(0.8),
                                      theme.colorScheme.primary.withOpacity(
                                        0.0,
                                      ),
                                    ],
                                    stops: const [0.0, 0.4, 0.6, 1.0],
                                    transform: GradientRotation(
                                      _borderAnimationController.value *
                                          2 *
                                          3.14159,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Main Content
                        Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.all(29),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 100,
                                width: 100,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(
                                    0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Image.asset('assets/LogoPrimHub.png'),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                AppLocale.recoverPassword.getString(context),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                AppLocale.recoverPasswordHelp.getString(
                                  context,
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 32),
                              TextFormField(
                                controller: _userController,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _resetPassword(),
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: AppLocale.userOrEmail.getString(
                                    context,
                                  ),
                                  hintText: AppLocale.enterUser.getString(
                                    context,
                                  ),
                                  prefixIcon: const Icon(Icons.person_rounded),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                switchInCurve: Curves.elasticOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                child: _isLoading
                                    ? Container(
                                        key: const ValueKey('loading'),
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              AppLocale.sending.getString(
                                                context,
                                              ),
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.onPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color:
                                                    theme.colorScheme.onPrimary,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : CustomButton(
                                        key: const ValueKey('button'),
                                        text: AppLocale.sendInstructions
                                            .getString(context),
                                        onPressed: _resetPassword,
                                        isLoading: false,
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        borderRadius: 12,
                                      ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  context.pop();
                                },
                                child: Text(
                                  AppLocale.backToLogin.getString(context),
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
