import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/widgets/custom_drawer.dart';
import 'package:primhub/ui/Shared_Custom/user_info_leading.dart';
import 'package:primhub/ui/pages/Projects/Documents/project_file_manager.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:go_router/go_router.dart';

import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_container.dart';
import 'package:primhub/ui/widgets/project_bottom_nav.dart';
import 'package:primhub/ui/widgets/project_sidebar.dart';
import 'package:flutter_localization/flutter_localization.dart';
class BPartnerDocumentsPage extends StatefulWidget {
  final String viewType; // 'General' or 'Seguimiento'

  const BPartnerDocumentsPage({super.key, required this.viewType});

  @override
  State<BPartnerDocumentsPage> createState() => _BPartnerDocumentsPageState();
}

class _BPartnerDocumentsPageState extends State<BPartnerDocumentsPage> {
  final Map<int, GlobalKey<ProjectFileManagerState>> _fileManagerKeys = {};
  bool _isRoot = true;

  GlobalKey<ProjectFileManagerState> _getKeyForId(int id) {
    if (!_fileManagerKeys.containsKey(id)) {
      _fileManagerKeys[id] = GlobalKey<ProjectFileManagerState>();
    }
    return _fileManagerKeys[id]!;
  }
  
  List<int> _selectedBPartnerIds = [];
  List<dynamic> _bPartners = [];
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (AccessControl.isAdmin) {
      _loadBPartners();
    } else {
      if (User.cBPartnerID != null) {
        _selectedBPartnerIds = [User.cBPartnerID!];
        
        String bpName = 'Mi Empresa';
        try {
          final payload = Token.decodePayload(Token.token);
          bpName = payload['client_name'] ?? payload['clientName'] ?? 'Mi Empresa';
        } catch (_) {
      // Ignored: Fail silently
    }

        // Try to get the actual BPartner name from GlobalCache if available
        final matches = GlobalCache.bPartners.where((e) => e['id'] == User.cBPartnerID);
        if (matches.isNotEmpty) {
          bpName = matches.first['Name'] ?? bpName;
        }

        _bPartners = [
          {'id': User.cBPartnerID, 'Name': bpName}
        ];
      }
    }
  }

  void _loadBPartners() {
    setState(() {
      _bPartners = GlobalCache.bPartners;
    });
  }

  String _localizedTitle(BuildContext context) {
    final section = AccessControl.isAdmin
        ? AppLocale.supportDocuments.getString(context)
        : AppLocale.documents.getString(context);
    final view = widget.viewType == 'General'
        ? AppLocale.general.getString(context)
        : AppLocale.tracking.getString(context);
    return '$section: $view';
  }

  @override
  Widget build(BuildContext context) {
    final String route = widget.viewType == 'General' ? '/bpartner-docs/general' : '/bpartner-docs/seguimiento';

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(_localizedTitle(context))),
        drawer: CustomDrawer(currentRoute: route),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_selectedBPartnerIds.isEmpty && !AccessControl.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_localizedTitle(context)),
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ),
        drawer: CustomDrawer(currentRoute: route),
        bottomNavigationBar:
            (MediaQuery.of(context).size.width < 900 && !AccessControl.isAdmin)
            ? ProjectBottomNav(currentRoute: route)
            : null,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (MediaQuery.of(context).size.width >= 900 &&
                !AccessControl.isAdmin)
              ProjectSideBar(currentRoute: route),
            Expanded(
              child: Center(child: Text(AppLocale.noPartnerInformation.getString(context))),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_localizedTitle(context)),
        leadingWidth: !AccessControl.isAdmin ? 220 : null,
        leading: !AccessControl.isAdmin
            ? const UserInfoLeading()
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: AppLocale.mainMenu.getString(context),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: [
          if (AccessControl.canManageFiles) ...[
            if (_isRoot)
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'Nueva Carpeta',
                onPressed: () {
                  if (_selectedBPartnerIds.length == 1) {
                    final fm = _fileManagerKeys[_selectedBPartnerIds.first]?.currentState;
                    if (fm != null && !fm.isRoot()) {
                       ToastMessage.show(context: context, message: 'No se permiten subcarpetas.', type: ToastType.help);
                    } else {
                       fm?.createFolderDialog();
                    }
                } else if (_selectedBPartnerIds.isEmpty) {
                  ToastMessage.show(context: context, message: AppLocale.mustSelectBPartner.getString(context), type: ToastType.help);
                } else {
                  ToastMessage.show(context: context, message: 'Seleccione un solo tercero para crear carpeta', type: ToastType.help);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Subir Archivo',
              onPressed: () {
                if (_selectedBPartnerIds.length == 1) {
                  _fileManagerKeys[_selectedBPartnerIds.first]?.currentState?.pickAndUploadFile();
                } else if (_selectedBPartnerIds.isEmpty) {
                  ToastMessage.show(context: context, message: AppLocale.mustSelectBPartner.getString(context), type: ToastType.help);
                } else {
                  ToastMessage.show(context: context, message: 'Seleccione un solo tercero para subir archivo', type: ToastType.help);
                }
              },
            ),
          ],
          if (!AccessControl.isAdmin)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              tooltip: AppLocale.logout.getString(context),
              onPressed: () => showLogoutConfirmation(context),
            ),
        ],
      ),
      drawer: CustomDrawer(currentRoute: route),
      bottomNavigationBar:
          (MediaQuery.of(context).size.width < 900 && !AccessControl.isAdmin)
          ? ProjectBottomNav(currentRoute: route)
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.of(context).size.width >= 900 &&
              !AccessControl.isAdmin)
            ProjectSideBar(currentRoute: route),
          Expanded(
            child: SafeArea(
              child: Column(
          children: [
            if (AccessControl.isAdmin && _bPartners.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: CustomContainer(
                  title: AppLocale.filterByPartner.getString(context),
                  action: const Icon(
                    Icons.filter_alt_rounded,
                    color: Colors.grey,
                  ),
                  child: _DocsBpSelector(
                    bPartners: _bPartners,
                    selectedBpIds: _selectedBPartnerIds,
                    onSelectionChanged: (ids) {
                      setState(() {
                        _selectedBPartnerIds = ids;
                      });
                    },
                  ),
                ),
              ),
            Expanded(
              child: _selectedBPartnerIds.isEmpty
                  ? Center(child: Text(AppLocale.selectPartnerDocuments.getString(context)))
                  : _selectedBPartnerIds.length == 1
                      ? _buildTerceroContainer(_selectedBPartnerIds.first, context, true)
                      : ListView.builder(
                          itemCount: _selectedBPartnerIds.length,
                          itemBuilder: (context, index) {
                            return _buildTerceroContainer(_selectedBPartnerIds[index], context, false);
                          },
                        ),
            ),
          ],
        ),
      ),
      ),
      ],
      ),
    );
  }

  Widget _buildTerceroContainer(int id, BuildContext context, bool isSingle) {
    final matches = _bPartners.where((e) => e['id'] == id);
    final bp = matches.isNotEmpty ? matches.first : null;
    final name = bp != null ? bp['Name'] : 'Tercero $id';
    
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text(
            name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ProjectFileManager(
            key: _getKeyForId(id),
            bPartnerId: id,
            bPartnerName: name,
            viewType: widget.viewType,
            onRootChanged: (isRoot) {
              if (_isRoot != isRoot) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _isRoot = isRoot);
                });
              }
            },
            onExit: () {
              context.go('/');
            },
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      height: isSingle ? null : 600,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}

