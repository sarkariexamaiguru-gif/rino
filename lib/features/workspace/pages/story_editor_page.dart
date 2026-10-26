import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/media_store.dart';

/// The story surface: you write and read the story *here*, not in a chat.
///
/// One continuous text stream with two inline markers:
///   [[img:ID]]   an image or GIF, rendered between paragraphs
///   [[page]]     a page break the author inserted
///
/// Reading and editing are the same screen — Edit, change text, Done.
class StoryEditorPage extends StatefulWidget {
  const StoryEditorPage({
    super.key,
    required this.storyId,
    required this.storyTitle,
    this.chapter = 1,
  });

  final String storyId;
  final String storyTitle;
  final int chapter;

  @override
  State<StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends State<StoryEditorPage> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _loading = true;
  bool _editing = false;
  Map<String, MediaEntry> _media = <String, MediaEntry>{};

  String get _key => 'rino.storytext.${widget.storyId}.${widget.chapter}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await MediaStore.instance.load();
    final List<MediaEntry> entries = MediaStore.instance.forStory(widget.storyId);
    if (!mounted) return;
    setState(() {
      _ctl.text = prefs.getString(_key) ?? '';
      _media = <String, MediaEntry>{for (final MediaEntry e in entries) e.id: e};
      _loading = false;
    });
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _ctl.text);
  }

  void _insert(String snippet) {
    final TextSelection sel = _ctl.selection;
    final String text = _ctl.text;
    if (sel.isValid && sel.start >= 0) {
      final String before = text.substring(0, sel.start);
      final String after = text.substring(sel.end);
      final String pad = before.endsWith('\n') || before.isEmpty ? '' : '\n';
      _ctl.text = '$before$pad$snippet\n$after';
      _ctl.selection = TextSelection.collapsed(offset: (before + pad + snippet + '\n').length);
    } else {
      final String pad = text.isEmpty || text.endsWith('\n') ? '' : '\n';
      _ctl.text = '$text$pad$snippet\n';
      _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
    }
    setState(() {});
  }

  Future<void> _addImage({required bool fromGallery}) async {
    if (fromGallery) {
      try {
        final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        final MediaEntry e = await MediaStore.instance.addFile(
          storyId: widget.storyId,
          chapter: widget.chapter,
          sourcePath: picked.path,
        );
        setState(() => _media[e.id] = e);
        _insert('[[img:${e.id}]]');
      } catch (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $err')));
      }
      return;
    }

    final TextEditingController urlCtl = TextEditingController();
    final TextEditingController capCtl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Image from URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: urlCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://... .jpg / .gif / .mp4',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: capCtl,
              decoration: const InputDecoration(labelText: 'Caption (optional)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Add')),
        ],
      ),
    );
    final String url = urlCtl.text.trim();
    final String cap = capCtl.text.trim();
    urlCtl.dispose();
    capCtl.dispose();
    if (ok != true || url.isEmpty) return;
    final MediaEntry e = await MediaStore.instance.addUrl(
      storyId: widget.storyId,
      chapter: widget.chapter,
      url: url,
      caption: cap,
    );
    setState(() => _media[e.id] = e);
    _insert('[[img:${e.id}]]');
  }

  void _addSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Image from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addImage(fromGallery: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Image from URL'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addImage(fromGallery: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.horizontal_rule),
              title: const Text('Page break'),
              onTap: () {
                Navigator.of(ctx).pop();
                _insert('[[page]]');
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleEdit() async {
    if (_editing) {
      await _save();
      if (!mounted) return;
      setState(() => _editing = false);
    } else {
      setState(() => _editing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.storyTitle} · Ch ${widget.chapter}',
            overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          TextButton(
            onPressed: _loading ? null : _toggleEdit,
            child: Text(_editing ? 'Done' : 'Edit'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _editing
              ? _editor()
              : _reader(cs),
      floatingActionButton: _editing
          ? FloatingActionButton(onPressed: _addSheet, child: const Icon(Icons.add))
          : null,
    );
  }

  Widget _editor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 16, height: 1.6),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Write, or let the model write. Tap + to drop an image or a page break.',
        ),
      ),
    );
  }

  Widget _reader(ColorScheme cs) {
    if (_ctl.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.menu_book_outlined, size: 44, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('This chapter is empty',
                  style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Tap Edit to write, or add an image with the + button.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _toggleEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Start writing'),
              ),
            ],
          ),
        ),
      );
    }

    final List<String> lines = _ctl.text.split('\n');
    final List<Widget> out = <Widget>[];
    final List<String> buf = <String>[];
    int page = 1;

    void flush() {
      final String para = buf.join('\n').trim();
      buf.clear();
      if (para.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(para, style: const TextStyle(fontSize: 17, height: 1.78)),
      ));
    }

    for (final String line in lines) {
      final String t = line.trim();
      if (t.startsWith('[[page]]')) {
        flush();
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: <Widget>[
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Page $page',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ));
        page++;
        continue;
      }
      final RegExpMatch? m = RegExp(r'^\[\[img:([^\]]+)\]\]').firstMatch(t);
      if (m != null) {
        flush();
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _inlineMedia(_media[m.group(1)], cs),
        ));
        continue;
      }
      buf.add(line);
    }
    flush();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: out,
    );
  }

  Widget _inlineMedia(MediaEntry? e, ColorScheme cs) {
    if (e == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text('Media missing',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      );
    }
    final Widget img = e.isFile
        ? Image.file(File(e.source.substring('file://'.length)),
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _broken(cs))
        : Image.network(e.source,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _broken(cs),
            loadingBuilder: (BuildContext c, Widget w, ImageChunkEvent? p) =>
                p == null ? w : _placeholder(cs));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
        if (e.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(e.caption,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _broken(ColorScheme cs) => Container(
        height: 140,
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
      );

  Widget _placeholder(ColorScheme cs) => Container(
        height: 180,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      );
}
