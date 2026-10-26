import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/media_store.dart';

/// Picme — the image surface, same shape as the Katha story surface.
///
/// A prompt you keep, and a gallery of images added from the device or a URL.
/// Everything is stored in the same local media table, scoped by project id.
class PicmeStudioPage extends StatefulWidget {
  const PicmeStudioPage({super.key, required this.projectId, required this.title});

  final String projectId;
  final String title;

  @override
  State<PicmeStudioPage> createState() => _PicmeStudioPageState();
}

class _PicmeStudioPageState extends State<PicmeStudioPage> {
  final TextEditingController _prompt = TextEditingController();
  bool _loading = true;
  List<MediaEntry> _items = <MediaEntry>[];

  String get _storyId => 'picme:${widget.projectId}';
  String get _key => 'rino.picme.prompt.${widget.projectId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await MediaStore.instance.load();
    if (!mounted) return;
    setState(() {
      _prompt.text = p.getString(_key) ?? '';
      _items = MediaStore.instance.forStory(_storyId);
      _loading = false;
    });
  }

  Future<void> _savePrompt() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_key, _prompt.text);
  }

  Future<void> _add({required bool fromGallery}) async {
    try {
      if (fromGallery) {
        final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        await MediaStore.instance.addFile(
          storyId: _storyId, chapter: 1, sourcePath: picked.path);
      } else {
        final TextEditingController c = TextEditingController();
        final String? url = await showDialog<String>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Image from URL'),
            content: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'https://... .jpg / .gif'),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('Add')),
            ],
          ),
        );
        c.dispose();
        final String trimmed = (url ?? '').trim();
        if (trimmed.isEmpty) return;
        await MediaStore.instance.addUrl(
          storyId: _storyId, chapter: 1, url: trimmed);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  void _sheet() {
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
              onTap: () { Navigator.of(ctx).pop(); _add(fromGallery: true); },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('From URL'),
              onTap: () { Navigator.of(ctx).pop(); _add(fromGallery: false); },
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
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: <Widget>[
                TextField(
                  controller: _prompt,
                  minLines: 2,
                  maxLines: 5,
                  onSubmitted: (_) => _savePrompt(),
                  onTapOutside: (_) => _savePrompt(),
                  decoration: InputDecoration(
                    labelText: 'Prompt',
                    hintText: 'Describe the image you want',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _add(fromGallery: true),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Gallery'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _add(fromGallery: false),
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('URL'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.image_outlined, size: 40, color: cs.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text('No images yet',
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3),
                    itemCount: _items.length,
                    itemBuilder: (BuildContext ctx, int i) {
                      final MediaEntry m = _items[i];
                      final Widget img = m.isFile
                          ? Image.file(File(m.source.substring('file://'.length)),
                              fit: BoxFit.cover)
                          : Image.network(m.source, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.broken_image_outlined,
                                    color: cs.onSurfaceVariant),
                              ));
                      return GestureDetector(
                        onTap: () async {
                          await MediaStore.instance.remove(m);
                          await _load();
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: img,
                        ),
                      );
                    },
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(onPressed: _sheet, child: const Icon(Icons.add)),
    );
  }
}
