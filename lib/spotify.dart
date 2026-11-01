import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String _clientId = '5aaf3e6c5b214e73b17c2c06faa0d0e2';
const String _redirect = 'charles://spotify-callback';
const String _scopes =
    'user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative';

class Spotify {
  static String? _access;
  static DateTime _expires = DateTime(2000);

  static String _rand(int n) {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => c[r.nextInt(c.length)]).join();
  }

  static Future<void> _store(Map<String, dynamic> j) async {
    final p = await SharedPreferences.getInstance();
    _access = j['access_token'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _expires = DateTime.now().add(Duration(seconds: secs - 60));
    final rt = j['refresh_token'] as String?;
    if (rt != null && rt.isNotEmpty) await p.setString('sp_refresh', rt);
  }

  static Future<bool> _refresh() async {
    try {
      final p = await SharedPreferences.getInstance();
      final rt = p.getString('sp_refresh') ?? '';
      if (rt.isEmpty) return false;
      final r = await http.post(Uri.parse('https://accounts.spotify.com/api/token'),
          body: {'grant_type': 'refresh_token', 'refresh_token': rt, 'client_id': _clientId});
      if (r.statusCode != 200) return false;
      await _store(jsonDecode(r.body) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> login() async {
    try {
      final verifier = _rand(64);
      final challenge =
          base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
      final url = Uri.https('accounts.spotify.com', '/authorize', {
        'response_type': 'code',
        'client_id': _clientId,
        'scope': _scopes,
        'redirect_uri': _redirect,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
      });
      final result = await FlutterWebAuth2.authenticate(
          url: url.toString(), callbackUrlScheme: 'charles');
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return 'Spotify Anmeldung abgebrochen.';
      final r = await http.post(Uri.parse('https://accounts.spotify.com/api/token'), body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirect,
        'client_id': _clientId,
        'code_verifier': verifier,
      });
      if (r.statusCode != 200) return 'Spotify Anmeldung Fehler ${r.statusCode}.';
      await _store(jsonDecode(r.body) as Map<String, dynamic>);
      return 'Spotify ist verbunden.';
    } catch (e) {
      return 'Spotify Anmeldung fehlgeschlagen: $e';
    }
  }

  static Future<http.Response?> _call(String method, String path,
      {Map<String, String>? q, Object? body}) async {
    if (_access == null || DateTime.now().isAfter(_expires)) {
      if (!await _refresh()) return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final uri = Uri.https('api.spotify.com', '/v1$path', q);
      final h = {'Authorization': 'Bearer $_access', 'Content-Type': 'application/json'};
      final b = body == null ? null : jsonEncode(body);
      http.Response r;
      switch (method) {
        case 'GET':
          r = await http.get(uri, headers: h);
          break;
        case 'POST':
          r = await http.post(uri, headers: h, body: b);
          break;
        default:
          r = await http.put(uri, headers: h, body: b);
      }
      if (r.statusCode == 401 && attempt == 0) {
        if (!await _refresh()) return null;
        continue;
      }
      return r;
    }
    return null;
  }

  static Future<String?> _deviceId({String? wanted}) async {
    final r = await _call('GET', '/me/player/devices');
    if (r == null || r.statusCode != 200) return null;
    final list = (jsonDecode(r!.body)['devices'] as List?) ?? [];
    if (list.isEmpty) return null;
    if (wanted != null && wanted.isNotEmpty) {
      for (final d in list) {
        if ((d['name'] ?? '').toString().toLowerCase().contains(wanted.toLowerCase())) {
          return d['id'] as String?;
        }
      }
    }
    for (final d in list) {
      if (d['is_active'] == true) return d['id'] as String?;
    }
    return list.first['id'] as String?;
  }

  static Future<http.Response?> _player(String method, String path,
      {Map<String, String>? q, Object? body}) async {
    var r = await _call(method, path, q: q, body: body);
    if (r != null && r.statusCode == 404) {
      var id = await _deviceId();
      if (id == null) {
        try {
          await launchUrl(Uri.parse('spotify:'), mode: LaunchMode.externalApplication);
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 4));
        id = await _deviceId();
      }
      if (id == null) return r;
      await _call('PUT', '/me/player', body: {'device_ids': [id], 'play': false});
      await Future.delayed(const Duration(milliseconds: 800));
      r = await _call(method, path, q: q, body: body);
    }
    return r;
  }

  static bool _ok(http.Response? r) => r != null && r.statusCode >= 200 && r.statusCode < 300;

  static String _err(http.Response? r) {
    if (r == null) return 'Spotify ist nicht verbunden. Bitte zuerst mit action login anmelden.';
    if (r.statusCode == 403) return 'Spotify verweigert das (Premium noetig, Geraet erlaubt es nicht oder Berechtigung fehlt).';
    if (r.statusCode == 404) return 'Kein aktives Spotify-Geraet gefunden. Spotify muss auf einem Geraet offen sein.';
    return 'Spotify Fehler ${r.statusCode}.';
  }

  static Future<Map<String, dynamic>?> _search(String q, String type) async {
    final r = await _call('GET', '/search', q: {'q': q, 'type': type, 'limit': '5'});
    if (r == null || r.statusCode != 200) return null;
    final items = (jsonDecode(r.body)['${type}s']?['items'] as List?) ?? [];
    for (final i in items) {
      if (i != null) return Map<String, dynamic>.from(i as Map);
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _myPlaylist(String q) async {
    final r = await _call('GET', '/me/playlists', q: {'limit': '50'});
    if (r == null || r.statusCode != 200) return null;
    final items = (jsonDecode(r.body)['items'] as List?) ?? [];
    final qq = q.toLowerCase();
    for (final i in items) {
      if (i != null && (i['name'] ?? '').toString().toLowerCase().contains(qq)) {
        return Map<String, dynamic>.from(i as Map);
      }
    }
    return null;
  }

  static String _artists(dynamic item) {
    final l = (item?['artists'] as List?) ?? [];
    return l.map((e) => e['name']).join(', ');
  }

  static Future<String> run(Map<String, dynamic> a) async {
    final action = (a['action'] ?? '').toString();
    try {
      if (action == 'login') return await login();
      switch (action) {
        case 'play':
          {
            final qy = (a['query'] ?? '').toString().trim();
            if (qy.isEmpty) {
              final r = await _player('PUT', '/me/player/play');
              return _ok(r) ? 'Wiedergabe laeuft.' : _err(r);
            }
            final t = (a['type'] ?? 'track').toString();
            final type = ['track', 'artist', 'album', 'playlist'].contains(t) ? t : 'track';
            Map<String, dynamic>? hit;
            if (type == 'playlist') hit = await _myPlaylist(qy);
            hit ??= await _search(qy, type);
            if (hit == null) return 'Nichts gefunden zu $qy.';
            final body = type == 'track' ? {'uris': [hit['uri']]} : {'context_uri': hit['uri']};
            final r = await _player('PUT', '/me/player/play', body: body);
            if (!_ok(r)) return _err(r);
            final by = type == 'track' ? ' von ${_artists(hit)}' : '';
            return 'Spiele ${hit['name']}$by.';
          }
        case 'pause':
          {
            final r = await _player('PUT', '/me/player/pause');
            return _ok(r) ? 'Pausiert.' : _err(r);
          }
        case 'resume':
          {
            final r = await _player('PUT', '/me/player/play');
            return _ok(r) ? 'Wiedergabe laeuft.' : _err(r);
          }
        case 'next':
          {
            final r = await _player('POST', '/me/player/next');
            return _ok(r) ? 'Naechster Titel.' : _err(r);
          }
        case 'previous':
          {
            final r = await _player('POST', '/me/player/previous');
            return _ok(r) ? 'Voriger Titel.' : _err(r);
          }
        case 'volume':
          {
            final v = ((a['percent'] ?? 50) as num).round().clamp(0, 100);
            final r = await _player('PUT', '/me/player/volume', q: {'volume_percent': '$v'});
            return _ok(r) ? 'Lautstaerke $v Prozent.' : _err(r);
          }
        case 'shuffle':
          {
            final on = (a['mode'] ?? 'on').toString() != 'off';
            final r = await _player('PUT', '/me/player/shuffle', q: {'state': '$on'});
            return _ok(r) ? (on ? 'Zufallswiedergabe an.' : 'Zufallswiedergabe aus.') : _err(r);
          }
        case 'repeat':
          {
            final m = (a['mode'] ?? 'context').toString();
            final state = ['off', 'track', 'context'].contains(m) ? m : 'context';
            final r = await _player('PUT', '/me/player/repeat', q: {'state': state});
            return _ok(r) ? 'Wiederholen: $state.' : _err(r);
          }
        case 'queue':
          {
            final qy = (a['query'] ?? '').toString().trim();
            final hit = await _search(qy, 'track');
            if (hit == null) return 'Nichts gefunden zu $qy.';
            final r = await _player('POST', '/me/player/queue', q: {'uri': hit['uri'].toString()});
            return _ok(r) ? '${hit['name']} von ${_artists(hit)} ist in der Warteschlange.' : _err(r);
          }
        case 'now_playing':
          {
            final r = await _call('GET', '/me/player/currently-playing');
            if (r == null || r.statusCode >= 300) return _err(r);
            if (r.statusCode == 204 || r.body.isEmpty) return 'Es laeuft gerade nichts.';
            final j = jsonDecode(r.body);
            final item = j['item'];
            if (item == null) return 'Es laeuft gerade nichts.';
            final playing = j['is_playing'] == true ? 'Laeuft' : 'Pausiert';
            return '$playing: ${item['name']} von ${_artists(item)}.';
          }
        case 'devices':
          {
            final r = await _call('GET', '/me/player/devices');
            if (!_ok(r)) return _err(r);
            final list = (jsonDecode(r!.body)['devices'] as List?) ?? [];
            if (list.isEmpty) return 'Keine Spotify-Geraete aktiv.';
            return list.map((d) => '${d['name']}${d['is_active'] == true ? ' (aktiv)' : ''}').join(', ');
          }
        case 'transfer':
          {
            final id = await _deviceId(wanted: (a['device'] ?? '').toString());
            if (id == null) return 'Kein passendes Spotify-Geraet gefunden.';
            final r = await _call('PUT', '/me/player', body: {'device_ids': [id], 'play': true});
            return _ok(r) ? 'Wiedergabe wurde verschoben.' : _err(r);
          }
      }
      return 'Unbekannte Spotify-Aktion: $action';
    } catch (e) {
      return 'Spotify Fehler: $e';
    }
  }
}