import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  int _mode = 0; // 0 edit, 1 text preview, 2 rendered HTML

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

  Future<void> _switch(int mode) async {
    if (mode != 0) await _save();
    if (!mounted) return;
    setState(() => _mode = mode);
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
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('Edit')),
                ButtonSegment<int>(value: 1, label: Text('Text')),
                ButtonSegment<int>(value: 2, label: Text('HTML')),
              ],
              selected: <int>{_mode},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (Set<int> s) => _switch(s.first),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mode == 1
              ? _previewBody(cs)
              : _mode == 2
                  ? _HtmlPreview(html: _ctl.text)
                  : _editorBody()
              : _editorBody(),
      floatingActionButton: _mode == 1
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

  Widget _editorBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: TextField(
        controller: _ctl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Paste or write code here. HTML renders in the HTML tab.',
        ),
      ),
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

/// Renders the editor contents as HTML. If the text has no tags, it is wrapped
/// in a minimal dark document so plain text and markup both preview sensibly.
class _HtmlPreview extends StatefulWidget {
  const _HtmlPreview({required this.html});
  final String html;

  @override
  State<_HtmlPreview> createState() => _HtmlPreviewState();
}

class _HtmlPreviewState extends State<_HtmlPreview> {
  WebViewController? _c;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final String raw = widget.html;
    final String doc = raw.contains('<') && raw.contains('>')
        ? raw
        : '<pre style="white-space:pre-wrap;word-wrap:break-word;font-family:monospace;'
            'font-size:13px;line-height:1.5;color:#e6e6ea;margin:0">'
            '${raw.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</pre>';
    final String page = '<!doctype html><html><head><meta name="viewport" '
        'content="width=device-width,initial-scale=1"><style>'
        'body{background:#0f1117;color:#e6e6ea;font-family:system-ui,sans-serif;'
        'margin:12px;}a{color:#8b93ff;}img{max-width:100%;}'
        '</style></head><body>$doc</body></html>';
    final WebViewController c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadHtmlString(page);
    if (!mounted) return;
    setState(() => _c = c);
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? c = _c;
    if (c == null) return const Center(child: CircularProgressIndicator());
    return WebViewWidget(controller: c);
  }
}
