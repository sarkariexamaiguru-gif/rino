import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/media_store.dart';

/// Story media — profile header, chapter circles, four filters, 3-col grid.
///
/// Reads and writes the local media table ([MediaStore]). Media can be added
/// from the device gallery or by URL, and every item belongs to a chapter, so
/// this screen and the reader always agree about what is where.
class StoryMediaPage extends StatefulWidget {
  const StoryMediaPage({
    super.key,
    required this.storyId,
    required this.storyTitle,
    this.subtitle = 'Story',
    this.words = 0,
    this.startChapter = 1,
  });

  final String storyId;
  final String storyTitle;
  final String subtitle;
  final int words;
  final int startChapter;

  @override
  State<StoryMediaPage> createState() => _StoryMediaPageState();
}

class _StoryMediaPageState extends State<StoryMediaPage> {
  int _filter = 0; // 0 images, 1 gifs, 2 videos, 3 saved
  int? _chapter;
  int _addChapter = 1;
  bool _loading = true;
  List<MediaEntry> _all = <MediaEntry>[];

  static const List<String> _filterLabels = <String>['Images', 'GIFs', 'Videos', 'Saved'];
  static const List<IconData> _filterIcons = <IconData>[
    Icons.image_outlined,
    Icons.gif_box_outlined,
    Icons.videocam_outlined,
    Icons.bookmark_outline,
  ];

  @override
  void initState() {
    super.initState();
    _chapter = null;
    _addChapter = widget.startChapter;
    _reload();
  }

  Future<void> _reload() async {
    await MediaStore.instance.load();
    if (!mounted) return;
    setState(() {
      _all = MediaStore.instance.forStory(widget.storyId);
      _loading = false;
    });
  }

  int get _chapters {
    final int fromStore = MediaStore.instance.chapterCount(widget.storyId);
    return fromStore < widget.startChapter ? widget.startChapter : fromStore;
  }

  List<MediaEntry> get _visible {
    return _all.where((MediaEntry m) {
      if (_chapter != null && m.chapter != _chapter) return false;
      switch (_filter) {
        case 0:
          return m.type == MediaType.image;
        case 1:
          return m.type == MediaType.gif;
        case 2:
          return m.type == MediaType.video;
        default:
          return m.saved;
      }
    }).toList();
  }

  Future<void> _addUrl() async {
    final TextEditingController urlCtl = TextEditingController();
    final TextEditingController capCtl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Add to chapter $_addChapter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: urlCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Image, GIF or video URL',
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
    await MediaStore.instance.addUrl(
      storyId: widget.storyId,
      chapter: _addChapter,
      url: url,
      caption: cap,
    );
    await _reload();
  }

  Future<void> _addFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await MediaStore.instance.addFile(
        storyId: widget.storyId,
        chapter: _addChapter,
        sourcePath: picked.path,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add image: $e')),
      );
    }
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
              title: const Text('From gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('From URL'),
              onTap: () {
                Navigator.of(ctx).pop();
                _addUrl();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _itemMenu(MediaEntry m) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(m.saved ? Icons.bookmark : Icons.bookmark_outline),
              title: Text(m.saved ? 'Remove from saved' : 'Save'),
              onTap: () => Navigator.of(ctx).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Caption'),
              onTap: () => Navigator.of(ctx).pop('caption'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') {
      await MediaStore.instance.toggleSaved(m);
      await _reload();
    } else if (action == 'delete') {
      await MediaStore.instance.remove(m);
      await _reload();
    } else if (action == 'caption' && mounted) {
      final TextEditingController ctl = TextEditingController(text: m.caption);
      final String? text = await showDialog<String>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Caption'),
          content: TextField(controller: ctl, autofocus: true),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctl.text), child: const Text('Save')),
          ],
        ),
      );
      ctl.dispose();
      if (text != null) {
        await MediaStore.instance.setCaption(m, text.trim());
        await _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<MediaEntry> items = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.storyTitle, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add media',
            onPressed: _addSheet,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: <Widget>[
                _header(cs),
                const SizedBox(height: 16),
                _stats(cs),
                const SizedBox(height: 16),
                _chapterRow(cs),
                const SizedBox(height: 12),
                _filterBar(cs),
                const SizedBox(height: 12),
                if (items.isEmpty) _empty(cs) else _grid(items),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Row(
      children: <Widget>[
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary.withValues(alpha: 0.55), width: 2),
            color: cs.surfaceContainerHighest,
          ),
          alignment: Alignment.center,
          child: Text(
            widget.storyTitle.isEmpty ? '?' : widget.storyTitle.characters.first.toUpperCase(),
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.storyTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(widget.subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stats(ColorScheme cs) {
    return Row(
      children: <Widget>[
        _statCard(cs, Icons.menu_book_outlined, '$_chapters', 'Chapters'),
        const SizedBox(width: 8),
        _statCard(cs, Icons.edit_outlined, _fmt(widget.words), 'Words'),
        const SizedBox(width: 8),
        _statCard(cs, Icons.photo_library_outlined, '${_all.length}', 'Media'),
      ],
    );
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _statCard(ColorScheme cs, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _chapterRow(ColorScheme cs) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _chapterDot(cs, null, 'All'),
          for (int i = 1; i <= _chapters; i++) _chapterDot(cs, i, 'Ch $i'),
        ],
      ),
    );
  }

  Widget _chapterDot(ColorScheme cs, int? index, String label) {
    final bool on = _chapter == index;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () {
          setState(() {
            _chapter = on ? null : index;
            if (index != null) _addChapter = index;
          });
        },
        child: SizedBox(
          width: 64,
          child: Column(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: on ? cs.primary : cs.outlineVariant,
                    width: on ? 2.5 : 1.5,
                  ),
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                ),
                alignment: Alignment.center,
                child: Text(
                  index == null ? 'All' : '$index',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: on ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBar(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List<Widget>.generate(4, (int i) {
          final bool on = _filter == i;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _filter = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: on ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: on ? cs.primary.withValues(alpha: 0.5) : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(_filterIcons[i], size: 20, color: on ? cs.primary : cs.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      _filterLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _thumb(MediaEntry m, ColorScheme cs) {
    if (m.isFile) {
      return Image.file(
        File(m.source.substring('file://'.length)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined, size: 22)),
        ),
      );
    }
    return Image.network(
      m.source,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 22)),
      ),
      loadingBuilder: (BuildContext c, Widget w, ImageChunkEvent? p) =>
          p == null ? w : ColoredBox(color: cs.surfaceContainerHighest),
    );
  }

  Widget _grid(List<MediaEntry> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext ctx, int i) {
        final MediaEntry m = items[i];
        final ColorScheme cs = Theme.of(ctx).colorScheme;
        return GestureDetector(
          onTap: () => _itemMenu(m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _thumb(m, cs),
                if (m.type != MediaType.image)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        m.type == MediaType.gif ? 'GIF' : 'VIDEO',
                        style: const TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                if (m.caption.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                        ),
                      ),
                      child: Text(
                        m.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _empty(ColorScheme cs) {
    final String msg = _filter == 3
        ? 'Nothing saved yet.'
        : (_chapter != null
            ? 'No ${_filterLabels[_filter].toLowerCase()} in this chapter yet.'
            : 'No ${_filterLabels[_filter].toLowerCase()} yet.');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(_filterIcons[_filter], size: 38, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(msg, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _addSheet,
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add to chapter $_addChapter'),
          ),
        ],
      ),
    );
  }
}
