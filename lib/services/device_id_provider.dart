import 'device_id_provider_stub.dart'
    if (dart.library.io) 'device_id_provider_io.dart' as platform;

Future<({String machineGuid, String? systemUuid})>
    readWindowsMachineIdentifiers() => platform.readWindowsMachineIdentifiers();
