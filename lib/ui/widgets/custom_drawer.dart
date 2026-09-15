import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/api_http.dart' as http;
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';
import '../../api/access_control.dart';
import '../../api/api_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hover_widgets.dart';
import 'package:flutter_localization/flutter_localization.dart';

class CustomDrawer extends StatefulWidget {
  final String currentRoute;
  const CustomDrawer({super.key, required this.currentRoute});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String _username = '';
  String _role = '';
  String _client = '';
  String _userRolePref = 'ADMIN';
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

    if (partnerId == null) {
      try {
        final payload = Token.decodePayload(Token.token);
        final userId = payload['AD_User_ID'];
        if (userId != null) {
          final userUrl = Uri.parse(
            '${Endpoint.adUser}/$userId?\$select=C_BPartner_ID',
          );
          final userResp = await http.get(
            userUrl,
            headers: {'Authorization': Token.token},
          );
          if (userResp.statusCode == 200) {
            final userData = json.decode(utf8.decode(userResp.bodyBytes));
            final bpField = userData['C_BPartner_ID'];
            if (bpField is Map) {
              partnerId = bpField['id'];
            } else if (bpField is int) {
              partnerId = bpField;
            }
            if (partnerId != null) User.cBPartnerID = partnerId;
          }
        }
      } catch (_) {
        // Ignored: Fail silently
      }
    }

    if (partnerId == null) return;

