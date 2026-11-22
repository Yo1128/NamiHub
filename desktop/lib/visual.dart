import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

const paper = Color(0xfff7f7f3),
    rail = Color(0xffeeefea),
    ink = Color(0xff20231f),
    muted = Color(0xff62685f),
    rule = Color(0xffdadcd4),
    signal = Color(0xffff693e),
    dark = Color(0xff242722),
    steel = Color(0xffb7beb0);
const mono = 'Consolas';
bool reduced(BuildContext c) =>
    MediaQuery.disableAnimationsOf(c) || MediaQuery.accessibleNavigationOf(c);
Duration motion(BuildContext c, int ms) =>
    Duration(milliseconds: reduced(c) ? 0 : ms);

String bytesLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final mb = bytes / (1024 * 1024);
  return mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(1)} GiB'
      : mb >= 1
      ? '${mb.toStringAsFixed(2)} MiB'
      : '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

const kinds = {'video': '视频', 'audio': '音乐', 'book': '书籍', 'other': '其他'};
IconData typeIcon(String kind) => switch (kind) {
  'video' => Icons.movie_outlined,
  'audio' => Icons.graphic_eq,
  'book' => Icons.menu_book_outlined,
  _ => Icons.insert_drive_file_outlined,
};

class HubMark extends StatelessWidget {
  const HubMark({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _Mark()),
  );
}

class _Mark extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 36, s.height / 36);
    final paint = Paint()..color = signal;
    for (final x in [0.0, 10.0, 20.0]) {
      final dy = x == 10 ? 0.0 : 6.0;
      c.drawPath(
        Path()
          ..moveTo(x, 12 + dy)
          ..lineTo(x + 9, 6 + dy)
          ..lineTo(x + 9, 24 + dy)
          ..lineTo(x, 30 + dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Mark old) => false;
}

/// Each indexed content type occupies a plate. Filtering draws that plate out.
class ArchiveStack extends StatelessWidget {
  const ArchiveStack({
    super.key,
    required this.types,
    required this.selected,
    required this.online,
  });
  final List<String> types;
  final String selected;
  final bool online;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: online ? 1 : 0),
      duration: motion(context, 340),
      curve: Curves.easeOutCubic,
      builder: (c, lift, _) => TweenAnimationBuilder<double>(
        tween: Tween(
          end: selected == 'all' ? -1.0 : types.indexOf(selected).toDouble(),
        ),
        duration: motion(c, 250),
        curve: Curves.easeOutCubic,
        builder: (_, focus, _) => RepaintBoundary(
          child: CustomPaint(
            painter: _StackPainter(types, focus, lift),
            size: Size.infinite,
          ),
        ),
      ),
    ),
  );
}

class _StackPainter extends CustomPainter {
  const _StackPainter(this.types, this.focus, this.lift);
  final List<String> types;
  final double focus, lift;
  Path plate(double w, double h, double cut) => Path()
    ..moveTo(0, 0)
    ..lineTo(w - cut, 0)
    ..lineTo(w, cut)
    ..lineTo(w, h)
    ..lineTo(cut, h)
    ..lineTo(0, h - cut)
    ..close();
  @override
  void paint(Canvas c, Size size) {
    final scale = math.min(size.width / 356, size.height / 211);
    c.translate(size.width * .5, size.height * .52);
    c.scale(scale);
    final layers = types;
    void face(double x, double y, void Function() draw) {
      c.save();
      c.translate(x - 20, y - 48);
      c.transform(
        Float64List.fromList([
          1,
          .30,
          0,
          0,
          -.80,
          .52,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]),
      );
      c.translate(-64, -28);
      draw();
      c.restore();
    }

    final paint = Paint()..isAntiAlias = true;
    void fill(Path path, Color color) {
      paint
        ..style = PaintingStyle.fill
        ..color = color;
      c.drawPath(path, paint);
    }

    void line(Offset a, Offset b, Color col, [double width = 1]) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = col;
      c.drawLine(a, b, paint);
    }

