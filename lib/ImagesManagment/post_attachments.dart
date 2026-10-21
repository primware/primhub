import 'dart:convert';
import 'package:http/http.dart' as http_client;
import 'package:primhub/api/api_http.dart';
import 'package:primhub/api/api_utils.dart';
import 'package:primhub/api/token.dart';
import 'package:primhub/endpoint/endpoint.dart';

Future<bool> postAttachments({
  required int recordID,
  required String tableName,
  required Map<String, String> convertedFile,
  bool shouldUpdateStatus = false,
}) async {
  try {
    final Map<String, dynamic> data = {"name": convertedFile['title'], "data": convertedFile['base64']};

    var response = await post(
      Uri.parse(PostMedia(recordID: recordID, tableName: tableName).endPoint),
      headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
      body: jsonEncode(data),
    );

    if (response.statusCode == 401) {
      final refreshed = await handleTokenRefresh();
      if (refreshed) {
        response = await post(
          Uri.parse(PostMedia(recordID: recordID, tableName: tableName).endPoint),
          headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
          body: jsonEncode(data),
        );
      }
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (shouldUpdateStatus && !tableName.contains('R_Request')) {
        _updateStatus(tableName, recordID, 'Pendiente');
      }
      return true;
    } else {
      return false;
    }
  } catch (e) {
    return false;
  }
}

Future<void> _updateStatus(String tableName, int recordID, String status) async {
  try {
    final Uri url = tableName.startsWith('http') ? Uri.parse('$tableName/$recordID') : Uri.parse('${Endpoint.baseUrl}/api/v1/models/$tableName/$recordID');
    // Usar http_client directo con timeout para no disparar alertas de desconexión falsas
    await http_client.put(
      url,
      headers: {'Content-Type': 'application/json', 'Authorization': Token.token},
      body: jsonEncode({'Status': status}),
    ).timeout(const Duration(seconds: 5));
  } catch (e) { /* Ignore error */ }
}
