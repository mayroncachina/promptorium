import 'package:flutter/widgets.dart';

/// Body of the text buttons (SmallButton, AmberButton, ChipButton,
/// ProtoButton; SPEC-075): [height] tall, the content centered. With [expand]
/// false it is as wide as the content (plus [padding] on each side) in any
/// parent; with [expand] true it takes all the width the parent offers. A
/// parent that imposes an exact width (Expanded, a stretched Column) still
/// decides it.
class ButtonBox extends StatelessWidget {
  const ButtonBox({
    super.key,
    required this.height,
    required this.padding,
    this.expand = false,
    required this.child,
  });

  final double height;
  final double padding;
  final bool expand;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: expand ? double.infinity : null,
    padding: EdgeInsets.symmetric(horizontal: padding),
    // A Container with an alignment fills the width it gets; widthFactor 1
    // shrinks it to the content and keeps the vertical centering.
    child: Align(widthFactor: expand ? null : 1, child: child),
  );
}
