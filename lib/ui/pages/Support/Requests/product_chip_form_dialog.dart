import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:flutter/services.dart';
import 'package:primhub/api/global_cache.dart';
import 'package:primhub/ui/Shared_Custom/custom_button.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import 'package:primhub/ui/Shared_Custom/custom_modal.dart';
import 'package:primhub/ui/Shared_Custom/custom_toast.dart';
import 'package:primhub/ui/pages/Support/Requests/product_chip_functions.dart';
import 'package:flutter_localization/flutter_localization.dart';

class ProductChipFormDialog extends StatefulWidget {
  const ProductChipFormDialog({super.key});

  @override
  State<ProductChipFormDialog> createState() => _ProductChipFormDialogState();
}

class _ProductChipFormDialogState extends State<ProductChipFormDialog> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;

  Future<void> _openSearchModal<T>({
    required String title,
    required List<dynamic> items,
    required T? currentValue,
    required String Function(dynamic) getTitle,
    String Function(dynamic)? getSubtitle,
    required T Function(dynamic) getValue,
    required void Function(T) onSelected,
  }) async {
    final double dialogHeight = MediaQuery.of(context).size.height * 0.6;
    final T? result = await showDialog<T>(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetAnimationDuration: Duration.zero,
          child: Container(
            width: 400,
            height: dialogHeight,
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                final filteredItems = items.where((item) {
                  return getTitle(
                    item,
                  ).toLowerCase().contains(searchQuery.toLowerCase());
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleccionar $title *',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.filter_list, color: Colors.grey),
                        hintText: 'Filtrar...',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      onChanged: (val) =>
                          setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Colors.grey,
                          thickness: 0.3,
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final itemValue = getValue(item);
                          final isSelected = itemValue == currentValue;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            tileColor: isSelected
                                ? Colors.grey.withOpacity(0.1)
                                : null,
                            title: Text(
                              getTitle(item),
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: getSubtitle != null
                                ? Text(
                                    getSubtitle(item),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(itemValue),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null) onSelected(result);
  }

  Widget _buildSearchableField<T>({
    required String label,
    required String? hintText,
    required T? value,
    required bool isLoading,
    required bool isDisabled,
    required String displayText,
    required VoidCallback onTap,
    IconData? prefixIcon,
  }) {
    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, color: Theme.of(context).colorScheme.primary)
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: isLoading
              ? Transform.scale(
                  scale: 0.5,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(Icons.search),
        ),
        isEmpty: value == null,
        child: Text(
          value == null ? (hintText ?? '') : displayText,
          style: TextStyle(
            fontSize: 16,
            color: (isLoading || isDisabled || value == null)
                ? Colors.grey[600]
                : Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // Selected values
  int? _selectedBPartnerId;
  int? _selectedContactId;
  int? _selectedLocationId;
  int? _selectedProductId;
  String? _selectedFrequencyType;
  int? _selectedPriceListId;

  // Form Fields
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _contractNoController = TextEditingController();

  DateTime? _serviceStartDate;
  DateTime? _serviceFinishDate;

  // Lists
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _frequencies = [];
  List<Map<String, dynamic>> _priceLists = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _qtyController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _contractNoController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {});
  }

  bool get _isFormValid {
    return _selectedBPartnerId != null &&
        _selectedContactId != null &&
        _selectedLocationId != null &&
        _selectedProductId != null &&
        _selectedFrequencyType != null &&
        _selectedPriceListId != null &&
        _serviceStartDate != null &&
        _qtyController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        _contractNoController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _descriptionController.dispose();
    _contractNoController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // Ejecutar en paralelo las llamadas a la API que no dependen del BPartner
    final results = await Future.wait([
      fetchSupportProducts(),
      fetchPriceLists(),
      fetchFrequencyTypes(),
    ]);

    if (!mounted) return;

    setState(() {
      _products = results[0];
      _priceLists = results[1];
      _frequencies = results[2];
      _isLoading = false;
    });
  }

  Future<void> _onBPartnerSelected(int? bPartnerId) async {
    if (bPartnerId == null) return;

    setState(() {
      _selectedBPartnerId = bPartnerId;
      _selectedContactId = null;
      _contacts = [];
    });

    final contacts = await fetchContactsForBPartner(bPartnerId);
    final locations = await fetchLocationsForBPartner(bPartnerId);
    if (!mounted) return;

    setState(() {
      _contacts = contacts;
      _locations = locations;
      // Auto-select if only one exists
      if (_contacts.length == 1) {
        _selectedContactId = (_contacts.first['id'] as num?)?.toInt();
      }
      if (_locations.length == 1) {
        _selectedLocationId = (_locations.first['id'] as num?)?.toInt();
      }
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime initialDate = isStart
        ? (_serviceStartDate ?? DateTime.now())
        : (_serviceFinishDate ?? (_serviceStartDate ?? DateTime.now()));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _serviceStartDate = picked;
          // Ensure finish date is not before start date
          if (_serviceFinishDate != null &&
              _serviceFinishDate!.isBefore(picked)) {
            _serviceFinishDate = null;
          }
        } else {
          _serviceFinishDate = picked;
        }
      });
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedBPartnerId == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar un Tercero',
        type: ToastType.warning,
      );
      return;
    }
    if (_selectedContactId == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar un Contacto de Facturación',
        type: ToastType.warning,
      );
      return;
    }
    if (_selectedLocationId == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar una Dirección de Factura',
        type: ToastType.warning,
      );
      return;
    }
    if (_selectedProductId == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar un Producto',
        type: ToastType.warning,
      );
      return;
    }
    if (_selectedFrequencyType == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar un Tipo de Frecuencia',
        type: ToastType.warning,
      );
      return;
    }
    if (_selectedPriceListId == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar una Lista de Precios',
        type: ToastType.warning,
      );
      return;
    }
    if (_contractNoController.text.trim().isEmpty) {
      ToastMessage.show(
        context: context,
        message: 'Debe ingresar el N° de Contrato',
        type: ToastType.warning,
      );
      return;
    }
    if (_serviceStartDate == null) {
      ToastMessage.show(
        context: context,
        message: 'Debe seleccionar la fecha de inicio',
        type: ToastType.warning,
      );
      return;
    }

    setState(() => _isSaving = true);

    final qty = double.tryParse(_qtyController.text.trim()) ?? 1.0;

    final result = await saveProductChip(
      context: context,
      bPartnerId: _selectedBPartnerId!,
      adUserId: _selectedContactId!,
      locationId: _selectedLocationId!,
      productId: _selectedProductId!,
      qty: qty,
      description: _descriptionController.text.trim(),
      frequencyType: _selectedFrequencyType!,
      contractNo: _contractNoController.text.trim(),
      serviceStartDate:
          "${_serviceStartDate!.year}-${_serviceStartDate!.month.toString().padLeft(2, '0')}-${_serviceStartDate!.day.toString().padLeft(2, '0')} 00:00:00",
      serviceFinishDate: _serviceFinishDate != null
          ? "${_serviceFinishDate!.year}-${_serviceFinishDate!.month.toString().padLeft(2, '0')}-${_serviceFinishDate!.day.toString().padLeft(2, '0')} 00:00:00"
          : null,
      priceListId: _selectedPriceListId!,
    );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ToastMessage.show(
        context: context,
        message: 'Ficha de producto creada exitosamente',
        type: ToastType.success,
      );
      Navigator.of(context).pop(_selectedBPartnerId);
    } else {
      ToastMessage.show(
        context: context,
        message: result['message'],
        type: ToastType.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return CustomModal(
        title: AppLocale.newProductSheet.getString(context),
        content: const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [],
      );
    }

    // Preparar BPartners

    final isMobile = MediaQuery.of(context).size.width < 600;

    Widget buildPair(Widget w1, Widget w2) {
      if (isMobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [w1, const SizedBox(height: 16), w2],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: w1),
          const SizedBox(width: 16),
          Expanded(child: w2),
        ],
      );
    }

    return CustomModal(
      title: AppLocale.newProductSheet.getString(context),
      width: 1000,
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocale.mainInformation.getString(context),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              // FILA 1: Tercero y Contacto
              buildPair(
                _buildSearchableField<int>(
                  label: AppLocale.associatedPartner.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedBPartnerId,
                  isLoading: false,
                  isDisabled: false,
                  prefixIcon: Icons.business,
                  displayText: _selectedBPartnerId != null
                      ? (GlobalCache.bPartners.firstWhere(
                              (b) => b['id'] == _selectedBPartnerId,
                              orElse: () => {},
                            )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<int>(
                      title: 'Tercero Asociado',
                      items: GlobalCache.bPartners,
                      currentValue: _selectedBPartnerId,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => (item['id'] as num).toInt(),
                      onSelected: _onBPartnerSelected,
                    );
                  },
                ),
                _buildSearchableField<int>(
                  label: AppLocale.billingContact.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedContactId,
                  isLoading: _isLoading,
                  isDisabled: _contacts.isEmpty,
                  prefixIcon: Icons.person_outline,
                  displayText: _selectedContactId != null
                      ? (_contacts.firstWhere(
                              (c) => c['id'] == _selectedContactId,
                              orElse: () => {},
                            )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<int>(
                      title: 'Contacto de Facturación',
                      items: _contacts,
                      currentValue: _selectedContactId,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => (item['id'] as num).toInt(),
                      onSelected: (val) {
                        setState(() => _selectedContactId = val);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // FILA 2: Dirección y Producto
              buildPair(
                _buildSearchableField<int>(
                  label: AppLocale.billingAddress.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedLocationId,
                  isLoading: _isLoading,
                  isDisabled: _locations.isEmpty,
                  prefixIcon: Icons.location_on_outlined,
                  displayText: _selectedLocationId != null
                      ? (_locations.firstWhere(
                              (l) => l['id'] == _selectedLocationId,
                              orElse: () => {},
                            )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<int>(
                      title: 'Dirección de Factura',
                      items: _locations,
                      currentValue: _selectedLocationId,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => (item['id'] as num).toInt(),
                      onSelected: (val) {
                        setState(() => _selectedLocationId = val);
                      },
                    );
                  },
                ),
                _buildSearchableField<int>(
                  label: AppLocale.supportProduct.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedProductId,
                  isLoading: _isLoading,
                  isDisabled: _products.isEmpty,
                  prefixIcon: Icons.inventory_2_outlined,
                  displayText: _selectedProductId != null
                      ? (_products.firstWhere(
                              (p) => p['id'] == _selectedProductId,
                              orElse: () => {},
                            )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<int>(
                      title: 'Producto (Soporte)',
                      items: _products,
                      currentValue: _selectedProductId,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => (item['id'] as num).toInt(),
                      onSelected: (val) {
                        setState(() => _selectedProductId = val);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // FILA 3: Descripción
              CustomTextField(
                controller: _descriptionController,
                label: AppLocale.productSheetName.getString(context),
                prefixIcon: Icon(
                  Icons.label_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Requerido' : null,
              ),

              const Divider(height: 48),

              Text(
                AppLocale.billingAndContract.getString(context),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              // FILA 4: Frecuencia y Lista de Precios
              buildPair(
                _buildSearchableField<String>(
                  label: AppLocale.frequencyType.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedFrequencyType,
                  isLoading: _isLoading,
                  isDisabled: false,
                  prefixIcon: Icons.update,
                  displayText: _selectedFrequencyType != null
                      ? ((_frequencies.isNotEmpty
                                    ? _frequencies
                                    : [
                                        {'Value': 'M', 'Name': 'Mensual'},
                                        {'Value': 'A', 'Name': 'Anual'},
                                        {'Value': 'H', 'Name': 'Por Hora'},
                                      ])
                                .firstWhere(
                                  (f) => f['Value'] == _selectedFrequencyType,
                                  orElse: () => {},
                                )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<String>(
                      title: 'Tipo de Frecuencia',
                      items: _frequencies.isNotEmpty
                          ? _frequencies
                          : [
                              {'Value': 'M', 'Name': 'Mensual'},
                              {'Value': 'A', 'Name': 'Anual'},
                              {'Value': 'H', 'Name': 'Por Hora'},
                            ],
                      currentValue: _selectedFrequencyType,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => item['Value']?.toString() ?? '',
                      onSelected: (val) {
                        setState(() => _selectedFrequencyType = val);
                      },
                    );
                  },
                ),
                _buildSearchableField<int>(
                  label: AppLocale.priceList.getString(context),
                  hintText: AppLocale.select.getString(context),
                  value: _selectedPriceListId,
                  isLoading: false,
                  isDisabled: false,
                  prefixIcon: Icons.request_quote_outlined,
                  displayText: _selectedPriceListId != null
                      ? (_priceLists.firstWhere(
                              (pl) => pl['id'] == _selectedPriceListId,
                              orElse: () => {},
                            )['Name'] ??
                            'Desconocido')
                      : '',
                  onTap: () {
                    _openSearchModal<int>(
                      title: 'Lista de Precios',
                      items: _priceLists,
                      currentValue: _selectedPriceListId,
                      getTitle: (item) =>
                          item['Name'] ?? item['name'] ?? 'Desconocido',
                      getValue: (item) => (item['id'] as num).toInt(),
                      onSelected: (val) {
                        setState(() => _selectedPriceListId = val);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // FILA 5: Cantidad y N° Contrato
              buildPair(
                CustomTextField(
                  controller: _qtyController,
                  label: AppLocale.quantity.getString(context),
                  prefixIcon: Icon(
                    Icons.numbers,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Requerido'
                      : null,
                ),
                CustomTextField(
                  controller: _contractNoController,
                  label: AppLocale.contractNumber.getString(context),
                  prefixIcon: Icon(
                    Icons.receipt_long_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Requerido'
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // FILA 6: Fechas
              buildPair(
                InkWell(
                  onTap: () => _selectDate(context, true),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocale.serviceStart.getString(context),
                      prefixIcon: Icon(
                        Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    child: Text(
                      _serviceStartDate != null
                          ? "${_serviceStartDate!.day}/${_serviceStartDate!.month}/${_serviceStartDate!.year}"
                          : AppLocale.selectDate.getString(context),
                      style: TextStyle(
                        fontSize: 16,
                        color: _serviceStartDate != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _selectDate(context, false),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocale.serviceEnd.getString(context),
                      prefixIcon: Icon(
                        Icons.event_busy,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    child: Text(
                      _serviceFinishDate != null
                          ? "${_serviceFinishDate!.day}/${_serviceFinishDate!.month}/${_serviceFinishDate!.year}"
                          : AppLocale.selectDate.getString(context),
                      style: TextStyle(
                        fontSize: 16,
                        color: _serviceFinishDate != null
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(AppLocale.cancel.getString(context)),
        ),
        CustomButton(
          text: AppLocale.createProductSheet.getString(context),
          onPressed: _isFormValid ? _saveForm : null,
          isLoading: _isSaving,
          backgroundColor: _isFormValid
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
        ),
      ],
    );
  }
}
