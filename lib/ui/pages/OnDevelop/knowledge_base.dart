import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/ui/Shared_Custom/cardcustom.dart';
import 'package:primhub/ui/Shared_Custom/custom_inputs.dart';
import '../../widgets/custom_drawer.dart';
import 'package:flutter_localization/flutter_localization.dart';

class KnowledgeBasePage extends StatelessWidget {
  const KnowledgeBasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocale.knowledgeBase.getString(context))),
      drawer: const CustomDrawer(currentRoute: '/knowledge-base'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomTextField(hintText: 'Buscar...', prefixIcon: Icon(Icons.search), filled: true, fillColor: Colors.white),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 800) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCard('Guías de Usuario', ['Manual de usuario (CMS)', 'Primeros pasos con la plataforma', 'Gestion de Roles y Permisos']),
                        const SizedBox(height: 16),
                        _buildCard('Solucion de Problemas (FAQ)', ['¿Como recupero mi contraseña?', 'Error 500 al subir un archivo', 'El reporte no se genera']),
                        const SizedBox(height: 16),
                        _buildCard('Politicas y S.O.P', ['Politica de Soporte SLAs', 'Procedimiento para solicitudes urgentes']),
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildCard('Guías de Usuario', ['Manual de usuario (CMS)', 'Primeros pasos con la plataforma', 'Gestion de Roles y Permisos'])),
                        const SizedBox(width: 16),
                        Expanded(child: _buildCard('Solucion de Problemas (FAQ)', ['¿Como recupero mi contraseña?', 'Error 500 al subir un archivo', 'El reporte no se genera'])),
                        const SizedBox(width: 16),
                        Expanded(child: _buildCard('Politicas y S.O.P', ['Politica de Soporte SLAs', 'Procedimiento para solicitudes urgentes'])),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String title, List<String> items) {
    return CardCustom(
      height: null,
      width: null,
      hover: true,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...items.map((item) => _HoverableListItem(text: item)),
          ],
        ),
      ),
    );
  }
}

class _HoverableListItem extends StatefulWidget {
  final String text;
  const _HoverableListItem({required this.text});

  @override
  State<_HoverableListItem> createState() => _HoverableListItemState();
}

class _HoverableListItemState extends State<_HoverableListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _isHovered ? Colors.deepPurple.shade900 : Colors.deepPurple;

    return MouseRegion(
      onEnter: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isHovered = true);
        });
      },
      onExit: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isHovered = false);
        });
      },
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
            Expanded(
              child: Text(widget.text, style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
