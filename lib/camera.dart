import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite/tflite.dart';
import 'dart:math' as math;

typedef Callback = void Function(List<dynamic> list, int h, int w);

class Camera extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Callback setRecognitions;
  final String model;

  const Camera(this.cameras, this.model, this.setRecognitions, {super.key});

  @override
  // ignore: library_private_types_in_public_api
  _CameraState createState() => _CameraState();
}

class _CameraState extends State<Camera> {
  CameraController? controller;
  bool isDetecting = false;
  FlutterTts? flutterTts;
  bool objectSpoken = false;
  String? lastDetectedObject;
  DateTime? lastDetectionTime;

  @override
  void initState() {
    super.initState();

    // Initialize Flutter TTS
    flutterTts = FlutterTts();

    if (widget.cameras == null || widget.cameras.isEmpty) {
      if (kDebugMode)
      {
        print('No camera is found');
      }
    } else {
      controller = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
      );
      controller?.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});

        controller?.startImageStream((CameraImage img) {
          if (!isDetecting) {
            isDetecting = true;

            int startTime = DateTime.now().millisecondsSinceEpoch;

            Tflite.detectObjectOnFrame(
              bytesList: img.planes.map((plane) {
                return plane.bytes;
              }).toList(),
              model: "SSDMobileNet",
              imageHeight: img.height,
              imageWidth: img.width,
              imageMean: 127.5,
              imageStd: 127.5,
              numResultsPerClass: 1,
              numBoxesPerBlock: 2,
              threshold: 0.6,
            ).then((recognitions) {
              int endTime = DateTime.now().millisecondsSinceEpoch;
              if (kDebugMode)
              {
                print("Detection took ${endTime - startTime}");
              }

              widget.setRecognitions(recognitions!, img.height, img.width);

              isDetecting = false;

              // Convert the detected object to speech
              if (recognitions != null && recognitions.isNotEmpty) {
                String detectedObject = recognitions[0]['detectedClass'];
                if (detectedObject != lastDetectedObject ||
                    lastDetectionTime == null ||
                    DateTime.now().difference(lastDetectionTime!) >=
                        const Duration(seconds: 30)) {
                  speak(recognitions);
                  lastDetectedObject = detectedObject;
                  lastDetectionTime = DateTime.now();
                }
              }
            });
          }
        });
      });
    }
  }

  @override
  void dispose() async {
    await Tflite.close();
    controller?.dispose();
    super.dispose();
  }

  // Method to convert text to speech
  Future<void> speak(List<dynamic> recognitions) async {
    // Sort the recognitions based on confidence in descending order
    recognitions.sort((a, b) => b['confidenceInClass'].compareTo(a['confidenceInClass']));

    String speechText = '';

    for (int i = 0; i < recognitions.length; i++) {
      String detectedObject = recognitions[i]['detectedClass'];

      if (i == recognitions.length - 1 && recognitions.length > 1) {
        // Last detected object
        speechText += 'and $detectedObject';
      } else
      {
        speechText += detectedObject;
      }
    }

    await flutterTts?.speak(speechText);
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Container();
    }

    var tmp = MediaQuery.of(context).size;
    var screenH = math.max(tmp.height, tmp.width);
    var screenW = math.min(tmp.height, tmp.width);
    tmp = controller!.value.previewSize!;
    var previewH = math.max(tmp.height, tmp.width);
    var previewW = math.min(tmp.height, tmp.width);
    var screenRatio = screenH / screenW;
    var previewRatio = previewH / previewW;

    return OverflowBox(
      maxHeight:
      screenRatio > previewRatio ? screenH : screenW / previewW * previewH,
      maxWidth:
      screenRatio > previewRatio ? screenH / previewH * previewW : screenW,
      child: CameraPreview(controller!),
    );
  }
}