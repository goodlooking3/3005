part of '../accounting_repository.dart';

const _cashFlowCategories = {'unclassified', 'operating', 'investing', 'financing'};
const _positionClasses = {'unclassified', 'current', 'non_current'};
const _positionKinds = {
  AccountKind.asset, AccountKind.liability, AccountKind.cash,
  AccountKind.bank, AccountKind.customer, AccountKind.supplier,
};

extension AccountingRepositoryAccounts on AccountingRepository {
  Future<List<Voucher>> vouchers() async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query('vouchers', orderBy: 'date DESC');
    return Future.wait(rows.map((row) async {
      final lineRows = await db.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      return Voucher(
        id: row['id'] as int?,
        number: row['number']! as String,
        type: VoucherType.values.firstWhere(
          (v) => v.name == row['type'],
          orElse: () => VoucherType.journal,
        ),
        description: row['description']! as String,
        amount: (row['amount']! as num).toDouble(),
        currency: row['currency']! as String,
        date: DateTime.parse(row['date']! as String),
        recipientName: row['recipient_name'] as String?,
        payerName: row['payer_name'] as String?,
        debitAccountId: row['debit_account_id'] as int?,
        creditAccountId: row['credit_account_id'] as int?,
        lines: lineRows
            .map((line) => VoucherLine(
                  accountId: line['account_id'] as int?,
                  partyId: line['party_id'] as int?,
                  accountName: line['account_name']! as String,
                  debit: (line['debit']! as num).toDouble(),
                  credit: (line['credit']! as num).toDouble(),
                  currency: line['currency'] as String?,
                  partyName: line['party_name'] as String?,
                ))
            .toList(growable: false),
      );
    }));
  }

  Future<int> upsertAccount(Account account) => LocalDatabase.instance.write(
        (db) async {
          await AccountingAuthorization.instance
              .require(db, AccountingPermission.manageAccounts);
          final code = account.code.trim();
          if (code.isEmpty || account.name.trim().isEmpty) {
            throw ArgumentError('رقم واسم الحساب مطلوبان');
          }
          if (!_cashFlowCategories.contains(account.cashFlowCategory)) {
            throw ArgumentError('تصنيف التدفق النقدي غير صالح');
          }
          if (!_positionClasses.contains(account.positionClass)) {
            throw ArgumentError('تصنيف المركز المالي غير صالح');
          }
          if (account.positionClass != 'unclassified' &&
              !_positionKinds.contains(account.kind)) {
            throw ArgumentError('تصنيف الجاري يخص الأصول والالتزامات فقط');
          }
          final duplicate = await db.query('accounts',
              columns: ['id'], where: 'code = ?', whereArgs: [code], limit: 1);
          if (duplicate.isNotEmpty && duplicate.first['id'] != account.id) {
            throw StateError('رقم الحساب مستخدم مسبقًا');
          }
          if (account.parentId != null) {
            if (account.parentId == account.id) {
              throw StateError('لا يمكن جعل الحساب أبًا لنفسه');
            }
            final parent = await db.query(
              'accounts',
              columns: ['id'],
              where: 'id = ? AND active = 1',
              whereArgs: [account.parentId],
              limit: 1,
            );
            if (parent.isEmpty) {
              throw StateError('الحساب الأب غير موجود أو متوقف');
            }
            await _ensureNoAccountCycle(
              db,
              accountId: account.id,
              parentId: account.parentId!,
            );
          }
          final primaryCurrency = account.currency.trim().toUpperCase();
          if (primaryCurrency.isEmpty) {
            throw ArgumentError('عملة الحساب مطلوبة');
          }
          final supported = <String>{
            primaryCurrency,
            ...account.supportedCurrencies
                .map((value) => value.trim().toUpperCase())
                .where((value) => value.isNotEmpty),
          };
          for (final currency in supported) {
            final active = await db.query(
              'currencies',
              columns: ['code'],
              where: 'code = ? AND active = 1',
              whereArgs: [currency],
              limit: 1,
            );
            if (active.isEmpty) {
              throw StateError('العملة $currency غير نشطة أو غير معروفة');
            }
          }
          final values = {
            'code': code,
            'name': account.name.trim(),
            'name_ar': account.nameAr?.trim().isEmpty == true
                ? null
                : account.nameAr?.trim(),
            'name_en': account.nameEn?.trim().isEmpty == true
                ? null
                : account.nameEn?.trim(),
            'type': account.type,
            'kind': account.kind.name,
            'parent_id': account.parentId,
            'is_group': account.isGroup ? 1 : 0,
            'currency': primaryCurrency,
            'opening_balance': account.balance,
            'active': account.active ? 1 : 0,
            'cash_flow_category': account.cashFlowCategory,
            'position_class': account.positionClass,
          };
          final insertedId = account.id == null
              ? await db.insert('accounts', values)
              : account.id!;
          if (account.id != null) {
            final updated = await db.update(
              'accounts',
              values,
              where: 'id = ?',
              whereArgs: [account.id],
            );
            if (updated == 0) throw StateError('الحساب غير موجود');
          }
          await db.delete(
            'account_currencies',
            where: 'account_id = ?',
            whereArgs: [insertedId],
          );
          for (final currency in supported) {
            await db.insert('account_currencies', {
              'account_id': insertedId,
              'currency': currency,
              'is_primary': currency == primaryCurrency ? 1 : 0,
            });
          }
          return insertedId;
        },
      );

  Future<void> _ensureNoAccountCycle(
    Database db, {
    required int? accountId,
    required int parentId,
  }) async {
    if (accountId == null) return;
    final visited = <int>{accountId};
    var current = parentId;
    while (true) {
      if (!visited.add(current)) {
        throw StateError('لا يمكن إنشاء دورة في شجرة الحسابات');
      }
      final rows = await db.query(
        'accounts',
        columns: ['parent_id'],
        where: 'id = ?',
        whereArgs: [current],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['parent_id'] == null) return;
      current = rows.single['parent_id']! as int;
    }
  }

  Future<List<Account>> accounts({bool includeInactive = false}) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query(
      'accounts',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'code ASC',
    );
    final accounts = rows
        .map(
          (r) => Account(
            id: r['id'] as int,
            code: r['code']! as String,
            name: r['name']! as String,
            nameAr: r['name_ar'] as String?,
            nameEn: r['name_en'] as String?,
            type: r['type']! as String,
            kind: AccountKind.values.firstWhere(
              (k) => k.name == r['kind'],
              orElse: () => AccountKind.asset,
            ),
            parentId: r['parent_id'] as int?,
            isGroup: (r['is_group'] as int) == 1,
            currency: r['currency']! as String,
            balance: (r['opening_balance']! as num).toDouble(),
            active: (r['active'] as int? ?? 1) == 1,
            cashFlowCategory:
                r['cash_flow_category'] as String? ?? 'unclassified',
            positionClass: r['position_class'] as String? ?? 'unclassified',
          ),
        )
        .toList();
    for (var index = 0; index < accounts.length; index++) {
      final currencies = await _accountCurrencies(accounts[index].id!);
      if (currencies.isNotEmpty) {
        accounts[index] = accounts[index].withCurrencies(currencies);
      }
    }
    return accounts;
  }

  Future<List<String>> _accountCurrencies(int accountId) async {
    final rows = await (await _db).query(
      'account_currencies',
      columns: ['currency'],
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'is_primary DESC, currency ASC',
    );
    return rows
        .map((row) => row['currency']! as String)
        .toList(growable: false);
  }

  Future<int?> accountIdByName(String name) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<Account?> accountByCode(String code) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query(
      'accounts',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final account = _accountFromRow(rows.first);
    final currencies = await _accountCurrencies(account.id!);
    return currencies.isEmpty ? account : account.withCurrencies(currencies);
  }

  Future<int> ensureAccount(Account account) async {
    final existing = await accountByCode(account.code);
    if (existing?.id != null) return existing!.id!;
    return upsertAccount(account);
  }

  Account _accountFromRow(Map<String, Object?> row) => Account(
        id: row['id'] as int,
        code: row['code']! as String,
        name: row['name']! as String,
        nameAr: row['name_ar'] as String?,
        nameEn: row['name_en'] as String?,
        type: row['type']! as String,
        kind: AccountKind.values.firstWhere((kind) => kind.name == row['kind'],
            orElse: () => AccountKind.asset),
        parentId: row['parent_id'] as int?,
        isGroup: (row['is_group'] as int) == 1,
        currency: row['currency']! as String,
        balance: (row['opening_balance']! as num).toDouble(),
        active: (row['active'] as int? ?? 1) == 1,
        cashFlowCategory:
            row['cash_flow_category'] as String? ?? 'unclassified',
        positionClass: row['position_class'] as String? ?? 'unclassified',
      );

  Future<void> setAccountActive(int id, bool active) =>
      LocalDatabase.instance.write((db) async {
        await AccountingAuthorization.instance
            .require(db, AccountingPermission.manageAccounts);
        if (!active) {
          final children = await db.query('accounts',
              columns: ['id'],
              where: 'parent_id = ? AND active = 1',
              whereArgs: [id],
              limit: 1);
          if (children.isNotEmpty) {
            throw StateError('لا يمكن إيقاف حساب له حسابات فرعية نشطة');
          }
        }
        await db.update('accounts', {'active': active ? 1 : 0},
            where: 'id = ?', whereArgs: [id]);
      });

  Future<int> insertParty(Party party) => upsertParty(party);

  Future<int> upsertParty(Party party) => LocalDatabase.instance.write(
        (db) async {
          await AccountingAuthorization.instance
              .require(db, AccountingPermission.manageParties);
          final name = party.name.trim();
          final type = party.type.trim().toLowerCase();
          final currency = party.currency.trim().toUpperCase();
          if (name.length < 2 || !{'customer', 'supplier'}.contains(type)) {
            throw ArgumentError('اسم الطرف ونوعه مطلوبان');
          }
          final currencyRows = await db.query(
            'currencies',
            columns: ['code'],
            where: 'code = ? AND active = 1',
            whereArgs: [currency],
            limit: 1,
          );
          if (currencyRows.isEmpty) {
            throw StateError('العملة المختارة غير نشطة أو غير معروفة');
          }
          if (party.accountId == null) {
            throw StateError('يجب ربط الطرف بحساب تحليلي قبل الحفظ');
          }
          final accountRows = await db.query(
            'accounts',
            columns: ['kind', 'active', 'is_group'],
            where: 'id = ?',
            whereArgs: [party.accountId],
            limit: 1,
          );
          final account = accountRows.isEmpty ? null : accountRows.single;
          if (account == null ||
              (account['active'] as int? ?? 0) != 1 ||
              (account['is_group'] as int? ?? 1) == 1 ||
              account['kind'] != type) {
            throw StateError('اختر حسابًا تحليليًا نشطًا من نفس نوع الطرف');
          }
          final duplicate = await db.query(
            'parties',
            columns: ['id'],
            where: 'name = ? AND type = ? AND id != ?',
            whereArgs: [name, type, party.id ?? -1],
            limit: 1,
          );
          if (duplicate.isNotEmpty) {
            throw StateError('يوجد طرف بالاسم والنوع نفسيهما');
          }
          final values = {
            'account_id': party.accountId,
            'name': name,
            'name_ar': party.nameAr?.trim().isEmpty == true
                ? null
                : party.nameAr?.trim(),
            'name_en': party.nameEn?.trim().isEmpty == true
                ? null
                : party.nameEn?.trim(),
            'type': type,
            'phone': party.phone?.trim().isEmpty == true
                ? null
                : party.phone?.trim(),
            'email': party.email?.trim().isEmpty == true
                ? null
                : party.email?.trim(),
            'address': party.address?.trim().isEmpty == true
                ? null
                : party.address?.trim(),
            'credit_limit': party.creditLimit,
            'currency': currency,
            'active': party.active ? 1 : 0,
          };
          if (party.id == null) return db.insert('parties', values);
          final updated = await db.update(
            'parties',
            values,
            where: 'id = ?',
            whereArgs: [party.id],
          );
          if (updated == 0) throw StateError('الطرف غير موجود');
          return party.id!;
        },
      );
  Future<List<Party>> parties({String? type}) async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query(
      'parties',
      where: type == null ? 'active = 1' : 'active = 1 AND type = ?',
      whereArgs: type == null ? null : [type],
      orderBy: 'name ASC',
    );
    return rows
        .map(
          (r) => Party(
            id: r['id'] as int,
            accountId: r['account_id'] as int?,
            name: r['name']! as String,
            nameAr: r['name_ar'] as String?,
            nameEn: r['name_en'] as String?,
            type: r['type']! as String,
            phone: r['phone'] as String?,
            email: r['email'] as String?,
            address: r['address'] as String?,
            creditLimit: (r['credit_limit'] as num? ?? 0).toDouble(),
            currency: r['currency']! as String,
            active: (r['active'] as int? ?? 1) == 1,
          ),
        )
        .toList();
  }

  Future<void> saveCompany(CompanyProfile profile) =>
      LocalDatabase.instance.write((db) async {
        await db.transaction((txn) async {
          await AccountingAuthorization.instance
              .require(txn, AccountingPermission.manageCompanySettings);
          final current = await txn.query(
            'company_profile',
            columns: ['base_currency'],
            where: 'id = ?',
            whereArgs: [1],
            limit: 1,
          );
          final currentCurrency = current.isEmpty
              ? 'SAR'
              : (current.single['base_currency'] as String).toUpperCase();
          final normalizedCurrency = profile.baseCurrency.trim().toUpperCase();
          final activeCurrency = await txn.query(
            'currencies',
            columns: ['code'],
            where: 'code = ? AND active = 1',
            whereArgs: [normalizedCurrency],
            limit: 1,
          );
          if (activeCurrency.isEmpty && currentCurrency != normalizedCurrency) {
            throw StateError('اختر عملة محلية نشطة من قائمة العملات');
          }
          if (currentCurrency != normalizedCurrency) {
            final posted = Sqflite.firstIntValue(
                  await txn.rawQuery('SELECT COUNT(*) FROM journal_entries'),
                ) ??
                0;
            if (posted > 0) {
              throw StateError(
                'لا يمكن تغيير العملة الأساسية بعد ترحيل قيود؛ يلزم إجراء تقييم وتحويل افتتاحي معتمد',
              );
            }
          }
          await txn.insert(
              'company_profile',
              {
                'id': 1,
                'name': profile.name,
                'legal_name': profile.legalName,
                'tax_number': profile.taxNumber,
                'phone': profile.phone,
                'email': profile.email,
                'address': profile.address,
                'base_currency': normalizedCurrency,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        });
      });
  Future<CompanyProfile?> company() async {
    final db = await _db;
    await AccountingAuthorization.instance
        .requireRead(db, AccountingPermission.viewLedger);
    final rows = await db.query('company_profile', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CompanyProfile(
      name: r['name']! as String,
      legalName: r['legal_name'] as String?,
      taxNumber: r['tax_number'] as String?,
      phone: r['phone'] as String?,
      email: r['email'] as String?,
      address: r['address'] as String?,
      baseCurrency: r['base_currency']! as String,
    );
  }
}
