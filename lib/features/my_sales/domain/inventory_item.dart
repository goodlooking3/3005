class InventoryItem {
  final int? id;
  final String name;
  final String sku;
  final String? imagePath;
  final double costPrice;
  final double salePrice;
  final double quantity;
  final double lowStockThreshold;
  final String currency;
  final bool active;

  const InventoryItem({
    this.id,
    required this.name,
    this.sku = '',
    this.imagePath,
    required this.costPrice,
    required this.salePrice,
    required this.quantity,
    this.lowStockThreshold = 5,
    this.currency = 'SAR',
    this.active = true,
  });

  bool get lowStock => quantity <= lowStockThreshold;
  double get unitProfit => salePrice - costPrice;

  factory InventoryItem.fromMap(Map<String, Object?> map) => InventoryItem(
        id: map['id'] as int?,
        name: map['name']! as String,
        sku: map['sku'] as String? ?? '',
        imagePath: map['image_path'] as String?,
        costPrice: (map['cost_price']! as num).toDouble(),
        salePrice: (map['sale_price']! as num).toDouble(),
        quantity: (map['quantity']! as num).toDouble(),
        lowStockThreshold: (map['low_stock_threshold'] as num? ?? 5).toDouble(),
        currency: map['currency'] as String? ?? 'SAR',
        active: (map['active'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'sku': sku,
        'image_path': imagePath,
        'cost_price': costPrice,
        'sale_price': salePrice,
        'quantity': quantity,
        'low_stock_threshold': lowStockThreshold,
        'currency': currency,
        'active': active ? 1 : 0,
      };
}

class SalesInvoiceLine {
  final int itemId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double unitCost;
  const SalesInvoiceLine({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
  });
  double get total => quantity * unitPrice;
  double get costTotal => quantity * unitCost;
  double get profit => total - costTotal;
}

class SalesInvoice {
  final int? id;
  final int partyId;
  final String number;
  final String customerName;
  final String paymentAccount;
  final String currency;
  final DateTime issuedAt;
  final List<SalesInvoiceLine> lines;
  final String status;

  const SalesInvoice({
    this.id,
    required this.partyId,
    required this.number,
    required this.customerName,
    required this.paymentAccount,
    required this.currency,
    required this.issuedAt,
    required this.lines,
    this.status = 'posted',
  });

  double get total => lines.fold(0, (sum, line) => sum + line.total);
  double get costOfGoodsSold =>
      lines.fold(0, (sum, line) => sum + line.costTotal);
  double get profit => total - costOfGoodsSold;
}
