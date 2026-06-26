import 'sediment/service_io.dart'
    if (dart.library.js_interop) 'sediment/service_web.dart';
import 'sediment/service.dart';

export 'sediment/contract.dart';
export 'sediment/service.dart';

SedimentService createSedimentService() => createPlatformSedimentService();
