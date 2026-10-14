import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Importante para que funcionen los formatters

class CustomTextField extends StatelessWidget {
  final String? label;
  final String? hintText;
  final TextEditingController? controller;
  final int maxLines;
  final double? width;
  final double? height;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool filled;
  final Color? fillColor;
  final bool readOnly;
  final int? maxLength;
  final ScrollController? scrollController;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;


  const CustomTextField({
    super.key,
    this.label,
    this.hintText,
    this.controller,
    this.maxLines = 1,
    this.width,
    this.height,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.keyboardType,
    this.filled = false,
    this.fillColor,
    this.readOnly = false,
    this.maxLength,
    this.scrollController,
    this.inputFormatters, 
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final field = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: TextFormField(
        controller: controller,
        scrollController: scrollController,
        maxLines: maxLines,
        obscureText: obscureText,
        validator: validator,
        maxLength: maxLength,
        keyboardType: keyboardType,
        readOnly: readOnly,
        inputFormatters: inputFormatters, // Se pasa al TextFormField nativo
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        autofocus: autofocus,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          filled: filled,
          fillColor: fillColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: scrollController != null ? Scrollbar(controller: scrollController, thumbVisibility: true, child: field) : field,
    );
  }
}

class CustomDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final double? width;
  final double? height;
  final Widget? prefixIcon;
  final bool filled;
  final Color? fillColor;
  final String? Function(T?)? validator;

  const CustomDropdown({super.key, required this.value, required this.items, required this.onChanged, this.label, this.hintText, this.width, this.height, this.prefixIcon, this.filled = false, this.fillColor, this.validator});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final effectiveValue = (value != null && items.any((item) => item.value == value)) ? value : null;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: DropdownButtonFormField<T>(
        value: effectiveValue,
        items: items,
        onChanged: onChanged,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: prefixIcon,
          filled: filled,
          fillColor: fillColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down),
      ),
    );
  }
}
