import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/app_localizations.dart';
import '../core/connection_profile.dart';

class AppState extends ChangeNotifier {
  static const _profileKey = 'sui.connection.profile.v1';
  static const _localeKey = 'sui.locale.v1';
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  ConnectionProfile? profile;
  ApiClient? api;
  Map<String, dynamic> bootstrap = {};
  String localeCode = _initialLocale();
  bool restoring = true;
  bool busy = false;
  String? error;

  bool get connected => api != null && profile?.token.isNotEmpty == true;

  Future<void> restore() async {
    restoring = true;
    notifyListeners();
    try {
      final raw = await _storage.read(key: _profileKey);
      final storedLocale = await _storage.read(key: _localeKey);
      if (storedLocale != null && storedLocale.isNotEmpty) {
        localeCode = storedLocale;
      }
      if (raw != null && raw.isNotEmpty) {
        final restored = ConnectionProfile.decode(raw);
        if (restored.token.isNotEmpty) {
          final client = ApiClient(restored, localeCode: localeCode);
          await client.get('me');
          profile = restored;
          api = client;
          await refreshBootstrap(notify: false);
        }
      }
    } catch (exception) {
      error = exception.toString();
      profile = null;
      api = null;
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> setLocale(String code) async {
    localeCode = code;
    await _storage.write(key: _localeKey, value: code);
    notifyListeners();
  }

  Future<void> connectWithToken(ConnectionProfile next) async {
    await _connect(next);
  }

  Future<bool> connectWithCredentials(
    ConnectionProfile next,
    String username,
    String password,
    {String code = ''}
  ) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final login = await ApiClient.login(
        profile: next,
        username: username,
        password: password,
        code: code,
        localeCode: localeCode,
      );
	  if (login['requires2FA'] == true) {
		return true;
	  }
      final token = login['token']?.toString() ?? '';
      if (token.isEmpty) throw ApiException(AppLocalizations.tr(localeCode, 'error.noToken'));
      await _connect(next.copyWith(token: token), manageBusy: false);
	  return false;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _connect(ConnectionProfile next, {bool manageBusy = true}) async {
    if (manageBusy) {
      busy = true;
      error = null;
      notifyListeners();
    }
    try {
      if (next.normalizedBaseUrl.isEmpty) {
        throw ApiException(AppLocalizations.tr(localeCode, 'error.urlRequired'));
      }
      final uri = Uri.tryParse(next.normalizedBaseUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw ApiException(AppLocalizations.tr(localeCode, 'error.urlInvalid'));
      }
      if (next.token.trim().isEmpty) throw ApiException(AppLocalizations.tr(localeCode, 'error.tokenRequired'));
      final client = ApiClient(next, localeCode: localeCode);
      await client.get('meta');
      profile = next.copyWith(baseUrl: next.normalizedBaseUrl);
      api = client;
      await refreshBootstrap(notify: false);
      await _storage.write(key: _profileKey, value: profile!.encode());
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      if (manageBusy) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshBootstrap({bool notify = true}) async {
    final client = api;
    if (client == null) return;
    if (notify) {
      busy = true;
      notifyListeners();
    }
    try {
      bootstrap = Map<String, dynamic>.from(await client.get('bootstrap') as Map);
      error = null;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      if (notify) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<dynamic> getResource(String resource, {String? id}) {
    return api!.get('resources/$resource', query: {if (id != null) 'id': id});
  }

  Future<dynamic> saveResource(
    String resource,
    String action,
    dynamic data, {
    List<int> initUsers = const [],
    bool apply = true,
  }) async {
    final value = await api!.post('resources/$resource', data: {
      'action': action,
      'data': data,
      if (initUsers.isNotEmpty) 'initUsers': initUsers,
      'apply': apply,
    });
    await refreshBootstrap(notify: false);
    notifyListeners();
    return value;
  }

  Future<void> disconnect({bool revoke = false}) async {
    if (revoke && api != null) {
      try {
        await api!.delete('auth/token');
      } catch (_) {
        // Local logout must still succeed if the panel is offline.
      }
    }
    await _storage.delete(key: _profileKey);
    profile = null;
    api = null;
    bootstrap = {};
    error = null;
    notifyListeners();
  }

  void reconfigure() {
    api = null;
    bootstrap = {};
    error = null;
    notifyListeners();
  }
}

String _initialLocale() {
  final locale = ui.PlatformDispatcher.instance.locale;
  if (locale.languageCode == 'zh') return locale.scriptCode == 'Hant' ? 'zhHant' : 'zhHans';
  const supported = {'en', 'ja', 'fr', 'la', 'fa', 'vi', 'ru'};
  return supported.contains(locale.languageCode) ? locale.languageCode : 'en';
}
