import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatBytes(num? bytes, {int decimals = 1}) {
  final value = bytes?.toDouble() ?? 0;
  if (value <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final index = math.min((math.log(value) / math.log(1024)).floor(), suffixes.length - 1).toInt();
  return '${(value / math.pow(1024, index)).toStringAsFixed(decimals)} ${suffixes[index]}';
}

String prettyJson(dynamic value) => const JsonEncoder.withIndent('  ').convert(value);

int unixStartOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 1000;

int unixEndOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch ~/ 1000;

String formatTimestamp(dynamic timestamp) {
  final seconds = int.tryParse(timestamp?.toString() ?? '') ?? 0;
  if (seconds <= 0) return '—';
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
  );
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = '确认',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.label, this.icon = Icons.inbox_outlined});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}

class FilterCard extends StatelessWidget {
  const FilterCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );
}

class JsonEditorDialog extends StatefulWidget {
  const JsonEditorDialog({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onSave,
    this.actionLabel = '保存',
  });

  final String title;
  final dynamic initialValue;
  final Future<void> Function(dynamic value) onSave;
  final String actionLabel;

  @override
  State<JsonEditorDialog> createState() => _JsonEditorDialogState();
}

class _JsonEditorDialogState extends State<JsonEditorDialog> {
  late final TextEditingController controller;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: prettyJson(widget.initialValue));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    dynamic value;
    try {
      value = jsonDecode(controller.text);
    } catch (exception) {
      setState(() => error = 'JSON 格式错误：$exception');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          actions: [
            TextButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(widget.actionLabel),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(hintText: '{}', alignLabelWithHint: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