    try {
      final bpUrl = Uri.parse(
        '${Endpoint.cBPartner}/$partnerId?\$select=Logo_ID',
      );
      final bpResponse = await http.get(
        bpUrl,
        headers: {'Authorization': Token.token},
      );
      if (bpResponse.statusCode == 200) {
        final bpData = json.decode(utf8.decode(bpResponse.bodyBytes));
        final logoField = bpData['Logo_ID'];
        int? logoId = (logoField is Map)
            ? logoField['id']
            : (logoField is int ? logoField : null);

        if (logoId != null) {
          final imgUrl = Uri.parse(
            '${Endpoint.baseUrl}/api/v1/models/AD_Image/$logoId?\$select=BinaryData',
          );
          final imgResponse = await http.get(
            imgUrl,
            headers: {'Authorization': Token.token},
          );
          if (imgResponse.statusCode == 200) {
            final imgData = json.decode(utf8.decode(imgResponse.bodyBytes));
            final binaryData = imgData['BinaryData'];
            if (binaryData is String && binaryData.isNotEmpty) {
              final bytes = base64Decode(binaryData);
              User.profileImageBytes = bytes; // Guardar en caché
              if (mounted) setState(() => _profileImageBytes = bytes);
            }
          }
        }
      }
    } catch (_) {
      // Ignored: Fail silently
    }
  }

  void _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _userRolePref = prefs.getString('user_role') ?? 'ADMIN';

    try {
      final payload = Token.decodePayload(Token.token);
      setState(() {
        _username = payload['sub'] ?? 'Usuario';
        final clientId = payload['AD_Client_ID'];

        String exactRole = 'Usuario';
        if (AccessControl.isRealAdmin) {
          exactRole = 'Administrador';
        } else if (AccessControl.isRealSupport) {
          exactRole = 'Usuario de Soporte';
        } else if (AccessControl.isRealProject) {
          exactRole = 'Usuario de Proyecto';
        }

        _role = exactRole;
        _client =
            payload['client_name'] ??
            payload['clientName'] ??
            (clientId == 11 ? 'GardenWorld' : 'Cliente $clientId');
      });
    } catch (e) {
      // Ignore error
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      backgroundColor: theme.drawerTheme.backgroundColor ?? colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color:
                            theme.drawerTheme.backgroundColor ??
                            colorScheme.surface,
                        border: Border(
                          bottom: Divider.createBorderSide(
                            context,
                            color: theme.dividerColor,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/profile');
                              },
                              hoverColor: colorScheme.primary.withOpacity(0.05),
                              splashColor: colorScheme.primary.withOpacity(0.1),
                              highlightColor: colorScheme.primary.withOpacity(
                                0.05,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16.0,
                                  horizontal: 16.0,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor:
                                          colorScheme.primaryContainer,
                                      backgroundImage:
                                          _profileImageBytes != null
                                          ? MemoryImage(_profileImageBytes!)
                                          : null,
                                      child: _profileImageBytes != null
                                          ? null
                                          : Icon(
                                              Icons.person_rounded,
                                              size: 28,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _username.isNotEmpty
                                                ? _username
                                                : 'Nombre',
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _role.isNotEmpty ? _role : 'Rol',
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!AccessControl.isAdmin) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.business_rounded,
                                    color: colorScheme.primary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _client.isNotEmpty
                                          ? _client
                                          : 'Tu Empresa',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_userRolePref != 'PROYECTO')
                      HoverListTile(
                        builder: (isHovered) {
                          bool isSelected = widget.currentRoute == '/';
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor: colorScheme.primary
                                  .withOpacity(0.2),
                              tileColor: isHovered
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.transparent,
                              leading: Icon(
                                Icons.home_rounded,
                                color: isHovered || isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                AppLocale.dashboard.getString(context),
                                style: TextStyle(
                                  color: isHovered || isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/');
                              },
                            ),
                          );
                        },
                      ),
                    if (AccessControl.isSupport)
                      HoverListTile(
                        builder: (isHovered) {
                          bool isSelected = widget.currentRoute == '/support';
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor: colorScheme.primary
                                  .withOpacity(0.2),
                              tileColor: isHovered
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.transparent,
                              leading: Icon(
                                Icons.schedule_rounded,
                                color: isHovered || isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                AppLocale.hoursDashboard.getString(context),
                                style: TextStyle(
                                  color: isHovered || isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/support');
                              },
                            ),
                          );
                        },
                      ),
                    if (AccessControl.isSupport)
                      HoverListTile(
                        builder: (isHovered) {
                          bool isSelected =
                              widget.currentRoute == '/my-requests';
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor: colorScheme.primary
                                  .withOpacity(0.2),
                              tileColor: isHovered
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.transparent,
                              leading: Icon(
                                Icons.table_chart_rounded,
                                color: isHovered || isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                AppLocale.myRequests.getString(context),
                                style: TextStyle(
                                  color: isHovered || isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/my-requests');
                              },
                            ),
                          );
                        },
                      ),

                    if (AccessControl.isProject)
                      HoverListTile(
                        builder: (isHovered) {
                          bool isSelected =
                              widget.currentRoute == '/deliverables';
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor: colorScheme.primary
                                  .withOpacity(0.2),
                              tileColor: isHovered
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.transparent,
                              leading: Icon(
                                Icons.folder_rounded,
                                color: isHovered || isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                AppLocale.myProjects.getString(context),
                                style: TextStyle(
                                  color: isHovered || isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/deliverables');
                              },
                            ),
                          );
                        },
                      ),

                    HoverListTile(
                      builder: (isHovered) {
                        bool isSelected = widget.currentRoute == '/metrics';
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            selected: isSelected,
                            selectedTileColor: colorScheme.primary.withOpacity(
                              0.2,
                            ),
                            tileColor: isHovered
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.transparent,
                            leading: Icon(
                              Icons.bar_chart_rounded,
                              color: isHovered || isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              AppLocale.indicators.getString(context),
                              style: TextStyle(
                                color: isHovered || isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              context.push('/metrics');
                            },
                          ),
                        );
                      },
                    ),

                    if (AccessControl.isSupport)
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: Icon(
                            Icons.folder_shared,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            AccessControl.isAdmin
                                ? AppLocale.supportDocuments.getString(context)
                                : AppLocale.documents.getString(context),
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                          initiallyExpanded: widget.currentRoute.startsWith(
                            '/bpartner-docs',
                          ),
                          children: [
                            HoverListTile(
                              builder: (isHovered) {
                                bool isSelected =
                                    widget.currentRoute ==
                                    '/bpartner-docs/general';
                                return Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.only(
                                      left: 48,
                                      right: 16,
                                    ),
                                    selected: isSelected,
                                    selectedTileColor: colorScheme.primary
                                        .withOpacity(0.2),
                                    tileColor: isHovered
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.transparent,
                                    leading: Icon(
                                      Icons.description_rounded,
                                      color: isHovered || isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    title: Text(
                                      AppLocale.general.getString(context),
                                      style: TextStyle(
                                        color: isHovered || isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      context.push('/bpartner-docs/general');
                                    },
                                  ),
                                );
                              },
                            ),
                            HoverListTile(
                              builder: (isHovered) {
                                bool isSelected =
                                    widget.currentRoute ==
                                    '/bpartner-docs/seguimiento';
                                return Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.only(
                                      left: 48,
                                      right: 16,
                                    ),
                                    selected: isSelected,
                                    selectedTileColor: colorScheme.primary
                                        .withOpacity(0.2),
                                    tileColor: isHovered
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.transparent,
                                    leading: Icon(
                                      Icons.description_rounded,
                                      color: isHovered || isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    title: Text(
                                      AppLocale.tracking.getString(context),
                                      style: TextStyle(
                                        color: isHovered || isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      context.push(
                                        '/bpartner-docs/seguimiento',
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              HoverListTile(
                builder: (isHovered) => Material(
                  color: Colors.transparent,
                  child: ListTile(
                    tileColor: isHovered
                        ? Colors.red.withOpacity(0.05)
                        : Colors.transparent,
                    leading: Icon(
                      Icons.logout_rounded,
                      color: isHovered
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      AppLocale.logout.getString(context),
                      style: TextStyle(
                        color: isHovered
                            ? colorScheme.error
                            : colorScheme.onSurface,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Cierra el menú
                      showLogoutConfirmation(
                        context,
                      ); // Usa la función centralizada
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
