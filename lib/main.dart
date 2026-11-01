import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'butler.dart';
import 'stage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

const model = 'claude-sonnet-5-5';
const systemPrompt = 'Du bist Charles, der britische Butler und pers\u00f6nliche Sprachassistent auf dem iPhone. Sprich in gew\u00e4hlter, h\u00f6flicher Ausdrucksweise mit trocken-britischem Humor und sprich den Nutzer respektvoll mit Sie an. Antworte auf Deutsch, kurz in ein bis drei S\u00e4tzen, in nat\u00fcrlicher gesprochener Sprache, ohne Markdown, Aufz\u00e4hlungen, Emojis oder URLs. Nutze deine Werkzeuge, statt zu raten. Schalte Ger\u00e4te nur, wenn der Nutzer es ausdr\u00fccklich verlangt.';

const tools = [
  {'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 3},
  {
    'name': 'get_weather',
    'description': 'Aktuelles Wetter und Vorhersage fuer einen Ort. Leer = Heimatort.',
    'input_schema': {'type': 'object', 'properties': {'location': {'type': 'string'}, 'days': {'type': 'integer'}}}
  },
  {
    'name': 'set_timer',
    'description': 'Stellt einen Timer in Sekunden. Charles sagt Bescheid, wenn er ablaeuft.',
    'input_schema': {'type': 'object', 'properties': {'seconds': {'type': 'number'}, 'label': {'type': 'string'}}, 'required': ['seconds']}
  },
  {
    'name': 'ha_search',
    'description': 'Sucht Home-Assistant-Entitaeten nach Stichworten und liefert ihren Zustand. Immer zuerst nutzen.',
    'input_schema': {'type': 'object', 'properties': {'query': {'type': 'string'}}, 'required': ['query']}
  },
  {
    'name': 'ha_call_service',
    'description': 'Schaltet ein Geraet in Home Assistant, z. B. light.turn_on. Erlaubt: climate, cover, fan, light, media_player, scene, script, switch.',
    'input_schema': {
      'type': 'object',
      'properties': {'domain': {'type': 'string'}, 'service': {'type': 'string'}, 'entity_id': {'type': 'string'}, 'data': {'type': 'object'}},
      'required': ['domain', 'service', 'entity_id']
    }
  },
  {
    'name': 'whatsapp_send',
    'description': 'Oeffnet WhatsApp mit fertigem Text fuer einen Kontakt. Lorenz tippt selbst auf Senden. Kontaktname wird in den Kontakten gesucht, alternativ direkte Nummer.',
    'input_schema': {'type': 'object', 'properties': {'contact': {'type': 'string'}, 'number': {'type': 'string'}, 'text': {'type': 'string'}}, 'required': ['text']}
  },
  {
    'name': 'phone_call',
    'description': 'Startet einen normalen Telefonanruf an einen Kontakt oder eine Nummer. Lorenz bestaetigt am iPhone.',
    'input_schema': {'type': 'object', 'properties': {'contact': {'type': 'string'}, 'number': {'type': 'string'}}}
  },
];

void main() => runApp(const CharlesApp());

class CharlesApp extends StatelessWidget {
  const CharlesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Charles',
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark)),
        home: const ChatPage(),
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && sttOk && !busy) {
      listening = false;
      stt.stop().then((_) => toggleMic());
    }
  }

  final stt = SpeechToText();
  final tts = FlutterTts();
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  final shown = <MapEntry<bool, String>>[];
  final history = <Map<String, dynamic>>[];
  final storage = _Store();
  final cfg = <String, String>{};
  bool listening = false; bool conversation = false;
  bool sttOk = false;
  bool pulse = true;
  bool speaking = false;
  String? actionText;
  IconData? actionIcon;
  bool actionDone = false;
  Timer? actionTimer;

  void showAction(String text, IconData icon) {
    actionTimer?.cancel();
    setState(() {
      actionText = text;
      actionIcon = icon;
      actionDone = false;
    });
  }

  void finishAction() {
    actionTimer?.cancel();
    if (!mounted) return;
    setState(() => actionDone = true);
    actionTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          actionText = null;
          actionIcon = null;
          actionDone = false;
        });
      }
    });
  }

  MapEntry<String, IconData> toolInfo(String name) {
    switch (name) {
      case 'ha_call_service':
        return MapEntry('Ich k\u00fcmmere mich darum ...', Icons.lightbulb);
      case 'get_weather':
        return MapEntry('Ich schaue nach dem Wetter ...', Icons.cloud);
      case 'set_timer':
        return MapEntry('Ich stelle den Timer ...', Icons.timer);
      case 'whatsapp_send':
      return MapEntry('Ich oeffne WhatsApp ...', Icons.chat);
    case 'phone_call':
      return MapEntry('Ich starte den Anruf ...', Icons.call);
    case 'ha_search':
        return MapEntry('Ich sehe im Haus nach ...', Icons.home);
    }
    return MapEntry('Einen Augenblick ...', Icons.auto_awesome);
  }
  bool busy = false;
  StageKind stageKind = StageKind.generic;
  bool stageOn = true;

  void stageFor(String name, Map<String, dynamic> a) {
    stageOn = true;
    switch (name) {
      case 'get_weather':
        stageKind = StageKind.weather;
        break;
      case 'set_timer':
        stageKind = StageKind.timer;
        break;
      case 'ha_search':
        stageKind = StageKind.home;
        break;
      case 'whatsapp_send':
        stageKind = StageKind.whatsapp;
        break;
      case 'phone_call':
        stageKind = StageKind.phone;
        break;
      case 'ha_call_service':
        {
          final d = (a['domain'] ?? '').toString();
          final sv = (a['service'] ?? '').toString();
          if (d == 'cover') {
            stageKind = StageKind.blinds;
            stageOn = !sv.contains('open');
          } else if (d == 'light') {
            stageKind = StageKind.light;
            stageOn = !sv.contains('off');
          } else if (d == 'climate') {
            stageKind = StageKind.climate;
            stageOn = !sv.contains('off');
          } else {
            stageKind = StageKind.generic;
          }
        }
        break;
      default:
        stageKind = StageKind.generic;
    }
  }

  String contactDebug = '';

  int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var m = prev[j] + 1;
        if (cur[j - 1] + 1 < m) m = cur[j - 1] + 1;
        if (prev[j - 1] + cost < m) m = prev[j - 1] + cost;
        cur[j] = m;
      }
      prev = cur;
    }
    return prev[b.length];
  }

  String _norm(String s) => s.toLowerCase().replaceAll('Ã¤', 'ae').replaceAll('Ã¶', 'oe').replaceAll('Ã¼', 'ue').replaceAll('ÃŸ', 'ss').trim();

  Future<String?> findNumber(String contact, String number) async {
    contactDebug = '';
    var n = number.trim();
    if (n.isEmpty && contact.trim().isNotEmpty) {
      try {
        final st = await FlutterContacts.permissions.request(PermissionType.read);
        contactDebug = 'Erlaubnis: $st. ';
        final list = await FlutterContacts.getAll(properties: ContactProperties.all);
        contactDebug += '${list.length} Kontakte gelesen. ';
        final q = _norm(contact);
        final qt = q.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();
        dynamic best;
        var bestScore = 999;
        for (final c in list) {
          final dynamic cc = c;
          final nm = _norm('${cc.displayName}');
          final List ph = (cc.phones ?? []) as List;
          if (ph.isEmpty || nm.isEmpty) continue;
          final ct = nm.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();
          var score = 0;
          var ok = true;
          for (final t in qt) {
            var bd = 99;
            for (final x in ct) {
              var d = _lev(t, x);
              if (x.length >= 3 && t.length >= 3 && (x.startsWith(t) || t.startsWith(x))) d = 0;
              if (d < bd) bd = d;
            }
            final lim = t.length >= 5 ? 2 : 1;
            if (bd > lim) {
              ok = false;
              break;
            }
            score += bd;
          }
          if (!ok) continue;
          score = score * 10 + (ct.length - qt.length).abs();
          if (score < bestScore) {
            best = cc;
            bestScore = score;
          }
        }
        if (best != null) {
          final List ph = (best.phones ?? []) as List;
          final dynamic p = ph.first;
          n = '${p.number}';
          contactDebug += 'Treffer: ${best.displayName}. ';
        } else {
          contactDebug += 'Kein Kontakt mit Nummer passt zu $contact. ';
        }
      } catch (e) {
        contactDebug += 'Fehler: $e';
      }
    }
    n = n.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.isEmpty) return null;
    if (n.startsWith('00')) n = '+${n.substring(2)}';
    if (n.startsWith('0')) n = '+49${n.substring(1)}';
    return n;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
    Future.delayed(const Duration(seconds: 3), () {
    });
  }

  String pref(String k) => cfg[k] ?? '';

  Future<void> init() async {
    for (final k in ['key', 'home', 'ha_url', 'ha_url2', 'ha_token']) {
      cfg[k] = await storage.read(key: k) ?? '';
    }
    await tts.setLanguage('de-DE');
    await tts.setSpeechRate(0.42);
    tts.setStartHandler(() {
      if (mounted) setState(() => speaking = true);
    });
    tts.setCompletionHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setCancelHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setErrorHandler((_) {
      if (mounted) setState(() => speaking = false);
    });
    await tts.setPitch(0.8);
await tts.awaitSpeakCompletion(true); await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker, IosTextToSpeechAudioCategoryOptions.allowBluetooth, IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP, IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
    try {
      final voices = (await tts.getVoices) as List;
      for (final n in ['Markus', 'Yannick', 'Martin']) {
        final v = voices.firstWhere((x) => x['name'].toString().contains(n) && x['locale'].toString().startsWith('de'), orElse: () => null);
        if (v != null) {
          await tts.setVoice({'name': v['name'].toString(), 'locale': v['locale'].toString()});
          break;
        }
      }
    } catch (_) {}
    sttOk = await stt.initialize(onStatus: (s) { if ((s == 'done' || s == 'notListening') && listening && mounted && !busy) { setState(() => listening = false); if (ctrl.text.trim().isNotEmpty) { send(ctrl.text); } else { Future.delayed(const Duration(milliseconds: 800), () { if (conversation && mounted && !listening && !busy) toggleMic(); }); } } });
    if (pref('key').isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openSettings();
      });
    } else if (sttOk) {
      toggleMic();
    }
    setState(() {});
  }

  void openSettings() {
    final names = {
      'key': 'Claude API-SchlÃƒÂ¼ssel',
      'home': 'Heimatort',
      'ha_url': 'Home Assistant URL',
'ha_url2': 'Home Assistant URL extern (Tailscale)',
      'ha_token': 'Home Assistant Token',
    };
    final cs = {for (final k in names.keys) k: TextEditingController(text: pref(k))};
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Einstellungen'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in names.keys)
              TextField(
                controller: cs[k],
                obscureText: k == 'key' || k == 'ha_token',
                decoration: InputDecoration(labelText: names[k]),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              for (final k in cs.keys) {
                cfg[k] = cs[k]!.text.trim();
                await storage.write(key: k, value: cfg[k]);
              }
              setState(() {});
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> toggleMic() async {
    if (!sttOk) {
      setState(() => shown.add(MapEntry(false, 'Ich darf das Mikrofon nicht nutzen. Bitte erlaube es in den iPhone-Einstellungen.')));
      return;
    }
    if (listening) {
      conversation = false; await stt.stop();
      setState(() => listening = false);
      return;
    }
    conversation = true; await stt.stop(); await tts.stop();
    setState(() => listening = true);
    await stt.listen(
      localeId: 'de_DE', listenFor: const Duration(seconds: 60), pauseFor: const Duration(seconds: 3), listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) { setState(() => ctrl.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => listening = false);
          if (r.recognizedWords.trim().isEmpty) { Future.delayed(const Duration(milliseconds: 800), () { if (conversation && mounted && !listening && !busy) toggleMic(); }); } else { send(r.recognizedWords); }
        }
      },
    );
  }

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });

  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty || busy) return;
    ctrl.clear();
    setState(() {
      shown.add(MapEntry(true, text));
      busy = true;
    });
    scrollDown();
    final start = history.length; history.add({'role': 'user', 'content': '[Jetzt: ${DateTime.now()}] $text'});
    String answer;
    try {
      answer = await ask();
    } catch (e) {
      history.removeRange(start, history.length); answer = 'Das hat leider nicht geklappt: $e';
    }
    setState(() {
      shown.add(MapEntry(false, answer));
      busy = false;
    });
    scrollDown();
    if (actionText != null) finishAction();
    await tts.speak(answer);
