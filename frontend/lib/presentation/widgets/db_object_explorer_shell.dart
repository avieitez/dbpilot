import 'package:dbpilot/models/database_provider.dart';
import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../services/connection_api_service.dart' as api;

enum DbObjectCategory { tables, views, procedures, functions, triggers, extensions }
enum DbDetailTab { structure, data, query }

class DbExplorerObject {
  const DbExplorerObject({
    required this.name,
    required this.subtitle,
    required this.category,
    this.columns = const [],
    this.previewQuery,
    this.objectType,
  });

  final String name;
  final String subtitle;
  final DbObjectCategory category;
  final List<ExplorerColumnInfo> columns;
  final String? previewQuery;
  final String? objectType;

  DbExplorerObject copyWith({
    String? name,
    String? subtitle,
    DbObjectCategory? category,
    List<ExplorerColumnInfo>? columns,
    String? previewQuery,
    String? objectType,
  }) {
    return DbExplorerObject(
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      columns: columns ?? this.columns,
      previewQuery: previewQuery ?? this.previewQuery,
      objectType: objectType ?? this.objectType,
    );
  }
}

class ExplorerColumnInfo {
  const ExplorerColumnInfo({
    required this.name,
    required this.type,
    this.flag,
    this.isNullable,
  });

  final String name;
  final String type;
  final String? flag;
  final bool? isNullable;
}

class DbCategoryGroup {
  const DbCategoryGroup({
    required this.category,
    required this.label,
    required this.items,
  });

  final DbObjectCategory category;
  final String label;
  final List<DbExplorerObject> items;
}

class DbObjectExplorerShell extends StatefulWidget {
  const DbObjectExplorerShell({
    super.key,
    required this.providerLabel,
    required this.connectionSummary,
    required this.connection,
    this.initialCategories = const [],
    this.loadFromBackend = true,
  });

  final String providerLabel;
  final String connectionSummary;
  final ConnectionRequest connection;
  final List<DbCategoryGroup> initialCategories;
  final bool loadFromBackend;

  @override
  State<DbObjectExplorerShell> createState() => _DbObjectExplorerShellState();
}

