import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_locale_context.dart';

const _selectMenuRadius = BorderRadius.all(Radius.circular(16));
const _selectMenuMaxHeight = kMinInteractiveDimension * 4 + 8;

class SelectOption<T> {
  const SelectOption(this.value, this.label);

  final T value;
  final String label;
}

class AnchoredSelect<T> extends StatelessWidget {
  const AnchoredSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.helperText,
    this.prefixIcon,
    this.compact = false,
  });

  final T? value;
  final String? label;
  final String? helperText;
  final Widget? prefixIcon;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    SelectOption<T>? selected;
    for (final option in options) {
      if (option.value == value) {
        selected = option;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        crossAxisUnconstrained: false,
        style: MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, _selectMenuMaxHeight)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: _selectMenuRadius)),
        ),
        builder: (context, controller, child) => InkWell(
          borderRadius: _selectMenuRadius,
          onTap: controller.isOpen ? controller.close : controller.open,
          child: InputDecorator(
            isEmpty: selected == null,
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              prefixIcon: prefixIcon,
              isDense: compact,
              border: compact ? InputBorder.none : null,
              contentPadding: compact ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8) : null,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Flexible(child: Text(selected?.label ?? '', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                Icon(controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        menuChildren: [
          for (final option in options)
            MenuItemButton(
              leadingIcon: option.value == value ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18),
              onPressed: () => onChanged(option.value),
              child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

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
  String action = '',
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action.isEmpty ? context.t('common.confirm') : action)),
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
    this.actionLabel = '',
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
      setState(() => error = 'JSON: $exception');
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
              label: Text(widget.actionLabel.isEmpty ? context.t('common.save') : widget.actionLabel),
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
