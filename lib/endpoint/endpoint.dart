class Envirioment {
  static bool get isProduction {
    final url = Uri.base.toString();
    if (url.contains('hubtest.primware.net') || url.contains('localhost') || url.contains('127.0.0.1')) {
      return false;
    }
    return true;
  }
}

class Endpoint {
  static String baseUrl = _getInitialBaseUrl();

  static String _getInitialBaseUrl() {
    final url = Uri.base.toString();
    if (url.contains('localhost') || url.contains('127.0.0.1')) {
      return "https://demo.primware.net";
    } else if (url.contains('hubtest.primware.net')) {
      return "https://primhub.primware.net";
    } else if (url.contains('hub.primware.net')) {
      Envirioment.isProduction == true;
      return "https://erp.primware.net";
    }
    return Envirioment.isProduction ? "https://erp.primware.net" : "https://primhub.primware.net";
  }

  static bool get isProduction => Envirioment.isProduction;

  static String get request => "$baseUrl/api/v1/models/R_Request";
  static String get order => "$baseUrl/api/v1/models/C_Order";
  static String get productChip => "$baseUrl/api/v1/models/C_BPartner_Product_Chip";
  static String get mProduct => "$baseUrl/api/v1/models/M_Product";
  static String get priceList => "$baseUrl/api/v1/models/M_PriceList";
  static String get adRefList => "$baseUrl/api/v1/models/AD_Ref_List";
  static String get cBPartner => "$baseUrl/api/v1/models/C_BPartner";
  static String get adUser => "$baseUrl/api/v1/models/AD_User";
  static String get primConfig => "$baseUrl/api/v1/models/Prim_Config";
  static String get project => "$baseUrl/api/v1/models/C_Project";
  static String get primDocuments => "$baseUrl/api/v1/models/PRIM_Documents";
  static String get currency => "$baseUrl/api/v1/models/C_Currency";
  static String get adSysConfig => "$baseUrl/api/v1/models/AD_SysConfig";
  static String get rMailText => "$baseUrl/api/v1/models/R_MailText";
  static String get authTokens => "$baseUrl/api/v1/auth/tokens";
  static String get authRoles => "$baseUrl/api/v1/auth/roles";
  static String get authOrgs => "$baseUrl/api/v1/auth/organizations";
  static String get authWarehouses => "$baseUrl/api/v1/auth/warehouses";
  static String get authLogout => "$baseUrl/api/v1/auth/logout";
  static String get primDocumentsRelated => "$baseUrl/api/v1/models/PRIM_Documents_Related";
  static String get changePasswordProcess => "$baseUrl/api/v1/processes/setuserpasswordprocesspos";
}

class PostMedia {
  final int recordID;
  final String tableName;

  PostMedia({required this.recordID, required this.tableName});

  String get endPoint {
    if (tableName.startsWith('http')) {
      return '$tableName/$recordID/attachments';
    }
    return '${Endpoint.baseUrl}/api/v1/models/$tableName/$recordID/attachments';
  }
}
