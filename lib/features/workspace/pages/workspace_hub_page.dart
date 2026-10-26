import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'story_media_page.dart';
import 'story_editor_page.dart';
import 'codex_editor_page.dart';
import 'picme_studio_page.dart';

/// A ChatGPT-Projects-style hub with three sections: Katha, Codex, Picme.
///
/// Katha  - stories: title, last edited, word count. Opens the writing flow.
/// Codex  - code snippets / files the user keeps alongside a project.
/// Picme  - image projects (prompts, reference links).
///
/// Everything is stored locally in shared_preferences as JSON. No network.
class WorkspaceHubPage extends StatefulWidget {
  const WorkspaceHubPage({super.key, this.initialSection = 0});

  /// 0 = Katha, 1 = Codex, 2 = Picme.
  final int initialSection;

  @override
  State<WorkspaceHubPage> createState() => _WorkspaceHubPageState();
}

class _WorkspaceHubPageState extends State<WorkspaceHubPage> {
  static const List<String> _sections = <String>['Katha', 'Codex', 'Picme'];
  static const List<String> _storeKeys = <String>[
    'rino.hub.katha',
    'rino.hub.codex',
    'rino.hub.picme',
  ];

  late int _section = widget.initialSection.clamp(0, 2);
  final TextEditingController _search = TextEditingController();
  final Map<int, List<Map<String, String>>> _items = <int, List<Map<String, String>>>{};

  bool _loading = true;
  String _filter = 'all'; // 'all' | 'a' | 'b'

  /// Filters that actually mean something per section.
  static const Map<int, List<List<String>>> _filterSets = <int, List<List<String>>>{
    0: <List<String>>[<String>['all', 'All'], <String>['a', 'In progress'], <String>['b', 'Finished']],
    1: <List<String>>[<String>['all', 'All'], <String>['a', 'Snippets'], <String>['b', 'Files']],
    2: <List<String>>[<String>['all', 'All'], <String>['a', 'Prompts'], <String>['b', 'References']],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < _storeKeys.length; i++) {
      final String? raw = prefs.getString(_storeKeys[i]);
      List<Map<String, String>> parsed = <Map<String, String>>[];
      if (raw != null && raw.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
          parsed = decoded
              .map((dynamic e) => Map<String, String>.from(e as Map<dynamic, dynamic>))
              .toList();
        } catch (_) {
          parsed = <Map<String, String>>[];
        }
      }
      _items[i] = parsed;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save(int section) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeKeys[section], jsonEncode(_items[section] ?? <Map<String, String>>[]));
  }

  String _now() {
    final DateTime d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _create() async {
    final TextEditingController nameCtl = TextEditingController();
    final String label = _sections[_section];
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('New $label'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Name'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(nameCtl.text), child: const Text('Create')),
        ],
      ),
    );
    nameCtl.dispose();
    final String trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _items[_section] = <Map<String, String>>[
        <String, String>{
          'name': trimmed,
          'updated': _now(),
          'owner': 'mine',
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'tag': 'a',
          'meta': _section == 0 ? '0 words' : (_section == 1 ? 'code' : 'image project'),
        },
        ...(_items[_section] ?? <Map<String, String>>[]),
      ];
    });
    await _save(_section);
  }

  Future<void> _rename(int index) async {
    final List<Map<String, String>> list = _items[_section] ?? <Map<String, String>>[];
    final TextEditingController ctl = TextEditingController(text: list[index]['name']);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctl, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctl.text), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    final String trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    setState(() {
      list[index]['name'] = trimmed;
      list[index]['updated'] = _now();
    });
    await _save(_section);
  }

  Future<void> _delete(int index) async {
    setState(() {
      (_items[_section] ?? <Map<String, String>>[]).removeAt(index);
    });
    await _save(_section);
  }

  List<Map<String, String>> get _visible {
    final String q = _search.text.trim().toLowerCase();
    return (_items[_section] ?? <Map<String, String>>[]).where((Map<String, String> it) {
      if (_filter != 'all' && it['tag'] != _filter) return false;
      if (q.isEmpty) return true;
      return (it['name'] ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Map<String, String>> items = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(_sections[_section]),
        actions: <Widget>[
          IconButton(
            tooltip: 'New ${_sections[_section]}',
            onPressed: _create,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                // section switcher
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(value: 0, label: Text('Katha')),
                      ButtonSegment<int>(value: 1, label: Text('Codex')),
                      ButtonSegment<int>(value: 2, label: Text('Picme')),
                    ],
                    selected: <int>{_section},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<int> s) {
                      setState(() {
                        _section = s.first;
                        _filter = 'all';
                        _search.clear();
                      });
                    },
                  ),
                ),
                // filter chips
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: (_filterSets[_section] ?? <List<String>>[])
                        .map((List<String> f) => _chip(f[1], f[0]))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? _empty(cs)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext ctx, int i) {
                            final Map<String, String> it = items[i];
                            final int realIndex =
                                (_items[_section] ?? <Map<String, String>>[]).indexOf(it);
                            return Card(
                              elevation: 0,
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                onTap: () {
                                  if (_section == 0) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) {
                                          final String sid = it['id'] ?? (it['name'] ?? 'untitled');
                                          final String name = it['name'] ?? 'Untitled';
                                          if (_section == 0) {
                                            return StoryEditorPage(
                                                storyId: sid, storyTitle: name, chapter: 1);
                                          }
                                          if (_section == 1) {
                                            return CodexEditorPage(projectId: sid, title: name);
                                          }
                                          return PicmeStudioPage(projectId: sid, title: name);
                                        },
                                      ),
                                    );
                                  }
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _section == 0
                                        ? Icons.menu_book_outlined
                                        : (_section == 1 ? Icons.code : Icons.image_outlined),
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  it['name'] ?? 'Untitled',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(it['updated'] ?? ''),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (String v) {
                                    if (v == 'rename') _rename(realIndex);
                                    if (v == 'delete') _delete(realIndex);
                                  },
                                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
                                    PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text('New ${_sections[_section]}'),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(26)),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final bool on = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _section == 0
                  ? Icons.menu_book_outlined
                  : (_section == 1 ? Icons.code : Icons.image_outlined),
              size: 44,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No ${_sections[_section]} yet',
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the + button to create one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
