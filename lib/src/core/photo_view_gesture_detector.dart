import 'dart:async';
import 'dart:math' show exp;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'photo_view_hit_corners.dart';

class PhotoViewGestureDetector extends StatefulWidget {
  const PhotoViewGestureDetector({
    Key? key,
    this.hitDetector,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.child,
    this.onTapUp,
    this.onTapDown,
    this.behavior,
    this.onDoubleTapDown,
  }) : super(key: key);

  static bool get _isCtrlPressed => HardwareKeyboard.instance.isControlPressed;

  final GestureTapDownCallback? onDoubleTapDown;
  final HitCornersDetector? hitDetector;

  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onTapDown;

  final Widget? child;

  final HitTestBehavior? behavior;

  @override
  State<PhotoViewGestureDetector> createState() =>
      _PhotoViewGestureDetectorState();
}

class _PhotoViewGestureDetectorState extends State<PhotoViewGestureDetector> {
  // Debounce timer to group wheel events into a single synthetic scale gesture.
  Timer? _endTimer;

  // Whether a synthetic Ctrl-wheel zoom gesture is currently active.
  bool _isCtrlZooming = false;

  // Accumulated scale factor since the start of the synthetic gesture.
  // Scale in ScaleUpdateDetails represents scale since onScaleStart (1.0 initial).
  double _accumulatedScale = 1.0;

  // Configuration:
  static const double _sensitivity = 200.0;
  static const Duration _endDelay = Duration(milliseconds: 120);

  // Clamp bounds: lower bound > 0 to avoid Flutter's `scale >= 0.0` assertion.
  static const double _minScaleClamp = 0.01;
  static const double _maxScaleClamp = double.infinity;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }

    // If Ctrl isn't pressed, and we had an active synthetic gesture, end it.
    if (!PhotoViewGestureDetector._isCtrlPressed) {
      if (_isCtrlZooming) {
        _endSyntheticGesture();
      }
      return;
    }

    // Map scroll delta to a positive multiplicative factor using exp.
    // Negative dy (wheel up) -> factor > 1 (zoom in).
    // Positive dy (wheel down) -> factor < 1 (zoom out).
    final double delta = event.scrollDelta.dy;
    final double factor = exp(-delta / _sensitivity);

    if (!_isCtrlZooming) {
      _isCtrlZooming = true;
      _accumulatedScale = 1.0;
      widget.onScaleStart?.call(ScaleStartDetails(
        focalPoint: event.position,
        localFocalPoint: event.position,
        pointerCount: 2,
      ));
    }

    // Accumulate and clamp to avoid zero/negative values.
    _accumulatedScale =
        (_accumulatedScale * factor).clamp(_minScaleClamp, _maxScaleClamp);

    widget.onScaleUpdate?.call(ScaleUpdateDetails(
      focalPoint: event.position,
      localFocalPoint: event.position,
      focalPointDelta: event.scrollDelta,
      scale: _accumulatedScale,
      pointerCount: 2,
    ));

    // Reset debounce timer for end event.
    _endTimer?.cancel();
    _endTimer = Timer(_endDelay, _endSyntheticGesture);
  }

  void _endSyntheticGesture() {
    if (!_isCtrlZooming) {
      return;
    }
    _isCtrlZooming = false;
    _endTimer?.cancel();
    _endTimer = null;

    widget.onScaleEnd?.call(ScaleEndDetails(
      pointerCount: 2,
      velocity: Velocity.zero,
    ));
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = PhotoViewGestureDetectorScope.of(context);

    final Axis? axis = scope?.axis;

    final Map<Type, GestureRecognizerFactory> gestures =
        <Type, GestureRecognizerFactory>{};

    if (widget.onTapDown != null || widget.onTapUp != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: this),
        (TapGestureRecognizer instance) {
          instance
            ..onTapDown = widget.onTapDown
            ..onTapUp = widget.onTapUp;
        },
      );
    }

    gestures[DoubleTapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
      () => DoubleTapGestureRecognizer(debugOwner: this),
      (DoubleTapGestureRecognizer instance) {
        instance..onDoubleTapDown = widget.onDoubleTapDown;
      },
    );

    gestures[PhotoViewGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<PhotoViewGestureRecognizer>(
      () => PhotoViewGestureRecognizer(
          hitDetector: widget.hitDetector,
          debugOwner: this,
          validateAxis: axis),
      (PhotoViewGestureRecognizer instance) {
        instance
          ..dragStartBehavior = DragStartBehavior.start
          ..onStart = widget.onScaleStart
          ..onUpdate = widget.onScaleUpdate
          ..onEnd = widget.onScaleEnd;
      },
    );

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: RawGestureDetector(
        behavior: widget.behavior,
        child: widget.child,
        gestures: gestures,
      ),
    );
  }
}

