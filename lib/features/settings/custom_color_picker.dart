import 'package:hand_gesture/shared/app_dialog.dart';
import 'package:hand_gesture/shared/reaction_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/l10n/app_strings.dart';

/// A draft picker. The caller restores its original color if dismissed.
class CustomColorPicker extends StatefulWidget {
  const CustomColorPicker({
    super.key,
    required this.color,
    required this.background,
    required this.reaction,
    required this.emoji,
    required this.onChanged,
  });
  final Color color, background;
  final bool reaction;
  final int emoji;
  final ValueChanged<Color> onChanged;
  @override
  State<CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<CustomColorPicker> {
  late HSVColor _hsv;
  final _form = GlobalKey<FormState>();
  final _hex = TextEditingController();
  final _rgb = List.generate(3, (_) => TextEditingController());
  Color get _color => _hsv.toColor();
  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(
      widget.reaction ? widget.color : widget.background,
    );
    _sync();
  }

  void _sync() {
    final n = _color.toARGB32();
    _hex.text =
        '#${(n & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    for (var i = 0; i < 3; i++) {
      _rgb[i].text = ((n >> (16 - i * 8)) & 255).toString();
    }
  }

  void _change(HSVColor value) {
    setState(() {
      _hsv = value;
      _sync();
    });
    widget.onChanged(_color);
  }

  @override
  void dispose() {
    _hex.dispose();
    for (final c in _rgb) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.reaction
        ? 'Change reaction Color'
        : 'Change Background Color',
    icon: Icons.palette_outlined,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 80,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: widget.reaction ? widget.background : _color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: reactionArtwork(
              widget.emoji == 0
                  ? 'assets/control/face.png'
                  : 'assets/settings/face-happy.png',
              filterQuality: widget.emoji != 0
                  ? FilterQuality.none
                  : FilterQuality.medium,
              color: widget.reaction ? _color : widget.color,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              void select(Offset point) => _change(
                _hsv
                    .withSaturation((point.dx / box.maxWidth).clamp(0.0, 1.0))
                    .withValue((1 - point.dy / 150).clamp(0.0, 1.0)),
              );
              return Semantics(
                label: tr(context, 'Color spectrum'),
                child: GestureDetector(
                  key: const ValueKey('color-spectrum'),
                  onPanDown: (d) => select(d.localPosition),
                  onPanUpdate: (d) => select(d.localPosition),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  HSVColor.fromAHSV(
                                    1,
                                    _hsv.hue,
                                    1,
                                    1,
                                  ).toColor(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: (_hsv.saturation * box.maxWidth - 9).clamp(
                            0.0,
                            box.maxWidth - 18,
                          ),
                          top: ((1 - _hsv.value) * 150 - 9).clamp(0.0, 132.0),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const LText('Hue'),
              Expanded(
                child: Slider(
                  key: const ValueKey('color-hue'),
                  value: _hsv.hue,
                  max: 360,
                  onChanged: (v) => _change(_hsv.withHue(v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const LText('Saturation'),
              Expanded(
                child: Slider(
                  value: _hsv.saturation,
                  onChanged: (v) => _change(_hsv.withSaturation(v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const LText('Brightness'),
              Expanded(
                child: Slider(
                  value: _hsv.value,
                  onChanged: (v) => _change(_hsv.withValue(v)),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const ValueKey('color-hex'),
                  controller: _hex,
                  decoration: const InputDecoration(labelText: 'HEX'),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[#a-fA-F0-9]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  validator: (v) =>
                      RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(v ?? '')
                      ? null
                      : tr(context, 'Enter a 6-digit hex color.'),
                  onChanged: (v) {
                    if (RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(v)) {
                      _change(
                        HSVColor.fromColor(
                          Color(
                            0xff000000 |
                                int.parse(v.replaceAll('#', ''), radix: 16),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              for (var i = 0; i < 3; i++) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _rgb[i],
                    decoration: InputDecoration(labelText: ['R', 'G', 'B'][i]),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 0 && n <= 255 ? null : '0–255';
                    },
                    onChanged: (_) {
                      final values = _rgb
                          .map((c) => int.tryParse(c.text))
                          .toList();
                      if (values.every(
                        (n) => n != null && n >= 0 && n <= 255,
                      )) {
                        _change(
                          HSVColor.fromColor(
                            Color.fromARGB(
                              255,
                              values[0]!,
                              values[1]!,
                              values[2]!,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
    actions: [
      appDialogAction('Cancel', () => Navigator.pop(context), primary: false),
      appDialogAction('Use color', () {
        if (_form.currentState!.validate()) {
          Navigator.pop(context, _color.toARGB32());
        }
      }, key: const ValueKey('use-custom-color')),
    ],
  );
}
