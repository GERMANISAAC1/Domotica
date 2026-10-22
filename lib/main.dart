
// ╔══════════════════════════════════════════════════════════════════╗
// ║  DOMÓTICA PRO  v5.7  —  Producción                              ║
// ╚══════════════════════════════════════════════════════════════════╝
//
// NOVEDADES v5.5:
//  [IPC-1] Nuevo tipo TipoD.ipcam — app "Android IP Camera" (puerto 4444).
//          Video MJPEG : /video/m.jpeg  (o /video/mjpeg según versión)
//          Audio en vivo: /audio         (WAV)
//          Foto         : /video/snapshot
//          Linterna     : /?torch=on  |  /?torch=off
//  [IPC-2] Usuario y contraseña (Basic Auth) por dispositivo.
//  [IPC-3] CamaraPage: botones Ver/Detener, Escuchar, Linterna, Diagnóstico.
//  Se mantiene TipoD.camara (Web Remote Droid, fotos periódicas) y
//  TipoD.celular (flash /flash/on, /flash/off).
//
// Requisitos Android: permiso INTERNET y usesCleartextTraffic="true".
// Requiere just_audio, path_provider y share_plus en pubspec.yaml.
//
// NOVEDADES v5.6:
//  [REC-1] Grabar video desde la app: guarda los cuadros JPEG del stream en
//          un archivo .mjpeg dentro de la app (solo video, sin audio).
//  [REC-2] Pantalla "Grabaciones": lista, compartir (VLC, Drive...) y borrar.
//  [ROT-1] Botón "Girar" (0/90/180/270°) en la vista de la cámara.
//  [IPC-4] Ruta de video por defecto: /video/mjpeg (confirmada), luego
//          /video/m.jpeg.
//
// NOVEDADES v5.7:
//  [BAT-1] Nivel de batería de los celulares (Celular flash / Cámara Web
//          Remote Droid): lee GET /battery/level (JSON o texto plano) cada
//          15 s, con el mismo formato que usa el monitor bateria.py.
//  [BAT-2] Indicador visual (icono de batería + %, rayo al cargar, rojo
//          <=15 %, naranja <=40 %, verde) en Control, Habitaciones,
//          Dispositivos y en la barra superior de la cámara.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════
// TOKENS DE DISEÑO
// ════════════════════════════════════════════════════════════════
class C {
  static const bg         = Color(0xFF070B14);
  static const surface    = Color(0xFF0D1220);
  static const card       = Color(0xFF131A2E);
  static const cardHi     = Color(0xFF1A2340);
  static const border     = Color(0xFF1E2845);
  static const blue       = Color(0xFF4F8EF7);
  static const blueGlow   = Color(0x264F8EF7);
  static const green      = Color(0xFF2ECC8E);
  static const greenGlow  = Color(0x262ECC8E);
  static const orange     = Color(0xFFFF9142);
  static const orangeGlow = Color(0x26FF9142);
  static const red        = Color(0xFFFF4D6A);
  static const redGlow    = Color(0x26FF4D6A);
  static const purple     = Color(0xFF9B6DFF);
  static const purpleGlow = Color(0x269B6DFF);
  static const yellow     = Color(0xFFFFCC44);
  static const yellowGlow = Color(0x26FFCC44);
  static const cyan       = Color(0xFF00D4FF);
  static const cyanGlow   = Color(0x2600D4FF);
  static const t1         = Color(0xFFF0F4FF);
  static const t2         = Color(0xFF7B8DB8);
  static const t3         = Color(0xFF3D4E78);
}

class R {
  static const xs = BorderRadius.all(Radius.circular(8));
  static const sm = BorderRadius.all(Radius.circular(12));
  static const md = BorderRadius.all(Radius.circular(18));
  static const lg = BorderRadius.all(Radius.circular(24));
  static const xl = BorderRadius.all(Radius.circular(32));
}

// ════════════════════════════════════════════════════════════════
// CONSTANTES DE PRODUCCIÓN
// ════════════════════════════════════════════════════════════════
class AppConfig {
  static const cmdTimeout   = Duration(seconds: 8);
  static const pingTimeout  = Duration(seconds: 5);
  static const maxRetries   = 1;
  static const retryDelay   = Duration(milliseconds: 600);
  static const maxLogItems  = 300;
  static const storageKey   = 'domotica_v5';
  static const snapInterval = Duration(milliseconds: 700);
}

// ════════════════════════════════════════════════════════════════
// MODO DE CONEXIÓN
// ════════════════════════════════════════════════════════════════
enum ModoConexion { lan, movil, url }

extension ModoConexionX on ModoConexion {
  String get label => switch (this) {
        ModoConexion.lan   => 'LAN / WiFi',
        ModoConexion.movil => 'IP directa',
        ModoConexion.url   => 'URL completa',
      };
  String get hint => switch (this) {
        ModoConexion.lan   => '192.168.1.100',
        ModoConexion.movil => '100.64.75.125',
        ModoConexion.url   => 'https://mi-tunel.ngrok.io',
      };
  String get descripcion => switch (this) {
        ModoConexion.lan   => 'Misma red WiFi. IP privada (192.168.x.x, 10.x.x.x).',
        ModoConexion.movil => 'Cualquier red. IP pública, Tailscale (100.x.x.x) o puerto abierto.',
        ModoConexion.url   => 'URL completa. Túneles ngrok, Cloudflare, DDNS.',
      };
  IconData get icon => switch (this) {
        ModoConexion.lan   => Icons.wifi_rounded,
        ModoConexion.movil => Icons.signal_cellular_alt_rounded,
        ModoConexion.url   => Icons.public_rounded,
      };
  Color get color => switch (this) {
        ModoConexion.lan   => C.green,
        ModoConexion.movil => C.orange,
        ModoConexion.url   => C.purple,
      };
  static ModoConexion fromStr(String s) => ModoConexion.values
      .firstWhere((e) => e.name == s, orElse: () => ModoConexion.lan);
}

// ════════════════════════════════════════════════════════════════
// ENUMS DISPOSITIVO
// ════════════════════════════════════════════════════════════════
// camara = Web Remote Droid (fotos) · ipcam = Android IP Camera (video+audio)
enum TipoD { tasmota, sonoff, shelly, celular, camara, ipcam, otro }

extension TipoDX on TipoD {
  String get label => switch (this) {
        TipoD.tasmota => 'Tasmota',
        TipoD.sonoff  => 'Sonoff',
        TipoD.shelly  => 'Shelly',
        TipoD.celular => 'Celular (flash)',
        TipoD.camara  => 'Cámara (Web Remote Droid)',
        TipoD.ipcam   => 'Android IP Camera',
        TipoD.otro    => 'Genérico',
      };
  IconData get icon => switch (this) {
        TipoD.tasmota => Icons.electrical_services_rounded,
        TipoD.sonoff  => Icons.bolt_rounded,
        TipoD.shelly  => Icons.router_rounded,
        TipoD.celular => Icons.smartphone_rounded,
        TipoD.camara  => Icons.photo_camera_rounded,
        TipoD.ipcam   => Icons.videocam_rounded,
        TipoD.otro    => Icons.settings_input_hdmi_rounded,
      };
  Color get color => switch (this) {
        TipoD.tasmota => C.blue,
        TipoD.sonoff  => C.orange,
        TipoD.shelly  => C.green,
        TipoD.celular => C.yellow,
        TipoD.camara  => C.cyan,
        TipoD.ipcam   => C.cyan,
        TipoD.otro    => C.t2,
      };

  // Las cámaras no usan comandos on/off de red: solo activan la vista.
  String get pathOn => switch (this) {
        TipoD.tasmota => '/cm?cmnd=Power+On',
        TipoD.sonoff  => '/control?cmd=on',
        TipoD.shelly  => '/relay/0?turn=on',
        TipoD.celular => '/flash/on',
        TipoD.camara  => '/',
        TipoD.ipcam   => '/',
        TipoD.otro    => '/on',
      };
  String get pathOff => switch (this) {
        TipoD.tasmota => '/cm?cmnd=Power+Off',
        TipoD.sonoff  => '/control?cmd=off',
        TipoD.shelly  => '/relay/0?turn=off',
        TipoD.celular => '/flash/off',
        TipoD.camara  => '/',
        TipoD.ipcam   => '/',
        TipoD.otro    => '/off',
      };

  // Foto
  String get pathSnapshot => switch (this) {
        TipoD.ipcam => '/video/snapshot',
        _           => '/camera/0/picture', // Web Remote Droid
      };

  // Video MJPEG (solo ipcam). Se prueban en orden.
  List<String> get pathsStream =>
      this == TipoD.ipcam ? ['/video/mjpeg', '/video/m.jpeg'] : const [];

  // Audio en vivo (solo ipcam)
  String get pathAudio => '/audio';

  List<String> get pathsOnFallback => switch (this) {
        TipoD.celular => ['/flash/on', '/?action=on', '/flash?on=1'],
        TipoD.tasmota => ['/cm?cmnd=Power+On', '/cm?cmnd=Power1+On'],
        TipoD.shelly  => ['/relay/0?turn=on', '/rpc/Switch.Set?id=0&on=true'],
        _ => [pathOn],
      };

  List<String> get pathsOffFallback => switch (this) {
        TipoD.celular => ['/flash/off', '/?action=off', '/flash?on=0'],
        TipoD.tasmota => ['/cm?cmnd=Power+Off', '/cm?cmnd=Power1+Off'],
        TipoD.shelly  => ['/relay/0?turn=off', '/rpc/Switch.Set?id=0&on=false'],
        _ => [pathOff],
      };

  bool get esCamara  => this == TipoD.camara || this == TipoD.ipcam;
  bool get usaStream => this == TipoD.ipcam;

  // [BAT-1] El celular que corre el servidor (puerto 8888) expone el nivel
  // de batería en /battery/level. Se prueban las rutas en orden.
  bool get soportaBateria => this == TipoD.celular || this == TipoD.camara;
  List<String> get pathsBateria => const ['/battery/level', '/battery'];

  int get puertoDefault => switch (this) {
        TipoD.camara  => 8888,
        TipoD.celular => 8888,
        TipoD.ipcam   => 4444,
        _             => 80,
      };

  static TipoD fromStr(String s) => TipoD.values
      .firstWhere((e) => e.name == s.toLowerCase(), orElse: () => TipoD.otro);
}

enum CatArtefacto { luz, ventilador, televisor, aire, enchufe, calefactor, camara, otro }

extension CatX on CatArtefacto {
  String get label => switch (this) {
        CatArtefacto.luz        => 'Luz',
        CatArtefacto.ventilador => 'Ventilador',
        CatArtefacto.televisor  => 'Televisor',
        CatArtefacto.aire       => 'A/C',
        CatArtefacto.enchufe    => 'Enchufe',
        CatArtefacto.calefactor => 'Calefactor',
        CatArtefacto.camara     => 'Cámara',
        CatArtefacto.otro       => 'Otro',
      };
  IconData get icon => switch (this) {
        CatArtefacto.luz        => Icons.light_rounded,
        CatArtefacto.ventilador => Icons.air_rounded,
        CatArtefacto.televisor  => Icons.tv_rounded,
        CatArtefacto.aire       => Icons.ac_unit_rounded,
        CatArtefacto.enchufe    => Icons.power_rounded,
        CatArtefacto.calefactor => Icons.local_fire_department_rounded,
        CatArtefacto.camara     => Icons.videocam_rounded,
        CatArtefacto.otro       => Icons.device_unknown_rounded,
      };
  Color get color => switch (this) {
        CatArtefacto.luz        => C.yellow,
        CatArtefacto.ventilador => C.blue,
        CatArtefacto.televisor  => C.purple,
        CatArtefacto.aire       => C.blue,
        CatArtefacto.enchufe    => C.green,
        CatArtefacto.calefactor => C.orange,
        CatArtefacto.camara     => C.cyan,
        CatArtefacto.otro       => C.t2,
      };
  static CatArtefacto fromStr(String s) => CatArtefacto.values
      .firstWhere((e) => e.name == s, orElse: () => CatArtefacto.otro);
}

// ════════════════════════════════════════════════════════════════
// RESULTADO DE COMANDO
// ════════════════════════════════════════════════════════════════
enum CmdStatus { ok, timeout, error, offline }

class CmdResult {
  final CmdStatus status;
  final String?   detail;
  bool get ok => status == CmdStatus.ok;
  const CmdResult(this.status, {this.detail});
  static const success = CmdResult(CmdStatus.ok);
}

