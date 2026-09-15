import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/admin_mode_views.dart';
import 'package:go_router/go_router.dart';
import 'package:primhub/api/access_control.dart';
import 'package:primhub/ui/pages/Projects/Documents/project_file_manager.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';

import 'package:primhub/ui/pages/Projects/Documents/documents_logic.dart';
import 'package:primhub/ui/pages/Projects/Projects_Widgets/project_item.dart';
import 'package:primhub/ui/pages/Projects/Documents/project_form_page.dart';
import 'package:primhub/ui/widgets/project_sidebar.dart';
import '../../../widgets/custom_drawer.dart';
import 'package:primhub/api/admin_view_mode.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/widgets/project_bottom_nav.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/ui/Shared_Custom/custom_skeleton.dart';
import 'package:primhub/ui/Shared_Custom/user_info_leading.dart';
import 'package:primhub/ui/Shared_Custom/help_icon.dart';

class DeliverablesPage extends StatefulWidget {
  const DeliverablesPage({super.key});

  @override
  State<DeliverablesPage> createState() => _DeliverablesPageState();
}

class _DeliverablesPageState extends State<DeliverablesPage> {
  bool _showingFiles = false;
  bool _isFileManagerRoot = true;
  final GlobalKey<ProjectFileManagerState> _fileManagerKey = GlobalKey();
  final _adminViewModeManager = AdminViewModeManager();

  List<dynamic> _projects = [];
  Map<String, dynamic>? _selectedProject;
  bool _isLoadingProjects = false;
  String? _projectsErrorMessage;
  final TextEditingController _searchController = TextEditingController();

  // FILTROS DE ADMINISTRADOR
  final bool _showInactive = false;
  bool _viewingInactive = false;

  final Set<int> _expandedProjectIds = {};

  bool _isInit = true;
  String _currentViewType = '';
  final ProjectsLogic _logic = ProjectsLogic();

