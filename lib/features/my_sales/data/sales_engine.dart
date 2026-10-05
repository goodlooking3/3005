import 'package:sqflite/sqflite.dart';

import '../../../../data/accounting_repository.dart';
import '../../../../data/currency_policy.dart';
import '../../../../data/local_database.dart';
import '../../../../data/inventory_ledger_posting.dart';
import '../domain/inventory_item.dart';
import '../domain/inventory_movement.dart';

part 'sales_engine_inventory.dart';

class SalesEngine {
  final AccountingRepository accounting;
  final InventoryLedgerPosting inventoryLedger;
  SalesEngine({AccountingRepository? accounting})
      : accounting = accounting ?? AccountingRepository(),
        inventoryLedger = InventoryLedgerPosting(
          accounting ?? AccountingRepository(),
        );

  Future<int> completeSale({
    required SalesInvoice invoice,
    required int cashAccountId,
    required int salesAccountId,
  }) async {
    _validateInvoice(invoice);
    return LocalDatabase.instance.write((db) async {
      return db.transaction((txn) async {
        final parties = await txn.query(
          'parties',
          columns: ['id'],
          where: "id = ? AND type = 'customer' AND active = 1",
          whereArgs: [invoice.partyId],
          limit: 1,
        );
        if (parties.isEmpty) throw StateError('يجب اختيار عميل نشط للفاتورة');
        final costedInvoice = await _costInvoiceAtCurrentAverage(txn, invoice);
        final journalId = await accounting.insertSalesJournal(
          txn,
          number: invoice.number,
          description: 'مبيعات للعميل ${invoice.customerName}',
          amount: invoice.total,
          currency: invoice.currency,
          date: invoice.issuedAt,
          cashAccountId: cashAccountId,
          salesAccountId: salesAccountId,
          partyId: invoice.partyId,
          paymentAccount: invoice.paymentAccount,
          customerName: invoice.customerName,
        );
        final costJournalId = await inventoryLedger.postCostOfGoods(
          txn: txn,
          number: 'COGS-SALE-${invoice.number}',
          description: 'تكلفة البضاعة المباعة للفاتورة ${invoice.number}',
          amount: costedInvoice.costOfGoodsSold,
          currency: invoice.currency,
          date: invoice.issuedAt,
        );
        await _decrementStock(txn, costedInvoice.lines);
        await _saveInvoice(
          txn,
          costedInvoice,
          journalId,
          costJournalId: costJournalId,
        );
        await _recordMovements(
          txn,
          costedInvoice.lines,
          movementType: 'sale',
          referenceType: 'sales_invoice',
          referenceId: invoice.number,
          note: 'بيع الفاتورة ${invoice.number}',
        );
        return journalId;
      });
    });
  }

  Future<int> returnSale({
    required String invoiceNumber,
    int? cashAccountId,
    int? salesAccountId,
    Map<int, double>? quantitiesByLineId,
    DateTime? returnedAt,
  }) =>
      _reverseSale(
        invoiceNumber: invoiceNumber,
        cashAccountId: cashAccountId,
        salesAccountId: salesAccountId,
        returnedAt: returnedAt ?? DateTime.now(),
        referenceType: 'sales_return',
        movementType: 'return',
        numberPrefix: 'RET-',
        description: 'مرتجع الفاتورة $invoiceNumber',
        quantitiesByLineId: quantitiesByLineId,
      );

  Future<int> cancelSale({
    required String invoiceNumber,
    int? cashAccountId,
    int? salesAccountId,
    DateTime? canceledAt,
  }) =>
      _reverseSale(
        invoiceNumber: invoiceNumber,
        cashAccountId: cashAccountId,
        salesAccountId: salesAccountId,
        returnedAt: canceledAt ?? DateTime.now(),
        referenceType: 'sales_cancellation',
        movementType: 'cancellation',
        numberPrefix: 'CAN-',
        description: 'إلغاء الفاتورة $invoiceNumber',
        quantitiesByLineId: null,
      );

