import '../../../../data/accounting_repository.dart';
import '../../../../data/currency_policy.dart';
import '../../../../data/local_database.dart';
import '../../my_wallet/application/accounting_ledger_bridge.dart';
import '../../my_wallet/domain/models/wallet_transaction.dart';
import '../domain/vendor_model.dart';

class PurchaseEngine {
  final AccountingRepository accounting;
  final AccountingLedgerBridge ledger;

  PurchaseEngine._(AccountingRepository repository)
      : accounting = repository,
        ledger = AccountingLedgerBridge(repository);

  factory PurchaseEngine({AccountingRepository? repository}) =>
      PurchaseEngine._(repository ?? AccountingRepository());

  Future<MarketplaceReceipt> checkout({
    required Vendor vendor,
    required PurchaseCart cart,
    required String walletName,
    required String walletAccount,
  }) async {
    final adjustments = cart.adjustments;
    if (cart.lines.isEmpty || cart.subtotal <= 0 || cart.total <= 0) {
      throw ArgumentError('سلة المشتريات فارغة');
    }
    if ([
          adjustments.shipping,
          adjustments.discount,
          adjustments.recoverableTax,
          adjustments.nonRecoverableTax
        ].any((value) => !value.isFinite || value < 0) ||
        adjustments.discount > cart.subtotal) {
      throw ArgumentError('تسويات الشراء غير صالحة');
    }
    if (adjustments.totalTax > 0) {
      throw StateError(
        'الضرائب معطلة حتى تهيئة سياسة ضريبية خاصة ببلد المنشأة',
      );
    }
    if (cart.lines.any((line) =>
        line.quantity <= 0 ||
        !line.product.price.isFinite ||
        line.product.price < 0)) {
      throw ArgumentError('كمية أو تكلفة منتج الشراء غير صالحة');
    }
    if (cart.lines.any((line) => !line.product.available)) {
      throw StateError('يوجد منتج غير متوفر في السلة');
    }
    final currency = cart.currency.trim().toUpperCase();
    if (cart.lines.any(
        (line) => line.product.currency.trim().toUpperCase() != currency)) {
      throw StateError(
          'لا يمكن جمع منتجات بعملات مختلفة في طلب واحد دون تحويل صريح');
    }
    final number = 'PUR-${DateTime.now().millisecondsSinceEpoch}';
    final order = PurchaseOrder(
      number: number,
      partyId: vendor.partyId,
      vendorId: vendor.id,
      vendorName: vendor.name,
      walletName: walletName,
      total: cart.total,
      shipping: adjustments.shipping,
      discount: adjustments.discount,
      recoverableTax: adjustments.recoverableTax,
      nonRecoverableTax: adjustments.nonRecoverableTax,
      currency: currency,
      createdAt: DateTime.now(),
    );
    await LocalDatabase.instance.write((db) async {
      await db.transaction((txn) async {
        final suppliers = await txn.query(
          'parties',
          columns: ['id'],
          where: "id = ? AND type = 'supplier' AND active = 1",
          whereArgs: [vendor.partyId],
          limit: 1,
        );
        if (suppliers.isEmpty) {
          throw StateError('اختر مورداً نشطاً من دفتر الأطراف قبل الشراء');
        }
        final valuation = await currencyPolicy.value(
          db: txn,
          amount: cart.total,
          currency: currency,
          at: order.createdAt,
        );
        final posted = await ledger.postInTransaction(
          txn,
          WalletTransaction(
            fromAccount: walletAccount,
            toAccount: vendor.name,
            type: WalletTransactionType.purchase,
            amount: cart.total,
            currency: currency,
            note: 'شراء من ${vendor.name} — $number',
            date: order.createdAt,
            reference: number,
            relatedModule: 'my_purchases',
            relatedEntityId: number,
          ),
          capitalizeAsInventory: true,
        );
        await txn.insert('wallet_transactions', posted.toMap());
        await txn.insert(
          'purchase_orders',
          order.toMap()
            ..['base_total'] = valuation.baseAmount
            ..['base_currency'] = valuation.baseCurrency
            ..['exchange_rate'] = valuation.exchangeRate
            ..['journal_entry_id'] = posted.journalEntryId,
        );
        for (final line in cart.lines) {
          final lineShare = line.total / cart.subtotal;
          final landedLineCost = line.total -
              (adjustments.discount * lineShare) +
              (adjustments.shipping * lineShare) +
              (adjustments.nonRecoverableTax * lineShare);
          final landedUnitCost = landedLineCost / line.quantity;
          final inventoryItemId =
              await _receiveIntoInventory(txn, line, number, landedUnitCost);
          await txn.insert('purchase_order_lines', {
            'order_number': number,
            'product_id': line.product.id,
            'product_name': line.product.name,
            'quantity': line.quantity,
            'unit_price': line.product.price,
            'line_total': line.total,
            'unit_cost': landedUnitCost,
          });
          if (line.product.id != null) {
            await txn.update(
              'marketplace_products',
              {'inventory_item_id': inventoryItemId},
              where: 'id = ?',
              whereArgs: [line.product.id],
            );
          }
        }
      });
    });
    return MarketplaceReceipt(order: order);
  }

