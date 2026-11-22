import 'dart:io';

import 'package:nami_hub_client/nami_hub_client.dart';

Future<void> main() async {
  stdout.writeln('Enter the eight digits displayed on the Windows Hub:');
  final echo = stdin.hasTerminal && stdin.echoMode;
  if (echo) stdin.echoMode = false;
  late final String code;
  try {
    code = stdin.readLineSync()?.trim() ?? '';
  } finally {
    if (echo) stdin.echoMode = true;
  }
  final client = await HubLan.pair(code, 'Nami SDK');
  try {
    await for (final book in client.resources(type: 'book')) {
      stdout.writeln(book.name);
    }
  } finally {
    client.close();
  }
}
