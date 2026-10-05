part of 'sales_engine.dart';

extension _SalesEngineInventoryOperations on SalesEngine {
  Future<SalesInvoice> _costInvoiceAtCurrentAverage(
    Transaction txn,
    SalesInvoice invoice,
  ) async {
    final costedLines = <SalesInvoiceLine>[];
    for (final line in invoice.lines) {
      final rows = await txn.query(
        'inventory_items',
        columns: ['quantity', 'cost_price', 'active', 'currency'],
        where: 'id = ?',
        whereArgs: [line.itemId],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['active'] != 1) {
        throw StateError('الصنف غير موجود أو غير نشط: ${line.itemName}');
      }
      if ((rows.single['currency'] as String).trim().toUpperCase() !=
          invoice.currency.trim().toUpperCase()) {
        throw StateError('عملة الصنف لا تطابق عملة الفاتورة: ${line.itemName}');
      }
      if ((rows.single['quantity'] as num).toDouble() < line.quantity) {
        throw StateError('المخزون غير كافٍ للمنتج ${line.itemName}');
      }
      final averageCost = (rows.single['cost_price']! as num).toDouble();
      if (!averageCost.isFinite || averageCost < 0) {
        throw StateError('متوسط تكلفة الصنف غير صالح: ${line.itemName}');
      }
      costedLines.add(SalesInvoiceLine(
        itemId: line.itemId,
        itemName: line.itemName,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        unitCost: averageCost,
      ));
    }
    return SalesInvoice(
      id: invoice.id,
      partyId: invoice.partyId,
      number: invoice.number,
      customerName: invoice.customerName,
      paymentAccount: invoice.paymentAccount,
      currency: invoice.currency,
      issuedAt: invoice.issuedAt,
      lines: costedLines,
      status: invoice.status,
    );
  }

  Future<void> _recordMovements(
    Transaction txn,
    List<SalesInvoiceLine> lines, {
    required String movementType,
    required String referenceType,
    required String referenceId,
    required String note,
  }) async {
    for (final line in lines) {
      final item = await txn.query(
        'inventory_items',
        columns: ['quantity'],
        where: 'id = ?',
        whereArgs: [line.itemId],
        limit: 1,
      );
      await txn.insert('inventory_movements', {
        'item_id': line.itemId,
        'quantity': -line.quantity,
        'movement_type': movementType,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'unit_cost': line.unitCost,
        'unit_price': line.unitPrice,
        'balance_after': item.single['quantity'],
        'created_at': DateTime.now().toIso8601String(),
        'note': note,
      });
    }
  }
}
