import '../../domain/vendor_model.dart';

abstract interface class RemoteMarketplaceApi {
  Future<Vendor> registerVendor(Vendor vendor);
  Future<List<MarketplaceProduct>> fetchCatalog(int vendorId);
}

class LocalMarketplaceApi implements RemoteMarketplaceApi {
  const LocalMarketplaceApi();

  @override
  Future<Vendor> registerVendor(Vendor vendor) async => vendor;

  @override
  Future<List<MarketplaceProduct>> fetchCatalog(int vendorId) async => const [];
}