// ════════════════════════════════════════════════════════════════
// MODELOS
// ════════════════════════════════════════════════════════════════
class LogEntry {
  final DateTime ts;
  final String   msg;
  final bool     ok;
  LogEntry(this.ts, this.msg, this.ok);
}

// [BAT-1] Lectura de batería. Acepta un número suelto, texto plano
// ("85%", "85 charging") o JSON ({"percentage":85,"status":"CHARGING"}).
class BateriaInfo {
  final int     nivel;
  final bool    cargando;
  final String? detalle; // estado · temperatura
  const BateriaInfo(this.nivel, {this.cargando = false, this.detalle});

  static BateriaInfo? parse(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;

    num? nivel;
    var cargando = false;
    final extra = <String>[];

    Object? data;
    var esJson = true;
    try {
      data = jsonDecode(t);
    } catch (_) {
      esJson = false;
    }

    if (esJson && data is num) {
      nivel = data;
    } else if (esJson && data is Map) {
      for (final k in const [
        'percentage', 'percent', 'level', 'battery', 'capacity', 'batteryLevel'
      ]) {
        if (data[k] != null) {
          nivel = num.tryParse(data[k].toString());
          break;
        }
      }
      final st = (data['status'] ?? data['state'] ?? '').toString().toUpperCase();
      cargando = st.contains('CHARGING') && !st.contains('DISCHARGING');
      if (st.isNotEmpty) extra.add(st);
      if (data['temperature'] != null) extra.add('${data['temperature']} °C');
    } else {
      final m = RegExp(r'(\d{1,3}(?:\.\d+)?)').firstMatch(t);
      if (m != null) nivel = num.tryParse(m.group(1)!);
      cargando = RegExp(r'charging|cargando', caseSensitive: false).hasMatch(t) &&
          !RegExp(r'discharging', caseSensitive: false).hasMatch(t);
    }

    if (nivel == null || nivel.isNaN || nivel.isInfinite) return null;
    return BateriaInfo(
      nivel.round().clamp(0, 100).toInt(),
      cargando: cargando,
      detalle:  extra.isEmpty ? null : extra.join(' · '),
    );
  }
}

class Dispositivo {
  final int    id;
  String       nombre;
  TipoD        tipo;
  CatArtefacto cat;
  ModoConexion modo;
  String       ip;
  int          puerto;
  String       urlBase;
  String       habitacion;
  String       usuario;
  String       clave;
  bool         encendido;
  DateTime?    ultimaAccion;
  int          toggleCount;
  bool?        online;

  // [BAT-1] Estado de batería (transitorio, no se guarda en disco)
  int?         bateria;               // 0–100, null = aún sin lectura
  bool         cargando     = false;
  String?      bateriaInfo;           // p. ej. "DISCHARGING · 30.0 °C"
  DateTime?    bateriaTs;             // última lectura correcta
  bool         bateriaError = false;  // la última lectura falló

  Dispositivo({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.cat        = CatArtefacto.enchufe,
    this.modo       = ModoConexion.lan,
    this.ip         = '',
    this.puerto     = 80,
    this.urlBase    = '',
    this.habitacion = 'General',
    this.usuario    = '',
    this.clave      = '',
    this.encendido  = false,
    this.ultimaAccion,
    this.toggleCount = 0,
    this.online,
  });

  String get _base {
    switch (modo) {
      case ModoConexion.url:
        return urlBase.trim().replaceAll(RegExp(r'/$'), '');
      case ModoConexion.lan:
      case ModoConexion.movil:
        return 'http://${ip.trim()}:$puerto';
    }
  }

  // Cabeceras de autenticación Basic (vacío si no hay usuario)
  Map<String, String> get authHeaders {
    if (usuario.trim().isEmpty) return const {};
    final cred = base64Encode(utf8.encode('${usuario.trim()}:$clave'));
    return {'Authorization': 'Basic $cred'};
  }

  String get urlOn  => '$_base${tipo.pathOn}';
  String get urlOff => '$_base${tipo.pathOff}';

  String get urlSnapshot => '$_base${tipo.pathSnapshot}';
  List<String> get urlsStream =>
      tipo.pathsStream.map((p) => '$_base$p').toList();
  String get urlAudio => '$_base${tipo.pathAudio}';
  String urlTorch(bool on) => '$_base/?torch=${on ? "on" : "off"}';
  List<String> get urlsBateria =>
      tipo.pathsBateria.map((p) => '$_base$p').toList();

  List<String> get urlsOnFallback  =>
      tipo.pathsOnFallback.map((p) => '$_base$p').toList();
  List<String> get urlsOffFallback =>
      tipo.pathsOffFallback.map((p) => '$_base$p').toList();

  String get conexionDisplay {
    switch (modo) {
      case ModoConexion.url:
        return urlBase.isEmpty ? '—' : urlBase;
      case ModoConexion.lan:
      case ModoConexion.movil:
        return '${ip.trim()}:$puerto';
    }
  }

  Map<String, dynamic> toJson() => {
        'id':          id,
        'nombre':      nombre,
        'tipo':        tipo.name,
        'cat':         cat.name,
        'modo':        modo.name,
        'ip':          ip,
        'puerto':      puerto,
        'urlBase':     urlBase,
        'habitacion':  habitacion,
        'usuario':     usuario,
        'clave':       clave,
        'encendido':   encendido,
        'toggleCount': toggleCount,
        'ultimaAccion': ultimaAccion?.toIso8601String(),
      };

  factory Dispositivo.fromJson(Map<String, dynamic> j) => Dispositivo(
        id:          j['id']          as int,
        nombre:      j['nombre']      as String,
        tipo:        TipoDX.fromStr(j['tipo']   as String? ?? 'otro'),
        cat:         CatX.fromStr(j['cat']      as String? ?? 'otro'),
        modo:        ModoConexionX.fromStr(j['modo'] as String? ?? 'lan'),
        ip:          j['ip']          as String? ?? '',
        puerto:      j['puerto']      as int?    ?? 80,
        urlBase:     j['urlBase']     as String? ?? '',
        habitacion:  j['habitacion']  as String? ?? 'General',
        usuario:     j['usuario']     as String? ?? '',
        clave:       j['clave']       as String? ?? '',
        encendido:   j['encendido']   as bool?   ?? false,
        toggleCount: j['toggleCount'] as int?    ?? 0,
      );

  Dispositivo copyWith({
    String?       nombre,
    TipoD?        tipo,
    CatArtefacto? cat,
    ModoConexion? modo,
    String?       ip,
    int?          puerto,
    String?       urlBase,
    String?       habitacion,
    String?       usuario,
    String?       clave,
    bool?         encendido,
    DateTime?     ultimaAccion,
    int?          toggleCount,
    bool?         online,
  }) =>
      Dispositivo(
        id:           id,
        nombre:       nombre      ?? this.nombre,
        tipo:         tipo        ?? this.tipo,
        cat:          cat         ?? this.cat,
        modo:         modo        ?? this.modo,
        ip:           ip          ?? this.ip,
        puerto:       puerto      ?? this.puerto,
        urlBase:      urlBase     ?? this.urlBase,
        habitacion:   habitacion  ?? this.habitacion,
        usuario:      usuario     ?? this.usuario,
        clave:        clave       ?? this.clave,
        encendido:    encendido   ?? this.encendido,
        ultimaAccion: ultimaAccion ?? this.ultimaAccion,
        toggleCount:  toggleCount ?? this.toggleCount,
        online:       online      ?? this.online,
      )
        ..bateria      = bateria
        ..cargando     = cargando
        ..bateriaInfo  = bateriaInfo
        ..bateriaTs    = bateriaTs
        ..bateriaError = bateriaError;
}

