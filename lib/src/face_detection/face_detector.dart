import 'dart:developer' as dev;
import 'package:camera/camera.dart';
import 'package:facelivenessdetection/src/debouncer/debouncer.dart';
import 'package:facelivenessdetection/src/detector_view/detector_view.dart';
import 'package:facelivenessdetection/src/painter/dotted_painter.dart';
import 'package:facelivenessdetection/src/rule_set/rule_set.dart';
import 'package:flutter/material.dart';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorView extends StatefulWidget {
  final Size cameraSize;
  final Function(bool validated) onSuccessValidation;
  final void Function(Rulesets ruleset)? onRulesetCompleted;
  final List<Rulesets> ruleset;
  final Color activeProgressColor;
  final Color progressColor;
  final List<Widget> Function(
      {required Rulesets state,
      required int countdown,
      required bool hasFace})? onChildren;
  final int totalDots;
  final double dotRadius;
  const FaceDetectorView(
      {super.key,
      required this.onRulesetCompleted,
      this.ruleset = const [
        Rulesets.smiling,
        Rulesets.blink,
        Rulesets.toRight,
        Rulesets.toLeft,
        Rulesets.tiltUp,
        Rulesets.tiltDown
      ],
      this.onChildren,
      this.progressColor = Colors.green,
      this.activeProgressColor = Colors.red,
      this.totalDots = 60,
      this.dotRadius = 3,
      required this.onSuccessValidation,
      this.cameraSize = const Size(200, 200)})
      : assert(ruleset.length == 0, 'Ruleset cannot be empty');

  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  List<Rulesets> ruleset = [];
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  String? _text;
  final _cameraLensDirection = CameraLensDirection.front;
  late ValueNotifier<Rulesets?> _currentTest;
  Debouncer? _debouncer;
  CameraController? controller;
  bool hasFace = false;
  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    _debouncer?.stop();
    super.dispose();
  }

  @override
  void initState() {
    ruleset = widget.ruleset.toList();
    _currentTest = ValueNotifier<Rulesets?>(ruleset.first);
    _debouncer = Debouncer(
        durationInSeconds: 5,
        onComplete: () =>
            dev.log('Timer is completed', name: 'Photo verification timer'));
    _debouncer?.start();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: kToolbarHeight),
        ValueListenableBuilder(
          valueListenable: _currentTest,
          builder: (context, state, child) {
            double targetProgress = state != null
                ? (widget.ruleset.indexOf(state) / widget.ruleset.length)
                    .toDouble()
                : 1.0;
            return TweenAnimationBuilder(
                duration: Duration(milliseconds: 500), // Animation speed
                tween: Tween<double>(begin: 0, end: targetProgress),
                builder: (context, animation, _) {
                  return CustomPaint(
                    painter: DottedCirclePainter(
                        progress: animation,
                        totalDots: widget.totalDots,
                        dotRadius: widget.dotRadius),
                    child: child,
                  );
                });
          },
          child: Container(
            height: widget.cameraSize.height,
            width: widget.cameraSize.width,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: DetectorView(
              onController: (controller_) => controller = controller_,
              title: 'Face Detector',
              text: _text,
              onImage: _processImage,
              initialCameraLensDirection: _cameraLensDirection,
            ),
          ),
        ),
        SizedBox(height: 4.5),
        ValueListenableBuilder<Rulesets?>(
            valueListenable: _currentTest,
            builder: (context, state, child) {
              if (state != null) {
                return Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: widget.onChildren?.call(
                              state: state,
                              countdown: _debouncer!.timeLeft,
                              hasFace: hasFace) ??
                          []),
                );
              } else {
                return Center(child: SizedBox.shrink());
              }
            }),
      ],
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final faces = await _faceDetector.processImage(inputImage);
    hasFace = faces.isNotEmpty;
    if (!(_debouncer?.isRunning ?? false)) handleRuleSet(faces);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
    } else {
      String text = 'Faces found: ${faces.length}\n\n';
      for (final face in faces) {
        text += 'face: ${face.boundingBox}\n\n';
      }
      _text = text;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  void handleRuleSet(List<Face> faces) {
    if (faces.isEmpty) return;
    for (Face face in faces) {
      startRandomizedTime(face);
    }
  }

  startRandomizedTime(Face face) {
    if (ruleset.isEmpty) {
      widget.onSuccessValidation.call(true);
      return;
    } else {
      widget.onSuccessValidation.call(false);
    }
    var currentRuleset = ruleset.removeAt(0);
    bool isDetected = false;
    switch (currentRuleset) {
      case Rulesets.smiling:
        isDetected = _onSmilingDetected(face);
        break;
      case Rulesets.blink:
        isDetected = _onBlinkDetected(face);
        break;
      case Rulesets.tiltUp:
        isDetected = _detectHeadTiltUp(face);
        break;
      case Rulesets.tiltDown:
        isDetected = _detectHeadTiltDown(face);
        break;
      case Rulesets.toLeft:
        isDetected = _detectLeftHeadMovement(face);
        break;
      case Rulesets.toRight:
        isDetected = _detectRightHeadMovement(face);
        break;
    }
    if (!isDetected) {
      ruleset.insert(0, currentRuleset);
    } else {
      if (ruleset.isNotEmpty) {
        _currentTest.value = ruleset.first;
        _debouncer?.start();
      } else {
        _currentTest.value = null;
        _debouncer?.stop();
      }
    }
  }

  bool _detectHeadTiltUp(Face face) {
    return _detectHeadTilt(face, up: true);
  }

  bool _detectHeadTiltDown(Face face) {
    return _detectHeadTilt(face, up: false);
  }

  bool _detectHeadTilt(Face face, {bool up = true}) {
    final double? rotX = face.headEulerAngleX;
    if (rotX == null) return false;

    if (!up) {
      dev.log(rotX.toString(), name: 'Head Movement');
      if (rotX < -20) {
        // Adjust threshold if needed
        widget.onRulesetCompleted?.call(Rulesets.tiltUp);
        return true;
      }
    } else {
      if (rotX > 20) {
        widget.onRulesetCompleted?.call(Rulesets.tiltUp);
        return true;
      }
    }
    return false;
  }

  bool _detectRightHeadMovement(Face face) {
    return _detectHeadMovement(face, left: true);
  }

  bool _detectLeftHeadMovement(Face face) {
    return _detectHeadMovement(face, left: false);
  }

  bool _detectHeadMovement(Face face, {bool left = true}) {
    final double? rotY = face.headEulerAngleY;
    if (rotY == null) return false;
    if (left) {
      if (rotY < -40) {
        widget.onRulesetCompleted?.call(Rulesets.toLeft);
        return true;
      }
    } else {
      if (rotY > 40) {
        widget.onRulesetCompleted?.call(Rulesets.toRight);
        return true;
      }
    }
    return false;
  }

  bool _onBlinkDetected(Face face) {
    final double? leftEyeOpenProb = face.leftEyeOpenProbability;
    final double? rightEyeOpenProb = face.rightEyeOpenProbability;
    const double eyeOpenThreshold = 0.6;
    if (leftEyeOpenProb != null && rightEyeOpenProb != null) {
      if (leftEyeOpenProb < eyeOpenThreshold &&
          rightEyeOpenProb < eyeOpenThreshold) {
        widget.onRulesetCompleted?.call(Rulesets.blink);
        return true;
      }
    }
    return false;
  }

  bool _onSmilingDetected(Face face) {
    if (face.smilingProbability != null) {
      final double? smileProb = face.smilingProbability;
      if ((smileProb ?? 0) > .5) {
        if (widget.onRulesetCompleted != null) {
          widget.onRulesetCompleted!(Rulesets.smiling);
          return true;
        }
      }
    }
    return false;
  }
}
