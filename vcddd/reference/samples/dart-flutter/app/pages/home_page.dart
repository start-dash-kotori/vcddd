import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页骨架 — 替换为实际内容。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('{project_name}'),
      ),
      body: const Center(
        child: Text('Coming soon'),
      ),
    );
  }
}
