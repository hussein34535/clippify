import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class ShortProviderSettings {
  static const baseUrl = 'https://coarena.ai/api/v1';
  static const defaultModel = 'deepseek-v4-1-flash-1017';

  static const _legacyBaseUrl = 'https://gpt.teamsoclo.site/v1';
  static const _storageKey = 'clippify_short_teamsoclo_settings';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static Future<void>? _pendingUpdate;

  /// Reads the environment overrides for a new isolated desktop sidecar.
  static Future<Map<String, String>> loadLaunchEnvironment() async {
    try {
      final settings = await _readLatest();
      final apiKey = settings.apiKey;
      if (!settings.cloudEnabled || apiKey == null) {
        return const {};
      }
      return {
        'CLIPPIFY_SHORT_TEAMSOCLO_KEY': apiKey,
        'CLIPPIFY_SHORT_TEAMSOCLO_MODEL': settings.model,
        'CLIPPIFY_SHORT_AI_BASE_URL': settings.endpoint,
        if (settings.vision) 'CLIPPIFY_SHORT_AI_VISION': '1',
      };
    } on Exception {
      return const {};
    }
  }

  static Future<_SavedSettings> _readLatest() async {
    await _pendingUpdate;
    return _read();
  }

  static Future<_SavedSettings> _read() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) {
      return const _SavedSettings();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded case {
        'apiKey': final String? apiKey,
        'model': final String model,
        'cloudEnabled': final bool cloudEnabled,
      }) {
        final savedEndpoint = decoded['endpoint'];
        final endpoint = switch (savedEndpoint) {
          null when !decoded.containsKey('endpoint') => _legacyBaseUrl,
          final String url when url.trim().isNotEmpty => _endpoint(url),
          _ => null,
        };
        if (endpoint == null) return const _SavedSettings();
        final key = apiKey?.trim() ?? '';
        return _SavedSettings(
          apiKey: key.isEmpty ? null : key,
          model: _normalizeModel(model),
          cloudEnabled: cloudEnabled && key.isNotEmpty,
          endpoint: endpoint,
          vision: decoded['vision'] == true,
        );
      }
    } on FormatException {
      return const _SavedSettings();
    }
    return const _SavedSettings();
  }

  static String _normalizeModel(String model) {
    final trimmed = model.trim();
    return trimmed.isEmpty ? defaultModel : trimmed;
  }

  static String? _endpoint(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return baseUrl;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<bool> _update(
    _SavedSettings Function(_SavedSettings current) change,
  ) async {
    final previous = _pendingUpdate;
    final done = Completer<void>();
    _pendingUpdate = done.future;
    try {
      await previous;
      final settings = change(await _read());
      await _storage.write(
        key: _storageKey,
        value: jsonEncode({
          'apiKey': settings.apiKey,
          'model': settings.model,
          'cloudEnabled': settings.cloudEnabled,
          'endpoint': settings.endpoint,
          'vision': settings.vision,
        }),
      );
      return settings.apiKey != null;
    } finally {
      if (identical(_pendingUpdate, done.future)) {
        _pendingUpdate = null;
      }
      done.complete();
    }
  }
}

class _SavedSettings {
  const _SavedSettings({
    this.apiKey,
    this.model = ShortProviderSettings.defaultModel,
    this.cloudEnabled = false,
    this.endpoint = ShortProviderSettings.baseUrl,
    this.vision = false,
  });

  final String? apiKey;
  final String model;
  final bool cloudEnabled;
  final String endpoint;
  final bool vision;
}

class ShortProviderSettingsScreen extends StatefulWidget {
  const ShortProviderSettingsScreen({super.key});

  @override
  State<ShortProviderSettingsScreen> createState() =>
      _ShortProviderSettingsScreenState();
}

