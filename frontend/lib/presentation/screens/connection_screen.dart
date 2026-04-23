import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../widgets/provider_selector_card.dart';
import 'oracle_main.dart';
import 'postgresql_main.dart';
import 'sqlserver_main.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    this.initialData,
  });

  final Map<String, dynamic>? initialData;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ConnectionApiService();
  final _storageService = SavedConnectionStorageService();

  final _nameController = TextEditingController();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '5432');
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serviceNameController = TextEditingController(text: 'XE');
  final _sidController = TextEditingController();

  final _nameFocus = FocusNode();
  final _hostFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _databaseFocus = FocusNode();
  final _serviceNameFocus = FocusNode();
  final _sidFocus = FocusNode();
  final _portFocus = FocusNode();

  BannerAd? _bannerAd;
  DatabaseProvider _selectedProvider = DatabaseProvider.postgresql;
  DatabaseProvider? _originalProvider;
  Map<String, dynamic>? _originalData;
  String? _editingConnectionId;

  bool _loading = false;
  bool _obscurePassword = true;
  bool _encrypt = false;
  bool _trustServerCertificate = true;
  bool _showAdvanced = false;
  String? _statusMessage;
  bool? _statusSuccess;

  bool get _isEditing => widget.initialData != null;
  bool get _isOracle => _selectedProvider == DatabaseProvider.oracle;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadBanner();
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  void _loadInitialData() {
    final data = widget.initialData;
    if (data == null) {
      _applyProviderDefaults(_selectedProvider);
      return;
    }

    _originalData = Map<String, dynamic>.from(data);
    _editingConnectionId = data['id']?.toString();

    final providerValue = data['provider']?.toString() ?? 'postgresql';
    final provider = DatabaseProviderX.fromString(providerValue);

    _originalProvider = provider;
    _selectedProvider = provider;
    _applyDataToControllers(data, provider);
  }

  void _applyProviderDefaults(DatabaseProvider provider) {
    _portController.text = provider.defaultPort;
    if (provider == DatabaseProvider.postgresql) {
      _databaseController.text = 'postgres';
      _serviceNameController.clear();
      _sidController.clear();
    } else if (provider == DatabaseProvider.sqlServer) {
      _databaseController.text = 'master';
      _serviceNameController.clear();
      _sidController.clear();
    } else {
      _databaseController.clear();
      _serviceNameController.text = 'XE';
      _sidController.clear();
    }
  }

  void _applyDataToControllers(Map<String, dynamic> data, DatabaseProvider provider) {
    _nameController.text = data['name']?.toString() ?? '';
    _hostController.text = data['host']?.toString() ?? 'localhost';
    _portController.text = (data['port']?.toString().isNotEmpty ?? false)
        ? data['port'].toString()
        : provider.defaultPort;
    _databaseController.text = data['database']?.toString() ?? '';
    _usernameController.text = data['username']?.toString() ?? '';
    _passwordController.clear();
    _serviceNameController.text = (data['serviceName']?.toString().isNotEmpty ?? false)
        ? data['serviceName'].toString()
        : 'XE';
    _sidController.text = data['sid']?.toString() ?? '';
    _encrypt = data['encrypt'] == true;
    _trustServerCertificate = data['trustServerCertificate'] != false;
  }

  void _resetFieldsForProvider(DatabaseProvider provider) {
    if (_isEditing && _originalProvider == provider && _originalData != null) {
      _applyDataToControllers(_originalData!, provider);
      return;
    }

    _nameController.clear();
    _hostController.text = 'localhost';
    _usernameController.clear();
    _passwordController.clear();
    _encrypt = false;
    _trustServerCertificate = true;
    _applyProviderDefaults(provider);
  }

  void _onProviderSelected(DatabaseProvider provider) {
    setState(() {
      _selectedProvider = provider;
      _statusMessage = null;
      _statusSuccess = null;
      _resetFieldsForProvider(provider);
    });
  }

  ConnectionRequest _buildRequest() {
    final databaseValue = _databaseController.text.trim();

    return ConnectionRequest(
      name: _nameController.text.trim(),
      provider: _selectedProvider,
      host: _hostController.text.trim(),
      port: _portController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      database: _isOracle
          ? databaseValue
          : (databaseValue.isNotEmpty
              ? databaseValue
              : (_selectedProvider == DatabaseProvider.postgresql
                  ? 'postgres'
                  : 'master')),
      serviceName: _isOracle
          ? _serviceNameController.text.trim().isEmpty
              ? null
              : _serviceNameController.text.trim()
          : null,
      sid: _isOracle
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


  Future<void> _openProviderMain(ConnectionRequest request) async {
    Widget screen;
    switch (request.provider) {
      case DatabaseProvider.sqlServer:
        screen = SqlServerMain(connection: request);
        break;
      case DatabaseProvider.postgresql:
        screen = PostgreSqlMain(connection: request);
        break;
      case DatabaseProvider.oracle:
        screen = OracleMain(connection: request);
        break;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final request = _buildRequest();

    setState(() {
      _loading = true;
      _statusMessage = null;
      _statusSuccess = null;
    });

    try {
      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      setState(() {
        _statusSuccess = result.success;
        _statusMessage = result.durationMs == null
            ? result.message
            : '${result.message} (${result.durationMs} ms)';
      });

      if (!result.success) {
        return;
      }

      final connectionId =
          _editingConnectionId ?? DateTime.now().millisecondsSinceEpoch.toString();

      await _storageService.saveConnection(
        request,
        existingId: connectionId,
      );
      await _storageService.setActiveConnectionId(connectionId);

      if (!mounted) return;
      await _openProviderMain(request);
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


  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final request = _buildRequest();
    final connectionId =
        _editingConnectionId ?? DateTime.now().millisecondsSinceEpoch.toString();

    await _storageService.saveConnection(
      request,
      existingId: connectionId,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditing ? 'Connection updated.' : 'Connection saved.',
        ),
      ),
    );

    Navigator.of(context).pop(true);
  }

  TextInputAction _actionForField(String fieldKey) {
    switch (fieldKey) {
      case 'name':
      case 'host':
      case 'username':
      case 'password':
        return TextInputAction.next;
      case 'database':
      case 'sid':
        return TextInputAction.done;
      case 'serviceName':
      case 'port':
        return TextInputAction.next;
      default:
        return TextInputAction.next;
    }
  }

  void _submitField(String fieldKey) {
    switch (fieldKey) {
      case 'name':
        _hostFocus.requestFocus();
        break;
      case 'host':
        _usernameFocus.requestFocus();
        break;
      case 'username':
        _passwordFocus.requestFocus();
        break;
      case 'password':
        FocusScope.of(context).unfocus();
        break;
      case 'port':
        if (_isOracle) {
          _serviceNameFocus.requestFocus();
        } else {
          _databaseFocus.requestFocus();
        }
        break;
      case 'database':
        FocusScope.of(context).unfocus();
        break;
      case 'serviceName':
        _sidFocus.requestFocus();
        break;
      case 'sid':
        FocusScope.of(context).unfocus();
        break;
      default:
        FocusScope.of(context).unfocus();
        break;
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFF203454),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3EA5FF), width: 1.4),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String fieldKey,
    required String label,
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: _actionForField(fieldKey),
      onFieldSubmitted: (_) => _submitField(fieldKey),
      validator: validator,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildAdSection() {
    if (_bannerAd != null) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: Center(
          child: SizedBox(
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF132238),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'Ad banner area',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  @override
  void dispose() {
    _apiService.dispose();
    _bannerAd?.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serviceNameController.dispose();
    _sidController.dispose();
    _nameFocus.dispose();
    _hostFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _databaseFocus.dispose();
    _serviceNameFocus.dispose();
    _sidFocus.dispose();
    _portFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Connection' : 'New Connection'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: DatabaseProvider.values.map((provider) {
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: provider == DatabaseProvider.oracle ? 0 : 10,
                              ),
                              child: SizedBox(
                                height: 76,
                                child: ProviderSelectorCard(
                                  provider: provider,
                                  selected: provider == _selectedProvider,
                                  onTap: () => _onProviderSelected(provider),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        fieldKey: 'name',
                        label: 'Connection Name',
                        hint: 'Enter Name',
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Enter a name for this connection'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _hostController,
                        focusNode: _hostFocus,
                        fieldKey: 'host',
                        label: 'Host',
                        hint: 'Hostname / IP',
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        fieldKey: 'username',
                        label: 'Username',
                        hint: 'Enter Username',
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        fieldKey: 'password',
                        label: 'Password',
                        hint: '••••••••',
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
                      Theme(
                        data: theme.copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text(
                            'Advanced settings',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          initiallyExpanded: _showAdvanced,
                          onExpansionChanged: (value) {
                            setState(() => _showAdvanced = value);
                          },
                          children: [
                            const SizedBox(height: 4),
                            _buildTextField(
                              controller: _portController,
                              focusNode: _portFocus,
                              fieldKey: 'port',
                              label: 'Port',
                              hint: _selectedProvider.defaultPort,
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
                            const SizedBox(height: 14),
                            if (!_isOracle)
                              _buildTextField(
                                controller: _databaseController,
                                focusNode: _databaseFocus,
                                fieldKey: 'database',
                                label: 'Database (Optional)',
                                hint: _selectedProvider == DatabaseProvider.postgresql
                                    ? 'postgres'
                                    : 'master',
                              ),
                            if (_isOracle) ...[
                              _buildTextField(
                                controller: _serviceNameController,
                                focusNode: _serviceNameFocus,
                                fieldKey: 'serviceName',
                                label: 'Service Name',
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
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _sidController,
                                focusNode: _sidFocus,
                                fieldKey: 'sid',
                                label: 'SID',
                                hint: 'xe',
                              ),
                            ],
                            if (_selectedProvider == DatabaseProvider.sqlServer) ...[
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Encrypt connection'),
                                value: _encrypt,
                                onChanged: (value) => setState(() => _encrypt = value),
                              ),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Trust server certificate'),
                                value: _trustServerCertificate,
                                onChanged: (value) =>
                                    setState(() => _trustServerCertificate = value),
                              ),
                            ],
                          ],
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
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : _testConnection,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2D8CFF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.link_rounded),
                                label: const Text(
                                  'Test',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : _saveConnection,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D4D3C),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  _isEditing ? Icons.save_as_rounded : Icons.save_rounded,
                                ),
                                label: Text(
                                  _isEditing ? 'Update' : 'Save',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildAdSection(),
            ),
          ],
        ),
      ),
    );
  }
}