// ════════════════════════════════════════════════════════════════
// CONTROLADOR DE RED
// ════════════════════════════════════════════════════════════════
class NetCtrl {
  static Future<CmdResult> _tryGet(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(AppConfig.cmdTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) return CmdResult.success;
      return CmdResult(CmdStatus.error, detail: 'HTTP ${r.statusCode}');
    } on TimeoutException {
      return CmdResult(CmdStatus.timeout,
          detail: 'Timeout (${AppConfig.cmdTimeout.inSeconds}s)');
    } catch (e) {
      return CmdResult(CmdStatus.offline, detail: e.toString());
    }
  }

  static Future<CmdResult> _cmdConFallback(
    String baseUrl,
    List<String> paths,
  ) async {
    for (final path in paths) {
      final url = '$baseUrl$path';
      final r = await _tryGet(url);

      if (r.ok) return r;

      if (r.status == CmdStatus.timeout || r.status == CmdStatus.offline) {
        await Future.delayed(AppConfig.retryDelay);
        final retry = await _tryGet(url);
        if (retry.ok) return retry;
        return retry;
      }

      if (r.status == CmdStatus.error &&
          r.detail != null &&
          !r.detail!.contains('404')) {
        return r;
      }
    }
    return const CmdResult(
      CmdStatus.error,
      detail: 'Ningún path del firmware respondió correctamente.',
    );
  }

  static String _baseUrl(Dispositivo d) {
    switch (d.modo) {
      case ModoConexion.url:
        return d.urlBase.trim().replaceAll(RegExp(r'/$'), '');
      case ModoConexion.lan:
      case ModoConexion.movil:
        return 'http://${d.ip.trim()}:${d.puerto}';
    }
  }

  static Future<CmdResult> encender(Dispositivo d) =>
      _cmdConFallback(_baseUrl(d), d.tipo.pathsOnFallback);

  static Future<CmdResult> apagar(Dispositivo d) =>
      _cmdConFallback(_baseUrl(d), d.tipo.pathsOffFallback);

  static Future<bool> ping({
    required ModoConexion modo,
    required String       ip,
    required int          puerto,
    required String       urlBase,
  }) async {
    final url = modo == ModoConexion.url
        ? urlBase.trim()
        : 'http://${ip.trim()}:$puerto/';
    if (url.isEmpty) return false;
    try {
      final r = await http.get(Uri.parse(url)).timeout(AppConfig.pingTimeout);
      return r.statusCode < 600;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pingDispositivo(Dispositivo d) => ping(
        modo: d.modo, ip: d.ip, puerto: d.puerto, urlBase: d.urlBase);

  // [BAT-1] Lee el nivel de batería. null = sin respuesta o formato inválido.
  static Future<BateriaInfo?> leerBateria(Dispositivo d) async {
    for (final url in d.urlsBateria) {
      try {
        final r = await http
            .get(Uri.parse(url), headers: d.authHeaders)
            .timeout(AppConfig.pingTimeout);
        if (r.statusCode == 404) continue; // probar la siguiente ruta
        if (r.statusCode < 200 || r.statusCode >= 300) return null;
        return BateriaInfo.parse(utf8.decode(r.bodyBytes, allowMalformed: true));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════
// REPOSITORIO
// ════════════════════════════════════════════════════════════════
class DispositivoRepo {
  static List<Dispositivo> cargar(SharedPreferences p) {
    try {
      final raw = p.getString(AppConfig.storageKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Dispositivo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> guardar(
      SharedPreferences p, List<Dispositivo> items) async {
    await p.setString(AppConfig.storageKey,
        jsonEncode(items.map((d) => d.toJson()).toList()));
  }
}

// ════════════════════════════════════════════════════════════════
// NOTIFIER
// ════════════════════════════════════════════════════════════════
class DispositivosNotifier extends ChangeNotifier {
  final SharedPreferences _prefs;
  final List<Dispositivo> _items;
  int  _nextId = 1;
  bool _demo   = false;
  final List<LogEntry> _log = [];

  // [BAT-1] Sondeo periódico de batería
  static const _bateriaCada = Duration(seconds: 15);
  Timer? _bateriaTimer;
  bool   _bateriaBusy = false;

  DispositivosNotifier(List<Dispositivo> items, this._prefs)
      : _items = List.of(items) {
    if (_items.isNotEmpty) {
      _nextId =
          _items.map((d) => d.id).reduce((a, b) => a > b ? a : b) + 1;
    }
    _bateriaTimer =
        Timer.periodic(_bateriaCada, (_) => refrescarBaterias());
    // Primera lectura con un pequeño retraso para que la UI ya escuche.
    Future.delayed(const Duration(seconds: 1), refrescarBaterias);
  }

  @override
  void dispose() {
    _bateriaTimer?.cancel();
    super.dispose();
  }

  // [BAT-1] Lee la batería de todos los dispositivos compatibles en paralelo.
  // Solo notifica a la UI si algo cambió (la app entera escucha al notifier).
  Future<void> refrescarBaterias() async {
    if (_demo || _bateriaBusy) return;
    _bateriaBusy = true;
    try {
      final ids = _items
          .where((d) => d.tipo.soportaBateria)
          .map((d) => d.id)
          .toList();
      if (ids.isEmpty) return;
      final cambios = await Future.wait(ids.map(_leerBateria));
      if (cambios.any((c) => c) && hasListeners) notifyListeners();
    } finally {
      _bateriaBusy = false;
    }
  }

  Future<bool> _leerBateria(int id) async {
    final i0 = _items.indexWhere((d) => d.id == id);
    if (i0 == -1) return false;
    final info = await NetCtrl.leerBateria(_items[i0]);

    // El dispositivo pudo editarse o eliminarse mientras se esperaba.
    final i = _items.indexWhere((d) => d.id == id);
    if (i == -1) return false;
    final d = _items[i];

    if (info == null) {
      if (d.bateriaError) return false;
      d.bateriaError = true;
      return true;
    }
    final cambio = d.bateria != info.nivel ||
        d.cargando != info.cargando ||
        d.bateriaInfo != info.detalle ||
        d.bateriaError;
    d.bateria      = info.nivel;
    d.cargando     = info.cargando;
    d.bateriaInfo  = info.detalle;
    d.bateriaTs    = DateTime.now();
    d.bateriaError = false;
    return cambio;
  }

  List<Dispositivo> get items      => List.unmodifiable(_items);
  bool              get demo       => _demo;
  List<LogEntry>    get log        =>
      List.unmodifiable(_log.reversed.toList());
  int               get encendidos => _items.where((d) => d.encendido).length;
  List<String> get habitaciones {
    final set = _items.map((d) => d.habitacion).toSet().toList()..sort();
    return ['Todas', ...set];
  }

  List<Dispositivo> porHabitacion(String h) =>
      h == 'Todas' ? _items : _items.where((d) => d.habitacion == h).toList();

  bool esBusy(int id) => false;

  void toggle(int id) {
    final idx = _items.indexWhere((d) => d.id == id);
    if (idx == -1) return;

    final d           = _items[idx];
    final nuevoEstado = !d.encendido;

    _items[idx] = d.copyWith(
      encendido:    nuevoEstado,
      ultimaAccion: DateTime.now(),
      toggleCount:  d.toggleCount + 1,
    );
    _addLog(
      '${d.nombre} → ${nuevoEstado ? "ENCENDIDO" : "APAGADO"}',
      ok: true,
    );
    if (hasListeners) notifyListeners();
    _save();

    // Las cámaras solo activan/desactivan la vista: no hay comando de red.
    if (!_demo && !d.tipo.esCamara) {
      _fireAndForget(d, nuevoEstado);
    }
  }

  void _fireAndForget(Dispositivo d, bool encender) {
    final url = encender ? d.urlOn : d.urlOff;
    http
        .get(Uri.parse(url), headers: d.authHeaders)
        .timeout(AppConfig.cmdTimeout)
        .then((_) {})
        .catchError((_) {
          _addLog('${d.nombre} — sin respuesta de red', ok: false);
          if (hasListeners) notifyListeners();
        });
  }

  void toggleTodos(bool enc) {
    final ids = _items
        .where((d) => d.encendido != enc)
        .map((d) => d.id)
        .toList();
    for (final id in ids) {
      toggle(id);
    }
  }

  Future<bool> agregar({
    required String       nombre,
    required TipoD        tipo,
    required CatArtefacto cat,
    required ModoConexion modo,
    required String       ip,
    required int          puerto,
    required String       urlBase,
    required String       habitacion,
    String usuario = '',
    String clave   = '',
    bool skipPing = true,
  }) async {
    if (!skipPing) {
      final ok = await NetCtrl.ping(
          modo: modo, ip: ip, puerto: puerto, urlBase: urlBase);
      if (!ok) return false;
    }
    final hab = habitacion.trim().isEmpty ? 'General' : habitacion.trim();
    _items.add(Dispositivo(
      id:         _nextId++,
      nombre:     nombre.trim(),
      tipo:       tipo,
      cat:        cat,
      modo:       modo,
      ip:         ip.trim(),
      puerto:     puerto,
      urlBase:    urlBase.trim(),
      habitacion: hab,
      usuario:    usuario.trim(),
      clave:      clave,
    ));
    _addLog('Dispositivo "${nombre.trim()}" agregado', ok: true);
    if (hasListeners) notifyListeners();
    _save();
    unawaited(refrescarBaterias());
    return true;
  }

  void editar({
    required int          id,
    required String       nombre,
    required TipoD        tipo,
    required CatArtefacto cat,
    required ModoConexion modo,
    required String       ip,
    required int          puerto,
    required String       urlBase,
    required String       habitacion,
    String usuario = '',
    String clave   = '',
  }) {
    final idx = _items.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    final hab = habitacion.trim().isEmpty ? 'General' : habitacion.trim();
    _items[idx] = _items[idx].copyWith(
      nombre:     nombre.trim(),
      tipo:       tipo,
      cat:        cat,
      modo:       modo,
      ip:         ip.trim(),
      puerto:     puerto,
      urlBase:    urlBase.trim(),
      habitacion: hab,
      usuario:    usuario.trim(),
      clave:      clave,
    );
    _addLog('Dispositivo "${nombre.trim()}" actualizado', ok: true);
    if (hasListeners) notifyListeners();
    _save();
    unawaited(refrescarBaterias());
  }

  void eliminar(int id) {
    final idx = _items.indexWhere((x) => x.id == id);
    if (idx == -1) return;
    final nombre = _items[idx].nombre;
    _items.removeAt(idx);
    _addLog('"$nombre" eliminado', ok: true);
    if (hasListeners) notifyListeners();
    _save();
  }

  void toggleDemo() {
    _demo = !_demo;
    if (hasListeners) notifyListeners();
    if (!_demo) unawaited(refrescarBaterias());
  }

  void limpiarLog() {
    _log.clear();
    if (hasListeners) notifyListeners();
  }

  void _addLog(String msg, {required bool ok}) {
    _log.add(LogEntry(DateTime.now(), msg, ok));
    if (_log.length > AppConfig.maxLogItems) _log.removeAt(0);
  }

  void _save() => DispositivoRepo.guardar(_prefs, _items);
}

// ════════════════════════════════════════════════════════════════
// MAIN
// ════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                    Colors.transparent,
    statusBarIconBrightness:           Brightness.light,
    systemNavigationBarColor:          Color(0xFF070B14),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final prefs = await SharedPreferences.getInstance();
  runApp(DomoticaApp(
      notifier:
          DispositivosNotifier(DispositivoRepo.cargar(prefs), prefs)));
}

// ════════════════════════════════════════════════════════════════
// SNACK helper
// ════════════════════════════════════════════════════════════════
void snack(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).clearSnackBars();
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Row(children: [
      Icon(
        error ? Icons.error_rounded : Icons.check_circle_rounded,
        color: error ? C.red : C.green,
        size: 18,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(color: C.t1))),
    ]),
    backgroundColor: C.cardHi,
    margin:          const EdgeInsets.all(14),
    behavior:        SnackBarBehavior.floating,
    shape: const RoundedRectangleBorder(borderRadius: R.sm),
    duration: const Duration(seconds: 4),
  ));
}

String _fmtTs(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60)  return 'hace ${d.inSeconds}s';
  if (d.inMinutes < 60)  return 'hace ${d.inMinutes}m';
  if (d.inHours   < 24)  return 'hace ${d.inHours}h';
  return '${t.day}/${t.month}/${t.year} '
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ════════════════════════════════════════════════════════════════
// [REC-1] GRABADOR — guarda los cuadros JPEG en un archivo .mjpeg
// ════════════════════════════════════════════════════════════════
class Grabador {
  IOSink?   _sink;
  File?     _file;
  DateTime? _inicio;
  int       frames = 0;
  int       bytes  = 0;

  bool get activo => _sink != null;

  Duration get duracion => _inicio == null
      ? Duration.zero
      : DateTime.now().difference(_inicio!);

  /// Carpeta privada de la app donde se guardan las grabaciones.
  static Future<Directory> carpeta() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/grabaciones');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _limpio(String s) {
    final t = s.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return t.isEmpty ? 'camara' : t;
  }

  Future<void> iniciar(String nombre) async {
    if (activo) return;
    final dir = await carpeta();
    final n   = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    final ts = '${n.year}${dos(n.month)}${dos(n.day)}_'
        '${dos(n.hour)}${dos(n.minute)}${dos(n.second)}';
    _file   = File('${dir.path}/${_limpio(nombre)}_$ts.mjpeg');
    _sink   = _file!.openWrite();
    _inicio = DateTime.now();
    frames  = 0;
    bytes   = 0;
  }

  /// Escribe un cuadro JPEG (ignora si no se está grabando).
  void agregar(Uint8List frame) {
    final s = _sink;
    if (s == null) return;
    s.add(frame);
    frames++;
    bytes += frame.length;
  }

  /// Cierra el archivo y devuelve su ruta (o null si no había grabación).
  Future<String?> detener() async {
    final s = _sink;
    final f = _file;
    _sink   = null;
    _file   = null;
    _inicio = null;
    if (s == null || f == null) return null;
    await s.flush();
    await s.close();
    return f.path;
  }
}

// ════════════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════════════
class DomoticaApp extends StatelessWidget {
  final DispositivosNotifier notifier;
  const DomoticaApp({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: notifier,
        builder: (_, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Domótica Pro',
          theme: ThemeData(
            useMaterial3: true,
            brightness:   Brightness.dark,
            scaffoldBackgroundColor: C.bg,
            colorScheme: const ColorScheme.dark(
              primary:   C.blue,
              secondary: C.green,
              surface:   C.surface,
              onSurface: C.t1,
              onPrimary: Colors.white,
            ),
            cardTheme:    const CardThemeData(color: C.card, elevation: 0),
            dividerColor: C.border,
            inputDecorationTheme: InputDecorationTheme(
              filled:         true,
              fillColor:      C.surface,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: R.xs,
                  borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: R.xs,
                  borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: R.xs,
                  borderSide: const BorderSide(color: C.blue, width: 1.5)),
              errorBorder: OutlineInputBorder(
                  borderRadius: R.xs,
                  borderSide: const BorderSide(color: C.red)),
              labelStyle: const TextStyle(color: C.t2),
              hintStyle:  const TextStyle(color: C.t3),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: C.blue,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: R.xs),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          home: Shell(notifier: notifier),
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// SHELL
// ════════════════════════════════════════════════════════════════
class Shell extends StatefulWidget {
  final DispositivosNotifier notifier;
  const Shell({super.key, required this.notifier});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final n     = widget.notifier;
    final pages = [
      ControlPage(notifier: n),
      HabitacionesPage(notifier: n),
      DispositivosPage(notifier: n),
      HistorialPage(notifier: n),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
            key: ValueKey(_tab), child: pages[_tab]),
      ),
      bottomNavigationBar: _BottomNav(
        current: _tab,
        onTap:   (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int current;
  final void Function(int) onTap;
  const _BottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.power_settings_new_rounded, 'Control'),
      (Icons.home_rounded,               'Habitaciones'),
      (Icons.devices_rounded,            'Dispositivos'),
      (Icons.history_rounded,            'Historial'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.border, width: 0.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(4, (i) {
              final sel = i == current;
              return GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? C.blueGlow : Colors.transparent,
                    borderRadius: R.md,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i].$1,
                        size: 22, color: sel ? C.blue : C.t3),
                    const SizedBox(height: 3),
                    Text(items[i].$2,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: sel ? C.blue : C.t3)),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// MJPEG WIDGET — video en vivo (Android IP Camera)
// ════════════════════════════════════════════════════════════════
/// Lee un stream multipart/x-mixed-replace (MJPEG) y muestra cada
/// frame JPEG. Prueba las [urls] en orden hasta que una responda 2xx.
class MjpegWidget extends StatefulWidget {
  final List<String>        urls;
  final Map<String, String> headers;
  final BoxFit              fit;
  final void Function(Uint8List frame)? onFrame;
  const MjpegWidget({
    super.key,
    required this.urls,
    this.headers = const {},
    this.fit = BoxFit.contain,
    this.onFrame,
  });

  @override
  State<MjpegWidget> createState() => _MjpegWidgetState();
}

class _MjpegWidgetState extends State<MjpegWidget> {
  http.Client?        _client;
  StreamSubscription? _sub;
  Uint8List?          _frame;
  String?             _error;
  bool                _connecting = true;

  static final _soiMarker = Uint8List.fromList([0xFF, 0xD8]);
  static final _eoiMarker = Uint8List.fromList([0xFF, 0xD9]);

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(MjpegWidget old) {
    super.didUpdateWidget(old);
    if (old.urls.join('|') != widget.urls.join('|')) {
      _disconnect();
      _connect();
    }
  }

  Future<void> _connect() async {
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _error      = null;
      _frame      = null;
    });

    String lastErr = 'Sin URL de video';
    for (final url in widget.urls) {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..headers.addAll(widget.headers);
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 10));

        if (!mounted) {
          client.close();
          return;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          _client = client;
          setState(() => _connecting = false);

          final buf = <int>[];
          _sub = response.stream.listen(
            (chunk) {
              buf.addAll(chunk);
              _extractFrames(buf);
              // Protección: si crece demasiado sin frames, limpiar
              if (buf.length > 4 * 1024 * 1024) buf.clear();
            },
            onError: (e) {
              if (mounted) setState(() => _error = 'Error de stream: $e');
            },
            onDone: () {
              if (mounted) setState(() => _error = 'Stream terminado');
            },
          );
          return;
        }

        client.close();
        if (response.statusCode == 401 || response.statusCode == 403) {
          lastErr = 'HTTP ${response.statusCode}: usuario o contraseña incorrectos';
          break;
        }
        lastErr = 'HTTP ${response.statusCode} en $url';
      } catch (e) {
        client.close();
        lastErr = e is TimeoutException
            ? 'Tiempo de espera agotado al conectar'
            : e.toString();
      }
    }

    if (mounted) {
      setState(() {
        _connecting = false;
        _error      = lastErr;
      });
    }
  }

  /// Extrae los frames JPEG completos (FFD8 … FFD9) del buffer.
  void _extractFrames(List<int> buf) {
    while (true) {
      final start = _indexOf(buf, _soiMarker, 0);
      if (start == -1) {
        buf.clear();
        break;
      }
      final end = _indexOf(buf, _eoiMarker, start + 2);
      if (end == -1) {
        if (start > 0) buf.removeRange(0, start);
        break;
      }
      final frameEnd = end + 2;
      final frame    = Uint8List.fromList(buf.sublist(start, frameEnd));
      buf.removeRange(0, frameEnd);
      widget.onFrame?.call(frame);
      if (mounted) {
        setState(() => _frame = frame);
      }
    }
  }

  int _indexOf(List<int> data, Uint8List pattern, int from) {
    outer:
    for (int i = from; i <= data.length - pattern.length; i++) {
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void _disconnect() {
    _sub?.cancel();
    _client?.close();
    _sub    = null;
    _client = null;
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: C.cyan, strokeWidth: 2),
            SizedBox(height: 16),
            Text('Conectando a la cámara...',
                style: TextStyle(color: C.t2, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  size: 48, color: C.red),
              const SizedBox(height: 16),
              const Text('Sin señal de cámara',
                  style: TextStyle(
                      color: C.t1,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: C.t3, fontSize: 12)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  _disconnect();
                  _connect();
                },
                icon:  const Icon(Icons.refresh_rounded, color: C.cyan),
                label: const Text('Reintentar',
                    style: TextStyle(color: C.cyan)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: C.cyan)),
              ),
            ],
          ),
        ),
      );
    }

    if (_frame == null) {
      return const Center(
        child: Text('Esperando primer cuadro...',
            style: TextStyle(color: C.t3, fontSize: 12)),
      );
    }

    return Image.memory(
      _frame!,
      fit:             widget.fit,
      gaplessPlayback: true,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SNAPSHOT WIDGET — "video" pidiendo fotos periódicas
// ════════════════════════════════════════════════════════════════
/// Pide una foto a [url] cada [interval] y la muestra. Sirve para
/// Web Remote Droid (/camera/0/picture), que no ofrece stream MJPEG.
class SnapshotWidget extends StatefulWidget {
  final String              url;
  final Map<String, String> headers;
  final Duration            interval;
  final BoxFit              fit;
  final void Function(Uint8List frame)? onFrame;
  const SnapshotWidget({
    super.key,
    required this.url,
    this.headers = const {},
    this.interval = AppConfig.snapInterval,
    this.fit = BoxFit.contain,
    this.onFrame,
  });

  @override
  State<SnapshotWidget> createState() => _SnapshotWidgetState();
}

class _SnapshotWidgetState extends State<SnapshotWidget> {
  Timer?     _timer;
  Uint8List? _frame;
  String?    _error;
  bool       _loading = false;
  int        _fails   = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(widget.interval, (_) => _fetch());
  }

  @override
  void didUpdateWidget(SnapshotWidget old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _frame = null;
      _error = null;
      _fails = 0;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_loading) return;
    _loading = true;
    try {
      final r = await http
          .get(Uri.parse('${widget.url}?quality=60&scale=0.7'),
              headers: widget.headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception('HTTP ${r.statusCode}');
      }
      if (r.bodyBytes.isEmpty) {
        throw Exception('Respuesta vacía');
      }
      _fails = 0;
      widget.onFrame?.call(r.bodyBytes);
      if (mounted) {
        setState(() {
          _frame = r.bodyBytes;
          _error = null;
        });
      }
    } catch (e) {
      _fails++;
      if (mounted && (_frame == null || _fails >= 3)) {
        setState(() => _error = e.toString());
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _frame == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  size: 48, color: C.red),
              const SizedBox(height: 16),
              const Text('Sin señal de cámara',
                  style: TextStyle(
                      color: C.t1,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: C.t3, fontSize: 12)),
              const SizedBox(height: 8),
              const Text(
                  'Revisa que la app de la cámara esté abierta y con permiso de cámara.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.t3, fontSize: 11)),
            ],
          ),
        ),
      );
    }

    if (_frame == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: C.cyan, strokeWidth: 2),
            SizedBox(height: 16),
            Text('Conectando a la cámara...',
                style: TextStyle(color: C.t2, fontSize: 13)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _frame!,
          fit:             widget.fit,
          gaplessPlayback: true,
        ),
        if (_error != null)
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: C.red.withValues(alpha: 0.85),
                  borderRadius: R.xl,
                ),
                child: const Text('Conexión inestable',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// CAMARA PAGE — pantalla completa con vista, audio y linterna
// ════════════════════════════════════════════════════════════════
class CamaraPage extends StatefulWidget {
  final Dispositivo          d;
  final DispositivosNotifier notifier;
  const CamaraPage({super.key, required this.d, required this.notifier});

  @override
  State<CamaraPage> createState() => _CamaraPageState();
}

class _CamaraPageState extends State<CamaraPage> {
  late Dispositivo _d;
  bool   _controlsVisible = true;
  Timer? _hideTimer;

  // Audio
  final AudioPlayer _player = AudioPlayer();
  bool _audioOn      = false;
  bool _audioLoading = false;

  // Linterna
  bool _torchOn = false;

  // Grabación
  final Grabador _rec = Grabador();
  bool   _grabando = false;
  Timer? _recTimer;

  // Giro de la imagen (cuartos de vuelta: 0, 1, 2, 3)
  int _giro = 0;

  @override
  void initState() {
    super.initState();
    _d = widget.d;
    widget.notifier.addListener(_onNotifier);
    _scheduleHide();
    if (!_d.encendido) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setCamara(true));
    }
  }

  void _onNotifier() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifier);
    _hideTimer?.cancel();
    _recTimer?.cancel();
    unawaited(_rec.detener());
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRec(Dispositivo d) async {
    if (_grabando) {
      await _detenerRec();
      return;
    }
    try {
      await _rec.iniciar(d.nombre);
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _grabando = true);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo iniciar la grabación: $e', error: true);
    }
  }

  Future<void> _detenerRec({bool aviso = true}) async {
    _recTimer?.cancel();
    _recTimer = null;
    final ruta = await _rec.detener();
    if (!mounted) return;
    setState(() => _grabando = false);
    if (aviso && ruta != null) {
      snack(context, 'Grabación guardada ✓ (ver en Grabaciones)');
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  // Idempotente: solo cambia el estado si es distinto al deseado
  Future<void> _setCamara(bool encender) async {
    final actual = widget.notifier.items
        .firstWhere((x) => x.id == _d.id, orElse: () => _d);
    if (actual.encendido != encender) {
      widget.notifier.toggle(_d.id);
    }
    if (!encender && _audioOn) {
      await _player.stop();
      _audioOn = false;
    }
    if (!encender && _grabando) {
      await _detenerRec();
    }
    final updated = widget.notifier.items
        .firstWhere((x) => x.id == _d.id, orElse: () => _d);
    if (mounted) setState(() => _d = updated);
  }

  Future<void> _toggleAudio(Dispositivo d) async {
    if (_audioLoading) return;
    if (_audioOn) {
      await _player.stop();
      if (mounted) setState(() => _audioOn = false);
      return;
    }
    setState(() => _audioLoading = true);
    try {
      final headers = d.authHeaders;
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(d.urlAudio),
          headers: headers.isEmpty ? null : headers,
        ),
      );
      unawaited(_player.play());
      if (mounted) setState(() => _audioOn = true);
    } catch (e) {
      if (mounted) {
        snack(context, 'No se pudo reproducir el audio: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _toggleTorch(Dispositivo d) async {
    final nuevo = !_torchOn;
    try {
      final r = await http
          .get(Uri.parse(d.urlTorch(nuevo)), headers: d.authHeaders)
          .timeout(AppConfig.cmdTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (mounted) setState(() => _torchOn = nuevo);
      } else if (mounted) {
        snack(context, 'Linterna: HTTP ${r.statusCode}', error: true);
      }
    } catch (e) {
      if (mounted) snack(context, 'Linterna: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dActual = widget.notifier.items
        .firstWhere((x) => x.id == _d.id, orElse: () => _d);
    final esIpCam = dActual.tipo.usaStream;

    Widget vista;
    if (!dActual.encendido) {
      vista = const _CamaraApagada();
    } else if (esIpCam) {
      vista = MjpegWidget(
        key:     ValueKey(dActual.urlsStream.join('|')),
        urls:    dActual.urlsStream,
        headers: dActual.authHeaders,
        onFrame: _rec.agregar,
      );
    } else {
      vista = SnapshotWidget(
        key:     ValueKey(dActual.urlSnapshot),
        url:     dActual.urlSnapshot,
        headers: dActual.authHeaders,
        onFrame: _rec.agregar,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── 1. Vista de la cámara ──────────────────────────────
        GestureDetector(
          onTap: _showControls,
          child: SizedBox.expand(
            child: RotatedBox(quarterTurns: _giro, child: vista),
          ),
        ),

        // ── 2. Gradiente superior ──────────────────────────────
        AnimatedOpacity(
          opacity:  _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Container(
              height: 140,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),

        // ── 3. App bar superior ────────────────────────────────
        AnimatedOpacity(
          opacity:  _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(children: [
                  _CamIconBtn(
                    icon:  Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(dActual.nombre,
                            style: const TextStyle(
                                color:      Colors.white,
                                fontSize:   16,
                                fontWeight: FontWeight.w700)),
                        Row(children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dActual.encendido
                                  ? C.green
                                  : C.red,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _grabando
                                ? '● GRABANDO ${_fmtDur(_rec.duracion)} · ${_fmtBytes(_rec.bytes)}'
                                : dActual.encendido
                                    ? (_audioOn ? 'En vivo · con audio' : 'En vivo')
                                    : 'Cámara apagada',
                            style: TextStyle(
                                color: _grabando
                                    ? C.red
                                    : dActual.encendido
                                        ? C.green
                                        : C.t3,
                                fontSize: 11,
                                fontWeight: _grabando
                                    ? FontWeight.w700
                                    : FontWeight.w400),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  if (dActual.tipo.soportaBateria) ...[
                    _BateriaPill(dActual, grande: true),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: C.cyanGlow,
                        borderRadius: R.xl,
                        border: Border.all(
                            color: C.cyan.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        dActual.conexionDisplay,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color:    C.cyan,
                            fontSize: 9,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // ── 4. Gradiente inferior ──────────────────────────────
        AnimatedOpacity(
          opacity:  _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 250,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end:   Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── 5. Controles inferiores ────────────────────────────
        AnimatedOpacity(
          opacity:  _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    runSpacing: 14,
                    children: [
                      _CamControlBtn(
                        icon: dActual.encendido
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        label: dActual.encendido
                            ? 'Detener vista'
                            : 'Ver cámara',
                        color: dActual.encendido ? C.red : C.cyan,
                        onTap: () => _setCamara(!dActual.encendido),
                      ),
                      if (esIpCam && dActual.encendido)
                        _CamControlBtn(
                          icon: _audioLoading
                              ? Icons.hourglass_top_rounded
                              : (_audioOn
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded),
                          label: _audioOn ? 'Silenciar' : 'Escuchar',
                          color: _audioOn ? C.orange : C.green,
                          onTap: () => _toggleAudio(dActual),
                        ),
                      if (esIpCam && dActual.encendido)
                        _CamControlBtn(
                          icon: _torchOn
                              ? Icons.flashlight_off_rounded
                              : Icons.flashlight_on_rounded,
                          label: _torchOn ? 'Apagar luz' : 'Linterna',
                          color: C.yellow,
                          onTap: () => _toggleTorch(dActual),
                        ),
                      if (dActual.encendido)
                        _CamControlBtn(
                          icon: _grabando
                              ? Icons.stop_circle_rounded
                              : Icons.fiber_manual_record_rounded,
                          label: _grabando ? 'Detener' : 'Grabar',
                          color: C.red,
                          onTap: () => _toggleRec(dActual),
                        ),
                      if (dActual.encendido)
                        _CamControlBtn(
                          icon:  Icons.rotate_right_rounded,
                          label: 'Girar ${_giro * 90}°',
                          color: C.purple,
                          onTap: () => setState(() => _giro = (_giro + 1) % 4),
                        ),
                      _CamControlBtn(
                        icon:  Icons.video_library_rounded,
                        label: 'Grabaciones',
                        color: C.green,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const GrabacionesPage()),
                        ),
                      ),
                      _CamControlBtn(
                        icon:  Icons.wifi_find_rounded,
                        label: 'Diagnóstico',
                        color: C.blue,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DiagnosticoPage(
                                d:        dActual,
                                notifier: widget.notifier),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// Pantalla negra cuando la cámara está apagada
class _CamaraApagada extends StatelessWidget {
  const _CamaraApagada();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_rounded,
                size: 64, color: Color(0xFF2A3050)),
            SizedBox(height: 16),
            Text('Cámara apagada',
                style: TextStyle(
                    color:    Color(0xFF3D4E78),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Toca "Ver cámara" para iniciar la vista',
                style: TextStyle(color: Color(0xFF2A3050), fontSize: 12)),
          ],
        ),
      );
}

// Botón circular para el app bar de la cámara
class _CamIconBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  const _CamIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

// Botón de control inferior en la pantalla de cámara
class _CamControlBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _CamControlBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58, height: 58,
              decoration: BoxDecoration(
                color:  color.withValues(alpha: 0.18),
                shape:  BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// PÁGINA: CONTROL
// ════════════════════════════════════════════════════════════════
class ControlPage extends StatefulWidget {
  final DispositivosNotifier notifier;
  const ControlPage({super.key, required this.notifier});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  void _onCardTap(Dispositivo d) {
    if (d.tipo.esCamara) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CamaraPage(d: d, notifier: widget.notifier),
        ),
      );
    } else {
      widget.notifier.toggle(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.notifier,
      builder: (_, _) {
        final n   = widget.notifier;
        final enc = n.encendidos;
        final tot = n.items.length;
        return Scaffold(
          backgroundColor: C.bg,
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned:         true,
              expandedHeight: 130,
              backgroundColor: C.surface,
              flexibleSpace: FlexibleSpaceBar(
                background: _ControlHeader(enc: enc, total: tot),
              ),
              title: Row(children: [
                const Text('Control',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: C.t1)),
                const SizedBox(width: 8),
                if (n.demo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: C.orangeGlow,
                      borderRadius: R.xl,
                      border: Border.all(
                          color: C.orange.withValues(alpha: 0.4)),
                    ),
                    child: const Text('DEMO',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: C.orange)),
                  ),
              ]),
              actions: [
                if (tot > 0) ...[
                  _IconBtn(
                    icon:    Icons.power_off_rounded,
                    color:   C.red,
                    tooltip: 'Apagar todo',
                    onTap:   () => n.toggleTodos(false),
                  ),
                  const SizedBox(width: 6),
                  _IconBtn(
                    icon:    Icons.power_rounded,
                    color:   C.green,
                    tooltip: 'Encender todo',
                    onTap:   () => n.toggleTodos(true),
                  ),
                  const SizedBox(width: 4),
                ],
                GestureDetector(
                  onTap: n.toggleDemo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Icon(Icons.science_rounded,
                        size:  20,
                        color: n.demo ? C.orange : C.t3),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (n.items.isEmpty)
              const SliverFillRemaining(child: _EmptyControl())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final d = n.items[i];
                      return _ControlCard(
                        key:     ValueKey(d.id),
                        d:       d,
                        busy:    n.esBusy(d.id),
                        onTap:   () => _onCardTap(d),
                        onToggle: () => _onCardTap(d),
                      );
                    },
                    childCount: n.items.length,
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _ControlHeader extends StatelessWidget {
  final int enc, total;
  const _ControlHeader({required this.enc, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : enc / total;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
          colors: [Color(0xFF0D1528), C.bg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 68, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:  MainAxisAlignment.end,
              children: [
                Text('$enc de $total encendidos',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: C.t1)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: R.xl,
                  child: TweenAnimationBuilder<double>(
                    tween:    Tween(begin: 0, end: pct),
                    duration: const Duration(milliseconds: 600),
                    builder: (_, v, _) => LinearProgressIndicator(
                      value:      v,
                      minHeight:  6,
                      backgroundColor: C.border,
                      valueColor:
                          const AlwaysStoppedAnimation(C.blue),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _PercentRing(enc: enc, total: total),
        ],
      ),
    );
  }
}

class _PercentRing extends StatelessWidget {
  final int enc, total;
  const _PercentRing({required this.enc, required this.total});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56, height: 56,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value:           total == 0 ? 0 : enc / total,
            backgroundColor: C.border,
            valueColor:      const AlwaysStoppedAnimation(C.blue),
            strokeWidth:     5,
            strokeCap:       StrokeCap.round,
          ),
          Text(
            '${total == 0 ? 0 : (enc * 100 ~/ total)}%',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: C.t1),
          ),
        ]),
      );
}

class _ControlCard extends StatelessWidget {
  final Dispositivo  d;
  final bool         busy;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  const _ControlCard({
    super.key,
    required this.d,
    required this.busy,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final col       = d.encendido ? d.tipo.color : C.t3;
    final bgCol     = d.encendido
        ? d.tipo.color.withValues(alpha: 0.10)
        : C.card;
    final borderCol = d.encendido
        ? d.tipo.color.withValues(alpha: 0.45)
        : C.border;

    final esCamara = d.tipo.esCamara;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        bgCol,
        borderRadius: R.sm,
        border: Border.all(
            color: borderCol, width: d.encendido ? 1.5 : 0.5),
      ),
      child: InkWell(
        onTap:        busy ? null : onTap,
        borderRadius: R.sm,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: d.encendido
                    ? d.tipo.color.withValues(alpha: 0.18)
                    : C.surface,
                borderRadius: R.sm,
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(d.cat.icon, size: 26, color: col),
                if (d.online != null)
                  Positioned(
                    bottom: 4, right: 4,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.online! ? C.green : C.red,
                        border: Border.all(color: C.card, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: d.encendido ? C.t1 : C.t2)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _MicroBadge(d.tipo.label, col: d.tipo.color),
                    _MicroBadge(d.habitacion, col: C.t3),
                    if (d.tipo.soportaBateria) _BateriaPill(d),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(d.modo.icon, size: 10, color: d.modo.color),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(d.conexionDisplay,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: C.t3)),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 12),
            esCamara
                ? _CameraOpenButton(
                    encendido: d.encendido,
                    color:     d.tipo.color,
                    onTap:     busy ? null : onTap,
                  )
                : _PowerButton(
                    encendido: d.encendido,
                    busy:      busy,
                    color:     d.tipo.color,
                    onTap:     busy ? null : onToggle,
                  ),
          ]),
        ),
      ),
    );
  }
}

// Botón de abrir cámara (en lugar del botón power)
class _CameraOpenButton extends StatelessWidget {
  final bool         encendido;
  final Color        color;
  final VoidCallback? onTap;
  const _CameraOpenButton({
    required this.encendido,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 56, height: 56,
          decoration: BoxDecoration(
            color:  encendido ? color : C.surface,
            shape:  BoxShape.circle,
            border: Border.all(
                color: encendido ? color : C.border, width: 1.5),
            boxShadow: encendido
                ? [
                    BoxShadow(
                        color:      color.withValues(alpha: 0.35),
                        blurRadius: 14,
                        spreadRadius: 2)
                  ]
                : [],
          ),
          child: Icon(
            encendido
                ? Icons.play_circle_filled_rounded
                : Icons.videocam_rounded,
            size:  26,
            color: encendido ? Colors.white : C.t3,
          ),
        ),
      );
}

class _PowerButton extends StatelessWidget {
  final bool         encendido, busy;
  final Color        color;
  final VoidCallback? onTap;
  const _PowerButton({
    required this.encendido,
    required this.busy,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return SizedBox(
        width: 56, height: 56,
        child: Center(
          child: SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: color),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        width: 56, height: 56,
        decoration: BoxDecoration(
          color:  encendido ? color : C.surface,
          shape:  BoxShape.circle,
          border: Border.all(
              color: encendido ? color : C.border, width: 1.5),
          boxShadow: encendido
              ? [
                  BoxShadow(
                      color:      color.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 2)
                ]
              : [],
        ),
        child: Icon(Icons.power_settings_new_rounded,
            size: 24, color: encendido ? Colors.white : C.t3),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ESTADO VACÍO
// ════════════════════════════════════════════════════════════════
class _EmptyControl extends StatelessWidget {
  const _EmptyControl();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                    color: C.blueGlow, shape: BoxShape.circle),
                child: const Icon(Icons.devices_other_rounded,
                    size: 48, color: C.blue),
              ),
              const SizedBox(height: 20),
              const Text('Sin dispositivos',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: C.t1)),
              const SizedBox(height: 8),
              const Text(
                'Toca la pestaña "Dispositivos"\ny agrega el primero.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: C.t2),
              ),
            ],
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// PÁGINA: HABITACIONES
// ════════════════════════════════════════════════════════════════
class HabitacionesPage extends StatefulWidget {
  final DispositivosNotifier notifier;
  const HabitacionesPage({super.key, required this.notifier});

  @override
  State<HabitacionesPage> createState() => _HabPageState();
}

class _HabPageState extends State<HabitacionesPage> {
  String _sel = 'Todas';

  void _onTileTap(BuildContext ctx, Dispositivo d) {
    if (d.tipo.esCamara) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) =>
              CamaraPage(d: d, notifier: widget.notifier),
        ),
      );
    } else {
      widget.notifier.toggle(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.notifier,
      builder: (_, _) {
        final n    = widget.notifier;
        final habs = n.habitaciones;
        if (!habs.contains(_sel)) _sel = 'Todas';
        final items = n.porHabitacion(_sel);

        return Scaffold(
          backgroundColor: C.bg,
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned:          true,
              backgroundColor: C.surface,
              title: const Text('Habitaciones',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: C.t1)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _HabTabs(
                    habs: habs,
                    sel:  _sel,
                    onSel: (h) => setState(() => _sel = h)),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    _sel == 'Todas'
                        ? 'Sin dispositivos aún'
                        : 'No hay dispositivos en $_sel',
                    style: const TextStyle(color: C.t2),
                  ),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 100),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _DevTile(
                      key:     ValueKey(items[i].id),
                      d:       items[i],
                      busy:    n.esBusy(items[i].id),
                      onTap:   () => _onTileTap(context, items[i]),
                    ),
                    childCount: items.length,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing:  12,
                    childAspectRatio: 0.82,
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _HabTabs extends StatelessWidget {
  final List<String>          habs;
  final String                sel;
  final void Function(String) onSel;
  const _HabTabs(
      {required this.habs, required this.sel, required this.onSel});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6),
          itemCount: habs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final h      = habs[i];
            final active = h == sel;
            return GestureDetector(
              onTap: () => onSel(h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color:        active ? C.blue : C.surface,
                  borderRadius: R.xl,
                  border: Border.all(
                      color: active ? C.blue : C.border),
                ),
                child: Text(h,
                    style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                        color:      active ? Colors.white : C.t2)),
              ),
            );
          },
        ),
      );
}

class _DevTile extends StatelessWidget {
  final Dispositivo  d;
  final bool         busy;
  final VoidCallback onTap;
  const _DevTile({
    super.key,
    required this.d,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = d.tipo.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      decoration: BoxDecoration(
        color: d.encendido
            ? col.withValues(alpha: 0.12)
            : C.card,
        borderRadius: R.md,
        border: Border.all(
          color: d.encendido
              ? col.withValues(alpha: 0.45)
              : C.border,
          width: d.encendido ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        onTap:        busy ? null : onTap,
        borderRadius: R.md,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: d.encendido
                          ? col.withValues(alpha: 0.22)
                          : C.surface,
                      borderRadius: R.sm,
                    ),
                    child: Icon(d.cat.icon,
                        size:  22,
                        color: d.encendido ? col : C.t3),
                  ),
                  d.tipo.esCamara
                      ? _CameraOpenButton(
                          encendido: d.encendido,
                          color:     col,
                          onTap:     busy ? null : onTap,
                        )
                      : _PowerButton(
                          encendido: d.encendido,
                          busy:      busy,
                          color:     col,
                          onTap:     busy ? null : onTap,
                        ),
                ],
              ),
              const Spacer(),
              if (d.tipo.soportaBateria) ...[
                _BateriaPill(d),
                const SizedBox(height: 6),
              ],
              Text(d.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                      color:      d.encendido ? C.t1 : C.t2)),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(child: _MicroBadge(d.tipo.label, col: col)),
                const SizedBox(width: 6),
                Text(d.encendido ? 'ON' : 'OFF',
                    style: TextStyle(
                        fontSize:   10,
                        fontWeight: FontWeight.w800,
                        color:      d.encendido ? col : C.t3)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PÁGINA: DISPOSITIVOS
// ════════════════════════════════════════════════════════════════
class DispositivosPage extends StatefulWidget {
  final DispositivosNotifier notifier;
  const DispositivosPage({super.key, required this.notifier});

  @override
  State<DispositivosPage> createState() => _DispPageState();
}

class _DispPageState extends State<DispositivosPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.notifier,
      builder: (_, _) {
        final n = widget.notifier;
        final q = _query.toLowerCase();
        final filtered = n.items
            .where((d) =>
                d.nombre.toLowerCase().contains(q) ||
                d.ip.contains(q) ||
                d.urlBase.toLowerCase().contains(q) ||
                d.habitacion.toLowerCase().contains(q))
            .toList();

        return Scaffold(
          backgroundColor: C.bg,
          body: CustomScrollView(slivers: [
            SliverAppBar(
              pinned:          true,
              backgroundColor: C.surface,
              title: const Text('Dispositivos',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: C.t1)),
              actions: [
                IconButton(
                  tooltip: 'Grabaciones',
                  icon: const Icon(Icons.video_library_rounded,
                      color: C.green),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GrabacionesPage()),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: C.t1, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: C.t3, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: C.t3, size: 18),
                              onPressed: () =>
                                  setState(() => _query = ''))
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    n.items.isEmpty
                        ? 'Sin dispositivos aún'
                        : 'Sin resultados',
                    style: const TextStyle(color: C.t2),
                  ),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _DispCard(
                        key:      ValueKey(filtered[i].id),
                        d:        filtered[i],
                        notifier: n),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                _showDeviceSheet(context, notifier: n),
            backgroundColor: C.blue,
            icon:  const Icon(Icons.add_rounded),
            label: const Text('Agregar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }
}

void _showDeviceSheet(BuildContext context,
    {required DispositivosNotifier notifier,
    Dispositivo? edit}) {
  showModalBottomSheet(
    context:            context,
    backgroundColor:    C.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) =>
        _DeviceForm(notifier: notifier, edit: edit),
  );
}

class _DispCard extends StatefulWidget {
  final Dispositivo          d;
  final DispositivosNotifier notifier;
  const _DispCard(
      {super.key, required this.d, required this.notifier});

  @override
  State<_DispCard> createState() => _DispCardState();
}

class _DispCardState extends State<_DispCard> {
  void _toggle() => widget.notifier.toggle(widget.d.id);

  void _openCamara() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CamaraPage(
            d: widget.d, notifier: widget.notifier),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d    = widget.d;
    final col  = d.tipo.color;
    final busy = widget.notifier.esBusy(d.id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: R.sm,
        border: Border.all(
          color: d.encendido
              ? col.withValues(alpha: 0.4)
              : C.border,
          width: d.encendido ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: d.encendido
                    ? col.withValues(alpha: 0.18)
                    : C.surface,
                borderRadius: R.xs,
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(d.cat.icon,
                    size:  22,
                    color: d.encendido ? col : C.t3),
                if (d.online != null)
                  Positioned(
                    bottom: 3, right: 3,
                    child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.online! ? C.green : C.red,
                        border: Border.all(
                            color: C.card, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.nombre,
                      style: const TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                          color:      C.t1)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _MicroBadge(d.tipo.label, col: col),
                    _MicroBadge(d.habitacion,  col: C.t2),
                    _MicroBadge(d.modo.label,  col: d.modo.color),
                    if (d.tipo.soportaBateria) _BateriaPill(d),
                  ]),
                ],
              ),
            ),
            busy
                ? SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: col))
                : d.tipo.esCamara
                    ? GestureDetector(
                        onTap: _openCamara,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color:        C.cyanGlow,
                            borderRadius: R.xs,
                            border: Border.all(
                                color: C.cyan.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 14, color: C.cyan),
                              SizedBox(width: 4),
                              Text('Ver',
                                  style: TextStyle(
                                      fontSize:   11,
                                      fontWeight: FontWeight.w700,
                                      color:      C.cyan)),
                            ],
                          ),
                        ),
                      )
                    : Switch(
                        value:    d.encendido,
                        onChanged: (_) => _toggle(),
                        activeThumbColor: Colors.white,
                        activeTrackColor: col,
                        inactiveThumbColor: C.t3,
                        inactiveTrackColor: C.surface,
                        trackOutlineColor:
                            WidgetStateProperty.resolveWith((s) =>
                                d.encendido
                                    ? col.withValues(alpha: 0.4)
                                    : C.border),
                      ),
          ]),
          const SizedBox(height: 8),
          const Divider(height: 1, color: C.border),
          const SizedBox(height: 8),
          Row(children: [
            Icon(d.modo.icon, size: 12, color: d.modo.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(d.conexionDisplay,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: C.t3)),
            ),
            const SizedBox(width: 8),
            Text('${d.toggleCount} ops',
                style: const TextStyle(fontSize: 11, color: C.t3)),
            const SizedBox(width: 10),
            _CardAction(
              icon:  Icons.wifi_find_rounded,
              color: C.blue,
              bg:    C.blueGlow,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiagnosticoPage(
                      d: d, notifier: widget.notifier),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _CardAction(
              icon:  Icons.edit_rounded,
              color: C.purple,
              bg:    C.purpleGlow,
              onTap: () => _showDeviceSheet(context,
                  notifier: widget.notifier, edit: d),
            ),
            const SizedBox(width: 6),
            _CardAction(
              icon:  Icons.delete_outline_rounded,
              color: C.red,
              bg:    C.redGlow,
              onTap: () => showDialog(
                context: context,
                builder: (_) => _DeleteDialog(
                  nombre:    d.nombre,
                  onConfirm: () {
                    widget.notifier.eliminar(d.id);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData     icon;
  final Color        color, bg;
  final VoidCallback onTap;
  const _CardAction({
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration:
              BoxDecoration(color: bg, borderRadius: R.xs),
          child: Icon(icon, size: 15, color: color),
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// FORMULARIO AGREGAR / EDITAR
// ════════════════════════════════════════════════════════════════
class _DeviceForm extends StatefulWidget {
  final DispositivosNotifier notifier;
  final Dispositivo?         edit;
  const _DeviceForm({required this.notifier, this.edit});

  @override
  State<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<_DeviceForm> {
  final _fk      = GlobalKey<FormState>();
  late final TextEditingController _cNombre;
  late final TextEditingController _cIp;
  late final TextEditingController _cPuerto;
  late final TextEditingController _cUrl;
  late final TextEditingController _cHab;
  late final TextEditingController _cUser;
  late final TextEditingController _cPass;

  late TipoD        _tipo;
  late CatArtefacto _cat;
  late ModoConexion  _modo;
  bool  _saving  = false;
  bool  _pinging = false;
  bool  _verClave = false;
  bool? _pingOk;

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final e  = widget.edit;
    _cNombre = TextEditingController(text: e?.nombre ?? '');
    _cIp     = TextEditingController(text: e?.ip ?? '');
    _cPuerto = TextEditingController(
        text: (e?.puerto ?? TipoD.ipcam.puertoDefault).toString());
    _cUrl    = TextEditingController(text: e?.urlBase ?? '');
    _cHab    =
        TextEditingController(text: e?.habitacion ?? 'General');
    _cUser   = TextEditingController(text: e?.usuario ?? '');
    _cPass   = TextEditingController(text: e?.clave ?? '');
    _tipo    = e?.tipo ?? TipoD.ipcam;
    _cat     = e?.cat  ?? CatArtefacto.camara;
    _modo    = e?.modo ?? ModoConexion.movil;
  }

  @override
  void dispose() {
    _cNombre.dispose();
    _cIp.dispose();
    _cPuerto.dispose();
    _cUrl.dispose();
    _cHab.dispose();
    _cUser.dispose();
    _cPass.dispose();
    super.dispose();
  }

  String get _base {
    if (_modo == ModoConexion.url) {
      return _cUrl.text.trim().replaceAll(RegExp(r'/$'), '');
    }
    final ip = _cIp.text.trim();
    if (ip.isEmpty) return '';
    return 'http://$ip:${_cPuerto.text.trim()}';
  }

  String get _urlPreview {
    final b = _base;
    if (b.isEmpty) {
      return _modo == ModoConexion.url
          ? '(ingresa la URL)'
          : '(ingresa la IP)';
    }
    return '$b${_tipo.pathOn}';
  }

  // Preview de la URL de video (ipcam) o foto (camara)
  String get _camPreview {
    final b = _base;
    if (b.isEmpty) {
      return _modo == ModoConexion.url
          ? '(ingresa la URL)'
          : '(ingresa la IP)';
    }
    return _tipo.usaStream
        ? '$b${_tipo.pathsStream.first}'
        : '$b${_tipo.pathSnapshot}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20),
      child: Form(
        key: _fk,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: C.border, borderRadius: R.xl),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Editar dispositivo' : 'Agregar dispositivo',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: C.t1),
              ),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'Modifica los datos y guarda los cambios.'
                    : 'Configura tu dispositivo para controlarlo desde la app.',
                style: const TextStyle(fontSize: 11, color: C.t2),
              ),
              const SizedBox(height: 18),

              // Nombre
              const _Lbl('Nombre'),
              TextFormField(
                controller: _cNombre,
                style: const TextStyle(color: C.t1),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Ej: Cámara entrada'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Requerido'
                    : null,
              ),
              const SizedBox(height: 14),

              // Habitación
              const _Lbl('Habitación / Zona'),
              TextFormField(
                controller: _cHab,
                style: const TextStyle(color: C.t1),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Sala, Cocina, Dormitorio...'),
              ),
              const SizedBox(height: 14),

              // Tipo de artefacto
              const _Lbl('Tipo de artefacto'),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: CatArtefacto.values.map((c) {
                  final sel = c == _cat;
                  return GestureDetector(
                    onTap: () => setState(() => _cat = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? c.color.withValues(alpha: 0.18)
                            : C.surface,
                        borderRadius: R.xs,
                        border: Border.all(
                            color: sel ? c.color : C.border),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(c.icon,
                                size:  13,
                                color: sel ? c.color : C.t3),
                            const SizedBox(width: 5),
                            Text(c.label,
                                style: TextStyle(
                                    fontSize:   11,
                                    fontWeight: FontWeight.w600,
                                    color:      sel ? c.color : C.t2)),
                          ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Firmware / Tipo
              const _Lbl('Firmware / Tipo'),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: TipoD.values.map((t) {
                  final sel = t == _tipo;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _tipo   = t;
                      _pingOk = null;
                      if (t.esCamara) _cat = CatArtefacto.camara;
                      if (_modo != ModoConexion.url) {
                        _cPuerto.text = t.puertoDefault.toString();
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? t.color.withValues(alpha: 0.2)
                            : C.surface,
                        borderRadius: R.xs,
                        border: Border.all(
                            color: sel ? t.color : C.border),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.icon,
                                size:  13,
                                color: sel ? t.color : C.t3),
                            const SizedBox(width: 5),
                            Text(t.label,
                                style: TextStyle(
                                    fontSize:   11,
                                    fontWeight: FontWeight.w600,
                                    color:      sel ? t.color : C.t2)),
                          ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Modo de conexión
              const _Lbl('Modo de conexión'),
              ...ModoConexion.values.map((m) {
                final sel = m == _modo;
                return GestureDetector(
                  onTap: () => setState(() {
                    _modo   = m;
                    _pingOk = null;
                    if (m != ModoConexion.url) {
                      _cPuerto.text = _tipo.puertoDefault.toString();
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sel
                          ? m.color.withValues(alpha: 0.10)
                          : C.surface,
                      borderRadius: R.sm,
                      border: Border.all(
                          color: sel ? m.color : C.border,
                          width: sel ? 1.5 : 0.5),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: sel
                              ? m.color.withValues(alpha: 0.18)
                              : C.card,
                          borderRadius: R.xs,
                        ),
                        child: Icon(m.icon,
                            size:  16,
                            color: sel ? m.color : C.t3),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(m.label,
                                style: TextStyle(
                                    fontSize:   13,
                                    fontWeight: FontWeight.w600,
                                    color:      sel ? m.color : C.t1)),
                            const SizedBox(height: 2),
                            Text(m.descripcion,
                                style: const TextStyle(
                                    fontSize: 10, color: C.t2)),
                          ],
                        ),
                      ),
                      if (sel)
                        Icon(Icons.check_circle_rounded,
                            size: 18, color: m.color),
                    ]),
                  ),
                );
              }),

              // Campos según modo
              if (_modo == ModoConexion.url) ...[
                const _Lbl('URL base del dispositivo'),
                TextFormField(
                  controller: _cUrl,
                  style: const TextStyle(color: C.t1),
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      hintText: 'https://abc123.ngrok.io'),
                  onChanged: (_) => setState(() => _pingOk = null),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'URL requerida';
                    }
                    if (!v.trim().startsWith('http')) {
                      return 'Debe empezar con http o https';
                    }
                    return null;
                  },
                ),
              ] else ...[
                const _Lbl('IP del dispositivo'),
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: C.orangeGlow,
                    borderRadius: R.xs,
                    border: Border.all(
                        color: C.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: C.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tipo == TipoD.ipcam
                            ? 'En Android IP Camera usa TLS "solo HTTP" y configura usuario y contraseña. Puerto 4444.'
                            : _tipo.esCamara || _tipo == TipoD.celular
                                ? 'Abre Web Remote Droid en el otro celular y copia la IP que muestra en la pantalla principal'
                                : 'Busca la IP en la interfaz web del dispositivo o en tu router',
                        style: const TextStyle(
                            fontSize: 10, color: C.orange),
                      ),
                    ),
                  ]),
                ),
                TextFormField(
                  controller: _cIp,
                  style: const TextStyle(color: C.t1),
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(hintText: _modo.hint),
                  onChanged: (_) => setState(() => _pingOk = null),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'IP requerida';
                    }
                    if (v.trim() == '0.0.0.0') {
                      return 'IP inválida';
                    }
                    if (v.trim() == 'localhost' ||
                        v.trim() == '127.0.0.1') {
                      return 'No uses localhost';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const _Lbl('Puerto'),
                TextFormField(
                  controller: _cPuerto,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: C.t1),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      hintText: _tipo.puertoDefault.toString()),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Requerido';
                    }
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1 || n > 65535) {
                      return 'Puerto inválido (1-65535)';
                    }
                    return null;
                  },
                ),
              ],

              // Usuario y contraseña (cámaras)
              if (_tipo.esCamara) ...[
                const SizedBox(height: 12),
                const _Lbl('Usuario (opcional)'),
                TextFormField(
                  controller: _cUser,
                  style: const TextStyle(color: C.t1),
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration:
                      const InputDecoration(hintText: 'usuario'),
                ),
                const SizedBox(height: 12),
                const _Lbl('Contraseña (opcional)'),
                TextFormField(
                  controller: _cPass,
                  style: const TextStyle(color: C.t1),
                  obscureText: !_verClave,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _verClave
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: C.t3,
                          size: 18),
                      onPressed: () =>
                          setState(() => _verClave = !_verClave),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Preview de URL
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        C.blueGlow,
                  borderRadius: R.xs,
                  border: Border.all(
                      color: C.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_tipo.esCamara) ...[
                      const Row(children: [
                        Icon(Icons.link_rounded,
                            size: 12, color: C.blue),
                        SizedBox(width: 6),
                        Text('URL al encender:',
                            style: TextStyle(
                                fontSize:   10,
                                fontWeight: FontWeight.w600,
                                color:      C.blue)),
                      ]),
                      const SizedBox(height: 4),
                      Text(_urlPreview,
                          style: const TextStyle(
                              fontSize:   11,
                              color:      C.t2,
                              fontFamily: 'monospace')),
                    ],
                    if (_tipo.esCamara) ...[
                      Row(children: [
                        const Icon(Icons.videocam_rounded,
                            size: 12, color: C.cyan),
                        const SizedBox(width: 6),
                        Text(
                            _tipo.usaStream
                                ? 'URL del video:'
                                : 'URL de la foto:',
                            style: const TextStyle(
                                fontSize:   10,
                                fontWeight: FontWeight.w600,
                                color:      C.cyan)),
                      ]),
                      const SizedBox(height: 4),
                      Text(_camPreview,
                          style: const TextStyle(
                              fontSize:   11,
                              color:      C.t2,
                              fontFamily: 'monospace')),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Botón ping
              OutlinedButton.icon(
                onPressed: _pinging ? null : _doPing,
                icon: _pinging
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: C.blue))
                    : Icon(
                        _pingOk == null
                            ? Icons.network_check_rounded
                            : _pingOk!
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                        size: 16,
                        color: _pingOk == null
                            ? C.t2
                            : _pingOk!
                                ? C.green
                                : C.red),
                label: Text(
                  _pinging
                      ? 'Verificando...'
                      : _pingOk == null
                          ? 'Probar conexión (opcional)'
                          : _pingOk!
                              ? 'Responde correctamente ✓'
                              : 'Sin respuesta — puedes agregar igual',
                  style: TextStyle(
                      fontSize: 13,
                      color: _pingOk == null
                          ? C.t2
                          : _pingOk!
                              ? C.green
                              : C.orange),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(
                      color: _pingOk == null
                          ? C.border
                          : _pingOk!
                              ? C.green
                              : C.orange),
                  shape: const RoundedRectangleBorder(
                      borderRadius: R.xs),
                ),
              ),
              const SizedBox(height: 10),

              // Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _doSave,
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : Text(_isEdit
                          ? 'Guardar cambios'
                          : 'Agregar dispositivo'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doPing() async {
    if (!_fk.currentState!.validate()) return;
    setState(() {
      _pinging = true;
      _pingOk  = null;
    });
    final ok = await NetCtrl.ping(
      modo:    _modo,
      ip:      _cIp.text.trim(),
      puerto:  int.tryParse(_cPuerto.text.trim()) ?? _tipo.puertoDefault,
      urlBase: _cUrl.text.trim(),
    );
    if (mounted) {
      setState(() {
        _pinging = false;
        _pingOk  = ok;
      });
    }
  }

  Future<void> _doSave() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);

    final puerto =
        int.tryParse(_cPuerto.text.trim()) ?? _tipo.puertoDefault;
    final usuario = _tipo.esCamara ? _cUser.text : '';
    final clave   = _tipo.esCamara ? _cPass.text : '';

    if (_isEdit) {
      widget.notifier.editar(
        id:         widget.edit!.id,
        nombre:     _cNombre.text,
        tipo:       _tipo,
        cat:        _cat,
        modo:       _modo,
        ip:         _cIp.text,
        puerto:     puerto,
        urlBase:    _cUrl.text,
        habitacion: _cHab.text,
        usuario:    usuario,
        clave:      clave,
      );
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Dispositivo actualizado ✓');
      }
    } else {
      final ok = await widget.notifier.agregar(
        nombre:     _cNombre.text,
        tipo:       _tipo,
        cat:        _cat,
        modo:       _modo,
        ip:         _cIp.text,
        puerto:     puerto,
        urlBase:    _cUrl.text,
        habitacion: _cHab.text,
        usuario:    usuario,
        clave:      clave,
        skipPing:   true,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (ok) {
          Navigator.pop(context);
          snack(context, 'Dispositivo agregado ✓');
        } else {
          snack(context, 'Error al guardar', error: true);
        }
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════
// PÁGINA: HISTORIAL
// ════════════════════════════════════════════════════════════════
class HistorialPage extends StatelessWidget {
  final DispositivosNotifier notifier;
  const HistorialPage({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: notifier,
      builder: (_, _) {
        final log = notifier.log;
        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.surface,
            title: const Text('Historial',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: C.t1)),
            actions: [
              if (log.isNotEmpty)
                TextButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: C.card,
                      shape: const RoundedRectangleBorder(
                          borderRadius: R.md),
                      title: const Text('Limpiar historial',
                          style: TextStyle(
                              color: C.t1, fontSize: 16)),
                      content: const Text(
                          '¿Borrar todo el historial?',
                          style: TextStyle(color: C.t2)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () {
                            notifier.limpiarLog();
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: C.red),
                          child: const Text('Limpiar'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded,
                      color: C.t3, size: 18),
                  label: const Text('Limpiar',
                      style:
                          TextStyle(color: C.t3, fontSize: 13)),
                ),
            ],
          ),
          body: log.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 46, color: C.t3),
                      SizedBox(height: 12),
                      Text('Sin actividad aún',
                          style: TextStyle(color: C.t2)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:    const EdgeInsets.all(14),
                  itemCount:  log.length,
                  itemBuilder: (_, i) => _LogTile(e: log[i]),
                ),
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry e;
  const _LogTile({required this.e});

  @override
  Widget build(BuildContext context) => Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: R.xs,
          border: Border.all(color: C.border),
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: (e.ok ? C.green : C.red)
                  .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              e.ok ? Icons.check_rounded : Icons.close_rounded,
              size:  15,
              color: e.ok ? C.green : C.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.msg,
                    style: const TextStyle(
                        fontSize: 13, color: C.t1)),
                const SizedBox(height: 2),
                Text(_fmtTs(e.ts),
                    style: const TextStyle(
                        fontSize: 11, color: C.t3)),
              ],
            ),
          ),
        ]),
      );
}

