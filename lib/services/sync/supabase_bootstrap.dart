import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SupabaseDefineProvider = String? Function(String name);

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
  SupabaseDefineProvider defineProvider = _dartDefineValue,
}) async {
  try {
    final defineConfig = _SupabaseConfig.fromValues(
      url: defineProvider('SUPABASE_URL'),
      publishableKey: defineProvider('SUPABASE_PUBLISHABLE_KEY'),
    );
    if (defineConfig != null) {
      return _initializeSupabase(defineConfig);
    }

    final envFile = await _findDotEnvFile(fileName);
    if (envFile == null) {
      return SupabaseBootstrapResult.disabled('当前未配置云同步，本地模式可正常使用。');
    }

    final raw = await envFile.readAsString();
    dotenv.loadFromString(envString: raw, isOptional: true);

    final envConfig = _SupabaseConfig.fromValues(
      url: dotenv.maybeGet('SUPABASE_URL'),
      publishableKey: dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY'),
    );
    if (envConfig == null) {
      return SupabaseBootstrapResult.disabled('Supabase 配置不完整，本地模式可正常使用。');
    }

    return _initializeSupabase(envConfig);
  } on Object {
    return SupabaseBootstrapResult.disabled('Supabase 初始化失败，本地模式可正常使用。');
  }
}

Future<SupabaseBootstrapResult> _initializeSupabase(
  _SupabaseConfig config,
) async {
  await Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
  );
  return SupabaseBootstrapResult.configured(Supabase.instance.client);
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
  try {
    startDirectories.add(await getApplicationSupportDirectory());
  } on Object {
    // Some test environments do not have a platform path provider.
  }

  for (final start in startDirectories) {
    var directory = start;
    for (var depth = 0; depth < 12; depth++) {
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

String? _dartDefineValue(String name) {
  final value = switch (name) {
    'SUPABASE_URL' => const String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_PUBLISHABLE_KEY' => const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    _ => '',
  };
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class _SupabaseConfig {
  const _SupabaseConfig({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;

  static _SupabaseConfig? fromValues({
    required String? url,
    required String? publishableKey,
  }) {
    final normalizedUrl = url?.trim();
    final normalizedKey = publishableKey?.trim();
    if (!_looksLikeSupabaseUrl(normalizedUrl) ||
        normalizedKey == null ||
        normalizedKey.isEmpty) {
      return null;
    }
    return _SupabaseConfig(url: normalizedUrl!, publishableKey: normalizedKey);
  }
}
