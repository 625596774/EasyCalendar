import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBootstrapResult {
  const SupabaseBootstrapResult._({
    required this.isConfigured,
    this.client,
    this.message,
  });

  factory SupabaseBootstrapResult.disabled(String message) {
    return SupabaseBootstrapResult._(isConfigured: false, message: message);
  }

  factory SupabaseBootstrapResult.configured(SupabaseClient client) {
    return SupabaseBootstrapResult._(isConfigured: true, client: client);
  }

  final bool isConfigured;
  final SupabaseClient? client;
  final String? message;
}

Future<SupabaseBootstrapResult> initializeSupabaseFromDotEnv({
  String fileName = '.env',
}) async {
  try {
    final envFile = await _findDotEnvFile(fileName);
    if (envFile == null) {
      return SupabaseBootstrapResult.disabled('当前未配置云同步，本地模式可正常使用。');
    }

    final raw = await envFile.readAsString();
    dotenv.loadFromString(envString: raw, isOptional: true);

    final url = dotenv.maybeGet('SUPABASE_URL')?.trim();
    final key = dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY')?.trim();
    if (!_looksLikeSupabaseUrl(url) || key == null || key.isEmpty) {
      return SupabaseBootstrapResult.disabled('Supabase 配置不完整，本地模式可正常使用。');
    }

    await Supabase.initialize(url: url!, publishableKey: key);
    return SupabaseBootstrapResult.configured(Supabase.instance.client);
  } on Object {
    return SupabaseBootstrapResult.disabled('Supabase 初始化失败，本地模式可正常使用。');
  }
}

Future<File?> _findDotEnvFile(String fileName) async {
  final direct = File(fileName);
  if (await direct.exists()) {
    return direct;
  }
  if (direct.isAbsolute) {
    return null;
  }

  final searched = <String>{};
  final startDirectories = [
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ];

  for (final start in startDirectories) {
    var directory = start;
    for (var depth = 0; depth < 8; depth++) {
      final candidate = File('${directory.path}/$fileName');
      if (searched.add(candidate.path) && await candidate.exists()) {
        return candidate;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
  }
  return null;
}

bool _looksLikeSupabaseUrl(String? value) {
  if (value == null || value.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return false;
  }
  return !uri.path.contains('/rest/v1');
}