// ════════════════════════════════════════════════════════════════
// PÁGINA: DIAGNÓSTICO DE RED
// ════════════════════════════════════════════════════════════════
class DiagnosticoPage extends StatefulWidget {
  final Dispositivo          d;
  final DispositivosNotifier notifier;
  const DiagnosticoPage(
      {super.key, required this.d, required this.notifier});

  @override
  State<DiagnosticoPage> createState() =>
      _DiagnosticoPageState();
}

class _DiagnosticoPageState extends State<DiagnosticoPage> {
  final List<_DiagLog> _logs = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  // Comprueba un endpoint sin descargar el stream completo
  Future<void> _probarEndpoint(Dispositivo d, String url, String etiqueta) async {
    _log('  GET $url', null);
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll(d.authHeaders);
      final resp = await client.send(req).timeout(AppConfig.pingTimeout);
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      _log(
        '  → HTTP ${resp.statusCode} ${ok ? "✓ $etiqueta disponible" : "— no disponible"}',
        ok,
      );
      if (ok) {
        _log('  Content-Type: ${resp.headers["content-type"] ?? "desconocido"}', null);
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        _log('  → Usuario o contraseña incorrectos', false);
      }
    } on TimeoutException {
      _log('  → TIMEOUT', false);
    } catch (e) {
      _log('  → ERROR: $e', false);
    } finally {
      client.close();
    }
  }

  Future<void> _run() async {
    setState(() {
      _logs.clear();
      _running = true;
    });

    final d    = widget.d;
    final demo = widget.notifier.demo;

    _log('Dispositivo: ${d.nombre}', null);
    _log('Firmware:    ${d.tipo.label}', null);
    _log('Modo:        ${d.modo.label}', null);
    _log('Conexión:    ${d.conexionDisplay}', null);
    _log('Autenticación: ${d.usuario.isEmpty ? "no" : "usuario ${d.usuario}"}', null);
    if (demo) {
      _log('⚠ Modo DEMO activo — simulando respuestas', null);
    }
    _log('─────────────────────────────', null);
    if (d.tipo.usaStream) {
      for (final u in d.urlsStream) {
        _log('URL video: $u', null);
      }
      _log('URL audio: ${d.urlAudio}', null);
    } else if (d.tipo.esCamara) {
      _log('URL foto: ${d.urlSnapshot}', null);
    } else {
      _log('URL ON:  ${d.urlOn}', null);
      _log('URL OFF: ${d.urlOff}', null);
    }
    _log('─────────────────────────────', null);

    // Ping base
    _log('▶ Probando conectividad base...', null);
    if (demo) {
      await Future.delayed(const Duration(milliseconds: 400));
      _log('  [DEMO] Simulado: OK ✓', true);
    } else {
      try {
        final baseUrl = d.modo == ModoConexion.url
            ? d.urlBase.trim()
            : 'http://${d.ip.trim()}:${d.puerto}';
        final resp = await http
            .get(Uri.parse(baseUrl), headers: d.authHeaders)
            .timeout(AppConfig.pingTimeout);
        _log('  GET $baseUrl → HTTP ${resp.statusCode}',
            resp.statusCode < 400);
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          _log('  → Requiere usuario y contraseña (o son incorrectos)', false);
        } else if (resp.statusCode >= 400) {
          _log('  → Verifica IP/URL y conexión de red', false);
        } else {
          _log('  Host alcanzable ✓', true);
        }
      } on TimeoutException {
        _log(
          '  TIMEOUT — sin respuesta en ${AppConfig.pingTimeout.inSeconds}s',
          false,
        );
        _log('  → Verifica IP/URL y que estés en la misma red', false);
      } catch (e) {
        _log('  ERROR: $e', false);
        _log('  → Si la app de la cámara usa HTTPS, cámbiala a "solo HTTP"', false);
      }
    }

    _log('─────────────────────────────', null);

    if (d.tipo.usaStream) {
      _log('▶ Verificando video MJPEG...', null);
      if (demo) {
        await Future.delayed(const Duration(milliseconds: 300));
        _log('  [DEMO] ${d.urlsStream.first} → OK ✓', true);
      } else {
        for (final u in d.urlsStream) {
          await _probarEndpoint(d, u, 'Video');
        }
      }
      _log('─────────────────────────────', null);
      _log('▶ Verificando audio...', null);
      if (demo) {
        await Future.delayed(const Duration(milliseconds: 300));
        _log('  [DEMO] ${d.urlAudio} → OK ✓', true);
      } else {
        await _probarEndpoint(d, d.urlAudio, 'Audio');
      }
    } else if (d.tipo.esCamara) {
      _log('▶ Verificando foto de la cámara...', null);
      if (demo) {
        await Future.delayed(const Duration(milliseconds: 300));
        _log('  [DEMO] ${d.urlSnapshot} → OK ✓', true);
      } else {
        try {
          final resp = await http
              .get(Uri.parse(d.urlSnapshot), headers: d.authHeaders)
              .timeout(AppConfig.pingTimeout);
          final ok = resp.statusCode >= 200 && resp.statusCode < 300;
          _log(
            '  GET ${d.urlSnapshot} → HTTP ${resp.statusCode} ${ok ? "✓ Foto disponible (${resp.bodyBytes.length} bytes)" : "— no disponible"}',
            ok,
          );
          if (!ok) {
            _log('  → Revisa el permiso de cámara en la app del otro celular', false);
          }
        } on TimeoutException {
          _log('  → TIMEOUT al pedir la foto', false);
        } catch (e) {
          _log('  → ERROR: $e', false);
        }
      }
    } else {
      _log('▶ Buscando ruta ON válida (${d.urlsOnFallback.length} paths)...', null);
      if (demo) {
        await Future.delayed(const Duration(milliseconds: 300));
        _log('  [DEMO] ${d.urlOn} → OK ✓', true);
      } else {
        bool foundOn = false;
        for (final url in d.urlsOnFallback) {
          _log('  GET $url', null);
          try {
            final resp = await http
                .get(Uri.parse(url), headers: d.authHeaders)
                .timeout(AppConfig.pingTimeout);
            final ok =
                resp.statusCode >= 200 && resp.statusCode < 300;
            _log(
              '  → HTTP ${resp.statusCode} ${ok ? "✓ RUTA CORRECTA" : "(404 — siguiente...)"}',
              ok ? true : null,
            );
            if (ok) {
              foundOn = true;
              break;
            }
          } on TimeoutException {
            _log('  → TIMEOUT', false);
            break;
          } catch (_) {
            _log('  → Sin respuesta HTTP', null);
          }
        }
        if (!foundOn) {
          _log('  ⚠ Ningún path ON respondió con 2xx', false);
        }
      }
    }

    _log('─────────────────────────────', null);
    _log('✓ Diagnóstico completo — el dispositivo NO fue activado', true);
    if (mounted) setState(() => _running = false);
  }

  void _log(String msg, bool? ok) {
    if (!mounted) return;
    setState(() => _logs.add(_DiagLog(msg, ok)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.surface,
          title: Text('Diagnóstico: ${widget.d.nombre}',
              style: const TextStyle(
                  color:      C.t1,
                  fontWeight: FontWeight.w700,
                  fontSize:   15)),
          actions: [
            if (!_running)
              IconButton(
                icon:    const Icon(Icons.refresh_rounded, color: C.blue),
                onPressed: _run,
                tooltip: 'Repetir diagnóstico',
              ),
          ],
        ),
        body: Column(children: [
          if (_running)
            const LinearProgressIndicator(
                color: C.blue, backgroundColor: C.border),
          Expanded(
            child: ListView.builder(
              padding:    const EdgeInsets.all(14),
              itemCount:  _logs.length,
              itemBuilder: (_, i) {
                final l = _logs[i];
                Color col = C.t2;
                if (l.ok == true) {
                  col = C.green;
                }
                if (l.ok == false) {
                  col = C.red;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l.msg,
                      style: TextStyle(
                          fontSize:   12,
                          color:      col,
                          fontFamily: 'monospace')),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _running ? null : _run,
                icon:  const Icon(Icons.play_arrow_rounded),
                label: const Text('Repetir prueba'),
              ),
            ),
          ),
        ]),
      );
}

