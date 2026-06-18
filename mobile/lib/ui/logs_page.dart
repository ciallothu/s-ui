import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final search = TextEditingController();
  final user = TextEditingController();
  DateTime start = DateTime.now().subtract(const Duration(days: 1));
  DateTime end = DateTime.now();
  String level = 'ALL';
  List<dynamic> items = [];
  int total = 0;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    user.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(await context.read<AppState>().api!.get('logs', query: {
        'level': level,
        'user': user.text.trim(),
        'search': search.text.trim(),
        'start': unixStartOfDay(start),
        'end': unixEndOfDay(end),
        'limit': 1000,
      }) as Map);
      if (mounted) {
        setState(() {
          items = List<dynamic>.from(result['items'] as List? ?? const []);
          total = int.tryParse(result['total']?.toString() ?? '') ?? 0;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickDate(bool isStart) async {
    final value = await showDatePicker(context: context, initialDate: isStart ? start : end, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (value == null) return;
    if (!mounted) return;
    setState(() {
      if (isStart) {
        start = value;
      } else {
        end = value;
      }
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(title: '日志', subtitle: '统一检索系统日志与管理员变更记录'),
        FilterCard(
          child: Column(
            children: [
              Row(children: [Expanded(child: TextField(controller: search, onSubmitted: (_) => load(), decoration: const InputDecoration(labelText: '全文搜索', prefixIcon: Icon(Icons.search)))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: load, icon: const Icon(Icons.refresh))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: TextField(controller: user, onSubmitted: (_) => load(), decoration: const InputDecoration(labelText: '用户 / 管理员', prefixIcon: Icon(Icons.person_search_outlined)))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(initialValue: level, decoration: const InputDecoration(labelText: '级别'), items: const ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) { setState(() => level = value ?? 'ALL'); load(); }))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(true), icon: const Icon(Icons.calendar_today_outlined), label: Text('起 ${_date(start)}'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(false), icon: const Icon(Icons.event_outlined), label: Text('止 ${_date(end)}')))]),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: error != null
              ? EmptyState(label: error!, icon: Icons.error_outline)
              : items.isEmpty
                  ? const EmptyState(label: '没有匹配的日志')
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) return Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('共 $total 条'));
                          return _logCard(Map<String, dynamic>.from(items[index - 1] as Map));
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _logCard(Map<String, dynamic> item) {
    final logLevel = item['level']?.toString() ?? 'INFO';
    final color = switch (logLevel) {
      'ERROR' => Colors.red,
      'WARNING' => Colors.orange,
      'DEBUG' => Colors.grey,
      _ => Colors.blue,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: .15), child: Icon(Icons.receipt_long_outlined, size: 18, color: color)),
        title: Text(item['message']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        subtitle: Text('${item['time'] ?? formatTimestamp(item['timestamp'])} · ${item['source'] ?? 'system'}${item['user']?.toString().isNotEmpty == true ? ' · ${item['user']}' : ''}'),
        trailing: Chip(label: Text(logLevel), side: BorderSide.none),
        children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Align(alignment: Alignment.centerLeft, child: SelectableText(item['message']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace'))))],
      ),
    );
  }
}

String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