  Map<String, int> _statusIdMap = {};
  final Map<String, String> _priorityMap = {
    'Urgente': '1',
    'Alta': '3',
    'Media': '5',
    'Baja': '7',
    'Menor': '9',
  };
  final Map<int, Map<String, dynamic>> _projectStats = {}; // Almacenar stats

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _fetchStatuses();
    _searchController.addListener(() => setState(() {}));
    _adminViewModeManager.addListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.addListener(_onBackgroundSyncChanged);
  }

  void _onBackgroundSyncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adminViewModeManager.removeListener(_onViewModeChanged);
    GlobalCache.backgroundSyncNotifier.removeListener(_onBackgroundSyncChanged);
    super.dispose();
  }

  void _onViewModeChanged() {
    _loadProjects();
  }

  // Carga de proyectos con filtros aplicados
  Future<void> _loadProjects({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingProjects = true;
      _projectsErrorMessage = null;
    });
    try {
      await GlobalCache.syncData(force: forceRefresh);

      List<dynamic> projects = [];
      if (_showInactive || _viewingInactive) {
        projects = await _logic.fetchProjects(
          showInactive: _showInactive,
          onlyInactive: _viewingInactive,
          isViewingMine: _adminViewModeManager.isViewingMine,
        );
      } else {
        projects = GlobalCache.projects;
        
        if (_adminViewModeManager.isViewingMine && AccessControl.isAdmin) {
          int? partnerID = User.cBPartnerID;
          int? userID = User.userID;
          projects = projects.where((p) {
            final bpId = p['C_BPartner_ID'] is Map
                ? p['C_BPartner_ID']['id']
                : p['C_BPartner_ID'];
            final repId = p['SalesRep_ID'] is Map
                ? p['SalesRep_ID']['id']
                : p['SalesRep_ID'];
            return (partnerID != null && bpId == partnerID) ||
                (userID != null && repId == userID);
          }).toList();
        }
      }

      if (mounted) {
        setState(() {
          _projects = projects;
          // Cargar stats en segundo plano para no bloquear
          _loadProjectStats();

          _isLoadingProjects = false;

          Object? extra;
          try {
            extra = GoRouterState.of(context).extra;
          } catch (_) {
      // Ignored: Fail silently
    }

          final args =
              (extra ?? ModalRoute.of(context)?.settings.arguments)
                  as Map<String, dynamic>?;
          if (args != null && _isInit) {
            _applyPendingArgs(args);
            _isInit = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProjects = false;
          _projectsErrorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadProjectStats() async {
    // Implementación simplificada o llamada a lógica compartida
  }

  Future<void> _fetchStatuses() async {
    final statuses = await DocumentsLogic.fetchStatuses();
    if (mounted) {
      setState(() {
        _statusIdMap = {
          for (var s in statuses)
            s['name'].toString(): int.tryParse(s['id'].toString()) ?? 0,
        };
      });
    }
  }

  // Navegación al formulario (Crear/Editar)
  Future<void> _navigateToForm({Map<String, dynamic>? project}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectFormPage(project: project),
      ),
    );

    if (result == true) {
      _loadProjects(forceRefresh: true);
      if (mounted) {
        ToastMessage.show(
          context: context,
          message: project == null ? 'Proyecto creado exitosamente' : 'Proyecto actualizado exitosamente',
          type: ToastType.success,
        );
      }
    }
  }

  void _applyPendingArgs(Map<String, dynamic> args) {
    final projectId = args['projectId'];
    final view = args['view'];
    final project = _projects.firstWhere(
      (p) => p['id'].toString() == projectId.toString(),
      orElse: () => null,
    );
    if (project == null) return;

    if (view == 'projects') {
      setState(() {
        final rawId = project['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
        _expandedProjectIds.add(id);
        _exitFileManager();
      });
    } else {
      _onShowFiles(project, view);
    }
  }

  void _onShowFiles(Map<String, dynamic> project, String viewType) {
    setState(() {
      _selectedProject = project;
      _currentViewType = viewType;
      _showingFiles = true;
      _isFileManagerRoot = true;
    });
  }

  void _exitFileManager() {
    setState(() {
      _showingFiles = false;
      _selectedProject = null;
      _currentViewType = '';
    });
  }

  // Métodos de fases y tareas
  Future<void> _createPhase(
    int projectId,
    Map<String, dynamic> data,
  ) async {
    setState(() {
      _isLoadingProjects = true;
      _expandedProjectIds.add(projectId);
    });
    final result = await _logic.createPhase(projectId, data);
    if (result['success'] == true) {
      _loadProjects(forceRefresh: true);
      if (mounted) {
        ToastMessage.show(
          context: context,
          message: 'Fase creada exitosamente',
          type: ToastType.success,
        );
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingProjects = false);
        ToastMessage.show(context: context, message: 'Error al crear fase: ${result['error']}', type: ToastType.failure);
      }
    }
  }

  Future<void> _createTask(int phaseId, int projectId, Map<String, dynamic> data) async {
    setState(() {
      _isLoadingProjects = true;
      _expandedProjectIds.add(projectId);
      data['C_Project_ID'] = projectId;
    });
    final result = await _logic.createTask(phaseId, data);
    if (result['success'] == true) {
      _loadProjects(forceRefresh: true);
      if (mounted) {
        ToastMessage.show(
          context: context,
          message: 'Tarea creada exitosamente',
          type: ToastType.success,
        );
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingProjects = false);
        ToastMessage.show(context: context, message: 'Error al crear tarea: ${result['error']}', type: ToastType.failure);
      }
    }
  }



  Widget _buildProjectFilterPopupMenu() {
    return PopupMenuButton<bool>(
      tooltip: 'Filtrar proyectos',
      onSelected: (bool viewingMine) =>
          _adminViewModeManager.setViewingMine(viewingMine),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _adminViewModeManager.isViewingMine ? Icons.person : Icons.group,
            ),
            const SizedBox(width: 8),
            Text(
              _adminViewModeManager.isViewingMine
                  ? AppLocale.myProjects.getString(context)
                  : AppLocale.allProjects.getString(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      itemBuilder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final isViewingMine = _adminViewModeManager.isViewingMine;
        PopupMenuItem<bool> buildItem(
          bool isMineOption,
          String text,
          IconData icon,
        ) {
          final isSelected = isViewingMine == isMineOption;
          return PopupMenuItem<bool>(
            value: isMineOption,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (isSelected) const Spacer(),
                  if (isSelected)
                    Icon(Icons.check, size: 18, color: colorScheme.primary),
                ],
              ),
            ),
          );
        }

        return [
          buildItem(true, AppLocale.myProjects.getString(context), Icons.person),
          buildItem(false, AppLocale.allProjects.getString(context), Icons.group),
        ];
      },
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final List<Widget> commonActions = [
      const HelpIcon(),
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Refrescar',
        onPressed: () {
          if (_showingFiles) {
            _fileManagerKey.currentState?.refresh();
          } else {
            setState(() => _isLoadingProjects = true);
            GlobalCache.forceFullSyncWithProgress(
              context,
              onSyncAction: () async => await _loadProjects(forceRefresh: true),
            );
          }
        },
      ),
      if (!AccessControl.isAdmin)
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.red),
          tooltip: AppLocale.logout.getString(context),
          onPressed: () => showLogoutConfirmation(context),
        ),
    ];

    if (_showingFiles) {
      final List<Widget> fileManagerActions = [];
      if (AccessControl.canManageFiles) {
        if (_isFileManagerRoot) {
          fileManagerActions.add(
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Nueva Carpeta',
              onPressed: () => _fileManagerKey.currentState?.createFolderDialog(),
            ),
          );
        }
        fileManagerActions.add(
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Subir Archivo',
            onPressed: () => _fileManagerKey.currentState?.pickAndUploadFile(),
          ),
        );
      }
      return [...fileManagerActions, ...commonActions];
    }

    if (isMobile) {
      List<PopupMenuItem<String>> mobileMenuItems = [];
      if (AccessControl.isAdmin) {
        mobileMenuItems.add(
          PopupMenuItem<String>(
            value: 'admin_mode',
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text(
                'Modo: ${_adminViewModeManager.currentMode == AdminViewMode.support ? 'Soporte' : (_adminViewModeManager.currentMode == AdminViewMode.project ? 'Proyecto' : 'Mixto')}',
              ),
            ),
          ),
        );
        mobileMenuItems.add(
          PopupMenuItem<String>(
            value: 'project_filter',
            child: ListTile(
              leading: Icon(
                _adminViewModeManager.isViewingMine
                    ? Icons.person
                    : Icons.group,
              ),
              title: Text(
                _adminViewModeManager.isViewingMine ? AppLocale.myProjects.getString(context) : AppLocale.allProjects.getString(context),
              ),
            ),
          ),
        );
      }
      if (!AccessControl.isProject) {
        mobileMenuItems.add(
          PopupMenuItem<String>(
            value: 'toggle_inactive',
            child: ListTile(
              leading: Icon(
                _viewingInactive ? Icons.visibility : Icons.visibility_off,
              ),
              title: Text(_viewingInactive ? 'Ver Activos' : 'Ver Inactivos'),
            ),
          ),
        );
      }

      return [
        if (mobileMenuItems.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'toggle_inactive') {
                setState(() {
                  _viewingInactive = !_viewingInactive;
                  _expandedProjectIds.clear();
                });
                _loadProjects();
              }
            },
            itemBuilder: (context) => mobileMenuItems,
          ),
        ...commonActions,
      ];
    }

    // Desktop view
    List<Widget> desktopActions = [];
    if (!_showingFiles) {
      if (AccessControl.isAdmin) {
        desktopActions.add(const AdminModeViews());
        desktopActions.add(_buildProjectFilterPopupMenu());
      }
      if (!AccessControl.isProject) {
        desktopActions.add(
          IconButton(
            icon: Icon(
              _viewingInactive ? Icons.archive : Icons.archive_outlined,
            ),
            tooltip: _viewingInactive
                ? 'Ver Proyectos Activos'
                : 'Ver Proyectos Desactivados',
            onPressed: () =>
                setState(() => _viewingInactive = !_viewingInactive),
          ),
        );
      }
    }

    return [...desktopActions, ...commonActions];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewingInactive ? AppLocale.projectLog.getString(context) : AppLocale.myProjects.getString(context),
          style: const TextStyle(fontSize: 22),
        ),
        leadingWidth: _showingFiles
            ? null
            : (!AccessControl.isAdmin ? 180 : null),
        leading: _showingFiles
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (!(_fileManagerKey.currentState?.navigateBack() ?? false)) {
                    _exitFileManager();
                  }
                },
              )
            : (!AccessControl.isAdmin
                  ? const UserInfoLeading()
                  : Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        tooltip: AppLocale.mainMenu.getString(context),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    )),
        actions: _buildAppBarActions(context),
      ),
      drawer: (_showingFiles || !AccessControl.isAdmin)
          ? null
          : const CustomDrawer(currentRoute: '/deliverables'),
      bottomNavigationBar: (MediaQuery.of(context).size.width < 900 &&
              !AccessControl.isAdmin &&
              !_showingFiles)
          ? const ProjectBottomNav(currentRoute: '/deliverables')
          : null,
      floatingActionButton:
          !_showingFiles &&
              !_viewingInactive &&
              AccessControl.canCreateProjectItems
          ? FloatingActionButton(
              onPressed: () => _navigateToForm(),
              tooltip: 'Nuevo Proyecto',
              child: const Icon(Icons.add),
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.of(context).size.width >= 900 &&
              !AccessControl.isAdmin &&
              !_showingFiles)
            const ProjectSideBar(currentRoute: '/deliverables'),
          Expanded(
            child: SafeArea(
              child: _showingFiles
                  ? ProjectFileManager(
                      key: _fileManagerKey,
                      project: _selectedProject!,
                      viewType: _currentViewType,
                      onExit: _exitFileManager,
                      onRootChanged: (isRoot) =>
                          setState(() => _isFileManagerRoot = isRoot),
                    )
                  : _buildProjectsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectsView() {
    if (_isLoadingProjects) return const SkeletonList();

    final filteredProjects = _projects.where((project) {
      final projectName = (project['Name'] as String? ?? '').toLowerCase();
      return projectName.contains(_searchController.text.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: CustomTextField(
            controller: _searchController,
            hintText: AppLocale.searchProject.getString(context),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        if (_projectsErrorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _projectsErrorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: filteredProjects.isEmpty
              ? Center(child: Text(AppLocale.noProjectsFound.getString(context)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredProjects.length,
                  itemBuilder: (context, index) {
                    final project = filteredProjects[index];
                    final projId = project['id'] is int
                        ? project['id'] as int
                        : int.tryParse(project['id'].toString()) ?? 0;
                    final isExpanded = _expandedProjectIds.contains(projId);
                    return ProjectItem(
                      key: ValueKey('pj-$projId-$isExpanded'),
                      project: project,
                      isExpanded: isExpanded,
                      statusIdMap: _statusIdMap,
                      priorityMap: _priorityMap,
                      onRefresh: _loadProjects,
                      onToggleExpansion: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedProjectIds.remove(projId);
                          } else {
                            _expandedProjectIds.add(projId);
                          }
                        });
                      },
                      // Al editar, abrimos el formulario de administrador
                      onEdit: (type, id, data) async {
                        if (type == 'project') {
                          _navigateToForm(project: project);
                        } else {
                          setState(() {
                            _isLoadingProjects = true;
                            _expandedProjectIds.add(projId);
                          });
                          final result = await _logic.updateItem(
                            type,
                            id,
                            data,
                          );
                          if (result['success'] == true) {
                            _loadProjects(forceRefresh: true);
                            if (mounted) {
                              ToastMessage.show(
                                context: context,
                                message: 'Actualizado exitosamente',
                                type: ToastType.success,
                              );
                            }
                          } else if (mounted) {
                            setState(() => _isLoadingProjects = false);
                            ToastMessage.show(context: context, message: 'Error al actualizar: ${result['error']}', type: ToastType.failure);
                          }
                        }
                      },
                      onCreatePhase: _createPhase,
                      onCreateTask: _createTask,
                      onShowFiles: _onShowFiles,
                      isArchived: _viewingInactive,
                      stats: _projectStats[projId], // Pasar stats
                    );
                  },
                ),
        ),
      ],
    );
  }
}
