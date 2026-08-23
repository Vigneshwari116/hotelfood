import 'package:flutter/material.dart';
import 'package:foodstock/database/database_helper.dart';
import 'package:foodstock/database/postgres_app_db.dart';
import 'package:foodstock/database/remote_db_config.dart';

class ServerConnectionScreen extends StatefulWidget {
  const ServerConnectionScreen({super.key});

  @override
  State<ServerConnectionScreen> createState() =>
      _ServerConnectionScreenState();
}

class _ServerConnectionScreenState extends State<ServerConnectionScreen> {
  final _host = TextEditingController(text: RemoteDbConfig.defaultHost);
  final _port = TextEditingController(text: '${RemoteDbConfig.defaultPort}');
  final _database =
      TextEditingController(text: RemoteDbConfig.defaultDatabase);
  final _user = TextEditingController(text: RemoteDbConfig.defaultUser);
  final _password = TextEditingController();

  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _database.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await RemoteDbConfig.load();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _host.text = config.host;
      _port.text = '${config.port}';
      _database.text = config.database;
      _user.text = config.username;
      _password.text = config.password;
      _loading = false;
    });
  }

  Future<void> _save({required bool testOnly}) async {
    final port = int.tryParse(_port.text.trim());
    if (port == null) {
      setState(() => _status = 'Port must be a number (use 5434 for testing).');
      return;
    }
    setState(() {
      _saving = true;
      _status = null;
    });
    final config = RemoteDbConfig(
      enabled: _enabled,
      host: _host.text.trim(),
      port: port,
      database: _database.text.trim(),
      username: _user.text.trim(),
      password: _password.text,
    );
    try {
      if (config.database == 'db_accounting_testing' ||
          config.database == 'db_accounting_live') {
        throw StateError(
          'Do not use the accounting databases. Use shilpa_enterprise.',
        );
      }
      if (testOnly) {
        final db = await PostgresAppDb.connect(config);
        await db.close();
        if (!mounted) return;
        setState(() {
          _saving = false;
          _status =
              'Connected to ${config.database} on ${config.host}:${config.port}.';
        });
        return;
      }
      await config.save();
      await DBHelper.instance.reconnect();
      if (_enabled) {
        await DBHelper.instance.appDb;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = _enabled
            ? 'Saved. Close and reopen the app on phone and Windows so both use the VPS.'
            : 'Saved. This device will keep using its local database.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Turn this on so phone and Windows share one shop database: '
                'shilpa_enterprise on the VPS. Do not use db_accounting_testing '
                'or live. After Save, close and reopen the app on every device.',
                style: TextStyle(color: Colors.teal.shade900, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Use VPS PostgreSQL'),
            subtitle: const Text('Off = this device only (SQLite)'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          TextField(
            controller: _host,
            decoration: const InputDecoration(labelText: 'Host (VPS IP)'),
          ),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Port'),
          ),
          TextField(
            controller: _database,
            decoration: const InputDecoration(labelText: 'Database name'),
          ),
          TextField(
            controller: _user,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(testOnly: true),
                  child: const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(testOnly: false),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!),
          ],
        ],
      ),
    );
  }
}
