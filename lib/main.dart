import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'butler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final storage = const FlutterSecureStorage();
  final cfg = <String, String>{};
  bool listening = false;
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
      case 'ha_search':
        return MapEntry('Ich sehe im Haus nach ...', Icons.home);
    }
    return MapEntry('Einen Augenblick ...', Icons.auto_awesome);
  }
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
  }

  String pref(String k) => cfg[k] ?? '';

  Future<void> init() async {
    for (final k in ['key', 'home', 'ha_url', 'ha_token']) {
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
    sttOk = await stt.initialize();
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
      'key': 'Claude API-SchlÃ¼ssel',
      'home': 'Heimatort',
      'ha_url': 'Home Assistant URL',
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
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    await tts.stop();
    setState(() => listening = true);
    await stt.listen(
      localeId: 'de_DE',
      onResult: (r) {
        if (r.finalResult) {
          setState(() => listening = false);
          send(r.recognizedWords);
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
    history.add({'role': 'user', 'content': text});
    String answer;
    try {
      answer = await ask();
    } catch (e) {
      answer = 'Das hat leider nicht geklappt: $e';
    }
    setState(() {
      shown.add(MapEntry(false, answer));
      busy = false;
    });
    scrollDown();
    if (actionText != null) finishAction();
    await tts.speak(answer);
  }

  Future<String> ask() async {
    for (var i = 0; i < 8; i++) {
      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'x-api-key': pref('key'), 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'max_tokens': 1024,
          'system': '$systemPrompt Jetzt ist ${DateTime.now()}. Heimatort des Nutzers: ${pref('home')}.',
          'tools': tools,
          'messages': history,
        }),
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) throw data['error']?['message'] ?? res.statusCode;
      final content = data['content'] as List;
      if (content.any((b) => b['type'] == 'server_tool_use')) {
        showAction('Ich recherchiere ...', Icons.search);
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
          final info = toolInfo(u['name']);
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
      case 'set_timer':
        final secs = (a['seconds'] as num).round();
        final label = (a['label'] ?? '').toString();
        Timer(Duration(seconds: secs), () => tts.speak('Dein Timer ist abgelaufen. $label'));
        return 'Timer gestellt auf $secs Sekunden. Er lÃ¤uft nur, solange die App offen bleibt.';
      case 'ha_search':
        final res = await http.get(Uri.parse('${pref('ha_url')}/api/states'),
            headers: {'Authorization': 'Bearer ${pref('ha_token')}'});
        final q = a['query'].toString().toLowerCase().split(' ');
        final hits = (jsonDecode(res.body) as List).where((s) {
          final t = '${s['entity_id']} ${s['attributes']?['friendly_name']}'.toLowerCase();
          return q.every(t.contains);
        }).take(15).map((s) => '${s['entity_id']}: ${s['state']}').join('\n');
        return hits.isEmpty ? 'Nichts gefunden.' : hits;
      case 'ha_call_service':
        const ok = ['climate', 'cover', 'fan', 'light', 'media_player', 'scene', 'script', 'switch'];
        if (!ok.contains(a['domain'])) return 'Domain nicht erlaubt.';
        final res = await http.post(Uri.parse('${pref('ha_url')}/api/services/${a['domain']}/${a['service']}'),
            headers: {'Authorization': 'Bearer ${pref('ha_token')}', 'content-type': 'application/json'},
            body: jsonEncode({'entity_id': a['entity_id'], ...Map<String, dynamic>.from(a['data'] ?? {})}));
        return res.statusCode == 200 ? 'Erledigt.' : 'Fehler ${res.statusCode}';
    }
    return 'Unbekanntes Werkzeug.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charles'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: openSettings)],
      ),
      body: Column(children: [
        ButlerAvatar(
          state: actionText != null
              ? ButlerState.acting
              : speaking
                  ? ButlerState.speaking
                  : listening
                      ? ButlerState.listening
                      : busy
                          ? ButlerState.thinking
                          : ButlerState.idle,
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: shown.length + (busy ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == shown.length) {
                return const Padding(padding: EdgeInsets.all(8), child: Text('Charles denkt nach ...'));
              }
              final m = shown[i];
              return Align(
                alignment: m.key ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(
                    color: m.key ? Colors.cyan.shade800 : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(m.value),
                ),
              );
            },
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: actionText == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(actionText),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.cyan.shade900, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    actionDone
                        ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                        : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.9, end: pulse ? 1.1 : 0.9),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeInOut,
                            onEnd: () => setState(() => pulse = !pulse),
                            builder: (_, s, child) => Transform.scale(scale: s, child: child),
                            child: Icon(actionIcon, color: Colors.amberAccent),
                          ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(actionDone ? 'Erledigt.' : actionText!)),
                  ]),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  onSubmitted: send,
                  decoration: const InputDecoration(hintText: 'Schreib Charles etwas ...', border: OutlineInputBorder()),
                ),
              ),
              IconButton(icon: const Icon(Icons.send), onPressed: () => send(ctrl.text)),
              IconButton.filled(
                onPressed: toggleMic,
                style: IconButton.styleFrom(backgroundColor: listening ? Colors.red : null),
                icon: Icon(listening ? Icons.stop : Icons.mic),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}









