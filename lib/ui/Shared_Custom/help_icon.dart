import 'package:flutter/material.dart';
import 'package:primhub/localization/app_locale.dart';
import 'package:primhub/api/access_control.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter_localization/flutter_localization.dart';

class HelpIcon extends StatelessWidget {
  final Color? color;
  const HelpIcon({super.key, this.color});

  void _openHelpUrl() {
    String url = 'https://docs.primware.net/books/primhub';
    
    if (AccessControl.isRealAdmin) {
      url = 'https://docs.primware.net/books/primhub/page/manual-de-usuario-perfil-administrador';
    } else if (AccessControl.isRealSupport) {
      url = 'https://docs.primware.net/books/primhub/page/manual-de-usuario-perfil-de-soporte';
    } else if (AccessControl.isRealProject) {
      url = 'https://docs.primware.net/books/primhub/page/manual-de-usuario-perfil-de-proyecto';
    }
    
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline_rounded),
      tooltip: AppLocale.helpManual.getString(context),
      color: color,
      onPressed: _openHelpUrl,
    );
  }
}
