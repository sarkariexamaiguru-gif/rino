import 'package:flutter/material.dart';

/// Story media screen — reimagined from the profile-gallery reference.
///
/// Header (avatar, title, subtitle) → three stat cards (Chapters / Words /
/// Media) → horizontally scrolling chapter circles → four filter tabs →
/// three-column media grid with type badges.
///
/// This is a *presentation* screen: pass in the story's media. With an empty
/// list it shows a truthful empty state rather than fake tiles.
class StoryMediaPage extends StatefulWidget {
  const StoryMediaPage({
    super.key,
    required this.storyTitle,
    this.subtitle = 'Story',
    this.chapters = 0,
    this.words = 0,
    this.media = const <StoryMediaItem>[],
  });

  final String storyTitle;
  final String subtitle;
  final int chapters;
  final int words;
  final List<StoryMediaItem> media;

  @override
  State<StoryMediaPage> createState() => _StoryMediaPageState();
}

enum MediaKind { image, gif, video }

class StoryMediaItem {
  const StoryMediaItem({
    required this.url,
    required this.kind,
    this.caption = '',
    this.chapter = 1,
    this.saved = false,
  });

  final String url;
  final MediaKind kind;
  final String caption;
  final int chapter;
  final bool saved;
}

class _StoryMediaPageState extends State<StoryMediaPage> {
  int _filter = 0; // 0 images, 1 gifs, 2 videos, 3 saved
  int? _chapter; // null = all chapters

  static const List<String> _filterLabels = <String>['Images', 'GIFs', 'Videos', 'Saved'];
  static const List<IconData> _filterIcons = <IconData>[
    Icons.image_outlined,
    Icons.gif_box_outlined,
    Icons.videocam_outlined,
    Icons.bookmark_outline,
  ];

  List<StoryMediaItem> get _visible {
    return widget.media.where((StoryMediaItem m) {
      if (_chapter != null && m.chapter != _chapter) return false;
      switch (_filter) {
        case 0:
          return m.kind == MediaKind.image;
        case 1:
          return m.kind == MediaKind.gif;
        case 2:
          return m.kind == MediaKind.video;
        default:
          return m.saved;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<StoryMediaItem> items = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.storyTitle, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add media',
            onPressed: () => _showAddHint(context),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: ListView(
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
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stats(ColorScheme cs) {
    return Row(
      children: <Widget>[
        _statCard(cs, Icons.menu_book_outlined, '${widget.chapters}', 'Chapters'),
        const SizedBox(width: 8),
        _statCard(cs, Icons.edit_outlined, _fmt(widget.words), 'Words'),
        const SizedBox(width: 8),
        _statCard(cs, Icons.photo_library_outlined, '${widget.media.length}', 'Media'),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

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
    final int maxCh = widget.chapters > 0 ? widget.chapters : 1;
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _chapterDot(cs, null, 'All'),
          for (int i = 1; i <= maxCh; i++) _chapterDot(cs, i, 'Ch $i'),
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
        onTap: () => setState(() => _chapter = on ? null : index),
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
                style: TextStyle(
                  fontSize: 11,
                  color: on ? cs.onSurface : cs.onSurfaceVariant,
                ),
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

  Widget _grid(List<StoryMediaItem> items) {
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
        final StoryMediaItem m = items[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.network(
                m.url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined, size: 22)),
                ),
                loadingBuilder: (BuildContext c, Widget w, ImageChunkEvent? p) =>
                    p == null ? w : ColoredBox(color: Theme.of(c).colorScheme.surfaceContainerHighest),
              ),
              if (m.kind != MediaKind.image)
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
                      m.kind == MediaKind.gif ? 'GIF' : 'VIDEO',
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
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
        ],
      ),
    );
  }

  void _showAddHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add media from a URL or the device')),
    );
  }
}
