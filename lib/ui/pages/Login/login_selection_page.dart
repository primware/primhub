import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/auth_entry_api.dart';
import 'package:primhub/api/auth_api.dart' deferred as session_auth;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:primhub/api/token.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/pages/Login/login_selection_args.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';

class LoginSelectionPage extends StatefulWidget {
  const LoginSelectionPage({this.args, super.key});
  final LoginSelectionArgs? args;

  @override
  State<LoginSelectionPage> createState() => _LoginSelectionPageState();
}

class _LoginSelectionPageState extends State<LoginSelectionPage> {
  String? _tempToken;
  String? _username;
  String? _password;
  List<dynamic> _clients = [];

  int? _selectedClientId;
  int? _selectedRoleId;
  int? _selectedOrgId;
  int? _selectedWarehouseId;

  List<dynamic> _roles = [];
  List<dynamic> _orgs = [];
  List<dynamic> _warehouses = [];

  bool _isLoading = false;
  bool _isInit = true;

  List<dynamic> _uniqueById(List<dynamic> list) {
    final seen = <int>{};
    return list.where((item) {
      final val = item['id'];
      final id = (val as num?)?.toInt();
      if (id != null && !seen.contains(id)) {
        seen.add(id);
        item['id'] =
            id; // Ensure the item map has the integer id for the dropdown
        return true;
      }
      return false;
    }).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final args = widget.args;
      if (args != null) {
        _tempToken = args.token;
        _clients = _uniqueById(args.clients);
        _username = args.username;
        _password = args.password;
        Token.preAuth = _tempToken;
      }
      _isInit = false;
      _autoSelectLastConfiguration();
    }
  }

  Future<void> _autoSelectLastConfiguration() async {
    if (_clients.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastClientId = prefs.getInt('last_login_client_id');
    final lastRoleId = prefs.getInt('last_login_role_id');
    final lastOrgId = prefs.getInt('last_login_org_id');

    if (lastClientId != null && _clients.any((c) => c['id'] == lastClientId)) {
      await _onClientChanged(lastClientId);

      if (lastRoleId != null && _roles.any((r) => r['id'] == lastRoleId)) {
        await _onRoleChanged(lastRoleId);

        if (lastOrgId != null && _orgs.any((o) => o['id'] == lastOrgId)) {
          await _onOrgChanged(lastOrgId);
        }
      }
    }
  }

  String _getName(dynamic item) {
    if (item is Map) {
      return item['name'] ?? item['identifier'] ?? item['id'].toString();
    }
    return item.toString();
  }

  Future<void> _onClientChanged(int? clientId) async {
    if (clientId == null) return;
    setState(() {
      _selectedClientId = clientId;
      _selectedRoleId = null;
      _selectedOrgId = null;
      _selectedWarehouseId = null;
      _roles = [];
      _orgs = [];
      _warehouses = [];
      _isLoading = true;
    });

    final roles = await getRoles(clientId, _tempToken!);

    if (mounted) {
      setState(() {
        _roles = _uniqueById(roles);
        _isLoading = false;
      });
    }
  }

  Future<void> _onRoleChanged(int? roleId) async {
    if (roleId == null) return;
    setState(() {
      _selectedRoleId = roleId;
      _selectedOrgId = null;
      _selectedWarehouseId = null;
      _orgs = [];
      _warehouses = [];
      _isLoading = true;
    });

    final orgs = await getOrgs(_selectedClientId!, roleId, _tempToken!);

    if (mounted) {
      setState(() {
        _orgs = _uniqueById(orgs);
        _isLoading = false;
      });
    }
  }

  Future<void> _onOrgChanged(int? orgId) async {
    if (orgId == null) return;
    setState(() {
      _selectedOrgId = orgId;
      _selectedWarehouseId = null;
      _warehouses = [];
      _isLoading = true;
    });

    final warehouses = await getWarehouses(
      _selectedClientId!,
      _selectedRoleId!,
      orgId,
      _tempToken!,
    );

    if (mounted) {
      setState(() {
        _warehouses = warehouses;
        if (_warehouses.isNotEmpty) {
          _selectedWarehouseId = _warehouses.first['id'];
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _finalizeLogin() async {
    if (_selectedClientId == null ||
        _selectedRoleId == null ||
        _selectedOrgId == null) {
      ToastMessage.show(
        context: context,
        message: AppLocale.selectLoginContext.getString(context),
        type: ToastType.warning,
      );
      return;
    }

    if (_username == null || _password == null) {
      ToastMessage.show(
        context: context,
        message: AppLocale.credentialError.getString(context),
        type: ToastType.failure,
      );
      return;
    }

    setState(() => _isLoading = true);

    Token.client = _selectedClientId;
    Token.rol = _selectedRoleId;
    Token.organitation = _selectedOrgId;
    Token.warehouseID = _selectedWarehouseId;

    // Capturar el AD_Role_UU del rol seleccionado
    try {
      final selectedRole = _roles.firstWhere(
        (r) => r['id'] == _selectedRoleId,
        orElse: () => null,
      );
      if (selectedRole != null) {
        Token.roleUU =
            selectedRole['role-uu'] ??
            selectedRole['uuid'] ??
            selectedRole['AD_Role_UU'];
        CurrentLogMessage.add("Rol seleccionado UUID: ${Token.roleUU}");
      }
    } catch (e) {
      CurrentLogMessage.add("Error capturando UUID del rol: $e");
    }

    Map<String, dynamic> params = {
      "clientId": _selectedClientId,
      "roleId": _selectedRoleId,
      "organizationId": _selectedOrgId,
      "language": "es_CO",
    };
    if (_selectedWarehouseId != null) {
      params["warehouseId"] = _selectedWarehouseId;
    }

    await session_auth.loadLibrary();
    final response = await session_auth.finalizeLogin(
      _username!,
      _password!,
      params,
      context,
    );

    if (mounted) {
      if (response == false) {
        setState(() => _isLoading = false);
        ToastMessage.show(
          context: context,
          message: AppLocale.invalidCredentials.getString(context),
          type: ToastType.failure,
        );
      } else {
        // Save preferences before navigating
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_login_client_id', _selectedClientId!);
        await prefs.setInt('last_login_role_id', _selectedRoleId!);
        await prefs.setInt('last_login_org_id', _selectedOrgId!);

        FocusScope.of(context).unfocus();
        await Future.delayed(const Duration(milliseconds: 150));

        if (mounted) {
          CurrentLogMessage.add("Login exitoso. Token guardado.");
          // Escape the Dart Zone using pure JS eval to force a reload!
          js.context.callMethod('eval', [
            'setTimeout(function(){ window.location.reload(); }, 100);',
          ]);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Container(
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
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(29),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppLocale.chooseLogin.getString(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    CustomDropdown<int>(
                      value: _selectedClientId,
                      label: AppLocale.company.getString(context),
                      hintText: AppLocale.selectCompany.getString(context),
                      items: _clients
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(_getName(c)),
                            ),
                          )
                          .toList(),
                      onChanged: _onClientChanged,
                    ),
                    const SizedBox(height: 16),
                    CustomDropdown<int>(
                      value: _selectedRoleId,
                      label: AppLocale.role.getString(context),
                      hintText: AppLocale.selectRole.getString(context),
                      items: _roles
                          .map(
                            (r) => DropdownMenuItem<int>(
                              value: r['id'],
                              child: Text(_getName(r)),
                            ),
                          )
                          .toList(),
                      onChanged: _selectedClientId == null
                          ? null
                          : _onRoleChanged,
                    ),
                    const SizedBox(height: 16),
                    CustomDropdown<int>(
                      value: _selectedOrgId,
                      label: AppLocale.organization.getString(context),
                      hintText: AppLocale.selectOrganization.getString(context),
                      items: _orgs
                          .map(
                            (o) => DropdownMenuItem<int>(
                              value: o['id'],
                              child: Text(_getName(o)),
                            ),
                          )
                          .toList(),
                      onChanged: _selectedRoleId == null ? null : _onOrgChanged,
                    ),
                    const SizedBox(height: 24),
                    CustomButton(
                      text: AppLocale.login.getString(context),
                      onPressed:
                          (_selectedClientId != null &&
                              _selectedRoleId != null &&
                              _selectedOrgId != null)
                          ? _finalizeLogin
                          : null,
                      isLoading: _isLoading,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      borderRadius: 12,
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
