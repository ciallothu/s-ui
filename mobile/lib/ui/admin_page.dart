import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_locale_context.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  List<dynamic> users = [];
  List<dynamic> tokens = [];
  List<dynamic> changes = [];
  Map<String, dynamic> security = {};
  final search = TextEditingController();
  final actor = TextEditingController();
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this)..addListener(() {
        if (!tabs.indexIsChanging) load();
      });
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    actor.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AppState>().api!;
      if (tabs.index == 0) {
        final value = await api.get('users');
        if (mounted) setState(() => users = List<dynamic>.from(value as List? ?? const []));
      } else if (tabs.index == 1) {
        final value = await api.get('tokens');
        if (mounted) setState(() => tokens = List<dynamic>.from(value as List? ?? const []));
      } else if (tabs.index == 2) {
        final value = Map<String, dynamic>.from(await api.get('changes', query: {'user': actor.text.trim(), 'search': search.text.trim(), 'limit': 500}) as Map);
        if (mounted) setState(() => changes = List<dynamic>.from(value['items'] as List? ?? const []));
	  } else {
		final value = await api.get('auth/security');
		if (mounted) setState(() => security = Map<String, dynamic>.from(value as Map? ?? const {}));
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changeCredentials(Map<String, dynamic> item) async {
    final oldPassword = TextEditingController();
    final username = TextEditingController(text: item['username']?.toString() ?? '');
    final password = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('admin.changeCred')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: oldPassword, obscureText: true, decoration: InputDecoration(labelText: context.t('admin.currentPassword'))),
              const SizedBox(height: 10),
              TextField(controller: username, decoration: InputDecoration(labelText: context.t('admin.newUsername'))),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: context.t('admin.newPassword'))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.t('common.cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppState>().api!.patch('users/${item['id']}', data: {'oldPassword': oldPassword.text, 'username': username.text.trim(), 'password': password.text});
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await load();
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: Text(context.t('common.save')),
          ),
        ],
      ),
    );
    oldPassword.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> addToken() async {
    final description = TextEditingController(text: 'Mobile/API');
    final days = TextEditingController(text: '30');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('admin.createToken')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: description, decoration: InputDecoration(labelText: context.t('admin.description'))), const SizedBox(height: 10), TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.t('admin.validDays')))]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.t('common.cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                final result = Map<String, dynamic>.from(await context.read<AppState>().api!.post('tokens', data: {'description': description.text, 'expiryDays': int.tryParse(days.text) ?? 30}) as Map);
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(title: Text(context.t('admin.saveTokenNow')), content: SelectableText(result['token']?.toString() ?? ''), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: Text(context.t('admin.done')))]));
                }
                await load();
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: Text(context.t('common.confirm')),
          ),
        ],
      ),
    );
    description.dispose();
    days.dispose();
  }

  Future<void> deleteToken(Map<String, dynamic> token) async {
    if (!await confirm(context, title: context.tr('admin.deleteToken'), message: context.tr('admin.deleteTokenMsg'), action: context.tr('common.delete'))) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api!.delete('tokens/${token['id']}');
      await load();
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> enableTotp() async {
	try {
	  final setup = Map<String, dynamic>.from(await context.read<AppState>().api!.post('auth/totp/begin') as Map);
	  if (!mounted) return;
	  final code = TextEditingController();
	  final confirmed = await showDialog<bool>(
		context: context,
		builder: (dialogContext) => AlertDialog(
		  title: Text(context.t('admin.enableTotp')),
		  content: SizedBox(
			width: 520,
			child: Column(mainAxisSize: MainAxisSize.min, children: [
			  Text(context.t('admin.totpSetup')),
			  const SizedBox(height: 10),
			  SelectableText(setup['uri']?.toString() ?? setup['secret']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace')),
			  const SizedBox(height: 12),
			  TextField(controller: code, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.t('admin.code6'))),
			]),
		  ),
		  actions: [
			TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.t('common.cancel'))),
			FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(context.t('common.confirm'))),
		  ],
		),
	  );
	  if (confirmed != true || !mounted) {
		code.dispose();
		return;
	  }
	  final result = Map<String, dynamic>.from(await context.read<AppState>().api!.post('auth/totp/enable', data: {'code': code.text.trim()}) as Map);
	  code.dispose();
	  if (!mounted) return;
	  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(
		title: Text(context.t('admin.recoveryCodes')),
		content: SelectableText((result['recoveryCodes'] as List? ?? const []).join('\n'), style: const TextStyle(fontFamily: 'monospace')),
		actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: Text(context.t('admin.saved')))],
	  ));
	  await load();
	} catch (exception) {
	  if (mounted) showMessage(context, exception.toString(), error: true);
	}
  }

  Future<void> disableTotp() async {
	final password = TextEditingController();
	final code = TextEditingController();
	final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
	  title: Text(context.t('admin.disableTotp')),
	  content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
		TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: context.t('admin.currentPassword'))),
		const SizedBox(height: 10),
		TextField(controller: code, decoration: InputDecoration(labelText: context.t('admin.codeOrRecovery'))),
	  ])),
	  actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.t('common.cancel'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(context.t('common.close')))],
	));
	if (confirmed == true && mounted) {
	  try {
		await context.read<AppState>().api!.post('auth/totp/disable', data: {'password': password.text, 'code': code.text.trim()});
		await load();
	  } catch (exception) {
		if (mounted) showMessage(context, exception.toString(), error: true);
	  }
	}
	password.dispose();
	code.dispose();
  }

  Future<void> deletePasskey(Map<String, dynamic> passkey) async {
	if (!await confirm(context, title: context.tr('admin.deletePasskey'), message: context.tr('admin.deletePasskeyMsg'), action: context.tr('common.delete'))) return;
	if (!mounted) return;
	try {
	  await context.read<AppState>().api!.delete('auth/passkeys/${passkey['id']}');
	  await load();
	} catch (exception) {
	  if (mounted) showMessage(context, exception.toString(), error: true);
	}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: context.t('admin.title'),
          subtitle: context.t('admin.subtitle'),
          actions: [if (tabs.index == 1) IconButton.filled(onPressed: addToken, icon: const Icon(Icons.add))],
        ),
        TabBar(controller: tabs, isScrollable: true, tabs: [Tab(text: context.t('admin.admins')), Tab(text: context.t('admin.tokens')), Tab(text: context.t('admin.changes')), Tab(text: context.t('admin.security'))]),
        if (tabs.index == 2)
          FilterCard(
            child: Row(children: [Expanded(child: TextField(controller: actor, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: context.t('admin.actor')))), const SizedBox(width: 8), Expanded(child: TextField(controller: search, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: context.t('common.search'), prefixIcon: const Icon(Icons.search)))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: load, icon: const Icon(Icons.refresh))]),
          ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: error != null
              ? EmptyState(label: error!, icon: Icons.error_outline)
              : TabBarView(controller: tabs, children: [_users(), _tokens(), _changes(), _security()]),
        ),
      ],
    );
  }

  Widget _users() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: users.isEmpty
              ? [EmptyState(label: context.t('admin.noAdmins'))]
              : [for (final raw in users) _userCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _userCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings_outlined)),
          title: Text(item['username']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('admin.lastLogin', args: {'time': item['lastLogin']?.toString().isNotEmpty == true ? item['lastLogin'] : '—'})),
          trailing: IconButton(onPressed: () => changeCredentials(item), icon: const Icon(Icons.edit_outlined)),
        ),
      );

  Widget _tokens() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: tokens.isEmpty
              ? [EmptyState(label: context.t('admin.noTokens'))]
              : [for (final raw in tokens) _tokenCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _tokenCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.key_outlined)),
          title: Text(item['desc']?.toString().isNotEmpty == true ? item['desc'].toString() : context.t('admin.unnamedToken')),
          subtitle: Text(_expiry(item['expiry'])),
          trailing: IconButton(onPressed: () => deleteToken(item), icon: const Icon(Icons.delete_outline)),
        ),
      );

  Widget _changes() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: changes.isEmpty
              ? [EmptyState(label: context.t('admin.noChanges'))]
              : [for (final raw in changes) _changeCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _changeCard(Map<String, dynamic> item) => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.history),
          title: Text('${item['action']} · ${item['key']}'),
          subtitle: Text('${item['actor']} · ${formatTimestamp(item['dateTime'])}'),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Align(alignment: Alignment.centerLeft, child: SelectableText(item['obj']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace'))))],
        ),
      );

  Widget _security() {
	final methods = Map<String, dynamic>.from(security['methods'] as Map? ?? const {});
	final passkeys = List<dynamic>.from(security['passkeys'] as List? ?? const []);
	final totpEnabled = security['totpEnabled'] == true;
	return RefreshIndicator(
	  onRefresh: load,
	  child: ListView(
		physics: const AlwaysScrollableScrollPhysics(),
		padding: const EdgeInsets.all(12),
		children: [
		  Card(child: SwitchListTile(
			secondary: const Icon(Icons.phonelink_lock_outlined),
			title: Text(context.t('admin.totp')),
			subtitle: Text(totpEnabled ? context.t('admin.totpEnabled') : context.t('admin.totpDisabled')),
			value: totpEnabled,
			onChanged: (_) => totpEnabled ? disableTotp() : enableTotp(),
		  )),
		  Card(child: Column(children: [
			ListTile(leading: const Icon(Icons.key_outlined), title: Text(context.t('admin.passkeys')), subtitle: Text(methods['passkey'] == true ? context.t('admin.passkeysWebOnly') : context.t('admin.passkeysDisabled'))),
			for (final raw in passkeys)
			  ListTile(
				leading: const Icon(Icons.key_outlined),
				title: Text((raw as Map)['name']?.toString() ?? context.t('auth.passkey')),
				subtitle: Text(formatTimestamp(raw['createdAt'])),
				trailing: IconButton(onPressed: () => deletePasskey(Map<String, dynamic>.from(raw)), icon: const Icon(Icons.delete_outline)),
			  ),
		  ])),
		  Card(child: ListTile(leading: const Icon(Icons.badge_outlined), title: Text(context.t('admin.oidc')), subtitle: Text(methods['oidc'] == true ? context.t('admin.oidcEnabled') : context.t('admin.oidcDisabled')))),
		],
	  ),
	);
  }

  String _expiry(dynamic value) {
    final timestamp = int.tryParse(value?.toString() ?? '') ?? 0;
    return timestamp == 0 ? context.t('time.forever') : context.t('time.expiry', args: {'time': formatTimestamp(timestamp)});
  }
}
