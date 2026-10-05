class Vendor {
  final int? id;
  final String name;
  final String category;
  final String phone;
  final String? imageUrl;
  final bool approved;

  const Vendor({
    this.id,
    required this.name,
    required this.category,
    this.phone = '',
    this.imageUrl,
    this.approved = true,
  });

  factory Vendor.fromMap(Map<String, Object?> map) => Vendor(
        id: map['id'] as int?,
        name: map['name']! as String,
        category: map['category']! as String,
        phone: map['phone'] as String? ?? '',
        imageUrl: map['image_url'] as String?,
        approved: (map['approved'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'phone': phone,
        'image_url': imageUrl,
        'approved': approved ? 1 : 0,
      };
}

class MarketplaceProduct {
  final int? id;
  final int vendorId;
  final int? inventoryItemId;
  final String name;
  final String category;
  final String currency;
  final double price;
  final String? imageUrl;
  final bool available;

  const MarketplaceProduct({
    this.id,
    required this.vendorId,
    this.inventoryItemId,
    required this.name,
    required this.category,
    required this.price,
    this.currency = 'SAR',
    this.imageUrl,
    this.available = true,
  });

  factory MarketplaceProduct.fromMap(Map<String, Object?> map) =>
      MarketplaceProduct(
        id: map['id'] as int?,
        vendorId: map['vendor_id']! as int,
        inventoryItemId: map['inventory_item_id'] as int?,
        name: map['name']! as String,
        category: map['category']! as String,
        price: (map['price']! as num).toDouble(),
        currency: map['currency']! as String,
        imageUrl: map['image_url'] as String?,
        available: (map['available'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'vendor_id': vendorId,
        'inventory_item_id': inventoryItemId,
        'name': name,
        'category': category,
        'price': price,
        'currency': currency,
        'image_url': imageUrl,
        'available': available ? 1 : 0,
      };
}

class PurchaseAdjustments {
  final double shipping;
  final double discount;
  final double recoverableTax;
  final double nonRecoverableTax;
  const PurchaseAdjustments({
    this.shipping = 0,
    this.discount = 0,
    this.recoverableTax = 0,
    this.nonRecoverableTax = 0,
  });

  static PurchaseAdjustments? tryParse({
    required String shipping,
    required String discount,
    required String recoverableTax,
    required String nonRecoverableTax,
    required double subtotal,
  }) {
    double? parse(String value) =>
        value.trim().isEmpty ? 0 : double.tryParse(value.trim());

    final parsedShipping = parse(shipping);
    final parsedDiscount = parse(discount);
    final parsedRecoverableTax = parse(recoverableTax);
    final parsedNonRecoverableTax = parse(nonRecoverableTax);
    if (!subtotal.isFinite ||
        subtotal <= 0 ||
        parsedShipping == null ||
        parsedDiscount == null ||
        parsedRecoverableTax == null ||
        parsedNonRecoverableTax == null) {
      return null;
    }
    if ([
          parsedShipping,
          parsedDiscount,
          parsedRecoverableTax,
          parsedNonRecoverableTax,
        ].any((value) => !value.isFinite || value < 0) ||
        parsedDiscount > subtotal) {
      return null;
    }
    final result = PurchaseAdjustments(
      shipping: parsedShipping,
      discount: parsedDiscount,
      recoverableTax: parsedRecoverableTax,
      nonRecoverableTax: parsedNonRecoverableTax,
    );
    final total =
        subtotal - result.discount + result.shipping + result.totalTax;
    return total.isFinite && total > 0 ? result : null;
  }

  double get totalTax => recoverableTax + nonRecoverableTax;
  bool get isZero => shipping == 0 && discount == 0 && totalTax == 0;
}

class PurchaseCartLine {
  final MarketplaceProduct product;
  final int quantity;
  const PurchaseCartLine({required this.product, this.quantity = 1});
  double get total => product.price * quantity;
}

class PurchaseCart {
  final List<PurchaseCartLine> lines;
  final PurchaseAdjustments adjustments;
  const PurchaseCart(
    this.lines, {
    this.adjustments = const PurchaseAdjustments(),
  });
  double get subtotal => lines.fold(0, (sum, line) => sum + line.total);
  double get total =>
      subtotal -
      adjustments.discount +
      adjustments.shipping +
      adjustments.totalTax;
  String get currency => lines.isEmpty ? 'SAR' : lines.first.product.currency;
}

class VendorCategory {
  static const values = ['الكل', 'مطاعم', 'تجزئة', 'خدمات', 'تقنية', 'مياه'];
}

class VendorSeedData {
  static const vendors = [
    Vendor(name: 'متجر النخبة', category: 'تجزئة', phone: '+967 777 123 456'),
    Vendor(name: 'مياه الصفوة', category: 'مياه', phone: '+967 711 222 333'),
    Vendor(name: 'حلول التقنية', category: 'تقنية', phone: '+967 733 444 555'),
  ];
}

class ProductSeedData {
  static const products = [
    MarketplaceProduct(
      vendorId: 1,
      name: 'سلة مواد غذائية',
      category: 'تجزئة',
      price: 85,
    ),
    MarketplaceProduct(
      vendorId: 1,
      name: 'منظفات منزلية',
      category: 'تجزئة',
      price: 32,
    ),
    MarketplaceProduct(
      vendorId: 2,
      name: 'كرتون مياه',
      category: 'مياه',
      price: 18,
    ),
  ];
}

class PurchaseOrder {
  final int? id;
  final String number;
  final int? vendorId;
  final String vendorName;
  final String walletName;
  final double total;
  final double shipping;
  final double discount;
  final double recoverableTax;
  final double nonRecoverableTax;
  final String currency;
  final String status;
  final DateTime createdAt;

  const PurchaseOrder({
    this.id,
    required this.number,
    this.vendorId,
    required this.vendorName,
    required this.walletName,
    required this.total,
    this.shipping = 0,
    this.discount = 0,
    this.recoverableTax = 0,
    this.nonRecoverableTax = 0,
    required this.currency,
    this.status = 'paid',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'number': number,
        'vendor_id': vendorId,
        'vendor_name': vendorName,
        'wallet_name': walletName,
        'total': total,
        'shipping': shipping,
        'discount': discount,
        'recoverable_tax': recoverableTax,
        'nonrecoverable_tax': nonRecoverableTax,
        'currency': currency,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  factory PurchaseOrder.fromMap(Map<String, Object?> map) => PurchaseOrder(
        id: map['id'] as int?,
        number: map['number']! as String,
        vendorId: map['vendor_id'] as int?,
        vendorName: map['vendor_name']! as String,
        walletName: map['wallet_name']! as String,
        total: (map['total']! as num).toDouble(),
        shipping: (map['shipping'] as num? ?? 0).toDouble(),
        discount: (map['discount'] as num? ?? 0).toDouble(),
        recoverableTax: (map['recoverable_tax'] as num? ?? 0).toDouble(),
        nonRecoverableTax: (map['nonrecoverable_tax'] as num? ?? 0).toDouble(),
        currency: map['currency']! as String,
        status: map['status']! as String,
        createdAt: DateTime.parse(map['created_at']! as String),
      );
}

class MarketplaceReceipt {
  final PurchaseOrder order;
  final String? deepLink;
  const MarketplaceReceipt({required this.order, this.deepLink});
}
