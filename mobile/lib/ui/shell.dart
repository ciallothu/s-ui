import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'admin_page.dart';
import 'analytics_page.dart';
import 'config_page.dart';
import 'dashboard_page.dart';
import 'logs_page.dart';
import 'resource_page.dart';
import 'tools_page.dart';
import 'widgets.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function() builder;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;

  late final destinations = <_Destination>[
    _Destination('主页', Icons.home_outlined, () => const DashboardPage()),
    _Destination('用户管理', Icons.people_outline, () => const ResourcePage(resource: 'clients', title: '用户管理', icon: Icons.people_outline)),
    _Destination('入站管理', Icons.cloud_download_outlined, () => const ResourcePage(resource: 'inbounds', title: '入站管理', icon: Icons.cloud_download_outlined)),
    _Destination('出站管理', Icons.cloud_upload_outlined, () => const ResourcePage(resource: 'outbounds', title: '出站管理', icon: Icons.cloud_upload_outlined)),
    _Destination('节点管理', Icons.cloud_queue_outlined, () => const ResourcePage(resource: 'endpoints', title: '节点管理', icon: Icons.cloud_queue_outlined)),
    _Destination('服务管理', Icons.dns_outlined, () => const ResourcePage(resource: 'services', title: '服务管理', icon: Icons.dns_outlined)),
    _Destination('TLS 设置', Icons.workspace_premium_outlined, () => const ResourcePage(resource: 'tls', title: 'TLS 设置', icon: Icons.workspace_premium_outlined)),
    _Destination('核心配置', Icons.tune, () => const ConfigPage()),
    _Destination('用量与统计', Icons.query_stats, () => const AnalyticsPage()),
    _Destination('日志', Icons.receipt_long_outlined, () => const LogsPage()),
    _Destination('管理员', Icons.admin_panel_settings_outlined, () => const AdminPage()),
    _Destination('设置与工具', Icons.settings_outlined, () => const ToolsPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final state = context.watch<AppState>();
    final body = KeyedSubtree(
      key: ValueKey(selected),
      child: destinations[selected].builder(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(destinations[selected].label),
        centerTitle: !wide,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: state.busy
                ? null
                : () async {
                    try {
                      await state.refreshBootstrap();
                      if (context.mounted) showMessage(context, '已刷新');
                    } catch (exception) {
                      if (context.mounted) showMessage(context, exception.toString(), error: true);
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: wide ? null : _drawer(context),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1180,
              selectedIndex: selected,
              onDestinationSelected: (index) => setState(() => selected = index),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircleAvatar(child: Icon(Icons.shield_outlined)),
              ),
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(icon: Icon(destination.icon), label: Text(destination.label)),
              ],
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final state = context.read<AppState>();
    return NavigationDrawer(
      selectedIndex: selected,
      onDestinationSelected: (index) {
        setState(() => selected = index);
        Navigator.pop(context);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.shield_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('S-UI', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(state.profile?.name ?? '', overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        for (final destination in destinations)
          NavigationDrawerDestination(icon: Icon(destination.icon), label: Text(destination.label)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('退出当前连接'),
          onTap: () async {
            Navigator.pop(context);
            final revoke = await confirm(context, title: '退出连接', message: '是否同时撤销当前移动端 API Token？', action: '撤销并退出');
            await state.disconnect(revoke: revoke);
          },
        ),
      ],
    );
  }
}
