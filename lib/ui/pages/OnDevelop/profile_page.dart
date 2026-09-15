import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/api_http.dart' as http;

import 'package:go_router/go_router.dart';
import '../../../api/token.dart';
import '../../widgets/custom_drawer.dart';
import '../../Shared_Custom/custom_modal.dart';

import 'package:primhub/endpoint/endpoint.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/auth_api.dart';
import 'package:primhub/api/global_cache.dart';
import '../../Shared_Custom/custom_button.dart';
import '../../Shared_Custom/custom_inputs.dart';
import '../../Shared_Custom/custom_toast.dart';
import 'package:flutter_localization/flutter_localization.dart';


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic> _userInfo = {};
  Uint8List? _profileImageBytes;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    if (User.profileImageBytes != null) {
      _profileImageBytes = User.profileImageBytes;
    } else {
      _loadPartnerLogo();
    }
  }

  Future<void> _loadPartnerLogo() async {
    int? partnerId = User.cBPartnerID;

    // Fallback: Si no hay ID en memoria, intentamos recuperarlo del usuario actual
    if (partnerId == null) {
      try {
        final payload = Token.decodePayload(Token.token);
        final userId = payload['AD_User_ID'];
        if (userId != null) {
          final userUrl = Uri.parse('${Endpoint.adUser}/$userId?\$select=C_BPartner_ID');
          final userResp = await http.get(userUrl, headers: {'Authorization': Token.token});
          if (userResp.statusCode == 200) {
            final userData = json.decode(utf8.decode(userResp.bodyBytes));
            final bpField = userData['C_BPartner_ID'];
            if (bpField is Map) {
              partnerId = bpField['id'];
            } else if (bpField is int) {
              partnerId = bpField;
            }
            if (partnerId != null) User.cBPartnerID = partnerId; // Guardar en memoria
          }
        }
      } catch (_) {
      // Ignored: Fail silently
    }
    }

    if (partnerId == null) return;

    try {
      // 1. Obtener Logo_ID del Tercero (C_BPartner)
      final bpUrl = Uri.parse('${Endpoint.cBPartner}/$partnerId?\$select=Logo_ID');
      final bpResponse = await http.get(bpUrl, headers: {'Authorization': Token.token});

      if (bpResponse.statusCode == 200) {
        final bpData = json.decode(utf8.decode(bpResponse.bodyBytes));
        final logoField = bpData['Logo_ID'];
        int? logoId;
        if (logoField is Map) {
          logoId = logoField['id'];
        } else if (logoField is int) {
          logoId = logoField;
        }

        if (logoId != null) {
          // 2. Obtener BinaryData de la imagen (AD_Image)
          final imgUrl = Uri.parse('${Endpoint.baseUrl}/api/v1/models/AD_Image/$logoId?\$select=BinaryData');
          final imgResponse = await http.get(imgUrl, headers: {'Authorization': Token.token});
          if (imgResponse.statusCode == 200) {
            final imgData = json.decode(utf8.decode(imgResponse.bodyBytes));
            final binaryData = imgData['BinaryData'];
            if (binaryData is String && binaryData.isNotEmpty) {
              try {
                final cleanBase64 = binaryData.replaceAll(RegExp(r'\s+'), '');
                final bytes = base64Decode(cleanBase64);
                User.profileImageBytes = bytes; // Guardar en caché
                if (mounted) {
                  setState(() {
                    _profileImageBytes = bytes;
                  });
                }
              } catch (_) {
                // Ignore error
              }
            }
          }
        }
      }
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final payload = Token.decodePayload(Token.token);
      if (mounted) {
        setState(() {
          _userInfo = payload;
        });
      }
      
      final userId = payload['AD_User_ID'] ?? User.userID;
      if (userId != null) {
        final url = Uri.parse('${Endpoint.adUser}/$userId');
        final response = await http.get(url, headers: {'Authorization': Token.token});
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (mounted) {
            setState(() {
              if (data['C_BPartner_ID'] != null && data['C_BPartner_ID'] is Map) {
                _userInfo['bpartner_name'] = data['C_BPartner_ID']['identifier'];
              }
              if (data['AD_Client_ID'] != null && data['AD_Client_ID'] is Map) {
                _userInfo['client_name'] = data['AD_Client_ID']['identifier'];
              }
              _userInfo['sub'] = data['Name'] ?? _userInfo['sub'];
              _userInfo['email'] = data['EMail'] ?? _userInfo['email'];
            });
          }
        }
      }
    } catch (e) {
      // Ignore error
    }
  }

  void _showChangePasswordModal(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return CustomModal(
              title: AppLocale.changePassword.getString(context),
              width: 450,
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      label: AppLocale.newPassword.getString(context),
                      controller: passwordController,
                      obscureText: obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return AppLocale.requiredField.getString(context);
                        if (value.length < 6) return AppLocale.passwordMinLength.getString(context);
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: AppLocale.confirmPassword.getString(context),
                      controller: confirmPasswordController,
                      obscureText: obscureConfirmPassword,
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setModalState(() => obscureConfirmPassword = !obscureConfirmPassword),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return AppLocale.requiredField.getString(context);
                        if (value != passwordController.text) return AppLocale.passwordsDoNotMatch.getString(context);
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                CustomButton(
                  text: AppLocale.cancel.getString(context),
                  onPressed: isLoading ? () {} : () => Navigator.of(context).pop(),
                  backgroundColor: Colors.grey[700],
                ),
                CustomButton(
                  text: AppLocale.save.getString(context),
                  isLoading: isLoading,
                  onPressed: isLoading
                      ? () {}
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setModalState(() => isLoading = true);
                            final result = await changePassword(newPassword: passwordController.text);
                            setModalState(() => isLoading = false);
                            if (result['success'] == true) {
                              Navigator.of(context).pop();
                              ToastMessage.show(context: context, message: result['message'], type: ToastType.success);
                            } else {
                              ToastMessage.show(context: context, message: result['message'], type: ToastType.failure);
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    // Mapeo de nombres amigabless basado en el token
    final String username = _userInfo['sub'] ?? 'Desconocido';
    final String email = _userInfo['email'] ?? 'admin@gardenworld.com';
    final String bPartner = _userInfo['bpartner_name'] ?? 'GardenWorld HQ';

    String roleName = 'Usuario';
    if (AccessControl.isRealAdmin) {
      roleName = AppLocale.primhubAdministrator.getString(context);
    } else if (AccessControl.isRealSupport) {
      roleName = AppLocale.supportUser.getString(context);
    } else if (AccessControl.isRealProject) {
      roleName = AppLocale.projectUser.getString(context);
    }


    return Scaffold(
      appBar: AppBar(
        leading: !AccessControl.isAdmin ? IconButton(icon: const Icon(Icons.arrow_back), tooltip: AppLocale.backToHome.getString(context), onPressed: () => context.go('/')) : null,
        title: Text(AppLocale.userProfile.getString(context)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: AppLocale.refreshData.getString(context), onPressed: () => GlobalCache.forceFullSyncWithProgress(context, onSyncAction: _loadUserInfo)),
          if (!AccessControl.isAdmin)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              tooltip: AppLocale.logout.getString(context),
              onPressed: () => showLogoutConfirmation(context),
            ),
        ],
      ),
      drawer: AccessControl.isAdmin ? const CustomDrawer(currentRoute: '/profile') : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: _profileImageBytes != null ? MemoryImage(_profileImageBytes!) : null,
                      onBackgroundImageError: _profileImageBytes != null
                          ? (exception, stackTrace) {
                              if (mounted) setState(() => _profileImageBytes = null);
                            }
                          : null,
                      child: _profileImageBytes != null
                          ? null
                          : Icon(Icons.person_rounded, size: 56, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                username,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(roleName, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              const SizedBox(height: 32),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildInfoTile(Icons.person, AppLocale.username.getString(context), username),
                      const Divider(),
                      _buildInfoTile(Icons.store, AppLocale.businessPartner.getString(context), bPartner),
                      const Divider(),
                      _buildInfoTile(Icons.email, AppLocale.email.getString(context), email),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    title: Text(AppLocale.changePassword.getString(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showChangePasswordModal(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4F47E5)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
