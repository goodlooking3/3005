import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

class CurrencyOption {
  final String code;
  final String name;
  final String symbol;
  const CurrencyOption(
      {required this.code, required this.name, required this.symbol});

  factory CurrencyOption.fromMap(Map<String, Object?> row) => CurrencyOption(
        code: row['code']! as String,
        name: row['name']! as String,
        symbol: row['symbol']! as String,
      );
}

class ExchangeRate {
  final String baseCurrency;
  final String quoteCurrency;
  final double rate;
  final DateTime effectiveAt;
  final String source;
  const ExchangeRate({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.rate,
    required this.effectiveAt,
    this.source = 'manual',
  });
}

class CurrencyRepository {
  Future<List<CurrencyOption>> activeCurrencies() async {
    final rows = await (await LocalDatabase.instance.database).query(
      'currencies',
      where: 'active = 1',
      orderBy: 'code ASC',
    );
    return rows.map(CurrencyOption.fromMap).toList(growable: false);
  }

  Future<void> saveRate(ExchangeRate rate) async {
    if (rate.baseCurrency == rate.quoteCurrency ||
        !rate.rate.isFinite ||
        rate.rate <= 0) {
      throw ArgumentError('سعر الصرف غير صالح');
    }
    await LocalDatabase.instance.write((db) async {
      await db.insert(
        'exchange_rates',
        {
          'base_currency': rate.baseCurrency,
          'quote_currency': rate.quoteCurrency,
          'rate': rate.rate,
          'effective_at': rate.effectiveAt.toIso8601String(),
          'source': rate.source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<double> requireRate({
    DatabaseExecutor? db,
    required String baseCurrency,
    required String quoteCurrency,
    DateTime? at,
  }) async {
    if (baseCurrency == quoteCurrency) return 1;
    final executor = db ?? await LocalDatabase.instance.database;
    final rows = await executor.query(
      'exchange_rates',
      where: 'base_currency = ? AND quote_currency = ? AND effective_at <= ?',
      whereArgs: [
        baseCurrency,
        quoteCurrency,
        (at ?? DateTime.now()).toIso8601String(),
      ],
      orderBy: 'effective_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('لا يوجد سعر صرف $baseCurrency إلى $quoteCurrency');
    }
    return (rows.single['rate']! as num).toDouble();
  }

  Future<double> convert({
    required double amount,
    required String from,
    required String to,
    DateTime? at,
  }) async {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('المبلغ غير صالح');
    }
    return amount *
        await requireRate(
          baseCurrency: from,
          quoteCurrency: to,
          at: at,
        );
  }
}