class _DiagLog {
  final String msg;
  final bool?  ok;
  _DiagLog(this.msg, this.ok);
}

// ════════════════════════════════════════════════════════════════
// [REC-2] PÁGINA: GRABACIONES
// ════════════════════════════════════════════════════════════════
class GrabacionesPage extends StatefulWidget {
  const GrabacionesPage({super.key});

  @override
  State<GrabacionesPage> createState() => _GrabacionesPageState();
}

class _GrabacionesPageState extends State<GrabacionesPage> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final dir = await Grabador.carpeta();
    final lista = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mjpeg'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) {
      setState(() {
        _files   = lista;
        _loading = false;
      });
    }
  }

  String _nombre(File f) => f.path.split('/').last;

  Future<void> _compartir(File f) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], text: _nombre(f)),
      );
    } catch (e) {
      if (mounted) snack(context, 'No se pudo compartir: $e', error: true);
    }
  }

  void _borrar(File f) {
    showDialog(
      context: context,
      builder: (_) => _DeleteDialog(
        titulo:    'Eliminar grabación',
        nombre:    _nombre(f),
        onConfirm: () {
          try {
            f.deleteSync();
          } catch (_) {}
          Navigator.pop(context);
          _cargar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.surface,
          title: const Text('Grabaciones',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: C.t1)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: C.blue),
              onPressed: _cargar,
              tooltip: 'Actualizar',
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: C.cyan))
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: C.blueGlow,
                      borderRadius: R.xs,
                      border: Border.all(
                          color: C.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Las grabaciones son archivos .mjpeg (solo video, sin audio). '
                      'Toca compartir y ábrelas con VLC. La velocidad de reproducción '
                      'puede no ser exacta.',
                      style: TextStyle(fontSize: 11, color: C.t2),
                    ),
                  ),
                  if (_files.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text('Aún no hay grabaciones',
                            style: TextStyle(color: C.t2)),
                      ),
                    ),
                  ..._files.map((f) {
                    final st = f.statSync();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: C.card,
                        borderRadius: R.sm,
                        border: Border.all(color: C.border),
                      ),
                      child: Row(children: [
                        const Icon(Icons.videocam_rounded,
                            color: C.cyan, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(_nombre(f),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: C.t1)),
                              const SizedBox(height: 2),
                              Text(
                                  '${_fmtBytes(st.size)} · ${_fmtTs(st.modified)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: C.t3)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded,
                              color: C.blue, size: 20),
                          onPressed: () => _compartir(f),
                          tooltip: 'Compartir',
                        ),
                        IconButton(
                          icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: C.red,
                              size: 20),
                          onPressed: () => _borrar(f),
                          tooltip: 'Eliminar',
                        ),
                      ]),
                    );
                  }),
                ],
              ),
      );
}