    final form = plate(184, 132, 9);
    final baseY = 28.0;
    for (var j = 0; j < 5; j++) {
      face(0, baseY + 22 - j * 3, () {
        fill(
          form,
          Color.lerp(const Color(0xff373b34), const Color(0xff656a5f), j / 5)!,
        );
      });
    }
    for (var i = 0; i < layers.length; i++) {
      final top = i == layers.length - 1;
      final selected = focus < -.5
          ? 0.0
          : (1 - (focus - i).abs()).clamp(0.0, 1.0);
      final slide = 38 * selected;
      final y = baseY - (i + 1) * (8 + lift * 2) - slide * .44;
      final base = top
          ? signal
          : (i.isEven ? const Color(0xffa0a69a) : const Color(0xffdedfd2));
      final color = Color.lerp(base, signal, selected)!;
      for (var depth = 4; depth >= 0; depth--) {
        face(slide, y + depth, () {
          fill(
            form,
            depth == 0
                ? color
                : Color.lerp(color, dark, depth == 1 ? 0.24 : 0.48)!,
          );
          if (depth != 0) return;
          c.save();
          c.clipPath(form);
          final etched = top
              ? const Color(0xff9c3822)
              : const Color(0xff6b7167);
          // Concentric grooves and register marks are printed into the archive surface.
          if (layers[i] == 'audio') {
            final center = const Offset(158, 30);
            for (var n = 0; n < 22; n++) {
              paint
                ..style = PaintingStyle.stroke
                ..strokeWidth = .82
                ..color = etched.withValues(alpha: .68);
              c.drawCircle(center, 14 + n * 4.2, paint);
            }
            paint
              ..style = PaintingStyle.fill
              ..color = etched;
            c.drawCircle(center, 4, paint);
            for (var j = 0; j < 3; j++) {
              final x = 13.0 + j * 10;
              fill(
                Path()
                  ..moveTo(x, 28)
                  ..lineTo(x + 7, 23)
                  ..lineTo(x + 7, 47)
                  ..lineTo(x, 52)
                  ..close(),
                dark,
              );
            }
            line(const Offset(12, 106), const Offset(63, 106), etched, 1.2);
            final bars = [
              2.0,
              1.0,
              3.0,
              1.0,
              1.0,
              2.0,
              4.0,
              1.0,
              3.0,
              1.0,
              2.0,
            ];
            var dx = 13.0;
            for (final width in bars) {
              line(Offset(dx, 112), Offset(dx, 119), dark, width);
              dx += width + 2;
            }
          } else if (layers[i] == 'video') {
            for (var col = 0; col < 13; col++) {
              for (final row in [8.0, 116.0]) {
                fill(
                  Path()..addRect(Rect.fromLTWH(8.0 + col * 13, row, 7, 7)),
                  dark,
                );
              }
            }
            for (var frame = 0; frame < 3; frame++) {
              paint
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.7
                ..color = etched;
              c.drawRect(Rect.fromLTWH(8.0 + frame * 57, 23, 51, 84), paint);
            }
          } else {
            line(const Offset(18, 12), const Offset(18, 116), etched, 1.8);
            for (var row = 0; row < 10; row++) {
              line(
                Offset(30, 22.0 + row * 9),
                Offset(row.isOdd ? 137 : 157, 22.0 + row * 9),
                etched,
                1.1,
              );
            }
            for (var n = 0; n < 17; n++) {
              line(
                Offset(10.0 + n * 10, 120),
                Offset(10.0 + n * 10, 125),
                etched,
                1.4,
              );
            }
          }
          c.restore();
        });
      }
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) =>
      old.focus != focus ||
      old.lift != lift ||
      old.types.join() != types.join();
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.label,
    this.icon,
    this.onPress, {
    super.key,
    this.primary = false,
    this.onDark = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final bool primary, onDark;
  @override
  Widget build(BuildContext c) {
    final fg = onDark ? paper : ink;
    return TextButton.icon(
      onPressed: onPress,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: fg,
        backgroundColor: primary
            ? signal
            : (onDark ? const Color(0xff393e36) : Colors.transparent),
        disabledForegroundColor: onDark ? steel : muted,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
