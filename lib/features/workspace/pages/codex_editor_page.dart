import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Codex — the coding surface, same shape as the Katha story surface.
///
/// Edit / Preview switcher in the app bar, monospace text, saved per project.
/// No network, no model calls: it is a place to keep and read code.
class CodexEditorPage extends StatefulWidget {
  const CodexEditorPage({super.key, required this.projectId, required this.title});

  final String projectId;
  final String title;

  @override
  State<CodexEditorPage> createState() => _CodexEditorPageState();
}

class _CodexEditorPageState extends State<CodexEditorPage> {
  final TextEditingController _ctl = TextEditingController();
  bool _loading = true;
  bool _preview = false;

  String get _key => 'rino.codex.${widget.projectId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ctl.text = p.getString(_key) ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_key, _ctl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _switch(bool preview) async {
    if (preview) await _save();
    if (!mounted) return;
    setState(() => _preview = preview);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Edit')),
                ButtonSegment<bool>(value: true, label: Text('Preview')),
              ],
              selected: <bool>{_preview},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (Set<bool> s) => _switch(s.first),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _preview
              ? _previewBody(cs)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: TextField(
                    controller: _ctl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Paste or write code here.',
                    ),
                  ),
                ),
      floatingActionButton: _preview
          ? FloatingActionButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _ctl.text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              child: const Icon(Icons.copy),
            )
          : null,
    );
  }

  Widget _previewBody(ColorScheme cs) {
    if (_ctl.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.code, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No code yet',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text('Switch to Edit to write or paste code.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: SelectableText(
            _ctl.text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.55),
          ),
        ),
      ],
    );
  }
}
