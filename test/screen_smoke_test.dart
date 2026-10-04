import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasel/data/accounting_repository.dart';
import 'package:wasel/data/local_database.dart';
import 'package:wasel/features/accounting/application/accounting_reports_controller.dart';
import 'package:wasel/features/accounting/presentation/accounting_reports_screen.dart';
import 'package:wasel/features/accounting/presentation/accounting_workspace_screen.dart';
import 'package:wasel/features/connectors/application/connector_center_controller.dart';
import 'package:wasel/features/connectors/presentation/connector_center_screen.dart';
import 'package:wasel/features/my_purchases/presentation/screens/marketplace_screen.dart';
import 'package:wasel/features/my_sales/presentation/screens/inventory_movements_screen.dart';
import 'package:wasel/features/my_sales/presentation/screens/add_product_screen.dart';
import 'package:wasel/features/my_sales/presentation/screens/my_sales_dashboard.dart';
import 'package:wasel/features/my_sales/presentation/screens/sales_reversals_screen.dart';
import 'package:wasel/features/my_sales/presentation/screens/sales_invoice_screen.dart';
import 'package:wasel/features/my_wallet/data/repositories/wallet_repository_impl.dart';
import 'package:wasel/features/my_wallet/presentation/providers/wallet_provider.dart';
import 'package:wasel/features/my_wallet/presentation/screens/my_wallet_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() => LocalDatabase.instance.resetForTests());

  Future<void> renders(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('all data-backed feature screens render without exceptions',
      (tester) async {
    final repository = AccountingRepository();
    final connectorController = ConnectorCenterController(repository);
    final reportsController = AccountingReportsController(repository);
    final walletProvider = WalletProvider(WalletRepositoryImpl());

    await renders(tester, const MySalesDashboard());
    await renders(tester, const InventoryMovementsScreen());
    await renders(tester, const AddProductScreen());
    await renders(tester, const SalesReversalsScreen());
    await renders(tester, const SalesInvoiceScreen());
    await renders(tester, const MarketplaceScreen());
    await renders(
      tester,
      AccountingReportsScreen(controller: reportsController),
    );
    await renders(
      tester,
      AccountingWorkspaceScreen(repository: repository),
    );
    await renders(
      tester,
      ConnectorCenterScreen(
        controller: connectorController,
        onSetup: (_) {},
      ),
    );
    await renders(tester, MyWalletScreen(provider: walletProvider));

    connectorController.dispose();
    reportsController.dispose();
    walletProvider.dispose();
  });
}
