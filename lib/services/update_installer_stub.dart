import 'package:http/http.dart' as http;

import 'update_install_result.dart';

/// Im Web gibt es kein Installieren aus der App.
bool get canInstallUpdateInApp => false;

Future<UpdateInstallResult> installUpdate(
  String url, {
  int? buildNumber,
  http.Client? client,
  void Function(double progress)? onProgress,
}) async =>
    UpdateInstallResult.failed;
