import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tagesbericht: protokolliert Aktionen und Fehler und erstellt daraus ein modernes PDF.
class Report {
  static const String _key = 'report_log';
  static final List<Map<String, dynamic>> _mem = [];
  static Future<void>? _loading;

  static Future<void> _load() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final old = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _mem.insertAll(0, old);
    } catch (_) {}
  }

  static void log(String kind, String text) {
    _mem.add({'t': DateTime.now().toIso8601String(), 'k': kind, 'x': text});
    _save();
  }

  static bool _isError(String s) {
    final l = s.toLowerCase();
    return l.startsWith('fehler') ||
        l.contains('nicht gefunden') ||
        l.contains('nicht erreichbar') ||
        l.contains('verweigert') ||
        l.contains('abgebrochen') ||
        l.contains('unbekannte') ||
        l.contains('kein passendes');
  }

  static void logTool(String name, String result) {
    final short = result.length > 180 ? result.substring(0, 180) : result;
    log(_isError(result) ? 'fehler' : 'ok', '$name: $short');
  }

  static Future<void> _save() async {
    try {
      await _load();
      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      _mem.removeWhere((e) => DateTime.parse(e['t'] as String).isBefore(cutoff));
      if (_mem.length > 600) _mem.removeRange(0, _mem.length - 600);
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_mem));
    } catch (_) {}
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static Future<void> share() async {
    try {
      await _load();
      final now = DateTime.now();
      final day = '${_two(now.day)}.${_two(now.month)}.${now.year}';
      final items = _mem.where((e) {
        final t = DateTime.parse(e['t'] as String);
        return t.year == now.year && t.month == now.month && t.day == now.day;
      }).toList();
      final okCount = items.where((e) => e['k'] == 'ok').length;
      final errors = items.where((e) => e['k'] == 'fehler').toList();

      final dark = PdfColor.fromInt(0xFF0F1B2D);
      final accent = PdfColor.fromInt(0xFF2DD4BF);
      final red = PdfColor.fromInt(0xFFF87171);
      final green = PdfColor.fromInt(0xFF34D399);
      final grey = PdfColor.fromInt(0xFF64748B);
      final redBg = PdfColor.fromInt(0xFFFEF2F2);

      pw.Widget stat(String label, String value, PdfColor c) => pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 8),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(children: [
                pw.Container(width: 4, height: 38, color: c),
                pw.SizedBox(width: 10),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(value, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: dark)),
                  pw.Text(label, style: pw.TextStyle(fontSize: 9, color: grey)),
                ]),
              ]),
            ),
          );

      pw.Widget row(Map<String, dynamic> e) {
        final isErr = e['k'] == 'fehler';
        final isInfo = e['k'] == 'info';
        final c = isErr ? red : (isInfo ? grey : green);
        final t = DateTime.parse(e['t'] as String);
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: isErr ? redBg : PdfColors.white,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              width: 8,
              height: 8,
              margin: const pw.EdgeInsets.only(top: 3, right: 8),
              decoration: pw.BoxDecoration(color: c, shape: pw.BoxShape.circle),
            ),
            pw.Text('${_two(t.hour)}:${_two(t.minute)}', style: pw.TextStyle(fontSize: 9, color: grey)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: pw.Text(e['x'].toString(), style: const pw.TextStyle(fontSize: 10))),
          ]),
        );
      }

      pw.Widget heading(String s) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
            child: pw.Text(s, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: dark)),
          );

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(color: dark, borderRadius: pw.BorderRadius.circular(14)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('CHARLES', style: pw.TextStyle(color: accent, fontSize: 10, letterSpacing: 3, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('Tagesbericht', style: pw.TextStyle(color: PdfColors.white, fontSize: 26, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(day, style: pw.TextStyle(color: PdfColors.grey400, fontSize: 11)),
            ]),
          ),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            stat('Eintraege', '${items.length}', accent),
            stat('Erfolgreich', '$okCount', green),
            stat('Fehler', '${errors.length}', red),
          ]),
          heading('Was nicht funktioniert hat'),
          if (errors.isEmpty)
            pw.Text('Heute gab es keine Fehler.', style: pw.TextStyle(fontSize: 11, color: grey))
          else
            ...errors.map(row),
          heading('Alle Aktionen des Tages'),
          if (items.isEmpty)
            pw.Text('Heute wurde noch nichts protokolliert.', style: pw.TextStyle(fontSize: 11, color: grey))
          else
            ...items.map(row),
        ],
      ));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Charles-Tagesbericht-${now.year}-${_two(now.month)}-${_two(now.day)}.pdf');
      await file.writeAsBytes(await doc.save());
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Charles Tagesbericht $day',
        text: 'Charles Tagesbericht $day',
      );
    } catch (e) {
      log('fehler', 'Bericht konnte nicht erstellt werden: $e');
    }
  }
}