import 'package:flutter/material.dart';

class SearchableDropdown<T> extends StatelessWidget {
  final String label;
  final String? hintText;
  final T? value;
  final bool isLoading;
  final bool isDisabled;
  final String displayText;
  final VoidCallback onTap;
  final String? errorMessage;

  const SearchableDropdown({
    super.key,
    required this.label,
    this.hintText,
    required this.value,
    this.isLoading = false,
    this.isDisabled = false,
    required this.displayText,
    required this.onTap,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: (isLoading || isDisabled) ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorMessage,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
            fontSize: 14,
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

  static Future<T?> openSearchModal<T>({
    required BuildContext context,
    required String title,
    required List<dynamic> items,
    required T? currentValue,
    required String Function(dynamic) getTitle,
    String Function(dynamic)? getSubtitle,
    required T Function(dynamic) getValue,
  }) async {
    final double dialogHeight = MediaQuery.of(context).size.height * 0.6;
    return showDialog<T>(
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
                  return getTitle(item).toLowerCase().contains(searchQuery.toLowerCase());
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Seleccionar $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.filter_list, color: Colors.grey),
                        hintText: 'Filtrar...',
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
                      ),
                      onChanged: (val) => setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.grey, thickness: 0.3),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final itemValue = getValue(item);
                          final isSelected = itemValue == currentValue;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            tileColor: isSelected ? Colors.grey.withOpacity(0.1) : null,
                            title: Text(getTitle(item), style: const TextStyle(fontSize: 14)),
                            subtitle: getSubtitle != null ? Text(getSubtitle(item), style: const TextStyle(fontSize: 12, color: Colors.grey)) : null,
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
  }
}
