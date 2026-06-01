import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createApiHttpClient() {
  final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
  return IOClient(client);
}
