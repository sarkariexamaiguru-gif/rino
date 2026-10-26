import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Local GGUF model manager.
///
/// Downloads model files from Hugging Face into app-private storage, lists what
/// is already on the device, and deletes files. It does NOT run the models —
/// there is no inference engine in this app. Point an engine (KoboldCpp,
/// llama.cpp) at the downloaded file.
class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  final TextEditingController _urlCtl = TextEditingController();
  final Dio _dio = Dio();

  Directory? _dir;
  List<File> _files = <File>[];
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  CancelToken? _token;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _token?.cancel();
    _urlCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/models');
      if (!await d.exists()) {
        await d.create(recursive: true);
      }
      if (!mounted) return;
      _dir = d;
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not open storage: $e');
    }
  }

  Future<void> _refresh() async {
    final dir = _dir;
    if (dir == null) return;
    List<File> items;
    try {
      items = dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.toLowerCase().endsWith('.gguf'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
    } catch (_) {
      items = <File>[];
    }
    if (!mounted) return;
    setState(() => _files = items);
  }

  Future<void> _download() async {
    final String url = _urlCtl.text.trim();
    final Directory? dir = _dir;
    if (url.isEmpty || dir == null || _busy) return;

    String name = 'model.gguf';
    try {
      final List<String> segs = Uri.parse(url).pathSegments;
      if (segs.isNotEmpty && segs.last.isNotEmpty) name = segs.last;
    } catch (_) {}

    final File target = File('${dir.path}/$name');
    final CancelToken token = CancelToken();
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Downloading $name';
      _token = token;
    });

    try {
      await _dio.download(
        url,
        target.path,
        cancelToken: token,
        onReceiveProgress: (int got, int total) {
          if (total > 0 && mounted) {
            setState(() => _progress = got / total);
          }
        },
      );
      if (mounted) setState(() => _status = 'Saved $name');
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _status = 'Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _token = null;
        });
      }
    }
  }

  Future<void> _delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
    await _refresh();
  }

  String _size(File f) {
    int b = 0;
    try {
      b = f.lengthSync();
    } catch (_) {}
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
    return '${(b / 1048576).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Local models')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Download a GGUF model from Hugging Face',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlCtl,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'https://huggingface.co/.../model.Q4_K_M.gguf',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: const Icon(Icons.download),
                  label: Text(_busy ? 'Downloading...' : 'Download'),
                ),
              ),
              if (_busy) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _token?.cancel(),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
              ),
            ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 22),
          const Text(
            'On this device',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            Text(
              'No models yet.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ..._files.map(
            (File f) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory),
              title: Text(
                f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_size(f)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(f),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'These files are downloaded into app storage. This app does not run '
            'them itself - there is no inference engine bundled. Load the file '
            'in a local engine such as KoboldCpp, or point one at this folder.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