// ════════════════════════════════════════════════════════════════
// WIDGETS REUTILIZABLES
// ════════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════
// [BAT-2] INDICADOR DE BATERÍA
// ════════════════════════════════════════════════════════════════
Color _colorBateria(int? n) => n == null
    ? C.t3
    : n <= 15
        ? C.red
        : n <= 40
            ? C.orange
            : C.green;

// Icono de batería con relleno animado.
class _BateriaGlyph extends StatelessWidget {
  final int?   nivel;
  final Color  color;
  final double w, h;
  const _BateriaGlyph({
    required this.nivel,
    required this.color,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w, height: h,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.4),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween:    Tween(begin: 0, end: (nivel ?? 0) / 100),
                duration: const Duration(milliseconds: 500),
                builder: (_, v, _) => FractionallySizedBox(
                  widthFactor:  v.clamp(0.0, 1.0).toDouble(),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:        color,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 2, height: h * 0.4,
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(1)),
            ),
          ),
        ],
      );
}

// Píldora: icono + porcentaje (+ rayo si carga, nube tachada si no responde).
class _BateriaPill extends StatelessWidget {
  final Dispositivo d;
  final bool        grande;
  const _BateriaPill(this.d, {this.grande = false});

  @override
  Widget build(BuildContext context) {
    final n   = d.bateria;
    final col = _colorBateria(n);
    final sc  = grande ? 1.2 : 1.0;

    final tip = StringBuffer('Batería');
    if (d.bateriaInfo != null) tip.write(' · ${d.bateriaInfo}');
    if (d.bateriaError) {
      tip.write(' · sin respuesta');
    } else if (d.bateriaTs != null) {
      tip.write(' · ${_fmtTs(d.bateriaTs!)}');
    }

    return Tooltip(
      message: tip.toString(),
      child: Opacity(
        opacity: d.bateriaError ? 0.55 : 1,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 7 * sc, vertical: 3 * sc),
          decoration: BoxDecoration(
            color:        col.withValues(alpha: 0.14),
            borderRadius: R.xl,
            border: Border.all(
                color: col.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _BateriaGlyph(nivel: n, color: col, w: 18 * sc, h: 9 * sc),
            SizedBox(width: 5 * sc),
            Text(n == null ? '--%' : '$n%',
                style: TextStyle(
                    fontSize:   10 * sc,
                    fontWeight: FontWeight.w800,
                    color:      col)),
            if (d.cargando && !d.bateriaError) ...[
              const SizedBox(width: 2),
              Icon(Icons.bolt_rounded, size: 12 * sc, color: C.yellow),
            ],
            if (d.bateriaError) ...[
              const SizedBox(width: 4),
              Icon(Icons.cloud_off_rounded, size: 11 * sc, color: C.t2),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MicroBadge extends StatelessWidget {
  final String text;
  final Color  col;
  const _MicroBadge(this.text, {required this.col});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:        col.withValues(alpha: 0.14),
          borderRadius: R.xl,
        ),
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize:   9,
                fontWeight: FontWeight.w700,
                color:      col)),
      );
}

class _Lbl extends StatelessWidget {
  final String text;
  const _Lbl(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color:      C.t2)),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
  final VoidCallback onTap;
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: R.xs,
              border: Border.all(
                  color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      );
}

class _DeleteDialog extends StatelessWidget {
  final String       nombre;
  final VoidCallback onConfirm;
  final String       titulo;
  const _DeleteDialog(
      {required this.nombre,
      required this.onConfirm,
      this.titulo = 'Eliminar dispositivo'});

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: C.card,
        shape: const RoundedRectangleBorder(borderRadius: R.md),
        title: Text(titulo,
            style: const TextStyle(color: C.t1, fontSize: 16)),
        content: Text(
          '¿Eliminar "$nombre"?\nNo se puede deshacer.',
          style: const TextStyle(color: C.t2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: onConfirm,
            style: TextButton.styleFrom(foregroundColor: C.red),
            child: const Text('Eliminar'),
          ),
        ],
      );
}
