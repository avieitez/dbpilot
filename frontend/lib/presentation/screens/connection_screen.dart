import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../widgets/provider_selector_card.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ConnectionApiService();

  final _nameController = TextEditingController();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '5432');
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serviceNameController = TextEditingController(text: 'XE');
  final _sidController = TextEditingController();

  DatabaseProvider _selectedProvider = DatabaseProvider.postgresql;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _encrypt = false;
  bool _trustServerCertificate = true;
  String? _statusMessage;
  bool? _statusSuccess;

  @override
  void dispose() {
    _apiService.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serviceNameController.dispose();
    _sidController.dispose();
    super.dispose();
  }

  void _onProviderSelected(DatabaseProvider provider) {
    setState(() {
      _selectedProvider = provider;
      _portController.text = provider.defaultPort;
      _statusMessage = null;
      _statusSuccess = null;

      if (provider == DatabaseProvider.oracle) {
        _databaseController.clear();
        _serviceNameController.text = 'XE';
      }
    });
  }

  ConnectionRequest _buildRequest() {
    return ConnectionRequest(
      name: _nameController.text.trim(),
      provider: _selectedProvider,
      host: _hostController.text.trim(),
      port: _portController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      database: _databaseController.text.trim(),
      serviceName: _selectedProvider == DatabaseProvider.oracle
          ? _serviceNameController.text.trim().isEmpty
                ? null
                : _serviceNameController.text.trim()
          : null,
      sid: _selectedProvider == DatabaseProvider.oracle
          ? _sidController.text.trim().isEmpty
                ? null
                : _sidController.text.trim()
          : null,
      encrypt: _selectedProvider == DatabaseProvider.sqlServer ? _encrypt : false,
      trustServerCertificate: _selectedProvider == DatabaseProvider.sqlServer
          ? _trustServerCertificate
          : false,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _statusMessage = null;
      _statusSuccess = null;
    });

    try {
      final result = await _apiService.testConnection(_buildRequest());
      if (!mounted) return;

      setState(() {
        _statusSuccess = result.success;
        _statusMessage = result.durationMs == null
            ? result.message
            : '${result.message} (${result.durationMs} ms)';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _statusSuccess = false;
        _statusMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _saveConnection() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_buildRequest());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Connection'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a provider',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select the engine, then enter the connection details below.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1,
                  children: DatabaseProvider.values
                      .map(
                        (provider) => ProviderSelectorCard(
                          provider: provider,
                          selected: provider == _selectedProvider,
                          onTap: () => _onProviderSelected(provider),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _nameController,
                          label: 'Connection name',
                          hint: 'Production / Local Oracle XE / etc.',
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'Enter a name for this connection'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _hostController,
                          label: 'Host',
                          hint: 'localhost or IP address',
                          validator: _requiredValidator,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _portController,
                                label: 'Port',
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  if (int.tryParse(value.trim()) == null) {
                                    return 'Numbers only';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                controller: _usernameController,
                                label: 'Username',
                                validator: _requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          obscureText: _obscurePassword,
                          validator: _requiredValidator,
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedProvider != DatabaseProvider.oracle)
                          _buildTextField(
                            controller: _databaseController,
                            label: 'Database',
                            hint: _selectedProvider == DatabaseProvider.postgresql
                                ? 'postgres'
                                : 'master',
                            validator: _requiredValidator,
                          ),
                        if (_selectedProvider == DatabaseProvider.oracle) ...[
                          _buildTextField(
                            controller: _serviceNameController,
                            label: 'Service name',
                            hint: 'XE',
                            validator: (value) {
                              final sidValue = _sidController.text.trim();
                              if ((value == null || value.trim().isEmpty) &&
                                  sidValue.isEmpty) {
                                return 'Enter a service name or SID';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _sidController,
                            label: 'SID (optional)',
                            hint: 'xe',
                          ),
                        ],
                        if (_selectedProvider == DatabaseProvider.sqlServer) ...[
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Encrypt connection'),
                            subtitle: const Text(
                              'Recommended when the server supports TLS',
                            ),
                            value: _encrypt,
                            onChanged: (value) => setState(() => _encrypt = value),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Trust server certificate'),
                            subtitle: const Text(
                              'Useful for local dev and self-signed certificates',
                            ),
                            value: _trustServerCertificate,
                            onChanged: (value) => setState(
                              () => _trustServerCertificate = value,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_statusMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_statusSuccess ?? false)
                          ? Colors.green.withOpacity(0.12)
                          : Colors.red.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (_statusSuccess ?? false)
                            ? Colors.green.withOpacity(0.35)
                            : Colors.red.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          (_statusSuccess ?? false)
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _testConnection,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text(_loading ? 'Testing...' : 'Test connection'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _saveConnection,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }
}
