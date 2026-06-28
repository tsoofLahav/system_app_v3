import 'package:flutter/material.dart';

import 'board_content.dart';

/// Full source image for crop editing (stretched to [width] x [height]).
class BoardCropSourceImage extends StatelessWidget {
  const BoardCropSourceImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
  });

  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
  }
}

/// Renders a board item's image: free stretch when uncropped, source-region crop otherwise.
class BoardItemImage extends StatelessWidget {
  const BoardItemImage({
    super.key,
    required this.item,
    required this.url,
  });

  final BoardItem item;
  final String url;

  @override
  Widget build(BuildContext context) {
    final w = item.width;
    final h = item.height;

    if (!boardItemHasCrop(item)) {
      return Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.fill,
        gaplessPlayback: true,
      );
    }

    final crop = boardItemCropRect(item);
    final fullW = w / crop.width;
    final fullH = h / crop.height;

    return ClipRect(
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -crop.left * fullW,
              top: -crop.top * fullH,
              width: fullW,
              height: fullH,
              child: Image.network(
                url,
                width: fullW,
                height: fullH,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
