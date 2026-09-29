import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/listing_model_viewer.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/model_viewer_controller.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/preview_download.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/preview_runtime.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

/// The listing page's 3D view, against the real seeded server. The
/// VM has no browser canvas, so the Lumina scene itself is covered by the
/// Chrome smoke; here: the toggle, lazy loading, the real preview download
/// and the progress / error states.
void main() {
  late TestBackend backend;
  setUpAll(() async => backend = await TestBackend.start());
  tearDownAll(() => backend.stop());

  final bananaBytes = File('$testAssetsDir/Props/Banana Bunch/banana_bunch_short.glb').readAsBytesSync();

  test('the preview downloads with increasing progress and a verified checksum', () async {
    final client = backend.client();
    final version = (await client.listing('banana-bunch')).latestVersion!;
    final progress = <double>[];
    final bytes = await downloadPreviewModel(client, version.previewModelUrl!,
        expectedSha256: version.previewModelSha256, expectedSize: version.previewModelSize, onProgress: progress.add);
    expect(bytes, bananaBytes);
    expect(sha256.convert(bytes).toString(), version.previewModelSha256);
    expect(progress.first, 0);
    expect(progress.last, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }

    await expectLater(
      downloadPreviewModel(client, version.previewModelUrl!, expectedSha256: '0' * 64, expectedSize: version.previewModelSize),
      throwsA(isA<PreviewDownloadException>().having((e) => e.message, 'message', contains('checksum'))),
    );
    var started = false;
    await expectLater(
      downloadPreviewModel(client, version.previewModelUrl!,
          expectedSize: version.previewModelSize, maxBytes: 1024, onProgress: (_) => started = true),
      throwsA(isA<PreviewDownloadException>().having((e) => e.message, 'message', contains('too large'))),
    );
    expect(started, isFalse, reason: 'refused before downloading');
    client.close();
  });

  testWidgets('model listings get a 3D view toggle that lazy-loads the Lumina runtime; themes do not', (tester) async {
    final client = backend.client();
    await pumpApp(tester, client, location: '/listings/lumina-ember');
    await settle(tester, until: find.byKey(const ValueKey('listing_title')));
    expect(find.byKey(const ValueKey('gallery_3d')), findsNothing, reason: 'a theme has no preview model');

    await pumpApp(tester, client, location: '/listings/banana-bunch');
    await settle(tester, until: find.byKey(const ValueKey('gallery_3d')));
    expect(find.text('3D view'), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery_images')), findsOneWidget);
    expect(find.byType(ListingModelViewer), findsNothing, reason: 'the images show first');
    expect(LuminaPreviewRuntime.isCodeLoaded, isFalse, reason: 'nothing of the runtime loads before the 3D view opens');

    await tester.tap(find.byKey(const ValueKey('gallery_3d')));
    await tester.pump();
    expect(find.byType(ListingModelViewer), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer_progress')), findsOneWidget, reason: 'the staged progress bar');
    expect(find.bySemanticsLabel(RegExp('^3D view loading')), findsOneWidget);

    // The model downloads from the server (verified), then the renderer is
    // asked for: off the browser there is none, so the error state shows.
    await settle(tester, until: find.byKey(const ValueKey('viewer_error')));
    expect(LuminaPreviewRuntime.isCodeLoaded, isTrue);
    final viewer = tester.widget<ListingModelViewer>(find.byType(ListingModelViewer));
    expect(viewer.controller.model, bananaBytes, reason: 'the preview downloaded and passed its checksum');
    expect(viewer.controller.stage, ViewerStage.error);
    expect(find.text('The 3D view needs a browser with WebGL2.'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer_retry')), findsOneWidget);

    expect(find.bySemanticsLabel(RegExp('^3D view error')), findsOneWidget);

    // Retry runs the stages again (the downloaded model is kept) and fails
    // the same way.
    final model = viewer.controller.model;
    final stages = <ViewerStage>[];
    void record() => stages.add(viewer.controller.stage);
    viewer.controller.addListener(record);
    await tester.tap(find.byKey(const ValueKey('viewer_retry')));
    await tester.pump();
    await settle(tester, until: find.byKey(const ValueKey('viewer_error')));
    viewer.controller.removeListener(record);
    expect(stages, [ViewerStage.loadingRuntime, ViewerStage.loadingRenderer, ViewerStage.error],
        reason: 'no second download');
    expect(viewer.controller.model, same(model));

    // Back to the images.
    await tapOn(tester, find.byKey(const ValueKey('gallery_images')));
    expect(find.byType(ListingModelViewer), findsNothing);
    client.close();
  });
}