  Future<int> _reverseSale({
    required String invoiceNumber,
    int? cashAccountId,
    int? salesAccountId,
    required DateTime returnedAt,
    required String referenceType,
    required String movementType,
    required String numberPrefix,
    required String description,
    required Map<int, double>? quantitiesByLineId,
  }) =>
      LocalDatabase.instance.write((db) async {
        return db.transaction((txn) async {
          final invoices = await txn.query(
            'sales_invoices',
            where: 'number = ?',
            whereArgs: [invoiceNumber],
            limit: 1,
          );
          if (invoices.isEmpty) {
            throw StateError('الفاتورة غير موجودة: $invoiceNumber');
          }
          final invoice = invoices.single;
          final linkedJournalId = invoice['journal_entry_id'] as int?;
          var originalJournal = <Map<String, Object?>>[];
          if (linkedJournalId != null) {
            originalJournal = await txn.rawQuery('''
              SELECT v.debit_account_id, v.credit_account_id
              FROM journal_entries je
              JOIN vouchers v ON v.id = je.voucher_id
              WHERE je.id = ?
            ''', [linkedJournalId]);
          }
          if (originalJournal.isEmpty) {
            originalJournal = await txn.rawQuery('''
              SELECT v.debit_account_id, v.credit_account_id
              FROM journal_entries je
              JOIN vouchers v ON v.id = je.voucher_id
              WHERE je.number = ? AND je.source = 'sales'
              ORDER BY je.id DESC
              LIMIT 1
            ''', [invoiceNumber]);
          }
          final originalAccounts =
              originalJournal.isEmpty ? null : originalJournal.single;
          final resolvedCashAccountId =
              originalAccounts?['debit_account_id'] as int? ?? cashAccountId;
          final resolvedSalesAccountId =
              originalAccounts?['credit_account_id'] as int? ?? salesAccountId;
          if (resolvedCashAccountId == null || resolvedSalesAccountId == null) {
            throw StateError(
              'تعذر تحديد حسابات الفاتورة الأصلية؛ راجع قيد البيع قبل عكسها',
            );
          }
          if (invoice['status'] != 'posted' &&
              invoice['status'] != 'partially_returned') {
            throw StateError('لا يمكن عكس فاتورة حالتها ${invoice['status']}');
          }
          final lines = await txn.query(
            'sales_invoice_lines',
            where: 'invoice_number = ?',
            whereArgs: [invoiceNumber],
            orderBy: 'id ASC',
          );
          if (lines.isEmpty) throw StateError('الفاتورة بلا أصناف');
          final alreadyReturned = await txn.rawQuery('''
            SELECT invoice_line_id, COALESCE(SUM(quantity), 0) returned
            FROM sales_return_lines WHERE invoice_number = ? GROUP BY invoice_line_id
          ''', [invoiceNumber]);
          final returnedByLine = <int, double>{
            for (final row in alreadyReturned)
              row['invoice_line_id']! as int:
                  (row['returned']! as num).toDouble(),
          };
          final selected = <Map<String, Object?>>[];
          var amount = 0.0;
          for (final line in lines) {
            final lineId = line['id']! as int;
            final originalQuantity = (line['quantity']! as num).toDouble();
            final remaining = originalQuantity - (returnedByLine[lineId] ?? 0);
            final requested = quantitiesByLineId == null
                ? remaining
                : (quantitiesByLineId[lineId] ?? 0);
            if (!requested.isFinite ||
                requested < 0 ||
                requested > remaining + 0.000001) {
              throw StateError('كمية المرتجع تتجاوز المتبقي للسطر $lineId');
            }
            if (requested > 0) {
              selected.add({...line, 'return_quantity': requested});
              amount += requested * (line['unit_price']! as num).toDouble();
            }
          }
          if (amount <= 0) throw StateError('لا توجد كمية متاحة للمرتجع');
          final isFullReturn = lines.every((line) {
            final id = line['id']! as int;
            final original = (line['quantity']! as num).toDouble();
            final requested = quantitiesByLineId == null
                ? original - (returnedByLine[id] ?? 0)
                : (quantitiesByLineId[id] ?? 0);
            return requested >= original - (returnedByLine[id] ?? 0) - 0.000001;
          });
          final computedStatus =
              isFullReturn ? 'returned' : 'partially_returned';
          final reversalCount = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM sales_return_lines WHERE invoice_number = ?',
                [invoiceNumber],
              )) ??
              0;
          final reversalNumber =
              '$numberPrefix$invoiceNumber-${reversalCount + 1}';
          final partyId = invoice['party_id'] as int?;
          if (partyId == null) {
            throw StateError('اربط الفاتورة القديمة بعميل قبل إنشاء المرتجع');
          }
          final reversalJournalId = await accounting.insertSalesReversalJournal(
            txn,
            number: reversalNumber,
            description: description,
            amount: amount,
            currency: invoice['currency']! as String,
            date: returnedAt,
            cashAccountId: resolvedCashAccountId,
            salesAccountId: resolvedSalesAccountId,
            partyId: partyId,
            paymentAccount: invoice['payment_account']! as String,
            customerName: invoice['customer_name']! as String,
            source: referenceType,
          );
          final returnCost = selected.fold<double>(
            0,
            (sum, line) =>
                sum +
                (line['return_quantity']! as num).toDouble() *
                    (line['unit_cost']! as num).toDouble(),
          );
          if (returnCost > 0 && invoice['cost_journal_entry_id'] == null) {
            throw StateError(
              'لا يمكن إرجاع فاتورة قديمة بلا قيد تكلفة؛ يلزم تسوية محاسبية موثقة أولاً',
            );
          }
          final costJournalId = invoice['cost_journal_entry_id'] == null
              ? null
              : await inventoryLedger.postCostOfGoods(
                  txn: txn,
                  number: 'COGS-$reversalNumber',
                  description: 'عكس تكلفة البضاعة للمرتجع $invoiceNumber',
                  amount: returnCost,
                  currency: invoice['currency']! as String,
                  date: returnedAt,
                  reverse: true,
                );
          for (final line in selected) {
            final itemId = line['item_id']! as int;
            final quantity = (line['return_quantity']! as num).toDouble();
            final returnedUnitCost = (line['unit_cost']! as num).toDouble();
            final existingItems = await txn.query(
              'inventory_items',
              columns: ['quantity', 'cost_price', 'currency', 'active'],
              where: 'id = ?',
              whereArgs: [itemId],
              limit: 1,
            );
            if (existingItems.isEmpty || existingItems.single['active'] != 1) {
              throw StateError('صنف المرتجع غير موجود أو غير نشط');
            }
            final existingItem = existingItems.single;
            if ((existingItem['currency']! as String).trim().toUpperCase() !=
                (invoice['currency']! as String).trim().toUpperCase()) {
              throw StateError('عملة الصنف لا تطابق عملة المرتجع');
            }
            final oldQuantity = (existingItem['quantity']! as num).toDouble();
            final oldAverageCost =
                (existingItem['cost_price']! as num).toDouble();
            final nextQuantity = oldQuantity + quantity;
            final nextAverageCost =
                (oldQuantity * oldAverageCost + quantity * returnedUnitCost) /
                    nextQuantity;
            if (!oldQuantity.isFinite ||
                oldQuantity < 0 ||
                !oldAverageCost.isFinite ||
                oldAverageCost < 0 ||
                !nextQuantity.isFinite ||
                nextQuantity <= 0 ||
                !nextAverageCost.isFinite ||
                nextAverageCost < 0) {
              throw StateError('تعذر حساب متوسط تكلفة صنف المرتجع');
            }
            final changed = await txn.rawUpdate(
              'UPDATE inventory_items SET quantity = ?, cost_price = ? WHERE id = ? AND active = 1',
              [nextQuantity, nextAverageCost, itemId],
            );
            if (changed != 1) throw StateError('تعذر إعادة الصنف للمخزون');
            final item = await txn.query(
              'inventory_items',
              columns: ['quantity'],
              where: 'id = ?',
              whereArgs: [itemId],
              limit: 1,
            );
            await txn.insert('inventory_movements', {
              'item_id': itemId,
              'quantity': quantity,
              'movement_type': movementType,
              'reference_type': referenceType,
              'reference_id': invoiceNumber,
              'unit_cost': line['unit_cost'],
              'unit_price': line['unit_price'],
              'balance_after': item.single['quantity'],
              'created_at': returnedAt.toIso8601String(),
              'note': description,
            });
            await txn.insert('sales_return_lines', {
              'invoice_number': invoiceNumber,
              'invoice_line_id': line['id'],
              'quantity': quantity,
              'amount': quantity * (line['unit_price']! as num).toDouble(),
              'party_id': invoice['party_id'],
              'journal_entry_id': reversalJournalId,
              'cost_journal_entry_id': costJournalId,
              'created_at': returnedAt.toIso8601String(),
            });
          }
          await txn.update(
            'sales_invoices',
            {
              'status': computedStatus,
              'reversal_journal_entry_id': reversalJournalId,
              'reversed_at': returnedAt.toIso8601String(),
            },
            where: 'number = ?',
            whereArgs: [invoiceNumber],
          );
          return reversalJournalId;
        });
      });

  Future<List<InventoryMovement>> movements({int? itemId, int? limit}) async {
    final rows = await (await LocalDatabase.instance.database).query(
      'inventory_movements',
      where: itemId == null ? null : 'item_id = ?',
      whereArgs: itemId == null ? null : [itemId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(InventoryMovement.fromMap).toList(growable: false);
  }

  void _validateInvoice(SalesInvoice invoice) {
    if (invoice.number.trim().isEmpty ||
        invoice.partyId <= 0 ||
        invoice.customerName.trim().isEmpty ||
        invoice.paymentAccount.trim().isEmpty ||
        invoice.currency.trim().isEmpty ||
        invoice.lines.isEmpty ||
        invoice.lines.any((line) =>
            !line.quantity.isFinite ||
            !line.unitPrice.isFinite ||
            line.quantity <= 0 ||
            line.unitPrice < 0)) {
      throw ArgumentError('بيانات الفاتورة غير صالحة');
    }
  }

  Future<void> _decrementStock(
    Transaction txn,
    List<SalesInvoiceLine> lines,
  ) async {
    for (final line in lines) {
      final changed = await txn.rawUpdate(
        'UPDATE inventory_items SET quantity = quantity - ? WHERE id = ? AND quantity >= ?',
        [line.quantity, line.itemId, line.quantity],
      );
      if (changed != 1) throw StateError('تغير المخزون أثناء إتمام البيع');
    }
  }

  Future<void> _saveInvoice(
      Transaction txn, SalesInvoice invoice, int journalId,
      {int? costJournalId}) async {
    final valuation = await currencyPolicy.value(
      db: txn,
      amount: invoice.total,
      currency: invoice.currency,
      at: invoice.issuedAt,
    );
    await txn.insert('sales_invoices', {
      'number': invoice.number,
      'party_id': invoice.partyId,
      'customer_name': invoice.customerName,
      'payment_account': invoice.paymentAccount,
      'currency': invoice.currency,
      'base_total': valuation.baseAmount,
      'base_currency': valuation.baseCurrency,
      'exchange_rate': valuation.exchangeRate,
      'total': invoice.total,
      'cost_of_goods_sold': invoice.costOfGoodsSold,
      'profit': invoice.profit,
      'issued_at': invoice.issuedAt.toIso8601String(),
      'journal_entry_id': journalId,
      'cost_journal_entry_id': costJournalId,
      'status': invoice.status,
    });
    for (final line in invoice.lines) {
      await txn.insert('sales_invoice_lines', {
        'invoice_number': invoice.number,
        'item_id': line.itemId,
        'item_name': line.itemName,
        'quantity': line.quantity,
        'unit_price': line.unitPrice,
        'unit_cost': line.unitCost,
        'line_total': line.total,
      });
    }
  }

  Future<Map<String, double>> summary() async {
    final rows = await (await LocalDatabase.instance.database).rawQuery('''
      SELECT COALESCE(SUM(total - COALESCE((SELECT SUM(srl.amount) FROM sales_return_lines srl WHERE srl.invoice_number = si.number), 0)), 0) sales,
        COALESCE(SUM(cost_of_goods_sold - COALESCE((SELECT SUM(srl.quantity * sil.unit_cost) FROM sales_return_lines srl JOIN sales_invoice_lines sil ON sil.id = srl.invoice_line_id WHERE srl.invoice_number = si.number), 0)), 0) costs
      FROM sales_invoices si WHERE status IN ('posted', 'partially_returned')
    ''');
    final row = rows.single;
    return {
      'sales': (row['sales'] as num).toDouble(),
      'costs': (row['costs'] as num).toDouble(),
      'profit':
          (row['sales'] as num).toDouble() - (row['costs'] as num).toDouble(),
    };
  }
}
