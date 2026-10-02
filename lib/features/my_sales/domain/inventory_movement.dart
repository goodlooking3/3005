class InventoryMovement {
  final int id;
  final int itemId;
  final double quantity;
  final String movementType;
  final String referenceType;
  final String referenceId;
  final double unitCost;
  final double unitPrice;
  final double balanceAfter;
  final DateTime createdAt;
  final String note;

  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.quantity,
    required this.movementType,
    required this.referenceType,
    required this.referenceId,
    required this.unitCost,
    required this.unitPrice,
    required this.balanceAfter,
    required this.createdAt,
    required this.note,
  });

  factory InventoryMovement.fromMap(Map<String, Object?> row) => InventoryMovement(
        id: row['id']! as int,
        itemId: row['item_id']! as int,
        quantity: (row['quantity']! as num).toDouble(),
        movementType: row['movement_type']! as String,
        referenceType: row['reference_type']! as String,
        referenceId: row['reference_id']! as String,
        unitCost: (row['unit_cost']! as num).toDouble(),
        unitPrice: (row['unit_price']! as num).toDouble(),
        balanceAfter: (row['balance_after']! as num).toDouble(),
        createdAt: DateTime.parse(row['created_at']! as String),
        note: row['note']! as String,
      );
}
