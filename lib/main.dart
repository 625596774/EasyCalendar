import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/sync/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseBootstrap = await initializeSupabaseFromDotEnv();
  runApp(ZrkCalendarApp(supabaseBootstrap: supabaseBootstrap));
}
