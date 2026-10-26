import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../data/media_store.dart';

/// The story surface for one chapter.
///
/// A Write / Read switcher sits at the top, scoped to *this story* — the same
/// switcher the app used to have app-wide, now living inside the chapter.
///
/// The chapter is one text stream with two inline markers:
///   [[img:ID]]   an image, GIF or video — plays automatically
///   [[page]]     a page break
class StoryEditorPage extends StatefulWidget {
  const StoryEditorPage({
    super.key,
    required this.storyId,
    required this.storyTitle,
    this.chapter = 1,
    this.startInRead = true,
  });

  final String storyId;
  final String storyTitle;
  final int chapter;
  final bool startInRead;

  @override
  State<StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends State<StoryEditorPage> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _loading = true;
  late bool _reading = widget.startInRead;
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

  Future<void> _switchTo(bool reading) async {
    if (reading) await _save();
    if (!mounted) return;
    setState(() => _reading = reading);
    if (!reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  void _insert(String snippet) {
    final TextSelection sel = _ctl.selection;
    final String text = _ctl.text;
    if (sel.isValid && sel.start >= 0) {
      final String before = text.substring(0, sel.start);
      final String after = text.substring(sel.end);
      final String pad = before.endsWith('\n') || before.isEmpty ? '' : '\n';
      _ctl.text = '$before$pad$snippet\n$after';
      _ctl.selection =
          TextSelection.collapsed(offset: (before + pad + snippet + '\n').length);
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
        final XFile? picked =
            await ImagePicker().pickImage(source: ImageSource.gallery);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add: $err')));
      }
      return;
    }

    final TextEditingController urlCtl = TextEditingController();
    final TextEditingController capCtl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Media from URL'),
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
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
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

  /// Append a passage to this chapter.
  ///
  /// This is the bridge from the model to the manuscript: copy a reply, tap
  /// this, and it lands at the end of the chapter as prose. Nothing is
  /// reformatted and nothing is overwritten.
  Future<void> _addProse() async {
    String seed = '';
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      seed = (data?.text ?? '').trim();
    } catch (_) {}

    final TextEditingController ctl = TextEditingController(text: seed);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Add prose'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Paste the passage, or tap the model reply and copy it first.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                autofocus: seed.isEmpty,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'The passage to append',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Append')),
        ],
      ),
    );
    final String body = ctl.text.trim();
    ctl.dispose();
    if (ok != true || body.isEmpty) return;

    final String pad = _ctl.text.isEmpty || _ctl.text.endsWith('\n') ? '' : '\n';
    _ctl.text = '${_ctl.text}$pad$body\n';
    await _save();
    if (!mounted) return;
    setState(() => _reading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to the chapter'), duration: Duration(seconds: 2)),
    );
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
              title: const Text('Media from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addImage(fromGallery: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Media from URL'),
              subtitle: const Text('Image, GIF or video - plays automatically'),
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

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.storyTitle} · Ch ${widget.chapter}',
            overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add prose to this chapter',
            onPressed: _addProse,
            icon: const Icon(Icons.playlist_add),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Write')),
                ButtonSegment<bool>(value: true, label: Text('Read')),
              ],
              selected: <bool>{_reading},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (Set<bool> s) => _switchTo(s.first),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reading
              ? _reader(cs)
              : _writer(),
      floatingActionButton: _reading
          ? null
          : FloatingActionButton(onPressed: _addSheet, child: const Icon(Icons.add)),
    );
  }

  Widget _writer() {
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
          hintText: 'Write, or let the model write. '
              'Tap + to drop media or a page break.',
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
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Switch to Write to begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _switchTo(false),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Write'),
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
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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

    Widget body;
    if (e.isFile) {
      // GIFs animate natively through Image.file.
      body = Image.file(
        File(e.source.substring('file://'.length)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _broken(cs),
      );
    } else if (e.type == MediaType.video) {
      body = _AutoVideo(url: e.source, cs: cs);
    } else {
      // Image.network animates GIFs automatically.
      body = Image.network(
        e.source,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _broken(cs),
        loadingBuilder: (BuildContext c, Widget w, ImageChunkEvent? p) =>
            p == null ? w : _placeholder(cs),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(borderRadius: BorderRadius.circular(10), child: body),
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

/// Network video that loads, mutes and loops itself.
class _AutoVideo extends StatefulWidget {
  const _AutoVideo({required this.url, required this.cs});

  final String url;
  final ColorScheme cs;

  @override
  State<_AutoVideo> createState() => _AutoVideoState();
}

class _AutoVideoState extends State<_AutoVideo> {
  VideoPlayerController? _vpc;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final VideoPlayerController c =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _vpc = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _vpc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 160,
        color: widget.cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.videocam_off_outlined, color: widget.cs.onSurfaceVariant),
      );
    }
    final VideoPlayerController? c = _vpc;
    if (c == null) {
      return Container(
        height: 180,
        color: widget.cs.surfaceContainerHighest.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
      child: VideoPlayer(c),
    );
  }
}
