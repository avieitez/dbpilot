import 'package:dbpilot/models/database_provider.dart';
import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../services/connection_api_service.dart';

import '../../core/strings/strings.dart';
import '../screens/query_editor/query_editor_screen.dart';

enum DbObjectCategory {
  tables,
  views,
  procedures,
  functions,
  triggers,
  extensions,
  materializedViews,
  packages,
  sequences,
}

class DbExplorerObject {
  const DbExplorerObject({
    required this.name,
    required this.subtitle,
    required this.category,
    this.columns = const [],
    this.previewQuery,
    this.objectType,
    this.schemaName,
    this.defaultQuery,
    this.parameters = const [],
    this.parametersLoaded = false,
    this.isDemo = false,
  });

  final String name;
  final String subtitle;
  final DbObjectCategory category;
  final List<DbColumnInfo> columns;
  final String? previewQuery;
  final String? objectType;
  final String? schemaName;
  final String? defaultQuery;
  final List<DbObjectParameterInfo> parameters;
  final bool parametersLoaded;
  final bool isDemo;

  String get qualifiedName =>
      schemaName == null || schemaName!.trim().isEmpty
          ? name
          : '${schemaName!}.$name';

  String get effectiveQuery => previewQuery ?? defaultQuery ?? '';

  DbExplorerObject copyWith({
    String? name,
    String? subtitle,
    DbObjectCategory? category,
    List<DbColumnInfo>? columns,
    String? previewQuery,
    String? objectType,
    String? schemaName,
    String? defaultQuery,
    List<DbObjectParameterInfo>? parameters,
    bool? parametersLoaded,
    bool? isDemo,
  }) {
    return DbExplorerObject(
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      columns: columns ?? this.columns,
      previewQuery: previewQuery ?? this.previewQuery,
      objectType: objectType ?? this.objectType,
      schemaName: schemaName ?? this.schemaName,
      defaultQuery: defaultQuery ?? this.defaultQuery,
      parameters: parameters ?? this.parameters,
      parametersLoaded: parametersLoaded ?? this.parametersLoaded,
      isDemo: isDemo ?? this.isDemo,
    );
  }
}


class DbColumnInfo {
  const DbColumnInfo({
    required this.name,
    required this.type,
    this.flag,
  });

  final String name;
  final String type;
  final String? flag;
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
  final FocusNode _searchFocusNode = FocusNode();
  late final ConnectionApiService _apiService;

  List<DbCategoryGroup> _categories = [];
  DbObjectCategory? _activeCategory;
  DbExplorerObject? _selectedObject;
  bool _loading = true;
  bool _loadingStructure = false;
  String? _errorMessage;
  final Set<String> _visibleStructureKeys = <String>{};

