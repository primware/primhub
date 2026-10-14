import 'package:flutter/widgets.dart';
import 'package:primhub/ui/pages/BPartner/bpartner_documents_page.dart';
import 'package:primhub/ui/pages/Profile/profile_page.dart';
import 'package:primhub/ui/pages/Admin/user_management_page.dart';

Widget buildProfilePage() => const ProfilePage();
Widget buildBPartnerDocumentsPage(String viewType) =>
    BPartnerDocumentsPage(viewType: viewType);
Widget buildUserManagementPage() => const UserManagementPage();