if (conversation && mounted && !listening) { await Future.delayed(const Duration(milliseconds: 1200)); if (conversation && mounted && !listening && !busy) toggleMic(); }
  }

  Future<String> ask() async {
    for (var i = 0; i < 8; i++) {
      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'x-api-key': pref('key'), 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'max_tokens': 1024,
        'system': '$systemPrompt Heimatort des Nutzers: ${pref('home')}.',
          'tools': tools,
          'messages': history,
        }),
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) throw data['error']?['message'] ?? res.statusCode;
      final content = data['content'] as List;
      if (content.any((b) => b['type'] == 'server_tool_use')) {
        stageKind = StageKind.search; stageOn = true; showAction('Ich recherchiere ...', Icons.search);
      }
      history.add({'role': 'assistant', 'content': content});
      final stop = data['stop_reason'];
      if (stop == 'pause_turn') continue;
      final uses = content.where((b) => b['type'] == 'tool_use').toList();
      if (stop != 'tool_use' || uses.isEmpty) {
        return content.where((b) => b['type'] == 'text').map((b) => b['text']).join(' ').trim();
      }
      final results = [];
      for (final u in uses) {
        String out;
        try {
          final info = toolInfo(u['name']); stageFor(u['name'], Map<String, dynamic>.from(u['input']));
          showAction(info.key, info.value);
          out = await runTool(u['name'], Map<String, dynamic>.from(u['input']));
        } catch (e) {
          out = 'Fehler: $e';
        }
        results.add({'type': 'tool_result', 'tool_use_id': u['id'], 'content': out});
      }
      history.add({'role': 'user', 'content': results});
    }
    return 'Das hat zu lange gedauert.';
  }

  Future<http.Response> haReq(String path, {String? body}) async { final h = {'Authorization': 'Bearer ${pref('ha_token')}', 'Content-Type': 'application/json'}; for (final k in ['ha_url', 'ha_url2']) { final base = pref(k).trim(); if (base.isEmpty) continue; try { final u = Uri.parse('$base$path'); final f = body == null ? http.get(u, headers: h) : http.post(u, headers: h, body: body); final ms = (k == 'ha_url' && pref('ha_url2').trim().isNotEmpty) ? 1500 : 6000; return await f.timeout(Duration(milliseconds: ms)); } catch (_) {} } throw 'Home Assistant nicht erreichbar'; }