class _DocsBpSelector extends StatelessWidget {
  final List<dynamic> bPartners;
  final List<int> selectedBpIds;
  final ValueChanged<List<int>> onSelectionChanged;

  const _DocsBpSelector({
    required this.bPartners,
    required this.selectedBpIds,
    required this.onSelectionChanged,
  });

  void _showMultiSelectBps(BuildContext context) async {
    final List<int> tempSelectedBpIds = List.from(selectedBpIds);
    List<dynamic> sortedBps = List.from(bPartners);
    sortedBps.sort((a, b) => (a['Name'] ?? '').compareTo(b['Name'] ?? ''));

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        String searchQuery = '';
        return CustomModal(
          title: AppLocale.selectPartnerTitle.getString(context),
          width: 500,
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              final filteredBps = sortedBps.where((bp) {
                return (bp['Name'] ?? '').toLowerCase().contains(
                  searchQuery.toLowerCase(),
                );
              }).toList();

              return SizedBox(
                height: 350,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CustomTextField(
                      hintText: AppLocale.filterHint.getString(context),
                      prefixIcon: const Icon(Icons.filter_list),
                      onChanged: (val) => setState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        bool? isAllSelected;
                        if (tempSelectedBpIds.length == filteredBps.length &&
                            filteredBps.isNotEmpty) {
                          isAllSelected = true;
                        } else if (tempSelectedBpIds.isEmpty) {
                          isAllSelected = false;
                        }

                        return CheckboxListTile(
                          title: Text(
                            AppLocale.allPartners.getString(context),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          tristate: true,
                          value: isAllSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (isAllSelected == true) {
                                tempSelectedBpIds.clear();
                              } else {
                                tempSelectedBpIds.clear();
                                tempSelectedBpIds.addAll(
                                  filteredBps.map<int>((bp) => bp['id'] as int),
                                );
                              }
                            });
                          },
                        );
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ListBody(
                          children: filteredBps.map((bp) {
                            final bool isSelected = tempSelectedBpIds.contains(
                              bp['id'],
                            );
                            return CheckboxListTile(
                              title: Text(bp['Name'] ?? 'Tercero sin nombre'),
                              value: isSelected,
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    tempSelectedBpIds.add(bp['id']);
                                  } else {
                                    tempSelectedBpIds.remove(bp['id']);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocale.cancel.getString(context)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            CustomButton(
              text: AppLocale.apply.getString(context),
              onPressed: () {
                onSelectionChanged(tempSelectedBpIds);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayText;

    final bool isSyncing = GlobalCache.bPartners.isEmpty && !GlobalCache.isDataLoaded;

    if (isSyncing) {
      displayText = 'Sincronizando terceros...';
    } else if (selectedBpIds.isEmpty) {
      if (bPartners.isEmpty) return const SizedBox.shrink();
      displayText = AppLocale.noPartnerSelected.getString(context);
    } else if (selectedBpIds.length == 1) {
      final bp = bPartners.firstWhere(
        (p) => p['id'] == selectedBpIds.first,
        orElse: () => {'Name': 'Tercero no encontrado'},
      );
      displayText = bp['Name'] ?? 'Tercero sin nombre';
    } else if (selectedBpIds.length == bPartners.length) {
      displayText = AppLocale.allPartnersSelected.getString(context);
    } else {
      displayText = '${selectedBpIds.length} terceros seleccionados';
    }

    final color = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: bPartners.length > 1 ? () => _showMultiSelectBps(context) : null,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_alt, size: 20, color: color),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSyncing)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
