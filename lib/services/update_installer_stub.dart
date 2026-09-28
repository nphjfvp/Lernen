import 'package:http/http.dart' as http;

/// Außerhalb von Windows (und im Web) gibt es kein Installieren aus der App.
bool get canInstallUpdateInApp => false;

Future<bool> installUpdate(String setupUrl, {http.Client? client, void Function(double progress)? onProgress}) async =>
    false;