  Future<int> _receiveIntoInventory(
    dynamic db,
    PurchaseCartLine line,
    String reference,
    double unitCost,
  ) async {
    final currency = line.product.currency.trim().toUpperCase();
    var existing = <Map<String, Object?>>[];
    if (line.product.inventoryItemId != null) {
      final inventoryItemId = line.product.inventoryItemId!;
      existing = await db.query(
        'inventory_items',
        where: 'id = ? AND active = 1',
        whereArgs: [inventoryItemId],
        limit: 1,
      );
      if (existing.isEmpty) {
        throw StateError(
            'صنف المخزون المرتبط بمنتج الشراء غير موجود أو غير نشط');
      }
    } else {
      existing = await db.query(
        'inventory_items',
        where: 'name = ? AND currency = ? AND active = 1',
        whereArgs: [line.product.name, currency],
        limit: 1,
      );
    }
    final itemId = existing.isEmpty
        ? await db.insert('inventory_items', {
            'name': line.product.name,
            'sku': 'PUR-${line.product.id ?? line.product.name.hashCode}',
            'cost_price': unitCost,
            'sale_price': line.product.price,
            'quantity': 0,
            'low_stock_threshold': 5,
            'currency': currency,
            'active': 1,
          })
        : existing.single['id'] as int;
    final itemRows = existing.isEmpty
        ? await db.query(
            'inventory_items',
            where: 'id = ? AND active = 1',
            whereArgs: [itemId],
            limit: 1,
          )
        : existing;
    final item = itemRows.single;
    if ((item['currency']! as String).trim().toUpperCase() != currency) {
      throw StateError('عملة صنف المخزون لا تطابق عملة الشراء');
    }
    final oldQuantity = (item['quantity']! as num).toDouble();
    final oldCost = (item['cost_price']! as num).toDouble();
    final nextQuantity = oldQuantity + line.quantity;
    if (!oldQuantity.isFinite ||
        !oldCost.isFinite ||
        !nextQuantity.isFinite ||
        nextQuantity <= 0 ||
        !unitCost.isFinite ||
        unitCost < 0) {
      throw StateError('تعذر حساب متوسط تكلفة صنف ${line.product.name}');
    }
    final weightedAverage =
        (oldQuantity * oldCost + line.quantity * unitCost) / nextQuantity;
    if (!weightedAverage.isFinite || weightedAverage < 0) {
      throw StateError('متوسط تكلفة صنف ${line.product.name} غير صالح');
    }
    final changed = await db.rawUpdate(
      'UPDATE inventory_items SET quantity = ?, cost_price = ? WHERE id = ? AND active = 1',
      [nextQuantity, weightedAverage, itemId],
    );
    if (changed != 1) throw StateError('تعذر تحديث مخزون ${line.product.name}');
    final current = await db.query(
      'inventory_items',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    await db.insert('inventory_movements', {
      'item_id': itemId,
      'quantity': line.quantity,
      'movement_type': 'purchase_receipt',
      'reference_type': 'purchase_order',
      'reference_id': reference,
      'unit_cost': unitCost,
      'unit_price': line.product.price,
      'balance_after': current.single['quantity'],
      'created_at': DateTime.now().toIso8601String(),
      'note': 'استلام شراء ${line.product.name}',
    });
    return itemId;
  }

  Future<List<PurchaseOrder>> orders() async {
    final rows = await (await LocalDatabase.instance.database).query(
      'purchase_orders',
      orderBy: 'created_at DESC',
    );
    return rows.map(PurchaseOrder.fromMap).toList(growable: false);
  }
}
