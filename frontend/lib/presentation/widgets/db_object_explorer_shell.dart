import 'package:dbpilot/models/database_provider.dart';
import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../services/connection_api_service.dart';

enum DbObjectCategory { tables, views, procedures, functions, triggers, extensions }

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
  final List<DbColumnInfo> columns;
  final String? previewQuery;
  final String? objectType;

  DbExplorerObject copyWith({
    String? name,
    String? subtitle,
    DbObjectCategory? category,
    List<DbColumnInfo>? columns,
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
  late final ConnectionApiService _apiService;

  List<DbCategoryGroup> _categories = [];
  DbObjectCategory? _activeCategory;
  DbExplorerObject? _selectedObject;
  bool _loading = true;
  bool _loadingStructure = false;
  String? _errorMessage;

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
    }
  }

  String _defaultQuery(DbExplorerObject object) {
    final objectType = (object.objectType ?? '').toLowerCase();
    if (objectType == 'procedure') {
      return object.previewQuery ?? 'EXEC ${object.name};';
    }
    if (widget.connection.provider.apiValue == 'postgresql') {
      return object.previewQuery ?? 'SELECT *\nFROM ${object.name}\nLIMIT 50;';
    }
    return object.previewQuery ?? 'SELECT TOP 50 *\nFROM [${object.name}];';
  }

  Future<void> _loadStructure(DbExplorerObject object) async {
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
            .map((item) => item.name == updated.name ? updated : item)
            .toList(),
      );
    }).toList();
    _categories = newCategories;
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

  Future<void> _showPreview(DbExplorerObject object) async {
    if (!widget.loadFromBackend) {
      _showInfoSnackBar('Preview no disponible todavía para Oracle.');
      return;
    }

    try {
      final preview = await _apiService.getObjectPreview(
        widget.connection,
        object.name,
        object.objectType ?? _objectTypeFromCategory(object.category),
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
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (preview.columns.isEmpty)
                    const Text('No hay filas para mostrar.')
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

  @override
  void dispose() {
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
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
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
            _loadStructure(item);
          }
        },
        leading: CircleAvatar(
          backgroundColor: colors.primary.withOpacity(0.14),
          foregroundColor: colors.primary,
          child: Icon(_iconForCategory(item.category)),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _buildStructureTable(theme, colors, panelColor, item.name == _selectedObject?.name ? (_selectedObject ?? item) : item),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showPreview(item),
                  icon: const Icon(Icons.table_chart_rounded),
                  label: const Text('Ver datos'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showInfoSnackBar(_defaultQuery(item)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Run Query'),
                ),
              ),
            ],
          ),
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
          'Selecciona un objeto para ver estructura o query.',
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
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selected.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
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
                  'Consulta de ejemplo',
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
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.cleaning_services_rounded),
                      label: const Text('Limpiar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showPreview(selected),
                      icon: const Icon(Icons.table_chart_rounded),
                      label: const Text('Preview'),
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
                  'Estructura',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${item.columns.length} columnas',
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
                'No hay columnas disponibles todavía.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else
            ...item.columns.map(
              (col) => ListTile(
                dense: true,
                title: Text(
                  col.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(col.type),
                trailing: col.flag == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          col.flag!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
