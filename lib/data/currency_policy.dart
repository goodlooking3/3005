import 'package:sqflite/sqflite.dart';

import 'currency_repository.dart';

class CurrencyValuation {
  final String currency;
  final String baseCurrency;
  final double amount;
  final double baseAmount;
  final double exchangeRate;

  const CurrencyValuation({
    required this.currency,
    required this.baseCurrency,
    required this.amount,
    required this.baseAmount,
    required this.exchangeRate,
  });
}

class ForeignExchangeDifference {
  final double bookedBaseAmount;
  final double settledBaseAmount;
  final double difference;

  const ForeignExchangeDifference({
    required this.bookedBaseAmount,
    required this.settledBaseAmount,
    required this.difference,
  });

  bool get isGain => difference > 0.000001;
  bool get isLoss => difference < -0.000001;
}

/// Central currency policy for all transaction-scoped financial postings.
class CurrencyPolicy {
  const CurrencyPolicy();

  Future<String> requireBaseCurrency(DatabaseExecutor db) async {
    final rows = await db.query(
      'company_profile',
      columns: ['base_currency'],
      limit: 1,
    );
    final code = rows.isEmpty ? 'SAR' : rows.single['base_currency'] as String;
    await requireActive(db, code);
    return code;
  }

  Future<void> requireActive(DatabaseExecutor db, String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) throw ArgumentError('العملة مطلوبة');
    final rows = await db.query(
      'currencies',
      columns: ['code'],
      where: 'code = ? AND active = 1',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('العملة غير نشطة أو غير معروفة: $normalized');
    }
  }

  Future<CurrencyValuation> value({
    required DatabaseExecutor db,
    required double amount,
    required String currency,
    DateTime? at,
  }) async {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('المبلغ غير صالح');
    }
    final normalized = currency.trim().toUpperCase();
    await requireActive(db, normalized);
    final base = await requireBaseCurrency(db);
    final rate = normalized == base
        ? 1.0
        : await CurrencyRepository().requireRate(
            db: db,
            baseCurrency: normalized,
            quoteCurrency: base,
            at: at,
          );
    return CurrencyValuation(
      currency: normalized,
      baseCurrency: base,
      amount: amount,
      baseAmount: amount * rate,
      exchangeRate: rate,
    );
  }

  ForeignExchangeDifference difference({
    required double bookedBaseAmount,
    required double settledBaseAmount,
  }) {
    if (!bookedBaseAmount.isFinite || !settledBaseAmount.isFinite) {
      throw ArgumentError('قيمة التسوية غير صالحة');
    }
    return ForeignExchangeDifference(
      bookedBaseAmount: bookedBaseAmount,
      settledBaseAmount: settledBaseAmount,
      difference: settledBaseAmount - bookedBaseAmount,
    );
  }
}

const currencyPolicy = CurrencyPolicy();
