import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// The plugin exposes its platform interface from this path, not printing.dart.
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ripot/core/services/engagement_service.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/reports/data/letterhead_repository.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:ripot/features/reports/ui/report_preview_screen.dart';
import 'package:ripot/features/reports/ui/ripot_pdf_preview.dart';
import 'package:ripot/features/reports/ui/saved_pdf_viewer_screen.dart';

/// Only the OS boundary is replaced. The real screens, PdfShareAction,
/// EngagementService, preference writes and in_app_review Dart plugin run.
class _NativePrinting extends PrintingPlatform {
  bool shareSucceeds = true;
  int shares = 0;
  int prints = 0;
  Uint8List? sharedBytes;
  String? sharedFilename;
  Completer<void>? shared;

  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, canShare: true);

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    shares++;
    sharedBytes = bytes;
    sharedFilename = filename;
    if (shared != null && !shared!.isCompleted) shared!.complete();
    return shareSucceeds;
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    prints++;
    return true;
  }

  @override
  Future<List<Printer>> listPrinters() async => [];

  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;

  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) => throw UnsupportedError('Not used by report previews');

  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) => const Stream.empty();
}

Future<void> _mount(WidgetTester tester, Widget screen) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(
    builder: (_, child) => ReviewPromptHost(child: child!),
    home: screen,
  ));
  // Resolve saved PDF futures and Printing.info(), then the raster debounce.
  // No raster output is needed to exercise the actual toolbar actions.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _returnToApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(seconds: 1));
}

Widget _savedPdf() => SavedPdfViewerScreen(
  title: 'Fictional test report',
  pdfFileName: 'fictional-report.pdf',
  pdfBytesFuture: Future.value(Uint8List.fromList([37, 80, 68, 70])),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const reviewChannel = MethodChannel('dev.britannio.in_app_review');
  late PrintingPlatform originalPrinting;
  late _NativePrinting printing;
  late int reviewRequests;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    originalPrinting = PrintingPlatform.instance;
    printing = _NativePrinting();
    PrintingPlatform.instance = printing;
    reviewRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reviewChannel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'requestReview':
          reviewRequests++;
          return null;
        default:
          throw StateError('Unexpected review method: ${call.method}');
      }
    });
  });

  tearDown(() {
    EngagementService.controller.stop();
    PrintingPlatform.instance = originalPrinting;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reviewChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('ten real saved-PDF Share taps reach review only after return',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, _savedPdf());
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(find.byTooltip('Share PDF'), findsOneWidget);

    for (var count = 1; count <= 10; count++) {
      await tester.tap(find.byTooltip('Share PDF'));
      await tester.pump();
      expect(printing.shares, count);
      expect(prefs.getInt('review.completedShares'), count);
      expect(reviewRequests, 0, reason: 'Never request over the share chooser');
      await _returnToApp(tester);
      expect(reviewRequests, count == 10 ? 1 : 0);
    }
    expect(printing.sharedFilename, 'fictional-report.pdf');
    expect(printing.sharedBytes, orderedEquals([37, 80, 68, 70]));
    expect(prefs.getInt('review.lastRequestShares'), 10);

    // Returning from Google's surface cannot immediately prompt again.
    await _returnToApp(tester);
    expect(reviewRequests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('draft Preview Share renders PDF and reaches the same counter',
      (tester) async {
    SharedPreferences.setMockInitialValues({'review.completedShares': 9});
    final prefs = await SharedPreferences.getInstance();
    final reports = ReportsRepository();
    final editor = ReportEditorProvider(
      repo: reports,
      templatesRepo: TemplatesRepository(),
    );
    final access = AccessProvider(repo: AccessRepository());
    addTearDown(editor.dispose);
    addTearDown(access.dispose);
    await _mount(tester, MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: editor),
        ChangeNotifierProvider.value(value: access),
        Provider.value(value: reports),
        Provider.value(value: LetterheadsRepository()),
      ],
      child: const ReportPreviewScreen(),
    ));
    expect(find.byIcon(Icons.share), findsOneWidget);
    printing.shared = Completer<void>();
    // The production renderer loads bundled fonts and performs real PDF IO.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Share PDF'));
      await printing.shared!.future.timeout(const Duration(seconds: 20));
    });
    await tester.pump();
    expect(printing.shares, 1);
    expect(printing.sharedBytes!.take(5), orderedEquals([37, 80, 68, 70, 45]));
    expect(printing.sharedFilename, reports.pdfFileNameForDoc(editor.doc));
    expect(prefs.getInt('review.completedShares'), 10);
    expect(reviewRequests, 0);
    await _returnToApp(tester);
    expect(reviewRequests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Print does not count as Share or reach the review threshold',
      (tester) async {
    SharedPreferences.setMockInitialValues({'review.completedShares': 9});
    final prefs = await SharedPreferences.getInstance();
    await _mount(tester, _savedPdf());
    await tester.tap(find.byIcon(Icons.print));
    await tester.pump();
    expect(printing.prints, 1);
    expect(printing.shares, 0);
    expect(prefs.getInt('review.completedShares'), 9);
    await _returnToApp(tester);
    expect(reviewRequests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unsuccessful native share does not count or request review',
      (tester) async {
    SharedPreferences.setMockInitialValues({'review.completedShares': 9});
    final prefs = await SharedPreferences.getInstance();
    printing.shareSucceeds = false;
    await _mount(tester, _savedPdf());
    await tester.tap(find.byTooltip('Share PDF'));
    await tester.pump();
    expect(printing.shares, 1);
    expect(prefs.getInt('review.completedShares'), 9);
    await _returnToApp(tester);
    expect(reviewRequests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview respects disabled sharing and printing', (tester) async {
    await _mount(tester, Scaffold(body: RipotPdfPreview(
      buildDocument: (_) async => Uint8List.fromList([37, 80, 68, 70]),
      pdfFileName: 'fictional-report.pdf',
      allowSharing: false,
      allowPrinting: false,
    )));
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.print), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
