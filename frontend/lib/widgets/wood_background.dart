import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage/app_theme.dart';

/// Both themes' backdrop is a real wood photo (CC0), tiled rather than
/// stretched: they're seamless PBR materials, and tiling keeps the grain at
/// a consistent scale across phone and desktop instead of cropping to
/// whatever the screen's aspect ratio happens to be.
class _WoodPhoto {
  final String asset;
  final double tileSize;
  final Color vignette;
  final double vignetteAlpha;
  final double lighten;
  const _WoodPhoto({
    required this.asset,
    required this.tileSize,
    required this.vignette,
    this.vignetteAlpha = .40,
    this.lighten = 0,
  });
}

/// Tile size is in logical pixels — chosen to read like a real board width
/// on a phone screen without the repeat becoming obvious. The light photo
/// is zoomed in further and lightened a touch so the grain reads calmer
/// instead of busy.
final _lightPhoto = _WoodPhoto(
  asset: 'assets/wood/light.jpg',
  tileSize: 480,
  vignette: lightWood.seam,
  vignetteAlpha: .20,
  lighten: .12,
);
final _darkPhoto = _WoodPhoto(
  asset: 'assets/wood/dark.jpg',
  tileSize: 340,
  vignette: darkWood.seam,
);

class WoodBackground extends StatefulWidget {
  final bool dark;
  final Widget child;

  const WoodBackground({super.key, required this.dark, required this.child});

  @override
  State<WoodBackground> createState() => _WoodBackgroundState();
}

class _WoodBackgroundState extends State<WoodBackground> {
  ui.Image? _photo;
  bool? _photoIsDark;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(WoodBackground old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) _loadPhoto();
  }

  void _loadPhoto() {
    final dark = widget.dark;
    final asset = (dark ? _darkPhoto : _lightPhoto).asset;
    AssetImage(asset).resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((info, _) {
            if (mounted) {
              setState(() {
                _photo = info.image;
                _photoIsDark = dark;
              });
            }
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final spec = widget.dark ? _darkPhoto : _lightPhoto;
    return CustomPaint(
      painter: photo != null && _photoIsDark == widget.dark
          ? PhotoWoodPainter(
              photo,
              tileSize: spec.tileSize,
              vignette: spec.vignette,
              vignetteAlpha: spec.vignetteAlpha,
              lighten: spec.lighten,
            )
          : _PlaceholderPainter(widget.dark ? darkWood.base : lightWood.base),
      isComplex: true,
      willChange: false,
      child: widget.child,
    );
  }
}

/// Flat fill shown for the one frame before the photo asset resolves.
class _PlaceholderPainter extends CustomPainter {
  final Color color;
  const _PlaceholderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = color);

  @override
  bool shouldRepaint(covariant _PlaceholderPainter old) => old.color != color;
}

/// Tiles a real wood photo across the canvas via [ImageShader], with a
/// vignette on top so the lighting isn't perfectly even.
@visibleForTesting
class PhotoWoodPainter extends CustomPainter {
  final ui.Image image;
  final double tileSize;
  final Color vignette;
  final double vignetteAlpha;
  final double lighten;

  PhotoWoodPainter(
    this.image, {
    required this.tileSize,
    required this.vignette,
    this.vignetteAlpha = .40,
    this.lighten = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final scale = tileSize / image.width;
    final matrix = Matrix4.identity().scaledByDouble(scale, scale, 1, 1).storage;
    canvas.drawRect(
      rect,
      Paint()..shader = ImageShader(image, TileMode.repeated, TileMode.repeated, matrix),
    );
    if (lighten > 0) {
      canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: lighten));
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.15, -.35),
          radius: 1.1,
          colors: [Colors.transparent, vignette.withValues(alpha: vignetteAlpha)],
          stops: const [.45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant PhotoWoodPainter old) =>
      old.image != image ||
      old.tileSize != tileSize ||
      old.vignette != vignette ||
      old.vignetteAlpha != vignetteAlpha ||
      old.lighten != lighten;
}

/// A `TextButton.icon` with a translucent surface pill behind it, for
/// buttons that sit directly on the wood background (no enclosing `Card`)
/// and would otherwise be flat text over busy grain.
class WoodLegibleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const WoodLegibleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
}