class _ShortProviderSettingsScreenState
    extends State<ShortProviderSettingsScreen> {
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  final _endpointController = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  bool _hasSavedKey = false;
  bool _cloudEnabled = false;
  bool _vision = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _endpointController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await action();
    } on Exception {
      if (mounted) {
        setState(
          () => _feedback = 'تعذّر الوصول إلى التخزين الآمن. حاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _load() => _run(() async {
    final settings = await ShortProviderSettings._readLatest();
    if (!mounted) {
      return;
    }
    _modelController.text = settings.model;
    _endpointController.text = settings.endpoint;
    setState(() {
      _loaded = true;
      _hasSavedKey = settings.apiKey != null;
      _cloudEnabled = settings.cloudEnabled;
      _vision = settings.vision;
    });
  });

  Future<void> _save() => _run(() async {
    final endpoint = ShortProviderSettings._endpoint(_endpointController.text);
    if (endpoint == null) {
      setState(
        () => _feedback =
            'اكتب عنوان HTTPS صحيح من غير مفتاح أو باراميترات في الرابط.',
      );
      return;
    }
    final replacement = _keyController.text.trim();
    final model = ShortProviderSettings._normalizeModel(_modelController.text);
    final cloudEnabled = _cloudEnabled;
    final hasKey = await ShortProviderSettings._update((current) {
      final changingHost =
          Uri.parse(endpoint).origin != Uri.parse(current.endpoint).origin;
      final apiKey = replacement.isEmpty
          ? (changingHost ? null : current.apiKey)
          : replacement;
      return _SavedSettings(
        apiKey: apiKey,
        model: model,
        cloudEnabled: cloudEnabled && apiKey != null,
        endpoint: endpoint,
        vision: _vision && cloudEnabled && apiKey != null,
      );
    });
    if (!mounted) {
      return;
    }
    _keyController.clear();
    _modelController.text = model;
    setState(() {
      _hasSavedKey = hasKey;
      _cloudEnabled = cloudEnabled && hasKey;
      _vision = _vision && _cloudEnabled;
      _feedback = cloudEnabled && !hasKey
          ? 'أدخل مفتاح API للمزوّد المختار.'
          : 'تم حفظ الإعدادات.';
    });
  });

  Future<void> _removeKey() => _run(() async {
    await ShortProviderSettings._update(
      (current) =>
          _SavedSettings(model: current.model, endpoint: current.endpoint),
    );
    if (!mounted) {
      return;
    }
    _keyController.clear();
    setState(() {
      _hasSavedKey = false;
      _cloudEnabled = false;
      _vision = false;
      _feedback = 'تمت إزالة المفتاح.';
    });
  });

  void _selectCoarena() {
    if (Uri.tryParse(_endpointController.text)?.host != 'coarena.ai') {
      _keyController.clear();
      _vision = false;
      _cloudEnabled = false;
    }
    _endpointController.text = ShortProviderSettings.baseUrl;
    _modelController.text = ShortProviderSettings.defaultModel;
    setState(() {});
  }

  Future<void> _testConnection() => _run(() async {
    final endpoint = ShortProviderSettings._endpoint(_endpointController.text);
    final stored = await ShortProviderSettings._readLatest();
    if (!mounted) return;
    if (endpoint == null) {
      setState(() => _feedback = 'اكتب عنوان HTTPS صحيح للمزوّد.');
      return;
    }
    final entered = _keyController.text.trim();
    final sameHost =
        Uri.parse(stored.endpoint).origin == Uri.parse(endpoint).origin;
    final key = entered.isNotEmpty
        ? entered
        : (sameHost ? stored.apiKey : null);
    if (key == null) {
      setState(() => _feedback = 'أدخل مفتاح API للمزوّد المختار.');
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    const timeout = Duration(seconds: 30);
    String feedback;
    try {
      final request = await client
          .postUrl(Uri.parse('$endpoint/chat/completions'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(
        jsonEncode({
          'model': ShortProviderSettings._normalizeModel(_modelController.text),
          'messages': [
            {
              'role': 'user',
              'content': 'Reply with OK. This is a connection test.',
            },
          ],
        }),
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 200) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout);
        final data = jsonDecode(body);
        feedback =
            data is Map &&
                data['choices'] is List &&
                (data['choices'] as List).isNotEmpty
            ? 'الاتصال شغال والموديل رد على الاختبار.'
            : 'المزوّد رجّع استجابة غير متوقعة.';
      } else {
        feedback = switch (response.statusCode) {
          401 || 403 => 'المزوّد رفض المفتاح أو صلاحياته.',
          404 => 'راجع عنوان المزوّد واسم الموديل.',
          429 => 'وصلت لحد طلبات المزوّد. جرّب بعد شوية.',
          final code => 'تعذّر الاتصال بالمزوّد (HTTP $code).',
        };
      }
    } on Exception {
      feedback = 'تعذّر الوصول للمزوّد. راجع العنوان والاتصال.';
    } finally {
      client.close(force: true);
    }
    if (mounted) setState(() => _feedback = feedback);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الذكاء الاصطناعي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loaded) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  label: const Text('Coarena · DeepSeek'),
                  onPressed: _busy ? null : _selectCoarena,
                ),
              ),
              TextField(
                controller: _endpointController,
                enabled: !_busy,
                onChanged: (_) {
                  if (_vision) setState(() => _vision = false);
                },
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'عنوان المزوّد (Base URL)',
                  hintText: ShortProviderSettings.baseUrl,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _modelController,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'الموديل',
                  hintText: ShortProviderSettings.defaultModel,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _keyController,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  labelText: _hasSavedKey ? 'مفتاح API بديل' : 'مفتاح API',
                  helperText: _hasSavedKey ? 'يوجد مفتاح محفوظ.' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('السماح باستخدام المزوّد السحابي'),
                subtitle: const Text(
                  'عند التفعيل، المزوّد يستقبل طلب المونتاج ومقتطفات من النص، '
                  'وCoarena يحتفظ بمحتوى الطلبات.',
                ),
                value: _cloudEnabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _cloudEnabled = value;
                        if (!value) _vision = false;
                      }),
              ),
              if (_cloudEnabled)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إرسال صور من الفيديو'),
                  subtitle: const Text(
                    'مخرج AI يرسل حتى ١٨ صورة مصغّرة من الفيديو، والوضع الهجين يرسل حتى ٥ صور. '
                    'مخرج AI محتاج التفعيل ده عشان يقدر يشوف المشهد ويقرر المونتاج. '
                    'Coarena يحتفظ بمحتوى الطلبات.',
                  ),
                  value: _vision,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _vision = value ?? false),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _busy ? null : _testConnection,
                  child: const Text('اختبر الاتصال'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('حفظ'),
                  ),
                  if (_hasSavedKey)
                    OutlinedButton(
                      onPressed: _busy ? null : _removeKey,
                      child: const Text('إزالة المفتاح'),
                    ),
                ],
              ),
            ] else if (!_busy)
              OutlinedButton(
                onPressed: _load,
                child: const Text('إعادة المحاولة'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_feedback case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
          ],
        ),
      ),
    );
  }
}
