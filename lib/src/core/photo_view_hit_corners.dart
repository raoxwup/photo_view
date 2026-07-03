import 'package:flutter/widgets.dart';

import 'package:photo_view/src/controller/photo_view_controller_delegate.dart'
    show PhotoViewControllerDelegate;

mixin HitCornersDetector on PhotoViewControllerDelegate {
  // Tolerance to absorb floating-point error from `childSize * scale`, so that
  // an image sized virtually equal to the viewport is still treated as fitting.
  static const double _hitEpsilon = 0.1;

  bool _fitsWithin(double screen, double child) => screen - child >= -_hitEpsilon;

  HitCorners _hitCornersX() {
    final double childWidth = scaleBoundaries.childSize.width * scale;
    final double screenWidth = scaleBoundaries.outerSize.width;
    if (_fitsWithin(screenWidth, childWidth)) {
      return const HitCorners(true, true);
    }
    final x = -position.dx;
    final cornersX = this.cornersX();
    return HitCorners(x <= cornersX.min, x >= cornersX.max);
  }

  HitCorners _hitCornersY() {
    final double childHeight = scaleBoundaries.childSize.height * scale;
    final double screenHeight = scaleBoundaries.outerSize.height;
    if (_fitsWithin(screenHeight, childHeight)) {
      return const HitCorners(true, true);
    }
    final y = -position.dy;
    final cornersY = this.cornersY();
    return HitCorners(y <= cornersY.min, y >= cornersY.max);
  }

  bool _shouldMoveAxis(
      HitCorners hitCorners, double mainAxisMove, double crossAxisMove) {
    if (mainAxisMove == 0) {
      return false;
    }
    if (!hitCorners.hasHitAny) {
      return true;
    }
    final axisBlocked = hitCorners.hasHitBoth ||
        (hitCorners.hasHitMax ? mainAxisMove > 0 : mainAxisMove < 0);
    if (axisBlocked) {
      return false;
    }
    return true;
  }

  bool _shouldMoveX(Offset move) {
    final hitCornersX = _hitCornersX();
    final mainAxisMove = move.dx;
    final crossAxisMove = move.dy;

    return _shouldMoveAxis(hitCornersX, mainAxisMove, crossAxisMove);
  }

  bool _shouldMoveY(Offset move) {
    final hitCornersY = _hitCornersY();
    final mainAxisMove = move.dy;
    final crossAxisMove = move.dx;

    return _shouldMoveAxis(hitCornersY, mainAxisMove, crossAxisMove);
  }

  bool shouldMove(Offset move, Axis mainAxis) {
    if (mainAxis == Axis.vertical) {
      return _shouldMoveY(move);
    }
    return _shouldMoveX(move);
  }
}

class HitCorners {
  const HitCorners(this.hasHitMin, this.hasHitMax);

  final bool hasHitMin;
  final bool hasHitMax;

  bool get hasHitAny => hasHitMin || hasHitMax;

  bool get hasHitBoth => hasHitMin && hasHitMax;
}