class _DbObjectExplorerShellState extends State<DbObjectExplorerShell> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  late final api.ConnectionApiService _apiService;

  List<DbCategoryGroup> _categories = [];
  DbObjectCategory? _activeCategory;
  DbExplorerObject? _selectedObject;
  DbDetailTab _activeDetailTab = DbDetailTab.structure;

  bool _loading = true;
  bool _loadingStructure = false;
  bool _loadingData = false;
  bool _runningQuery = false;
  String? _errorMessage;

  api.DbObjectPreviewResult? _preview;
  api.QueryExecuteResult? _queryResult;

  List<DbExplorerObject> get _activeItems {
    if (_activeCategory == null) return [];
    final group = _findGroup(_activeCategory!);
    final items = group?.items ?? [];
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return items;

    return items
        .where(
          (item) =>
              item.name.toLowerCase().contains(term) ||
              item.subtitle.toLowerCase().contains(term),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _apiService = api.ConnectionApiService();
    _searchController.addListener(() => setState(() {}));
    _initialize();
  }

  Future<void> _initialize() async {
    if (!widget.loadFromBackend) {
      _setCategories(widget.initialCategories);
      return;
    }

    try {
      final groups = await _apiService.getDbObjects(widget.connection);
      final mapped = groups
          .map(
            (group) => DbCategoryGroup(
              category: _categoryFromKey(group.key),
              label: group.label,
              items: group.items
                  .map(
                    (item) => DbExplorerObject(
                      name: item.name,
                      subtitle: item.subtitle,
                      category: _categoryFromObjectType(item.objectType),
                      objectType: item.objectType,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();

      _setCategories(mapped);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  DbCategoryGroup? _findGroup(DbObjectCategory category) {
    for (final group in _categories) {
      if (group.category == category) return group;
    }
    return null;
  }

  void _setCategories(List<DbCategoryGroup> value) {
    final firstCategory = value.isNotEmpty ? value.first.category : null;
    final firstItems = value.isNotEmpty ? value.first.items : <DbExplorerObject>[];

    setState(() {
      _categories = value;
      _activeCategory = firstCategory;
      _selectedObject = firstItems.isNotEmpty ? firstItems.first : null;
      _loading = false;
      _errorMessage = null;
      _activeDetailTab = DbDetailTab.structure;
    });

    if (_selectedObject != null && widget.loadFromBackend) {
      _selectObject(_selectedObject!, tab: DbDetailTab.structure);
    }
  }

  DbObjectCategory _categoryFromKey(String key) {
    switch (key.toLowerCase()) {
      case 'tables':
        return DbObjectCategory.tables;
      case 'views':
        return DbObjectCategory.views;
      case 'procedures':
        return DbObjectCategory.procedures;
      case 'functions':
        return DbObjectCategory.functions;
      case 'triggers':
        return DbObjectCategory.triggers;
      default:
        return DbObjectCategory.extensions;
    }
  }

  DbObjectCategory _categoryFromObjectType(String objectType) {
    switch (objectType.toLowerCase()) {
      case 'table':
        return DbObjectCategory.tables;
      case 'view':
        return DbObjectCategory.views;
      case 'procedure':
        return DbObjectCategory.procedures;
      case 'function':
        return DbObjectCategory.functions;
      case 'trigger':
        return DbObjectCategory.triggers;
      default:
        return DbObjectCategory.extensions;
    }
  }

  String _objectTypeFromCategory(DbObjectCategory category) {
    switch (category) {
      case DbObjectCategory.tables:
        return 'table';
      case DbObjectCategory.views:
        return 'view';
      case DbObjectCategory.procedures:
        return 'procedure';
      case DbObjectCategory.functions:
        return 'function';
      case DbObjectCategory.triggers:
        return 'trigger';
      case DbObjectCategory.extensions:
        return 'extension';
    }
  }

  IconData _iconForCategory(DbObjectCategory category) {
    switch (category) {
      case DbObjectCategory.tables:
        return Icons.table_rows_rounded;
      case DbObjectCategory.views:
        return Icons.remove_red_eye_outlined;
      case DbObjectCategory.procedures:
        return Icons.settings_suggest_rounded;
      case DbObjectCategory.functions:
        return Icons.functions_rounded;
      case DbObjectCategory.triggers:
        return Icons.bolt_rounded;
      case DbObjectCategory.extensions:
        return Icons.extension_rounded;
    }
  }

  String _defaultQuery(DbExplorerObject object) {
    final objectType = (object.objectType ?? '').toLowerCase();

    if (object.previewQuery != null && object.previewQuery!.trim().isNotEmpty) {
      return object.previewQuery!;
    }

    if (objectType == 'procedure') {
      return '-- Procedures con parametros vendran en el siguiente paso\n-- EXEC ${object.name};';
    }

    if (widget.connection.provider.apiValue == 'postgresql') {
      return 'SELECT *\nFROM ${object.name}\nLIMIT 50;';
    }

    return 'SELECT TOP 50 *\nFROM [${object.name}];';
  }

  Future<void> _selectObject(DbExplorerObject object, {DbDetailTab? tab}) async {
    setState(() {
      _selectedObject = object;
      _activeDetailTab = tab ?? _activeDetailTab;
      _preview = null;
      _queryResult = null;
      _queryController.text = _defaultQuery(object);
    });

    if (object.columns.isEmpty && widget.loadFromBackend) {
      await _loadStructure(object);
    }

    if ((tab ?? _activeDetailTab) == DbDetailTab.data) {
      await _loadPreview(object);
    }
  }

  Future<void> _loadStructure(DbExplorerObject object) async {
    if (!widget.loadFromBackend) return;

    setState(() {
      _loadingStructure = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.getObjectStructure(
        widget.connection,
        object.name,
        object.objectType ?? _objectTypeFromCategory(object.category),
      );

      final updated = object.copyWith(
        columns: result.columns
            .map(
              (col) => ExplorerColumnInfo(
                name: col.name,
                type: col.dataType,
                flag: col.flag,
                isNullable: col.isNullable,
              ),
            )
            .toList(),
      );

      _replaceObject(updated);
      if (!mounted) return;
      setState(() {
        _selectedObject = updated;
        _loadingStructure = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingStructure = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadPreview(DbExplorerObject object) async {
    final type = (object.objectType ?? _objectTypeFromCategory(object.category)).toLowerCase();
    if (type != 'table' && type != 'view') {
      _showInfoSnackBar('Preview disponible solo para tablas y vistas por ahora.');
      return;
    }

    setState(() {
      _activeDetailTab = DbDetailTab.data;
      _loadingData = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.getObjectPreview(
        widget.connection,
        object.name,
        type,
        limit: 50,
      );

      if (!mounted) return;
      setState(() {
        _preview = result;
        _loadingData = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingData = false);
      _showInfoSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _runQuery() async {
    final sql = _queryController.text.trim();
    if (sql.isEmpty) {
      _showInfoSnackBar('Escribe una query primero. La telepatia aun no esta implementada.');
      return;
    }

    setState(() {
      _runningQuery = true;
      _queryResult = null;
    });

    try {
      final result = await _apiService.executeQuery(widget.connection, sql, limit: 100);
      if (!mounted) return;
      setState(() {
        _queryResult = result;
        _runningQuery = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _runningQuery = false);
      _showInfoSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _replaceObject(DbExplorerObject updated) {
    _categories = _categories.map((group) {
      if (group.category != updated.category) return group;
      return DbCategoryGroup(
        category: group.category,
        label: group.label,
        items: group.items.map((item) => item.name == updated.name ? updated : item).toList(),
      );
    }).toList();
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _queryController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final panelColor = Color.alphaBlend(
      colors.surface.withOpacity(0.88),
      colors.surfaceContainerHighest.withOpacity(0.32),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.providerLabel),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState(theme)
                : Column(
                    children: [
                      _buildHeader(theme, colors, panelColor),
                      _buildTabs(theme, colors),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          children: [
                            ..._activeItems.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildObjectCard(theme, colors, panelColor, item),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Error desconocido',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _errorMessage = null;
                });
                _initialize();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colors, Color panelColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant.withOpacity(0.45)),
            ),
            child: Text(
              widget.connectionSummary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar tablas, vistas o procedimientos...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? const Icon(Icons.tune_rounded)
                  : IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(ThemeData theme, ColorScheme colors) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final group = _categories[index];
          final selected = group.category == _activeCategory;

          return ChoiceChip(
            selected: selected,
            onSelected: (_) {
              final items = group.items;
              setState(() {
                _activeCategory = group.category;
                _selectedObject = items.isNotEmpty ? items.first : null;
                _activeDetailTab = DbDetailTab.structure;
                _preview = null;
                _queryResult = null;
              });
              if (_selectedObject != null) {
                _selectObject(_selectedObject!, tab: DbDetailTab.structure);
              }
            },
            avatar: Icon(
              _iconForCategory(group.category),
              size: 18,
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
            ),
            label: Text('${group.label} (${group.items.length})'),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _categories.length,
      ),
    );
  }

  Widget _buildObjectCard(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
    DbExplorerObject item,
  ) {
    final isSelected = _selectedObject?.name == item.name &&
        _selectedObject?.category == item.category;
    final shown = isSelected ? (_selectedObject ?? item) : item;

    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? colors.primary.withOpacity(0.45) : colors.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: isSelected,
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        onExpansionChanged: (expanded) {
          if (expanded) {
            _selectObject(item, tab: DbDetailTab.structure);
          }
        },
        leading: CircleAvatar(
          backgroundColor: colors.primary.withOpacity(0.14),
          foregroundColor: colors.primary,
          child: Icon(_iconForCategory(item.category)),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _buildDetailTabs(colors),
          const SizedBox(height: 12),
          if (_activeDetailTab == DbDetailTab.structure)
            _buildStructurePanel(theme, colors, panelColor, shown)
          else if (_activeDetailTab == DbDetailTab.data)
            _buildDataPanel(theme, colors, panelColor)
          else
            _buildQueryPanel(theme, colors, panelColor),
          const SizedBox(height: 12),
          _buildActions(shown),
        ],
      ),
    );
  }

  Widget _buildDetailTabs(ColorScheme colors) {
    Widget tab(DbDetailTab tab, String label, IconData icon) {
      final selected = _activeDetailTab == tab;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            final selectedObject = _selectedObject;
            setState(() => _activeDetailTab = tab);
            if (tab == DbDetailTab.data && selectedObject != null) {
              await _loadPreview(selectedObject);
            }
            if (tab == DbDetailTab.query && selectedObject != null) {
              _queryController.text = _defaultQuery(selectedObject);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colors.primary.withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          tab(DbDetailTab.structure, 'Estructura', Icons.account_tree_rounded),
          tab(DbDetailTab.data, 'Datos', Icons.table_chart_rounded),
          tab(DbDetailTab.query, 'Query', Icons.terminal_rounded),
        ],
      ),
    );
  }

  Widget _buildStructurePanel(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
    DbExplorerObject item,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text('Estructura', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_loadingStructure)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Text('${item.columns.length} columnas', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!_loadingStructure && item.columns.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No hay columnas disponibles todavia.', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            )
          else
            ...item.columns.map(
              (col) => ListTile(
                dense: true,
                title: Text(col.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text('${col.type}${col.isNullable == true ? ' · nullable' : ''}'),
                trailing: col.flag == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: colors.primary.withOpacity(0.14), borderRadius: BorderRadius.circular(999)),
                        child: Text(col.flag!, style: theme.textTheme.labelMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w800)),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataPanel(ThemeData theme, ColorScheme colors, Color panelColor) {
    if (_loadingData) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final preview = _preview;
    if (preview == null) {
      return _emptyPanel(theme, colors, 'Pulsa Ver datos para cargar las primeras 50 filas.');
    }

    return _resultGrid(theme, colors, preview.columns, preview.rows, 'Filas: ${preview.rowCount}');
  }

  Widget _buildQueryPanel(ThemeData theme, ColorScheme colors, Color panelColor) {
    return Column(
      children: [
        TextField(
          controller: _queryController,
          minLines: 5,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'SELECT * FROM tabla...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _runningQuery ? null : () => _queryController.clear(),
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('Limpiar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _runningQuery ? null : _runQuery,
                icon: _runningQuery
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Ejecutar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_queryResult != null)
          _resultGrid(
            theme,
            colors,
            _queryResult!.columns,
            _queryResult!.rows,
            _queryResult!.message.isEmpty ? 'Filas: ${_queryResult!.rowCount}' : _queryResult!.message,
          ),
      ],
    );
  }

  Widget _emptyPanel(ThemeData theme, ColorScheme colors, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.4)),
      ),
      child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
    );
  }

  Widget _resultGrid(
    ThemeData theme,
    ColorScheme colors,
    List<String> columns,
    List<List<dynamic>> rows,
    String footer,
  ) {
    if (columns.isEmpty) {
      return _emptyPanel(theme, colors, 'No hay datos para mostrar.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(footer, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: columns.map((col) => DataColumn(label: Text(col))).toList(),
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: columns.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final value = idx < row.length ? row[idx] : null;
                          return DataCell(Text(value?.toString() ?? 'null'));
                        }).toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(DbExplorerObject object) {
    final type = (object.objectType ?? _objectTypeFromCategory(object.category)).toLowerCase();
    final canPreview = type == 'table' || type == 'view';

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: canPreview ? () => _loadPreview(object) : null,
            icon: const Icon(Icons.table_chart_rounded),
            label: const Text('Ver datos'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _activeDetailTab = DbDetailTab.query;
                _queryController.text = _defaultQuery(object);
              });
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Run Query'),
          ),
        ),
      ],
    );
  }
}