  List<DbExplorerObject> get _activeItems {
    if (_activeCategory == null) return [];
    final group = _categories.where((g) => g.category == _activeCategory).firstOrNull;
    final items = group?.items ?? [];
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return items;

    return items
        .where((item) =>
            item.name.toLowerCase().contains(term) ||
            item.subtitle.toLowerCase().contains(term))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _apiService = ConnectionApiService();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
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
                      schemaName: item.schemaName,
                      defaultQuery: item.defaultQuery,
                      previewQuery: item.defaultQuery,
                      isDemo: item.isDemo,
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

  void _setCategories(List<DbCategoryGroup> value) {
    final firstCategory = value.isNotEmpty ? value.first.category : null;
    final firstItems = value.isNotEmpty ? value.first.items : <DbExplorerObject>[];
    setState(() {
      _categories = value;
      _activeCategory = firstCategory;
      _selectedObject = firstItems.isNotEmpty ? firstItems.first : null;
      _loading = false;
      _errorMessage = null;
    });

    if (_selectedObject != null && widget.loadFromBackend) {
      _loadStructure(_selectedObject!);
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
      case 'extensions':
        return DbObjectCategory.extensions;
      case 'materialized_views':
      case 'materializedviews':
      case 'materialized views':
        return DbObjectCategory.materializedViews;
      case 'packages':
        return DbObjectCategory.packages;
      case 'sequences':
        return DbObjectCategory.sequences;
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
      case DbObjectCategory.materializedViews:
        return Icons.view_agenda_rounded;
      case DbObjectCategory.packages:
        return Icons.inventory_2_rounded;
      case DbObjectCategory.sequences:
        return Icons.format_list_numbered_rounded;        
    }
  }

  String _defaultQuery(DbExplorerObject object) {
    final objectType = (object.objectType ?? _objectTypeFromCategory(object.category))
        .toLowerCase()
        .replaceAll(' ', '_');
    final schema = object.schemaName?.trim();
    final provider = widget.connection.provider;

    switch (provider) {
      case DatabaseProvider.sqlServer:
        final qualified = _sqlServerQualifiedName(object.name, schema);
        if (objectType == 'procedure' || objectType == 'stored_procedure') return 'EXEC $qualified;';
        if (objectType == 'function') return 'SELECT *\nFROM $qualified();';
        if (objectType == 'trigger') return '-- Trigger $qualified. Open definition to inspect trigger source.';
        return 'SELECT *\nFROM $qualified;';
      case DatabaseProvider.postgresql:
        final qualified = _quotedQualifiedName(object.name, schema ?? 'public', '"');
        if (objectType == 'procedure' || objectType == 'stored_procedure') return 'CALL $qualified();';
        if (objectType == 'function') return 'SELECT *\nFROM $qualified();';
        if (objectType == 'extension') return '-- Extension ${object.name}. No preview query available.';
        return 'SELECT *\nFROM $qualified;';
      case DatabaseProvider.oracle:
        final qualified = _oracleQualifiedName(object.name, schema);
        if (objectType == 'procedure' || objectType == 'stored_procedure') return 'BEGIN\n  $qualified;\nEND;';
        if (objectType == 'function') return 'SELECT $qualified() AS VALUE\nFROM dual;';
        if (objectType == 'package') return '-- Package $qualified. Open definition to inspect package source.';
        if (objectType == 'trigger') return '-- Trigger $qualified. Open definition to inspect trigger source.';
        if (objectType == 'sequence') return 'SELECT $qualified.NEXTVAL AS NEXT_VALUE\nFROM dual;';
        return 'SELECT *\nFROM $qualified;';
    }
  }

  String _sqlServerQualifiedName(String objectName, String? schemaName) {
    String clean(String value) => value.replaceAll('[', '').replaceAll(']', '').trim();
    final schema = clean((schemaName == null || schemaName.trim().isEmpty) ? 'dbo' : schemaName);
    return '[${clean(schema)}].[${clean(objectName)}]';
  }

  String _quotedQualifiedName(String objectName, String schemaName, String quote) {
    String clean(String value) => value.replaceAll(quote, quote + quote).trim();
    final schema = clean(schemaName);
    final name = clean(objectName);
    return schema.isEmpty ? '$quote$name$quote' : '$quote$schema$quote.$quote$name$quote';
  }

  String _oracleQualifiedName(String objectName, String? schemaName) {
    final schema = schemaName?.trim().toUpperCase() ?? '';
    final name = objectName.trim().toUpperCase();
    return _quotedQualifiedName(name, schema, '"');
  }

  Future<void> _loadStructure(DbExplorerObject object) async {
    await _loadParameters(object);
    object = _findObject(object) ?? object;

    if (!widget.loadFromBackend) {
      setState(() => _selectedObject = object);
      return;
    }

    setState(() {
      _selectedObject = object;
      _loadingStructure = true;
    });

    try {
      final result = await _apiService.getObjectStructure(
        widget.connection,
        object.name,
        object.objectType ?? _objectTypeFromCategory(object.category),
        schemaName: object.schemaName,
      );

      final updated = object.copyWith(
        columns: result.columns
            .map(
              (col) => DbColumnInfo(
                name: col.name,
                type: col.dataType,
                flag: col.flag,
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

  void _replaceObject(DbExplorerObject updated) {
    final newCategories = _categories.map((group) {
      if (group.category != updated.category) return group;
      return DbCategoryGroup(
        category: group.category,
        label: group.label,
        items: group.items
            .map((item) => item.name == updated.name && item.schemaName == updated.schemaName ? updated : item)
            .toList(),
      );
    }).toList();
    _categories = newCategories;
  }

  DbExplorerObject? _findObject(DbExplorerObject object) {
    final key = _objectKey(object);
    for (final group in _categories) {
      for (final item in group.items) {
        if (_objectKey(item) == key) return item;
      }
    }
    return null;
  }

  String _objectTypeFromCategory(DbObjectCategory category) {
    switch (category) {
      case DbObjectCategory.tables:
        return AppStrings.table;
      case DbObjectCategory.views:
        return AppStrings.view;
      case DbObjectCategory.procedures:
        return AppStrings.procedure;
      case DbObjectCategory.functions:
        return AppStrings.function;
      case DbObjectCategory.triggers:
        return AppStrings.trigger;
      case DbObjectCategory.extensions:
        return AppStrings.extension;
      case DbObjectCategory.materializedViews:
        return 'materialized_view';
      case DbObjectCategory.packages:
        return 'package';
      case DbObjectCategory.sequences:
        return 'sequence';
    }
  }


  int _columnCountForObject(DbExplorerObject item) {
    if (item.columns.isNotEmpty) return item.columns.length;

    final match = RegExp(r'(\d+)\s+columns?', caseSensitive: false)
        .firstMatch(item.subtitle);

    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 0;
    }

    return 0;
  }

  String _objectSubtitle(DbExplorerObject item) {
    final parts = <String>[];

    final schema = item.schemaName?.trim();
    if (schema != null && schema.isNotEmpty) {
      parts.add(schema);
    }

    final columnCount = _columnCountForObject(item);
    if (columnCount > 0) {
      parts.add('$columnCount columns');
    }

    final pkMatch = RegExp(r'PK\s*[:·]\s*([A-Za-z0-9_]+)', caseSensitive: false)
        .firstMatch(item.subtitle);

    if (pkMatch != null) {
      parts.add('PK: ${pkMatch.group(1)}');
    }

    return parts.isEmpty ? item.subtitle : parts.join(' · ');
  }



  String _objectKey(DbExplorerObject item) {
    final schema = item.schemaName?.trim() ?? '';
    final type = item.objectType?.trim() ?? _objectTypeFromCategory(item.category);
    return '$type|$schema|${item.name}';
  }

  bool _isStructureVisible(DbExplorerObject item) {
    return _visibleStructureKeys.contains(_objectKey(item));
  }

  Future<void> _toggleStructure(DbExplorerObject item) async {
    final key = _objectKey(item);

    if (_visibleStructureKeys.contains(key)) {
      setState(() => _visibleStructureKeys.remove(key));
      return;
    }

    await _loadStructure(item);

    if (!mounted) return;

    setState(() {
      _visibleStructureKeys.add(key);
    });
  }


  Future<void> _showPreview(DbExplorerObject object) async {
    if (!widget.loadFromBackend) {
      _showInfoSnackBar('Preview is not available yet for Oracle.');
      return;
    }

    try {
      final preview = await _apiService.getObjectPreview(
        widget.connection,
        object.name,
        object.objectType ?? _objectTypeFromCategory(object.category),
        schemaName: object.schemaName,
      );

      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${object.name} · Preview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (preview.columns.isEmpty)
                    const Text(AppStrings.norows)
                  else
                    SizedBox(
                      height: 320,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: preview.columns
                                .map((col) => DataColumn(label: Text(col)))
                                .toList(),
                            rows: preview.rows
                                .map(
                                  (row) => DataRow(
                                    cells: row
                                        .map(
                                          (value) => DataCell(
                                            Text(value?.toString() ?? 'null'),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      _showInfoSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openQueryEditor(DbExplorerObject object) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QueryEditorScreen(
          connection: widget.connection,
          providerLabel: widget.providerLabel,
          connectionSummary: widget.connectionSummary,
          initialSql: _defaultQuery(object),
          objectName: object.name,
          objectType: object.objectType ?? _objectTypeFromCategory(object.category),
          schemaName: object.schemaName,
          objectColumns: object.columns.map((column) => column.name).toList(),
        ),
      ),
    );
  }


  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeItems = _activeItems;
    final selected = activeItems.any((item) => item.name == _selectedObject?.name)
        ? activeItems.firstWhere((item) => item.name == _selectedObject?.name)
        : (activeItems.isNotEmpty ? activeItems.first : _selectedObject);

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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;

                      if (isWide) {
                        return Row(
                          children: [
                            SizedBox(
                              width: 320,
                              child: _buildSidebar(theme, colors, panelColor, activeItems, selected),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: _buildDetail(theme, colors, panelColor, selected),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildHeader(theme, colors, panelColor),
                          _buildTabs(theme, colors),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              children: [
                                ...activeItems.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _buildMobileCard(theme, colors, panelColor, item),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _errorMessage ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
  ) {
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
              border: Border.all(
                color: colors.outlineVariant.withOpacity(0.45),
              ),
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
            focusNode: _searchFocusNode,
            autofocus: false,
            decoration: InputDecoration(
              hintText: AppStrings.search,
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
            onSelected: (_) => setState(() {
              _activeCategory = group.category;
              _selectedObject = group.items.isNotEmpty ? group.items.first : null;
              if (_selectedObject != null) {
                _loadStructure(_selectedObject!);
              }
            }),
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

  Widget _buildSidebar(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
    List<DbExplorerObject> activeItems,
    DbExplorerObject? selected,
  ) {
    return Column(
      children: [
        _buildHeader(theme, colors, panelColor),
        _buildTabs(theme, colors),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: activeItems.length,
            itemBuilder: (context, index) {
              final item = activeItems[index];
              final isSelected = selected?.name == item.name;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: isSelected
                      ? colors.primary.withOpacity(0.12)
                      : panelColor,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _loadStructure(item),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? colors.primary.withOpacity(0.6)
                              : colors.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconForCategory(item.category),
                            color: isSelected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _objectSubtitle(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                if (item.parameters.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _ParameterChips(parameters: item.parameters),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCard(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
    DbExplorerObject item,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: ExpansionTile(
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        onExpansionChanged: (expanded) {
          if (expanded) {
            setState(() => _selectedObject = item);
          }
        },
        leading: CircleAvatar(
          backgroundColor: colors.primary.withOpacity(0.14),
          foregroundColor: colors.primary,
          child: Icon(_iconForCategory(item.category)),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _objectSubtitle(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (item.parameters.isNotEmpty) ...[
            _ParameterChips(parameters: item.parameters),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _openQueryEditor(item),
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.lightBlueAccent,
                  ),
                  label: const Text(
                    AppStrings.runQuery,
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _toggleStructure(item),
                  icon: const Icon(
                    Icons.account_tree_rounded,
                    color: Colors.greenAccent,
                  ),
                  label: const Text(
                    AppStrings.structure,
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isStructureVisible(item)) ...[
            const SizedBox(height: 12),
            _buildStructureTable(
              theme,
              colors,
              panelColor,
              item.name == _selectedObject?.name ? (_selectedObject ?? item) : item,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail(
    ThemeData theme,
    ColorScheme colors,
    Color panelColor,
    DbExplorerObject? selected,
  ) {
    if (selected == null) {
      return Center(
        child: Text(
          'Select an object to view its structure or query.',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (selected.parameters.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ParameterChips(parameters: selected.parameters),
          ],
          const SizedBox(height: 16),
          if (_loadingStructure) const LinearProgressIndicator(),
          if (_loadingStructure) const SizedBox(height: 12),
          _buildStructureTable(theme, colors, panelColor, selected),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.outlineVariant.withOpacity(0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.exampleQuery,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _defaultQuery(selected),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openQueryEditor(selected),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(AppStrings.runQuery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _loadStructure(selected),
                        icon: const Icon(Icons.account_tree_rounded),
                        label: const Text(AppStrings.structure),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  String _formatColumnType(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    return clean.toUpperCase();
  }

  bool _isPrimaryKey(DbColumnInfo col) {
    return (col.flag ?? '').trim().toUpperCase() == 'PK';
  }

  bool _isForeignKey(DbColumnInfo col) {
    return (col.flag ?? '').trim().toUpperCase() == 'FK';
  }

  bool _supportsParameters(DbExplorerObject item) {
    final type = (item.objectType ?? _objectTypeFromCategory(item.category)).toLowerCase();
    return type == 'procedure' || type == 'stored_procedure' || type == 'function';
  }

  Future<void> _loadParameters(DbExplorerObject object) async {
    if (!widget.loadFromBackend || !_supportsParameters(object) || object.parametersLoaded) {
      return;
    }

    try {
      final result = await _apiService.getObjectParameters(
        widget.connection,
        object.name,
        object.objectType ?? _objectTypeFromCategory(object.category),
        schemaName: object.schemaName,
      );
      final updated = object.copyWith(
        parameters: result.parameters,
        parametersLoaded: true,
      );

      _replaceObject(updated);
      if (!mounted) return;
      setState(() {
        if (_selectedObject != null && _objectKey(_selectedObject!) == _objectKey(object)) {
          _selectedObject = updated;
        }
      });
    } catch (_) {
      final updated = object.copyWith(parametersLoaded: true);
      _replaceObject(updated);
      if (!mounted) return;
      setState(() {
        if (_selectedObject != null && _objectKey(_selectedObject!) == _objectKey(object)) {
          _selectedObject = updated;
        }
      });
    }
  }

  Widget _buildStructureTable(
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
        border: Border.all(
          color: colors.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  AppStrings.structure,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_columnCountForObject(item)} ${AppStrings.columns}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (item.columns.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppStrings.notStructure,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            ...item.columns.map(
              (col) {
                final typeLabel = _formatColumnType(col.type);
                final isPk = _isPrimaryKey(col);

                return ListTile(
                  dense: true,
                  title: Text(
                    col.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: typeLabel.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            typeLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                  trailing: isPk
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.shade400,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'PK',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ParameterChips extends StatelessWidget {
  const _ParameterChips({required this.parameters});

  final List<DbObjectParameterInfo> parameters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: parameters.map((parameter) {
        final direction = _directionLabel(parameter.direction);
        final color = _directionColor(direction);
        final name = parameter.name.isEmpty ? 'RETURN' : parameter.name;
        final defaultLabel = parameter.hasDefault == true ? ' = default' : '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.55)),
          ),
          child: Text(
            '$direction $name ${parameter.dataType}$defaultLabel',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _directionLabel(String? value) {
    final clean = (value ?? 'IN').trim().toUpperCase().replaceAll('OUTPUT', 'OUT');
    if (clean == 'IN/OUT' || clean == 'INOUT') return 'IN OUT';
    if (clean == 'RETURN') return 'OUT';
    if (clean == 'OUT' || clean == 'IN OUT') return clean;
    return 'IN';
  }

  Color _directionColor(String direction) {
    switch (direction) {
      case 'OUT':
        return Colors.orangeAccent;
      case 'IN OUT':
        return Colors.purpleAccent;
      default:
        return Colors.lightBlueAccent;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