class PhotoViewGestureRecognizer extends ScaleGestureRecognizer {
  PhotoViewGestureRecognizer({
    this.hitDetector,
    Object? debugOwner,
    this.validateAxis,
    PointerDeviceKind? kind,
  }) : super(debugOwner: debugOwner);
  final HitCornersDetector? hitDetector;
  final Axis? validateAxis;

  Map<int, Offset> _pointerLocations = <int, Offset>{};

  Offset? _initialFocalPoint;
  Offset? _currentFocalPoint;

  bool ready = true;

  @override
  void addAllowedPointer(event) {
    if (ready) {
      ready = false;
      _pointerLocations = <int, Offset>{};
    }
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    ready = true;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (validateAxis != null) {
      _computeEvent(event);
      _updateDistances();
      _decideIfWeAcceptEvent(event);
    }
    super.handleEvent(event);
  }

  void _computeEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!event.synthesized) {
        _pointerLocations[event.pointer] = event.position;
      }
    } else if (event is PointerDownEvent) {
      _pointerLocations[event.pointer] = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerLocations.remove(event.pointer);
    }

    _initialFocalPoint = _currentFocalPoint;
  }

  void _updateDistances() {
    final int count = _pointerLocations.keys.length;
    Offset focalPoint = Offset.zero;
    for (int pointer in _pointerLocations.keys)
      focalPoint += _pointerLocations[pointer]!;
    _currentFocalPoint =
        count > 0 ? focalPoint / count.toDouble() : Offset.zero;
  }

  void _decideIfWeAcceptEvent(PointerEvent event) {
    if (!(event is PointerMoveEvent)) {
      return;
    }
    final move = _initialFocalPoint! - _currentFocalPoint!;
    final bool shouldMove = hitDetector!.shouldMove(move, validateAxis!);
    if (shouldMove || _pointerLocations.keys.length > 1) {
      acceptGesture(event.pointer);
    }
  }
}

/// An [InheritedWidget] responsible to give a axis aware scope to [PhotoViewGestureRecognizer].
///
/// When using this, PhotoView will test if the content zoomed has hit edge every time user pinches,
/// if so, it will let parent gesture detectors win the gesture arena
///
/// Useful when placing PhotoView inside a gesture sensitive context,
/// such as [PageView], [Dismissible], [BottomSheet].
///
/// Usage example:
/// ```
/// PhotoViewGestureDetectorScope(
///   axis: Axis.vertical,
///   child: PhotoView(
///     imageProvider: AssetImage("assets/pudim.jpg"),
///   ),
/// );
/// ```
class PhotoViewGestureDetectorScope extends InheritedWidget {
  PhotoViewGestureDetectorScope({
    this.axis,
    required Widget child,
  }) : super(child: child);

  static PhotoViewGestureDetectorScope? of(BuildContext context) {
    final PhotoViewGestureDetectorScope? scope = context
        .dependOnInheritedWidgetOfExactType<PhotoViewGestureDetectorScope>();
    return scope;
  }

  final Axis? axis;

  @override
  bool updateShouldNotify(PhotoViewGestureDetectorScope oldWidget) {
    return axis != oldWidget.axis;
  }
}