Future<String> runTool(String name, Map<String, dynamic> a) async {
    switch (name) {
      case 'get_weather':
        final loc = (a['location'] ?? '').toString().isEmpty ? pref('home') : a['location'];
        final g = await http.get(Uri.parse(
            'https://geocoding-api.open-meteo.com/v1/search?count=1&language=de&name=${Uri.encodeComponent(loc)}'));
        final r = jsonDecode(g.body)['results'];
        if (r == null) return 'Ort nicht gefunden.';
        final days = (a['days'] ?? 3).toString();
        final w = await http.get(Uri.parse(
            'https://api.open-meteo.com/v1/forecast?latitude=${r[0]['latitude']}&longitude=${r[0]['longitude']}'
            '&current=temperature_2m,weather_code,wind_speed_10m'
            '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=auto&forecast_days=$days'));
        return '${r[0]['name']}: ${w.body}';
      case 'whatsapp_send':
    case 'phone_call':
      {
        final nr = await findNumber((a['contact'] ?? '').toString(), (a['number'] ?? '').toString());
        if (nr == null) return 'Kontakt oder Nummer nicht gefunden. ' + contactDebug;
        final isCall = name == 'phone_call';
        final uri = isCall ? Uri(scheme: 'tel', path: nr) : Uri.parse('whatsapp://send?phone=${nr.replaceAll('+', '')}&text=${Uri.encodeComponent((a['text'] ?? '').toString())}');
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) return 'Konnte die App nicht oeffnen.';
        return isCall ? 'Anruf wird gestartet, Lorenz bestaetigt am iPhone.' : 'WhatsApp ist offen, Lorenz muss nur noch auf Senden tippen.';
      }
    case 'set_timer':
        final secs = (a['seconds'] as num).round();
        final label = (a['label'] ?? '').toString();
        Timer(Duration(seconds: secs), () => tts.speak('Dein Timer ist abgelaufen. $label'));
        return 'Timer gestellt auf $secs Sekunden. Er lÃƒÂ¤uft nur, solange die App offen bleibt.';
      case 'ha_search':
      final res = await haReq('/api/states');
        final q = a['query'].toString().toLowerCase().split(' ');
        final hits = (jsonDecode(res.body) as List).where((s) {
          final t = '${s['entity_id']} ${s['attributes']?['friendly_name']}'.toLowerCase();
          return q.every(t.contains);
        }).take(15).map((s) => '${s['entity_id']}: ${s['state']}').join('\n');
        return hits.isEmpty ? 'Nichts gefunden.' : hits;
      case 'ha_call_service':
        const ok = ['climate', 'cover', 'fan', 'light', 'media_player', 'scene', 'script', 'switch'];
        if (!ok.contains(a['domain'])) return 'Domain nicht erlaubt.';
      final res = await haReq('/api/services/${a['domain']}/${a['service']}', body: jsonEncode({'entity_id': a['entity_id'], ...Map<String, dynamic>.from(a['data'] ?? {})}));
        return res.statusCode == 200 ? 'Erledigt.' : 'Fehler ${res.statusCode}';
    }
    return 'Unbekanntes Werkzeug.';
  }

  @override
  Widget build(BuildContext context) {
    final acting = actionText != null;
    final st = acting
        ? ButlerState.acting
        : speaking
            ? ButlerState.speaking
            : listening
                ? ButlerState.listening
                : busy
                    ? ButlerState.thinking
                    : ButlerState.idle;
    final caption = acting
        ? (actionDone ? 'Erledigt.' : actionText!)
        : listening
            ? 'Ich h\u00f6re zu ...'
            : busy
                ? 'Charles denkt nach ...'
                : '';
    final micColor = listening ? Colors.redAccent : const Color(0xFF4DD0E1);
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: acting
                ? ActionStage(key: ValueKey('${stageKind.name}-$stageOn'), kind: stageKind, done: actionDone, on: stageOn)
                : Center(key: const ValueKey('avatar'), child: Transform.scale(scale: 1.8, child: ButlerAvatar(state: st))),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 22, letterSpacing: 1)),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(icon: const Icon(Icons.settings, color: Colors.white24), onPressed: openSettings),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: GestureDetector(
                onTap: toggleMic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: listening ? 110 : 96,
                  height: listening ? 110 : 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: micColor,
                    boxShadow: [BoxShadow(color: micColor.withOpacity(0.5), blurRadius: listening ? 40 : 20, spreadRadius: listening ? 8 : 2)],
                  ),
                  child: Icon(listening ? Icons.stop : Icons.mic, size: 46, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Store {
  Future<String?> read({required String key}) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (e) {
      debugPrint('Store read: $e');
      return null;
    }
  }

  Future<void> write({required String key, required String? value}) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value ?? '');
    } catch (e) {
      debugPrint('Store write: $e');
    }
  }
}
