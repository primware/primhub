import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Admin/user_management_logic.dart';
import 'package:primhub/ui/Shared_Custom/searchable_dropdown.dart';
import 'package:primhub/ui/pages/Admin/widgets/team_modal.dart';
import 'package:primhub/ui/pages/Admin/widgets/user_modal.dart';
import 'package:primhub/ui/pages/Admin/widgets/bpartner_flow_modal.dart';
import 'package:primhub/ui/pages/Admin/widgets/user_check_modal.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/session_manager.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  late TextEditingController _teamSearchController;
  late TextEditingController _bPartnerSearchController;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _allUsers = [];
  Map<int, String> _roles = {};
  Map<int, String> _primhubRoles = {};
  List<Map<String, dynamic>> _bPartners = [];
  List<Map<String, dynamic>> _teams = []; // BPartner -> Users

  // Filters for Users Tab
  String _userSearchQuery = '';
  int? _filterRoleId;
  int? _filterBPartnerId;
  bool _filterClient = false;
  bool _filterSalesRep = false;
  bool _filterEmployee = false;
  bool _filterVendor = false;
  bool _filterNoValidRole = false;
  bool _filterActivePrimhubUsers = true;

  // Filters for Teams Tab
  String _teamSearchQuery = '';
  final Map<int, GlobalKey> _teamKeys = {};
  final Map<int, ExpansionTileController> _teamTileControllers = {};

  // Filters for BPartners Tab
  String _bPartnerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController = TextEditingController();
    _teamSearchController = TextEditingController();
    _bPartnerSearchController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _teamSearchController.dispose();
    _bPartnerSearchController.dispose();
    super.dispose();
  }



  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await UserManagementLogic.fetchFullUsersAndTeams();
    if (mounted) {
      setState(() {
        _allUsers = List<Map<String, dynamic>>.from(data['users'] ?? []);
        _roles = Map<int, String>.from(data['roles'] ?? {});
        _primhubRoles = Map<int, String>.from(data['primhubRoles'] ?? {});
        _bPartners = List<Map<String, dynamic>>.from(data['bPartners'] ?? []);
        _teams = List<Map<String, dynamic>>.from(data['teams'] ?? []);
        _isLoading = false;
      });
    }
  }

  void _showUserCheckModal() {
    showDialog(
      context: context,
      builder: (context) {
        return UserCheckModal(
          onProceedToCreate: (query) {
            _showUserModal(null, initialSearch: query);
          },
        );
      },
    );
  }

  void _showUserModal(Map<String, dynamic>? user, {String? initialSearch, int? initialBPartnerId}) {
    showDialog(
      context: context,
      builder: (context) {
        return UserModal(
          user: user,
          initialSearch: initialSearch,
          initialBPartnerId: initialBPartnerId,
          bPartners: _bPartners,
          roles: _primhubRoles,
          allRoles: _roles,
          onSuccess: _loadData,
        );
      }
    );
  }

  void _showResetPasswordModal(Map<String, dynamic> user) {
    final passwordController = TextEditingController();
    final isSelf = user['AD_User_ID'] == User.userID;
    
    String generatePassword() {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%^&*';
      final r = Random.secure();
      return List.generate(12, (index) => chars[r.nextInt(chars.length)]).join();
    }
    
    passwordController.text = generatePassword();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return CustomModal(
              title: isSelf ? 'Restablecer Mi Contraseña' : 'Restablecer Contraseña',
              width: 500,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Usuario: ${user['Name']} (${user['EMail']})'),
                  const SizedBox(height: 16),
                  if (isSelf) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Aviso: Estás cambiando tu propia contraseña. Al guardar, tu sesión actual se cerrará inmediatamente y serás expulsado del sistema para que inicies sesión con tu nueva contraseña.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          label: 'Nueva Contraseña',
                          controller: passwordController,
                          obscureText: false,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Generar nueva',
                        onPressed: () {
                          setState(() {
                            passwordController.text = generatePassword();
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copiar',
                        onPressed: () {
                          if (passwordController.text.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: passwordController.text));
                            ToastMessage.show(context: context, message: 'Contraseña copiada', type: ToastType.success);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                CustomButton(
                  text: 'Cancelar',
                  backgroundColor: Colors.grey,
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                ),
                CustomButton(
                  text: isSaving ? 'Guardando...' : (isSelf ? 'Confirmar y Salir' : 'Guardar'),
                  isLoading: isSaving,
                  backgroundColor: isSelf ? Colors.red : Theme.of(context).colorScheme.primary,
                  onPressed: isSaving ? null : () async {
                    if (passwordController.text.trim().isEmpty) {
                      ToastMessage.show(context: context, message: 'La contraseña no puede estar vacía', type: ToastType.warning);
                      return;
                    }

                    final userUuid = user['uuid']?.toString().trim();
                    if (userUuid == null || userUuid.isEmpty) {
                      ToastMessage.show(context: context, message: 'No se encontró el UUID del usuario para actualizar la contraseña', type: ToastType.failure);
                      return;
                    }

                    if (isSelf) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (confirmCtx) => CustomModal(
                          title: '¡Aviso de Cierre de Sesión!',
                          content: const Text(
                            'Estás a punto de cambiar tu propia contraseña.\n\nSerás expulsado de la sesión inmediatamente y deberás volver a iniciar sesión con tu nueva contraseña.\n\n¿Deseas continuar?',
                            style: TextStyle(fontSize: 14),
                          ),
                          actions: [
                            CustomButton(
                              text: 'Cancelar',
                              backgroundColor: Colors.grey,
                              onPressed: () => Navigator.of(confirmCtx).pop(false),
                            ),
                            CustomButton(
                              text: 'Confirmar y Salir',
                              backgroundColor: Colors.red,
                              onPressed: () => Navigator.of(confirmCtx).pop(true),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }
                    
                    setState(() => isSaving = true);
                    
                    final success = await UserManagementLogic.resetPassword(
                      uuid: userUuid,
                      newPassword: passwordController.text.trim(),
                    );
                    
                    if (success && mounted) {
                      Navigator.of(ctx).pop();
                      if (isSelf) {
                        SessionManager().showSessionExpiredDialog();
                        return;
                      }
                      ToastMessage.show(context: context, message: 'Contraseña actualizada', type: ToastType.success);
                      _loadData();
                    } else if (mounted) {
                      setState(() => isSaving = false);
                      ToastMessage.show(context: context, message: 'Error al actualizar contraseña', type: ToastType.failure);
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

  Future<void> _toggleUserActive(Map<String, dynamic> user, bool isActive) async {
    final userId = user['AD_User_ID']?.toString() ?? user['uuid']?.toString();
    if (userId == null || userId.isEmpty) return;
    
    final isSelf = user['AD_User_ID'] == User.userID;
    
    if (!isActive) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => CustomModal(
          title: isSelf ? '¡PELIGRO: Auto-Inactivación!' : '¿Inactivar Usuario?',
          content: Text(
            isSelf 
                ? 'Estás a punto de inactivarte a TI MISMO (${user['Name']}).\n\n'
                  'Si continúas, perderás tu acceso al sistema INMEDIATAMENTE y serás expulsado de la sesión en Primhub y en iDempiere.\n\n'
                  'ADVERTENCIA: Esta acción NO se puede deshacer desde Primhub.'
                : 'Estás a punto de inactivar a ${user['Name']}. Si continúas, este usuario se inactivará también en iDempiere, perdiendo todo acceso al sistema y desapareciendo de esta lista.\n\n'
                  'ADVERTENCIA: Esta acción NO se puede deshacer desde Primhub.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            CustomButton(
              text: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            CustomButton(
              text: 'Inactivar',
              backgroundColor: Colors.red,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    
    final success = await UserManagementLogic.toggleUserActiveStatus(userId, isActive);
    if (success) {
      if (isSelf && !isActive) {
        if (mounted) SessionManager().showSessionExpiredDialog();
        return;
      }
      
      if (mounted) ToastMessage.show(context: context, message: 'Estado del usuario actualizado exitosamente', type: ToastType.success);
      _loadData();
    } else {
      if (mounted) ToastMessage.show(context: context, message: 'Error al actualizar el estado', type: ToastType.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios y Terceros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar datos',
            onPressed: _loadData,
          ),
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.groups), text: 'Usuarios de Primhub'),
            Tab(icon: Icon(Icons.account_tree), text: 'Equipos Asignados a Terceros'),
            Tab(icon: Icon(Icons.business), text: 'Directorio de Terceros'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildTeamsTab(),
                _buildBPartnersTab(),
              ],
            ),
    );
  }

  // --- TAB 1: Usuarios ---

  Widget _buildUsersTab() {
    // Filtrar usuarios
    final filteredUsers = _allUsers.where((u) {
      if (_userSearchQuery.isNotEmpty) {
        final query = _userSearchQuery.toLowerCase();
        if (!(u['Name']?.toString().toLowerCase().contains(query) ?? false) &&
            !(u['EMail']?.toString().toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }
      
      if (_filterRoleId != null) {
        final roles = u['RoleIds'] as List<int>? ?? [];
        if (!roles.contains(_filterRoleId)) return false;
      }
      
      if (_filterBPartnerId != null) {
        if (u['C_BPartner_ID'] != _filterBPartnerId) return false;
      }
      
      if (_filterClient && !(u['IsCustomer'] == true)) return false;
      if (_filterSalesRep && !(u['IsSalesRep'] == true)) return false;
      if (_filterEmployee && !(u['IsEmployee'] == true)) return false;
      if (_filterVendor && !(u['IsVendor'] == true)) return false;
      
      if (_filterActivePrimhubUsers) {
        if (u['IsActive'] != true || u['HasValidRole'] != true) return false;
      } else {
        if (_filterNoValidRole && (u['HasValidRole'] == true || u['IsActive'] == false)) return false;
      }
      
      return true;
    }).toList();

    return Column(
      children: [
        _buildUserFilters(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: DataTable(
                          showCheckboxColumn: false,
                          headingTextStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          headingRowColor: WidgetStateProperty.all(Theme.of(context).primaryColor.withOpacity(0.08)),
                          dataRowColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return Theme.of(context).primaryColor.withOpacity(0.15); // Sombreado mucho más fuerte
                            }
                            return null;
                          }),
                          border: TableBorder(
                            verticalInside: BorderSide(color: Colors.grey.shade400, width: 1),
                            horizontalInside: BorderSide(color: Colors.grey.shade400, width: 1),
                          ),
                          dataRowMaxHeight: double.infinity,
                          dataRowMinHeight: 60,
                columns: const [
                  DataColumn(label: Expanded(child: Center(child: Text('Inactivar usuario')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Usuario')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Correo')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Tercero')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Rol Actual')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Contraseña')))),
                  DataColumn(label: Expanded(child: Center(child: Text('Acciones')))),
                ],
                rows: filteredUsers.map((u) {
                  final isActive = u['IsActive'] == true;
                  return DataRow(
                    onSelectChanged: (selected) => _showUserModal(u),
                    cells: [
                      DataCell(Align(
                        alignment: Alignment.center,
                        child: (u['Name'] == 'SuperUser' || u['AD_User_ID'] == 100)
                            ? const Tooltip(
                                message: 'El usuario administrador por defecto no puede ser inactivado',
                                child: Icon(Icons.shield, color: Colors.grey),
                              )
                            : isActive
                                ? CustomButton(
                                    text: 'Inactivar',
                                    backgroundColor: Colors.red,
                                    onPressed: () => _toggleUserActive(u, false),
                                  )
                                : CustomButton(
                                    text: 'Activar',
                                    backgroundColor: Colors.green,
                                    onPressed: () => _toggleUserActive(u, true),
                                  ),
                      )),
                      DataCell(Align(alignment: Alignment.center, child: Text(u['Name'] ?? ''))),
                      DataCell(Align(alignment: Alignment.center, child: Text(u['EMail'] ?? ''))),
                      DataCell(Align(alignment: Alignment.center, child: Text(u['Company'] ?? ''))),
                      DataCell(
                        Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: SizedBox(
                              width: 300,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _buildRoleBadges(u),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(Align(
                        alignment: Alignment.center,
                        child: Tooltip(
                          message: 'Restablecer Contraseña',
                          child: IconButton(
                            icon: const Icon(Icons.lock_reset),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () => _showResetPasswordModal(u),
                          ),
                        ),
                      )),
                      DataCell(Align(
                        alignment: Alignment.center,
                        child: CustomButton(
                          text: 'Editar',
                          icon: Icons.edit,
                          onPressed: () => _showUserModal(u),
                        ),
                      )),
                    ],
                  );
                }).toList(),
              ),
             ),
            ),
            ),
          ),
        );
      },
    ),
  ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomButton(
                text: 'Crear Nuevo Usuario',
                icon: Icons.person_add,
                onPressed: _showUserCheckModal,
              ),
              const SizedBox(width: 16),
              CustomButton(
                text: 'Crear Tercero',
                icon: Icons.business,
                backgroundColor: Colors.teal,
                onPressed: _showBPartnerCheckModal,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRoleBadges(Map<String, dynamic> u) {
    final bool isActive = u['IsActive'] == true;
    final bool hasValidRole = u['HasValidRole'] == true;
    final List<dynamic> rolesDetails = List.from(u['RolesDetails'] ?? []);
    rolesDetails.sort((a, b) {
      final roleA = (_roles[a['roleId']] ?? '').toUpperCase();
      final roleB = (_roles[b['roleId']] ?? '').toUpperCase();
      final aHasPrim = roleA.contains('PRIM');
      final bHasPrim = roleB.contains('PRIM');
      if (aHasPrim && !bHasPrim) return -1;
      if (!aHasPrim && bHasPrim) return 1;
      return roleA.compareTo(roleB);
    });

    List<Widget> badges = [];

    if (!hasValidRole && isActive) {
      badges.add(_buildBadge('Sin Acceso a Primhub', Colors.red.shade600, Icons.warning_amber_rounded));
    }
    if (rolesDetails.isEmpty && isActive) {
      badges.add(_buildBadge('Sin Roles Configurados', Colors.orange.shade700, Icons.info_outline));
    }

    for (var r in rolesDetails) {
      final rId = r['roleId'];
      final String roleName = _roles[rId] ?? 'Rol $rId';
      
      Color badgeColor = Colors.grey.shade600;
      if (_primhubRoles.containsKey(rId)) {
        if (roleName.toUpperCase().contains('ADMIN')) {
          badgeColor = Colors.blue.shade600;
        } else if (roleName.toUpperCase().contains('SUPPORT')) {
          badgeColor = Colors.orange.shade600;
        } else if (roleName.toUpperCase().contains('PROJECT')) {
          badgeColor = Colors.teal.shade600;
        }
      }
      
      // Si el usuario está inactivo, bajamos la intensidad de los colores
      if (!isActive) badgeColor = Colors.grey;

      badges.add(_buildBadge(roleName, badgeColor, Icons.security, isRole: true));
    }

    return badges;
  }

  Widget _buildBadge(String text, Color color, IconData icon, {bool isRole = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRole ? Colors.transparent : color.withOpacity(0.1),
        border: Border.all(color: isRole ? color.withOpacity(0.5) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    controller: _searchController,
                    label: 'Buscar usuario o correo',
                    prefixIcon: const Icon(Icons.search),
                    onChanged: (val) => setState(() => _userSearchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SearchableDropdown<int?>(
                    label: 'Filtrar por Rol',
                    value: _filterRoleId,
                    displayText: _filterRoleId != null ? _roles[_filterRoleId] ?? '' : 'Todos los roles',
                    onTap: () async {
                      final items = [{'key': null, 'value': 'Todos los roles'}, ..._roles.entries.map((e) => {'key': e.key, 'value': e.value})];
                      final res = await SearchableDropdown.openSearchModal<int?>(
                        context: context,
                        title: 'Rol',
                        items: items,
                        currentValue: _filterRoleId,
                        getTitle: (item) => item['value'],
                        getValue: (item) => item['key'],
                      );
                      if (res != null || res == null) setState(() => _filterRoleId = res); // El dialogo puede retornar null si cierran sin seleccionar, así que forzamos if (true)
                      // Nota: si regresan haciendo tap afuera devuelve null, lo que pondrá "Todos los roles".
                      // Idealmente, el modal puede diferenciar entre pop() vacío o con valor, pero así cumple el requerimiento.
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SearchableDropdown<int?>(
                    label: 'Filtrar por Tercero',
                    value: _filterBPartnerId,
                    displayText: _filterBPartnerId != null 
                        ? _bPartners.firstWhere((bp) => (bp['id'] ?? bp['C_BPartner_ID']) == _filterBPartnerId, orElse: () => <String, dynamic>{})['Name'] ?? 'ID $_filterBPartnerId'
                        : 'Todos los terceros',
                    onTap: () async {
                      final items = [{'id': null, 'Name': 'Todos los terceros'}, ..._bPartners];
                      final res = await SearchableDropdown.openSearchModal<int?>(
                        context: context,
                        title: 'Tercero',
                        items: items,
                        currentValue: _filterBPartnerId,
                        getTitle: (item) => item['Name'] ?? '',
                        getValue: (item) => item['id'] ?? item['C_BPartner_ID'],
                      );
                      setState(() => _filterBPartnerId = res);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              children: [
                FilterChip(
                  label: const Text('Usuarios Activos Primhub', style: TextStyle(fontWeight: FontWeight.bold)),
                  selected: _filterActivePrimhubUsers,
                  onSelected: (val) {
                    if (!val) {
                      // Al desactivar, avisar
                      ToastMessage.show(
                        context: context, 
                        message: 'Aviso: Ahora se muestran todos los usuarios, incluyendo inactivos y sin acceso.', 
                        type: ToastType.success // O neutral, success para que no salga en rojo
                      );
                    }
                    setState(() {
                      _filterActivePrimhubUsers = val;
                      if (val) {
                        // Si se activa, desactivamos los filtros que son mutuamente excluyentes lógicamente
                        _filterNoValidRole = false;
                      }
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Cliente'),
                  selected: _filterClient,
                  onSelected: (val) => setState(() => _filterClient = val),
                ),
                FilterChip(
                  label: const Text('Rep. Comercial'),
                  selected: _filterSalesRep,
                  onSelected: (val) => setState(() => _filterSalesRep = val),
                ),
                FilterChip(
                  label: const Text('Empleado'),
                  selected: _filterEmployee,
                  onSelected: (val) => setState(() => _filterEmployee = val),
                ),
                FilterChip(
                  label: const Text('Proveedor'),
                  selected: _filterVendor,
                  onSelected: (val) => setState(() => _filterVendor = val),
                ),
                if (!_filterActivePrimhubUsers) ...[
                  FilterChip(
                    label: const Text('Usuarios Sin Acceso'),
                    selected: _filterNoValidRole,
                    onSelected: (val) {
                      setState(() {
                        _filterNoValidRole = val;
                      });
                    },
                  ),
                ]
              ],
            ),
          ],
        ),
      );
  }

  // --- TAB 2: Equipos Asignados ---

  Widget _buildTeamsTab() {
    final filteredTeams = _teams.where((t) {
      if (_teamSearchQuery.isEmpty) return true;
      return t['Name'].toString().toLowerCase().contains(_teamSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _teamSearchController,
                  label: 'Buscar equipo por Tercero',
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (val) => setState(() => _teamSearchQuery = val),
                  suffixIcon: _teamSearchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _teamSearchController.clear();
                            setState(() => _teamSearchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              CustomButton(
                text: 'Crear Equipo',
                icon: Icons.group_add,
                onPressed: () => _showTeamModal(null),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: filteredTeams.map((team) {
              final users = team['Users'] as List<dynamic>;
              final teamBpId = team['C_BPartner_ID'];
              
              final bp = _bPartners.firstWhere(
                (b) => (b['id'] ?? b['C_BPartner_ID']) == teamBpId, 
                orElse: () => {}
              );
              final sr = bp['SalesRep_ID'];
              int? salesRepId;
              String? salesRepName;
              if (sr != null) {
                if (sr is Map) {
                  salesRepId = sr['id'] is int ? sr['id'] : int.tryParse(sr['id'].toString());
                  if (sr['identifier'] != null) {
                    salesRepName = sr['identifier'].toString();
                  }
                } else {
                  salesRepId = int.tryParse(sr.toString());
                }
              }
              if (salesRepId != null && salesRepName == null) {
                final srUser = _allUsers.cast<Map<String, dynamic>?>().firstWhere(
                  (u) => (u?['AD_User_ID'] ?? u?['id']) == salesRepId,
                  orElse: () => null,
                );
                salesRepName = srUser?['Name'] ?? 'ID $salesRepId';
              }
              final isSalesRepInTeam = salesRepId != null &&
                  users.any((u) => (u['AD_User_ID'] ?? u['id']) == salesRepId);

              final key = _teamKeys.putIfAbsent(teamBpId, () => GlobalKey());
              final tileController = _teamTileControllers.putIfAbsent(teamBpId, () => ExpansionTileController());

              return Card(
                key: key,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ExpansionTile(
                  controller: tileController,
                  key: PageStorageKey('team_${team['C_BPartner_ID']}'),
                  onExpansionChanged: (isExpanded) {
                    if (isExpanded) {
                      for (final entry in _teamTileControllers.entries) {
                        if (entry.key != teamBpId) {
                          try {
                            if (entry.value.isExpanded) {
                              entry.value.collapse();
                            }
                          } catch (_) {}
                        }
                      }
                    }
                  },
                  leading: const Icon(Icons.business_center),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              team['Name'],
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '${users.length} usuarios en el equipo',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (salesRepName != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isSalesRepInTeam ? Colors.green : Colors.amber).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: (isSalesRepInTeam ? Colors.green : Colors.amber.shade800).withOpacity(0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.star,
                                          size: 13,
                                          color: isSalesRepInTeam ? Colors.green.shade700 : Colors.amber.shade900,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Rep. Comercial: $salesRepName${isSalesRepInTeam ? '' : ' (No asignado al equipo)'}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isSalesRepInTeam ? Colors.green.shade800 : Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Sin Rep. Comercial asignado',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      CustomButton(
                        text: 'Ver contactos',
                        icon: Icons.people_outline,
                        onPressed: () => _showBPartnerContactsModal(bp, teamBpId),
                      ),
                      const SizedBox(width: 8),
                      CustomButton(
                        text: 'Añadir/editar',
                        icon: Icons.edit,
                        onPressed: () => _showTeamModal(team),
                      ),
                    ],
                  ),
                  children: [
                    if (salesRepName != null && !isSalesRepInTeam)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.star_outline_rounded, size: 20, color: Colors.amber.shade900),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'El representante comercial de este tercero es $salesRepName, pero no ha sido agregado a este equipo de trabajo.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _showTeamModal(team),
                              icon: const Icon(Icons.person_add_alt_1, size: 16),
                              label: const Text('Gestionar equipo', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ...users.map((u) {
                    final isActive = u['IsActive'] == true;
                    final isSalesRep = salesRepId != null && 
                                       ((u['AD_User_ID'] == salesRepId) || (u['id'] == salesRepId));
                    
                    return ListTile(
                      onTap: () => _showUserInfoModal(u, isTeamLeader: isSalesRep),
                      leading: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Icon(Icons.person, color: isActive ? Colors.green : Colors.red),
                        ],
                      ),
                      title: Text(u['Name'] ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u['EMail'] ?? ''),
                          if (isActive && u['HasValidRole'] != true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: _buildBadge('Sin Acceso a Primhub', Colors.red.shade600, Icons.warning_amber_rounded),
                            ),
                          if (isActive && (u['RolesDetails'] == null || (u['RolesDetails'] as List).isEmpty))
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: _buildBadge('Sin Roles Configurados', Colors.orange.shade700, Icons.info_outline),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSalesRep) ...[
                            _buildBadge('Líder de Equipo', Theme.of(context).colorScheme.primary, Icons.star, isRole: false),
                            const SizedBox(width: 8),
                          ],
                          Tooltip(
                            message: 'Ver Información',
                            child: IconButton(
                              icon: const Icon(Icons.visibility),
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () => _showUserInfoModal(u, isTeamLeader: isSalesRep),
                            ),
                          ),
                          if (!isSalesRep) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Hacer Líder de Equipo',
                              child: IconButton(
                                icon: const Icon(Icons.star_border),
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                onPressed: () async {
                                final bpName = bp['Name'] ?? 'ID ${team['C_BPartner_ID']}';
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => CustomModal(
                                    title: 'Cambiar Líder de Equipo',
                                    content: Text('Está a punto de cambiar el Representante Comercial del tercero $bpName.\n\n¿Está seguro que el usuario ${u['Name']} pasará a ser el líder del equipo y el encargado de la gestión del mismo?'),
                                    actions: [
                                      CustomButton(text: 'Cancelar', backgroundColor: Colors.grey, onPressed: () => Navigator.pop(ctx, false)),
                                      CustomButton(text: 'Sí, Cambiar Líder', backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.8), onPressed: () => Navigator.pop(ctx, true)),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  final uId = u['AD_User_ID'] ?? u['id'];
                                  if (uId != null) {
                                    final ok = await UserManagementLogic.updateTeamLeader(team['C_BPartner_ID'], uId);
                                    if (ok) {
                                      if (mounted) ToastMessage.show(context: context, message: 'Líder de equipo actualizado', type: ToastType.success);
                                      _loadData();
                                    } else {
                                      if (mounted) ToastMessage.show(context: context, message: 'Error al actualizar líder de equipo', type: ToastType.failure);
                                    }
                                  } else {
                                    if (mounted) ToastMessage.show(context: context, message: 'Error interno: ID del usuario no encontrado', type: ToastType.failure);
                                  }
                                }
                              },
                            ),
                            ),
                            Tooltip(
                              message: 'Quitar del Equipo',
                              child: IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: Theme.of(context).colorScheme.error.withOpacity(0.8),
                                onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => CustomModal(
                                  title: 'Quitar Usuario',
                                  content: Text('¿Desea quitar a ${u['Name']} del equipo?'),
                                  actions: [
                                    CustomButton(text: 'Cancelar', backgroundColor: Colors.grey, onPressed: () => Navigator.pop(ctx, false)),
                                    CustomButton(text: 'Quitar', backgroundColor: Colors.red, onPressed: () => Navigator.pop(ctx, true)),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final teamId = u['DevTeamID'];
                                if (teamId != null) {
                                  final ok = await UserManagementLogic.saveTeam(team['C_BPartner_ID'], [], [teamId]);
                                  if (ok) {
                                    if (mounted) ToastMessage.show(context: context, message: 'Usuario quitado del equipo', type: ToastType.success);
                                    _loadData();
                                  } else {
                                    if (mounted) ToastMessage.show(context: context, message: 'Error al quitar usuario', type: ToastType.failure);
                                  }
                                } else {
                                  if (mounted) ToastMessage.show(context: context, message: 'Error interno: ID del equipo no encontrado', type: ToastType.failure);
                                }
                              }
                            },
                            ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --- TAB 3: Directorio de Terceros ---

  Widget _buildBPartnersTab() {
    final filteredBPartners = _bPartners.where((bp) {
      if (_bPartnerSearchQuery.isEmpty) return true;
      return bp['Name'].toString().toLowerCase().contains(_bPartnerSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: CustomTextField(
            controller: _bPartnerSearchController,
            label: 'Buscar Tercero por nombre',
            prefixIcon: const Icon(Icons.search),
            onChanged: (val) => setState(() => _bPartnerSearchQuery = val),
            suffixIcon: _bPartnerSearchQuery.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _bPartnerSearchController.clear();
                      setState(() => _bPartnerSearchQuery = '');
                    },
                  )
                : null,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ListView.builder(
              itemCount: filteredBPartners.length,
              itemBuilder: (context, index) {
                final bp = filteredBPartners[index];
                final bpId = bp['id'] ?? bp['C_BPartner_ID'];
                
                // Buscar si este tercero tiene un equipo asignado
                final team = _teams.cast<Map<String, dynamic>?>().firstWhere(
                  (t) => t?['C_BPartner_ID'] == bpId, 
                  orElse: () => null
                );
                
                final String bpName = bp['Name'] ?? 'Sin nombre';
                final String bpValue = (bp['Value'] != null && bp['Value'].toString().trim().isNotEmpty)
                    ? bp['Value'].toString().trim()
                    : ((bp['TaxID'] != null && bp['TaxID'].toString().trim().isNotEmpty)
                        ? bp['TaxID'].toString().trim()
                        : 'Sin código');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.business, color: Colors.blueGrey, size: 36),
                    title: Text(bpName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Código: $bpValue\n${team != null ? 'Tiene un equipo asignado (${(team['Users'] as List).length} miembros)' : 'Sin equipo asignado'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomButton(
                          text: 'Ver contactos',
                          icon: Icons.people_outline,
                          onPressed: () => _showBPartnerContactsModal(bp, bpId),
                        ),
                        const SizedBox(width: 8),
                        team != null
                            ? CustomButton(
                                text: 'Ver equipo',
                                icon: Icons.group,
                                onPressed: () {
                                  setState(() {
                                    if (_teamSearchQuery.isNotEmpty) {
                                      _teamSearchController.clear();
                                      _teamSearchQuery = '';
                                    }
                                    _tabController.animateTo(1); 
                                  });
                                  Future.delayed(const Duration(milliseconds: 300), () {
                                    // Cerrar cualquier otro equipo abierto
                                    for (final entry in _teamTileControllers.entries) {
                                      if (entry.key != bpId) {
                                        try {
                                          if (entry.value.isExpanded) {
                                            entry.value.collapse();
                                          }
                                        } catch (_) {}
                                      }
                                    }

                                    final key = _teamKeys[bpId];
                                    final tileCtrl = _teamTileControllers[bpId];
                                    
                                    if (tileCtrl != null) {
                                      try {
                                        if (!tileCtrl.isExpanded) {
                                          tileCtrl.expand();
                                        }
                                      } catch (_) {}
                                    }
                                    
                                    if (key != null && key.currentContext != null) {
                                      Scrollable.ensureVisible(
                                        key.currentContext!,
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.easeInOut,
                                        alignment: 0.1, // Un poco despistado del borde superior
                                      );
                                    }
                                  });
                                },
                              )
                            : CustomButton(
                                text: 'Crear equipo',
                                icon: Icons.add,
                                backgroundColor: Colors.teal,
                                onPressed: () {
                                  _showTeamModal({
                                    'C_BPartner_ID': bpId,
                                    'Name': 'Equipo de $bpName',
                                    'Users': [],
                                  });
                                },
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showUserInfoModal(Map<String, dynamic> user, {bool isTeamLeader = false}) {
    showDialog(
      context: context,
      builder: (context) => CustomModal(
        title: 'Información del Usuario',
        width: 450,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isTeamLeader) ...[
              Row(
                children: [
                  Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Text('Líder de Equipo', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text('Nombre: ${user['Name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Email: ${user['EMail'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Empresa: ${user['Company'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Estado: ${user['IsActive'] == true ? 'Activo' : 'Inactivo'}'),
            const SizedBox(height: 8),
            const Text('Roles:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _buildRoleBadges(user),
            ),
          ],
        ),
        actions: [
          CustomButton(text: 'Cerrar', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  void _showBPartnerCheckModal() {
    showDialog(
      context: context,
      builder: (context) {
        return BPartnerFlowModal(
          onSuccess: _loadData,
        );
      }
    );
  }

  void _showTeamModal(Map<String, dynamic>? team) {
    List<Map<String, dynamic>> availableBPartners = _bPartners;
    if (team == null) {
      final teamBpIds = _teams.map((t) => t['C_BPartner_ID']).toSet();
      availableBPartners = _bPartners.where((bp) {
        final bpId = bp['id'] ?? bp['C_BPartner_ID'];
        return !teamBpIds.contains(bpId);
      }).toList();
    }

    showDialog(
      context: context,
      builder: (context) {
        return TeamModal(
          team: team,
          allUsers: _allUsers,
          bPartners: availableBPartners,
          onSuccess: _loadData,
        );
      }
    );
  }

  void _showBPartnerContactsModal(Map<String, dynamic> bp, int? bpId) {
    if (bpId == null) return;
    final String bpName = bp['Name'] ?? 'Tercero';

    showDialog(
      context: context,
      builder: (ctx) {
        String filterQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Filtrar los usuarios que pertenecen a este tercero
            final allContacts = _allUsers.where((u) => u['C_BPartner_ID'] == bpId).toList();
            allContacts.sort((a, b) => (a['Name']?.toString() ?? '').toLowerCase().compareTo((b['Name']?.toString() ?? '').toLowerCase()));

            final filteredContacts = allContacts.where((u) {
              if (filterQuery.isEmpty) return true;
              final q = filterQuery.toLowerCase();
              final name = (u['Name'] ?? '').toString().toLowerCase();
              final email = (u['EMail'] ?? '').toString().toLowerCase();
              return name.contains(q) || email.contains(q);
            }).toList();

            return CustomModal(
              title: 'Contactos de $bpName',
              width: 700,
              content: SizedBox(
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            label: 'Buscar contacto por nombre o correo',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            onChanged: (val) => setModalState(() => filterQuery = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        CustomButton(
                          text: 'Crear Contacto',
                          icon: Icons.person_add,
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showUserModal(null, initialBPartnerId: bpId);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${filteredContacts.length} de ${allContacts.length} ${allContacts.length == 1 ? 'contacto' : 'contactos'}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          'Solo usuarios con rol válido en Primhub pueden ser etiquetados',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Expanded(
                      child: allContacts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Este tercero no tiene contactos registrados.',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 16),
                                  CustomButton(
                                    text: 'Crear primer contacto',
                                    icon: Icons.person_add,
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showUserModal(null, initialBPartnerId: bpId);
                                    },
                                  ),
                                ],
                              ),
                            )
                          : filteredContacts.isEmpty
                              ? Center(
                                  child: Text(
                                    'No se encontraron contactos para "$filterQuery"',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filteredContacts.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final u = filteredContacts[index];
                                    final bool isActive = u['IsActive'] == true;
                                    final bool hasValidRole = u['HasValidRole'] == true;

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      leading: CircleAvatar(
                                        backgroundColor: isActive 
                                            ? (hasValidRole ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12))
                                            : Colors.grey.withOpacity(0.12),
                                        child: Icon(
                                          Icons.person,
                                          color: isActive
                                              ? (hasValidRole ? Colors.green.shade700 : Colors.orange.shade800)
                                              : Colors.grey,
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              u['Name'] ?? 'Sin nombre',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                          ),
                                          if (!isActive)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Inactivo',
                                                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 2),
                                          Text(
                                            u['EMail'] ?? 'Sin correo electrónico',
                                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              if (hasValidRole && isActive)
                                                _buildBadge('Tiene Acceso a Primhub', Colors.green.shade700, Icons.check_circle_outline),
                                              ..._buildRoleBadges(u),
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Tooltip(
                                            message: 'Ver Información',
                                            child: IconButton(
                                              icon: const Icon(Icons.visibility),
                                              color: Theme.of(context).colorScheme.primary,
                                              onPressed: () => _showUserInfoModal(u),
                                            ),
                                          ),
                                          Tooltip(
                                            message: 'Editar Usuario',
                                            child: IconButton(
                                              icon: const Icon(Icons.edit),
                                              color: Theme.of(context).colorScheme.primary,
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                _showUserModal(u);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                CustomButton(
                  text: 'Cerrar',
                  backgroundColor: Colors.grey.shade600,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
