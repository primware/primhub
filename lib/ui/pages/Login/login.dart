import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/auth_entry_api.dart';
import 'package:primhub/api/auth_api.dart' deferred as session_auth;
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:primhub/navigation/deferred_registry.dart';
import 'package:primhub/ui/pages/Login/login_selection_args.dart';
import 'package:primhub/build_version.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isCapsLockOn = false;
  bool _isShiftPressed = false;
  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();
  late AnimationController _animationController;
  late AnimationController _borderAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final String _loadingMessage = 'PrimHub';
  int _logoClickCount = 0;
  bool _showVersion = !Envirioment.isProduction;
  String _buildVersion = 'v-.-.-';

  @override
  void initState() {
    super.initState();

    if (appBuildVersion != '-.-.-') {
      _buildVersion = 'v$appBuildVersion';
    } else {
      const envVersion = String.fromEnvironment('APP_VERSION');
      if (envVersion.isNotEmpty) {
        _buildVersion = 'v$envVersion';
      } else {
        try {
          final build = html.window.localStorage['app_build'];
          if (build != null && build.isNotEmpty) {
            _buildVersion = 'v$build';
          }
        } catch (e) {
          // Ignore if not on web
        }
      }
    }

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
    RawKeyboard.instance.addListener(_handleKeyEvent);
    _userFocus.addListener(() => setState(() {}));
    _passFocus.addListener(() => setState(() {}));
    _loadSavedUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(
        const Duration(seconds: 1),
        DeferredRegistry.preloadHome,
      );
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _userController.dispose();
    _passController.dispose();
    _borderAnimationController.dispose();
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    bool shiftPressed = event.isShiftPressed;
    bool update = false;

    if (_isShiftPressed != shiftPressed) {
      _isShiftPressed = shiftPressed;
      update = true;
    }

    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.capsLock) {
      _isCapsLockOn = !_isCapsLockOn;
      update = true;
    }

    if (update) {
      setState(() {});
    }
  }

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUser = prefs.getString('saved_user');
    if (savedUser != null) _userController.text = savedUser;
  }

  void _login() async {
    TextInput.finishAutofillContext();
    setState(() {
      _isLoading = true;
    });

    final username = _userController.text.trim();
    final password = _passController.text.trim();

    // 1. Login Inicial (Step 1)
    final responseStep1 = await loginStep1(username, password);

    if (responseStep1.containsKey('error')) {
      final errorMessage = responseStep1['error'].toString();

      if (errorMessage.contains('401')) {
        _showError(AppLocale.invalidCredentials.getString(context));
      } else if (errorMessage.contains('Failed to fetch') ||
          errorMessage.contains('ClientException') ||
          errorMessage.contains('SocketException')) {
        _showError(AppLocale.connectionError.getString(context));
      } else {
        _showError(errorMessage);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_user', username);

    String tempToken = responseStep1['token'];
    Token.preAuth = tempToken;

    // Verificar si es login abreviado (ya tenemos token final) o necesitamos seleccionar contexto
    if (responseStep1.containsKey('clients')) {
      // Flujo Normal: Necesitamos seleccionar Cliente -> Rol -> Org
      List clients = responseStep1['clients'];
      if (clients.isEmpty) {
        _showError(AppLocale.noAssignedClients.getString(context));
        return;
      }

      // Lógica de auto-ingreso directo si solo tiene 1 cliente y 1 rol disponible
      if (clients.length == 1) {
        final client = clients[0];
        final roles = await getRoles(client['id'], tempToken);

        if (roles.length == 1) {
          final role = roles[0];
          final orgs = await getOrgs(client['id'], role['id'], tempToken);

          if (orgs.isNotEmpty) {
            final org = orgs[0];
            final warehouses = await getWarehouses(
              client['id'],
              role['id'],
              org['id'],
              tempToken,
            );
            // Tomamos el primer almacén por defecto o nulo
            int? warehouseId = warehouses.isNotEmpty
                ? warehouses[0]['id']
                : null;

            Token.client = client['id'];
            Token.rol = role['id'];
            Token.organitation = org['id'];
            Token.warehouseID = warehouseId;
            Token.roleUU =
                role['role-uu'] ?? role['uuid'] ?? role['AD_Role_UU'];

            Map<String, dynamic> params = {
              "clientId": client['id'],
              "roleId": role['id'],
              "organizationId": org['id'],
              "language": "es_CO",
            };
            if (warehouseId != null) params["warehouseId"] = warehouseId;

            await session_auth.loadLibrary();
            final responseFinal = await session_auth.finalizeLogin(
              username,
              password,
              params,
              context,
            );

            if (responseFinal == false) {
              ToastMessage.show(
                context: context,
                message: AppLocale.incorrectConfiguration.getString(context),
                type: ToastType.failure,
              );
            } else {
              if (mounted) {
                FocusScope.of(context).unfocus();
                await Future.delayed(const Duration(milliseconds: 150));

                if (mounted) {
                  CurrentLogMessage.add("Login exitoso (Auto - Ruta Única).");
                  // Escape the Dart Zone using pure JS eval to force a reload!
                  js.context.callMethod('eval', [
                    'setTimeout(function(){ window.location.reload(); }, 100);',
                  ]);
                }
              }
            }
            return; // Evita ir a la pantalla de selección
          }
        }
      }

      if (mounted) {
        FocusScope.of(context).unfocus();
        await Future.delayed(const Duration(milliseconds: 150));

        if (mounted) {
          setState(() => _isLoading = false);
          context.push(
            '/login-selection',
            extra: LoginSelectionArgs(
              token: tempToken,
              clients: clients,
              username: username,
              password: password,
            ),
          );
        }
      }
      return;
    } else {
      // Login Abreviado (Ya tenemos el token final)
      Token.auth = tempToken;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      CurrentLogMessage.add("Login exitoso. Token guardado.");
      // Escape the Dart Zone using pure JS eval to force a reload!
      js.context.callMethod('eval', [
        'setTimeout(function(){ window.location.reload(); }, 100);',
      ]);
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _isLoading = false);
      ToastMessage.show(
        context: context,
        message: message,
        type: ToastType.failure,
      );
    }
  }

  void _showChangeUrlDialog() {
    final TextEditingController urlController = TextEditingController(
      text: Endpoint.baseUrl,
    );

    showDialog(
      context: context,
      builder: (context) => CustomModal(
        title: AppLocale.configureServerUrl.getString(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocale.serverAddressHelp.getString(context)),
            const SizedBox(height: 16),
            CustomTextField(
              controller: urlController,
              label: 'Base URL',
              hintText: 'https://...',
            ),
            const SizedBox(height: 16),
            Text(
              AppLocale.buildVersion.getStringWithVariables(context, {
                'version': _buildVersion,
              }),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocale.cancel.getString(context)),
          ),
          CustomButton(
            text: AppLocale.save.getString(context),
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('api_base_url', newUrl);
                setState(() {
                  Endpoint.baseUrl = newUrl;
                });
                if (mounted) {
                  Navigator.pop(context);
                  ToastMessage.show(
                    context: context,
                    message: AppLocale.urlUpdated.getString(context),
                    type: ToastType.success,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showVersion)
            Text(
              _buildVersion,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (!Envirioment.isProduction) ...[
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _showChangeUrlDialog,
              child: const Icon(Icons.settings),
            ),
          ],
        ],
      ),
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
                          child: AutofillGroup(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  height: 130,
                                  width: 130,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: GestureDetector(
                                      onTap: () {
                                        _logoClickCount++;
                                        if (_logoClickCount >= 7) {
                                          setState(() => _showVersion = true);
                                          _logoClickCount = 0;
                                        }
                                      },
                                      child: Image.asset(
                                        'assets/LogoPrimHub.png',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'PrimHub',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                TextFormField(
                                  controller: _userController,
                                  textInputAction: TextInputAction.next,
                                  focusNode: _userFocus,
                                  autofillHints: const [AutofillHints.username],
                                  keyboardType: TextInputType
                                      .emailAddress, // Sugerencia para gestores de contraseñas
                                  decoration: InputDecoration(
                                    labelText: AppLocale.user.getString(
                                      context,
                                    ),
                                    hintText: AppLocale.enterUser.getString(
                                      context,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person_rounded,
                                    ),
                                    suffixIcon:
                                        (_userFocus.hasFocus &&
                                            (_isCapsLockOn != _isShiftPressed))
                                        ? Tooltip(
                                            message: AppLocale.capsLockOn
                                                .getString(context),
                                            child: const Icon(
                                              Icons.keyboard_capslock_rounded,
                                              color: Colors.orange,
                                            ),
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _login(),
                                  focusNode: _passFocus,
                                  keyboardType: TextInputType
                                      .visiblePassword, // Sugerencia para gestores de contraseñas
                                  autofillHints: const [AutofillHints.password],
                                  onEditingComplete:
                                      _login, // Para que el autocompletado funcione mejor
                                  decoration: InputDecoration(
                                    labelText: AppLocale.password.getString(
                                      context,
                                    ),
                                    hintText: AppLocale.enterPassword.getString(
                                      context,
                                    ),
                                    prefixIcon: const Icon(Icons.lock_rounded),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_passFocus.hasFocus &&
                                            (_isCapsLockOn != _isShiftPressed))
                                          Tooltip(
                                            message: AppLocale.capsLockOn
                                                .getString(context),
                                            child: const Icon(
                                              Icons.keyboard_capslock_rounded,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                          ),
                                          onPressed: () {
                                            setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                CustomDropdown<String>(
                                  value:
                                      FlutterLocalization
                                          .instance
                                          .currentLocale
                                          ?.languageCode ??
                                      'es',
                                  label: AppLocale.language.getString(context),
                                  hintText: AppLocale.language.getString(
                                    context,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'es',
                                      child: Text(
                                        AppLocale.spanish.getString(context),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'en',
                                      child: Text(
                                        AppLocale.english.getString(context),
                                      ),
                                    ),
                                  ],
                                  onChanged: (languageCode) async {
                                    if (languageCode == null) return;
                                    FlutterLocalization.instance.translate(
                                      languageCode,
                                    );
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setString(
                                      'languageCode',
                                      languageCode,
                                    );
                                  },
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
                                                _loadingMessage,
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: theme
                                                          .colorScheme
                                                          .onPrimary,
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : CustomButton(
                                          key: const ValueKey('button'),
                                          text: AppLocale.login.getString(
                                            context,
                                          ),
                                          onPressed: _login,
                                          isLoading: false,
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          borderRadius: 12,
                                        ),
                                ),
                              ],
                            ),
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
