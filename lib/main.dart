import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import 'core/accounting.dart';
import 'core/models.dart';
import 'core/production_config.dart';
import 'core/user_facing_errors.dart';
import 'data/local_database.dart';
import 'data/accounting_repository.dart';
import 'data/currency_repository.dart';
import 'services/account_import_service.dart';
import 'services/auth_service.dart';
import 'services/secure_backup_service.dart';
import 'core/design_system.dart';
import 'features/connectors/presentation/connector_center_screen.dart';
import 'features/connectors/domain/connector_item.dart';
import 'connectors/connector_adapter.dart';
import 'features/connectors/application/connector_service.dart';
import 'features/connectors/application/connector_center_controller.dart';
import 'services/android_notification_service.dart';
import 'features/accounting/application/accounting_reports_controller.dart';
import 'features/accounting/presentation/account_editor_dialog.dart';
import 'features/accounting/presentation/accounting_reports_screen.dart';
import 'features/accounting/presentation/accounting_policy_settings_screen.dart';
import 'features/accounting/presentation/accounting_workspace_screen.dart';
import 'features/accounting/presentation/party_editor_dialog.dart';
import 'features/accounting/presentation/voucher_editor_dialog.dart';
import 'features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'features/my_wallet/presentation/providers/wallet_provider.dart';
import 'features/my_wallet/presentation/screens/my_wallet_screen.dart';
import 'features/my_purchases/presentation/screens/marketplace_screen.dart';
import 'features/my_sales/presentation/screens/my_sales_dashboard.dart';
import 'widgets/archive_toolbar.dart';
import 'widgets/mobile_app_navigation.dart';

import 'package:intl/date_symbol_data_local.dart';

part 'app_shell_part.dart';
part 'home_shell_actions_part.dart';
part 'home_shell_account_actions_part.dart';
part 'home_shell_web_review_part.dart';
part 'sidebar_part.dart';
part 'auth_part.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  ProductionConfig.validate();
  runApp(const WaselApp());
}

class WaselApp extends StatelessWidget {
  const WaselApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'واصل',
        theme: waselTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: AuthGate(),
        ),
      );
}
