import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:charles/butler.dart';

void main() {
  testWidgets('icon', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            width: 1024,
            height: 1024,
            color: const Color(0xFF0B1220),
            child: Center(
              child: Transform.scale(
                scale: 5.0,
                child: const SizedBox(
                  width: 180,
                  height: 180,
                  child: ButlerAvatar(state: ButlerState.idle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('assets/icon').createSync(recursive: true);
      File('assets/icon/icon.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}