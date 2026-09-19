// ╔══════════════════════════════════════════════════════════════════╗
// ║  DOMÓTICA PRO  v5.3  —  Producción                              ║
// ╚══════════════════════════════════════════════════════════════════╝
//
// NOVEDADES v5.3:
//  [CAM-1] Nuevo tipo TipoD.camara — Web Remote Droid stream MJPEG.
//          Paths confirmados:
//            Encender cámara : /camera/on   (GET)
//            Apagar cámara   : /camera/off  (GET)
//            Stream MJPEG    : /video        (GET)
//            Snapshot JPG    : /shot.jpg     (GET — para miniatura)
//  [CAM-2] Al tocar la tarjeta de un dispositivo tipo cámara se abre
//          CamaraPage en pantalla completa con stream MJPEG en vivo.
//  [CAM-3] CamaraPage: controles ON/OFF, snap para foto, indicador
//          de estado de conexión y botón de pantalla completa.
//  [CAM-4] MjpegWidget: decodifica el stream multipart/x-mixed-replace
//          cuadro a cuadro sin paquete externo — solo dart:typed_data
//          y flutter/painting. Robusto a cortes de red.
//  [CAM-5] _ControlCard detecta tipo cámara y abre CamaraPage en
//          lugar del toggle habitual.
//
// CORRECCIONES anteriores mantenidas (v5.1 / v5.2):
//  [FIX-1..8] — ver cabecera original de v5.2

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  static const cyan       = Color(0xFF00D4FF);   // [CAM-1] color cámara
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
        ModoConexion.movil => '10.151.28.43',
        ModoConexion.url   => 'https://mi-tunel.ngrok.io',
      };
  String get descripcion => switch (this) {
        ModoConexion.lan   => 'Misma red WiFi. IP privada (192.168.x.x).',
        ModoConexion.movil => 'Cualquier red. IP pública + puerto abierto.',
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
// [CAM-1] Agregado TipoD.camara
enum TipoD { tasmota, sonoff, shelly, celular, camara, otro }

extension TipoDX on TipoD {
  String get label => switch (this) {
        TipoD.tasmota => 'Tasmota',
        TipoD.sonoff  => 'Sonoff',
        TipoD.shelly  => 'Shelly',
        TipoD.celular => 'Celular (flash)',
        TipoD.camara  => 'Cámara IP',
        TipoD.otro    => 'Genérico',
      };
  IconData get icon => switch (this) {
        TipoD.tasmota => Icons.electrical_services_rounded,
        TipoD.sonoff  => Icons.bolt_rounded,
        TipoD.shelly  => Icons.router_rounded,
        TipoD.celular => Icons.smartphone_rounded,
        TipoD.camara  => Icons.videocam_rounded,   // [CAM-1]
        TipoD.otro    => Icons.settings_input_hdmi_rounded,
      };
  Color get color => switch (this) {
        TipoD.tasmota => C.blue,
        TipoD.sonoff  => C.orange,
        TipoD.shelly  => C.green,
        TipoD.celular => C.yellow,
        TipoD.camara  => C.cyan,    // [CAM-1]
        TipoD.otro    => C.t2,
      };

  // [CAM-1] Paths Web Remote Droid para cámara
  String get pathOn => switch (this) {
        TipoD.tasmota => '/cm?cmnd=Power+On',
        TipoD.sonoff  => '/control?cmd=on',
        TipoD.shelly  => '/relay/0?turn=on',
        TipoD.celular => '/flash/on',
        TipoD.camara  => '/camera/on',
        TipoD.otro    => '/on',
      };
  String get pathOff => switch (this) {
        TipoD.tasmota => '/cm?cmnd=Power+Off',
        TipoD.sonoff  => '/control?cmd=off',
        TipoD.shelly  => '/relay/0?turn=off',
        TipoD.celular => '/flash/off',
        TipoD.camara  => '/camera/off',
        TipoD.otro    => '/off',
      };

  // [CAM-1] Path del stream MJPEG (solo para tipo camara)
  String get pathStream => '/video';

  // [CAM-1] Path del snapshot JPG (solo para tipo camara)
  String get pathSnapshot => '/shot.jpg';

  List<String> get pathsOnFallback => switch (this) {
        TipoD.celular => ['/flash/on', '/?action=on', '/flash?on=1'],
        TipoD.camara  => ['/camera/on', '/video/on', '/?camera=on'],  // [CAM-1]
        TipoD.tasmota => ['/cm?cmnd=Power+On', '/cm?cmnd=Power1+On'],
        TipoD.shelly  => ['/relay/0?turn=on', '/rpc/Switch.Set?id=0&on=true'],
        _ => [pathOn],
      };

  List<String> get pathsOffFallback => switch (this) {
        TipoD.celular => ['/flash/off', '/?action=off', '/flash?on=0'],
        TipoD.camara  => ['/camera/off', '/video/off', '/?camera=off'],  // [CAM-1]
        TipoD.tasmota => ['/cm?cmnd=Power+Off', '/cm?cmnd=Power1+Off'],
        TipoD.shelly  => ['/relay/0?turn=off', '/rpc/Switch.Set?id=0&on=false'],
        _ => [pathOff],
      };

  // [CAM-1] ¿Es un dispositivo de video?
  bool get esCamara => this == TipoD.camara;

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
  bool         encendido;
  DateTime?    ultimaAccion;
  int          toggleCount;
  bool?        online;

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

  String get urlOn  => '$_base${tipo.pathOn}';
  String get urlOff => '$_base${tipo.pathOff}';

  // [CAM-1] URLs específicas de cámara
  String get urlStream   => '$_base${tipo.pathStream}';
  String get urlSnapshot => '$_base${tipo.pathSnapshot}';

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
        encendido:    encendido   ?? this.encendido,
        ultimaAccion: ultimaAccion ?? this.ultimaAccion,
        toggleCount:  toggleCount ?? this.toggleCount,
        online:       online      ?? this.online,
      );
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
  List<Dispositivo> _items;
  int  _nextId = 1;
  bool _demo   = false;
  final List<LogEntry> _log = [];

  DispositivosNotifier(List<Dispositivo> items, this._prefs)
      : _items = List.of(items) {
    if (_items.isNotEmpty) {
      _nextId =
          _items.map((d) => d.id).reduce((a, b) => a > b ? a : b) + 1;
    }
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

    if (!_demo) {
      _fireAndForget(d, nuevoEstado);
    }
  }

  void _fireAndForget(Dispositivo d, bool encender) {
    final url = encender ? d.urlOn : d.urlOff;
    http
        .get(Uri.parse(url))
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
    ));
    _addLog('Dispositivo "${nombre.trim()}" agregado', ok: true);
    if (hasListeners) notifyListeners();
    _save();
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
    );
    _addLog('Dispositivo "${nombre.trim()}" actualizado', ok: true);
    if (hasListeners) notifyListeners();
    _save();
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

  @override
  void dispose() => super.dispose();
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

// ════════════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════════════
class DomoticaApp extends StatelessWidget {
  final DispositivosNotifier notifier;
  const DomoticaApp({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: notifier,
        builder: (_, __) => MaterialApp(
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
// [CAM-4] MJPEG WIDGET — stream MJPEG cuadro a cuadro sin plugin
// ════════════════════════════════════════════════════════════════
/// Decodifica un stream multipart/x-mixed-replace (MJPEG) cuadro
/// a cuadro usando solo http.Client y dart:typed_data.
/// Muestra cada frame como Image.memory en cuanto llega.
class MjpegWidget extends StatefulWidget {
  final String  streamUrl;
  final BoxFit  fit;
  const MjpegWidget({
    super.key,
    required this.streamUrl,
    this.fit = BoxFit.contain,
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

  // Marcadores JPEG
  static final _soiMarker = Uint8List.fromList([0xFF, 0xD8]); // Start Of Image
  static final _eoiMarker = Uint8List.fromList([0xFF, 0xD9]); // End Of Image

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(MjpegWidget old) {
    super.didUpdateWidget(old);
    if (old.streamUrl != widget.streamUrl) {
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

    try {
      _client = http.Client();
      final request  = http.Request('GET', Uri.parse(widget.streamUrl));
      final response = await _client!.send(request).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Timeout al conectar con la cámara'),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (mounted) setState(() => _connecting = false);

      // Buffer acumulador de bytes
      final buf = <int>[];

      _sub = response.stream.listen(
        (chunk) {
          buf.addAll(chunk);
          _extractFrames(buf);
        },
        onError: (e) {
          if (mounted) setState(() => _error = 'Error de stream: $e');
        },
        onDone: () {
          if (mounted) setState(() => _error = 'Stream terminado');
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error      = e.toString();
        });
      }
    }
  }

  /// Extrae todos los frames JPEG completos del buffer acumulado.
  /// Un frame JPEG comienza con FFD8 y termina con FFD9.
  void _extractFrames(List<int> buf) {
    while (true) {
      // Buscar inicio de JPEG
      final start = _indexOf(buf, _soiMarker, 0);
      if (start == -1) {
        // Sin SOI: limpiar basura
        buf.clear();
        break;
      }

      // Buscar fin de JPEG desde el inicio encontrado
      final end = _indexOf(buf, _eoiMarker, start + 2);
      if (end == -1) break; // Frame incompleto — esperar más datos

      // Frame completo: extraer
      final frameEnd = end + 2;
      final frame    = Uint8List.fromList(buf.sublist(start, frameEnd));

      // Quitar el frame procesado del buffer
      buf.removeRange(0, frameEnd);

      if (mounted) {
        setState(() => _frame = frame);
      }
    }
  }

  /// Busca la primera ocurrencia de [pattern] en [data] desde [from].
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
      gaplessPlayback: true, // evita parpadeo entre frames
    );
  }
}

// ════════════════════════════════════════════════════════════════
// [CAM-2] CAMARA PAGE — pantalla completa con stream y controles
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
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _d = widget.d;
    _scheduleHide();
    // Si la cámara no está encendida, encenderla automáticamente
    if (!_d.encendido) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setCamara(true));
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _setCamara(bool encender) async {
    widget.notifier.toggle(_d.id);
    // Refrescar estado local
    final updated = widget.notifier.items
        .firstWhere((x) => x.id == _d.id, orElse: () => _d);
    if (mounted) setState(() => _d = updated);
  }

  @override
  Widget build(BuildContext context) {
    // Mantener estado sincronizado con el notifier
    final dActual = widget.notifier.items
        .firstWhere((x) => x.id == _d.id, orElse: () => _d);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── 1. Stream de video ─────────────────────────────────
        GestureDetector(
          onTap: _showControls,
          child: SizedBox.expand(
            child: dActual.encendido
                ? MjpegWidget(
                    key:       ValueKey(dActual.urlStream),
                    streamUrl: dActual.urlStream,
                    fit:       BoxFit.contain,
                  )
                : const _CamaraApagada(),
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
                            dActual.encendido
                                ? 'En vivo'
                                : 'Cámara apagada',
                            style: TextStyle(
                                color: dActual.encendido
                                    ? C.green
                                    : C.t3,
                                fontSize: 11),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  // Badge de URL
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
                height: 160,
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Botón encender/apagar
                      _CamControlBtn(
                        icon: dActual.encendido
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        label: dActual.encendido
                            ? 'Apagar cámara'
                            : 'Encender cámara',
                        color: dActual.encendido ? C.red : C.cyan,
                        onTap: () => _setCamara(!dActual.encendido),
                      ),
                      const SizedBox(width: 24),
                      // Botón de diagnóstico
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
            Text('Toca "Encender cámara" para iniciar el stream',
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
  // [CAM-5] Redirige a CamaraPage si es tipo camara
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
      builder: (_, __) {
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
                    builder: (_, v, __) => LinearProgressIndicator(
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

// [CAM-5] _ControlCard ahora acepta onTap (para cámara) y onToggle
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

    // [CAM-5] Las tarjetas de cámara muestran ícono de play en lugar del botón power
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
                  Row(children: [
                    _MicroBadge(d.tipo.label, col: d.tipo.color),
                    const SizedBox(width: 6),
                    _MicroBadge(d.habitacion, col: C.t3),
                    if (esCamara) ...[
                      const SizedBox(width: 6),
                      _MicroBadge('MJPEG', col: C.cyan),
                    ],
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
            // [CAM-5] Botón diferente para cámara
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

// [CAM-5] Botón de abrir cámara (en lugar del botón power)
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
      builder: (_, __) {
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
          separatorBuilder: (_, __) => const SizedBox(width: 8),
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
              Text(d.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                      color:      d.encendido ? C.t1 : C.t2)),
              const SizedBox(height: 4),
              Row(children: [
                _MicroBadge(d.tipo.label, col: col),
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
      builder: (_, __) {
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
                  Wrap(spacing: 6, children: [
                    _MicroBadge(d.tipo.label, col: col),
                    _MicroBadge(d.habitacion,  col: C.t2),
                    _MicroBadge(d.modo.label,  col: d.modo.color),
                    if (d.tipo.esCamara)
                      _MicroBadge('MJPEG', col: C.cyan),
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
                    // [CAM-5] Switch diferente para cámara
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
                        activeColor:      Colors.white,
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

  late TipoD        _tipo;
  late CatArtefacto _cat;
  late ModoConexion  _modo;
  bool  _saving  = false;
  bool  _pinging = false;
  bool? _pingOk;

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final e  = widget.edit;
    _cNombre = TextEditingController(text: e?.nombre ?? '');
    _cIp     = TextEditingController(text: e?.ip ?? '');
    _cPuerto =
        TextEditingController(text: (e?.puerto ?? 8888).toString());
    _cUrl    = TextEditingController(text: e?.urlBase ?? '');
    _cHab    =
        TextEditingController(text: e?.habitacion ?? 'General');
    _tipo    = e?.tipo ?? TipoD.camara;    // [CAM-1] default cámara
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
    super.dispose();
  }

  String get _urlPreview {
    try {
      if (_modo == ModoConexion.url) {
        final base =
            _cUrl.text.trim().replaceAll(RegExp(r'/$'), '');
        return base.isEmpty
            ? '(ingresa la URL)'
            : '$base${_tipo.pathOn}';
      }
      final ip = _cIp.text.trim();
      final p  = _cPuerto.text.trim();
      return ip.isEmpty
          ? '(ingresa la IP)'
          : 'http://$ip:$p${_tipo.pathOn}';
    } catch (_) {
      return '—';
    }
  }

  // [CAM-1] Preview de la URL del stream
  String get _streamPreview {
    try {
      if (_tipo != TipoD.camara) return '';
      if (_modo == ModoConexion.url) {
        final base =
            _cUrl.text.trim().replaceAll(RegExp(r'/$'), '');
        return base.isEmpty ? '' : '$base${_tipo.pathStream}';
      }
      final ip = _cIp.text.trim();
      final p  = _cPuerto.text.trim();
      return ip.isEmpty ? '' : 'http://$ip:$p${_tipo.pathStream}';
    } catch (_) {
      return '';
    }
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
                      // [CAM-1] Autoseleccionar categoría y puerto según tipo
                      if (t == TipoD.camara) {
                        _cPuerto.text = '8888';
                        _cat = CatArtefacto.camara;
                      } else if (t == TipoD.celular) {
                        _cPuerto.text = '8888';
                      } else if (_modo != ModoConexion.url) {
                        _cPuerto.text = '80';
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
                    if (m != ModoConexion.url &&
                        (_tipo == TipoD.celular ||
                         _tipo == TipoD.camara)) {
                      _cPuerto.text = '8888';
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
                    if (v == null || v.trim().isEmpty)
                      return 'URL requerida';
                    if (!v.trim().startsWith('http'))
                      return 'Debe empezar con http o https';
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
                        _tipo == TipoD.camara || _tipo == TipoD.celular
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
                    if (v == null || v.trim().isEmpty)
                      return 'IP requerida';
                    if (v.trim() == '0.0.0.0')
                      return 'IP inválida';
                    if (v.trim() == 'localhost' ||
                        v.trim() == '127.0.0.1')
                      return 'No uses localhost';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const _Lbl('Puerto'),
                TextFormField(
                  controller: _cPuerto,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: C.t1),
                  decoration: InputDecoration(
                      hintText:
                          (_tipo == TipoD.celular ||
                           _tipo == TipoD.camara)
                              ? '8888'
                              : '80'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Requerido';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1 || n > 65535)
                      return 'Puerto inválido (1-65535)';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Preview URL principal
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
                    // [CAM-1] Mostrar URL del stream si es cámara
                    if (_tipo == TipoD.camara &&
                        _streamPreview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Row(children: [
                        Icon(Icons.videocam_rounded,
                            size: 12, color: C.cyan),
                        SizedBox(width: 6),
                        Text('URL del stream MJPEG:',
                            style: TextStyle(
                                fontSize:   10,
                                fontWeight: FontWeight.w600,
                                color:      C.cyan)),
                      ]),
                      const SizedBox(height: 4),
                      Text(_streamPreview,
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
      puerto:  int.tryParse(_cPuerto.text.trim()) ?? 8888,
      urlBase: _cUrl.text.trim(),
    );
    if (mounted) setState(() {
      _pinging = false;
      _pingOk  = ok;
    });
  }

  Future<void> _doSave() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);

    if (_isEdit) {
      widget.notifier.editar(
        id:         widget.edit!.id,
        nombre:     _cNombre.text,
        tipo:       _tipo,
        cat:        _cat,
        modo:       _modo,
        ip:         _cIp.text,
        puerto:     int.tryParse(_cPuerto.text.trim()) ?? 8888,
        urlBase:    _cUrl.text,
        habitacion: _cHab.text,
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
        puerto:     int.tryParse(_cPuerto.text.trim()) ?? 8888,
        urlBase:    _cUrl.text,
        habitacion: _cHab.text,
        skipPing:   true,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (ok) {
          Navigator.pop(context);
          snack(context, 'Cámara agregada ✓');
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
      builder: (_, __) {
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
    if (d.tipo.esCamara) {
      _log('Stream MJPEG: ${d.urlStream}', null);
    }
    if (demo) {
      _log('⚠ Modo DEMO activo — simulando respuestas', null);
    }
    _log('─────────────────────────────', null);
    _log('URL ON:  ${d.urlOn}', null);
    _log('URL OFF: ${d.urlOff}', null);
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
            .get(Uri.parse(baseUrl))
            .timeout(AppConfig.pingTimeout);
        _log('  GET $baseUrl → HTTP ${resp.statusCode}',
            resp.statusCode < 400);
        if (resp.statusCode >= 400) {
          _log('  → Verifica IP/URL y conexión de red', false);
        } else {
          _log('  Host alcanzable ✓', true);
        }
      } on TimeoutException {
        _log(
          '  TIMEOUT — sin respuesta en ${AppConfig.pingTimeout.inSeconds}s',
          false,
        );
        _log(
            '  → Verifica IP/URL y que estés en la misma red',
            false);
      } catch (e) {
        _log('  ERROR: $e', false);
        _log('  → Verifica IP/URL y conexión de red', false);
      }
    }

    _log('─────────────────────────────', null);

    // Probar paths ON
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
              .get(Uri.parse(url))
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

    _log('─────────────────────────────', null);

    // [CAM-1] Si es cámara, probar también el stream
    if (d.tipo.esCamara) {
      _log('▶ Verificando endpoint de stream MJPEG...', null);
      if (demo) {
        await Future.delayed(const Duration(milliseconds: 300));
        _log('  [DEMO] ${d.urlStream} → OK ✓', true);
      } else {
        try {
          final client  = http.Client();
          final request = http.Request('GET', Uri.parse(d.urlStream));
          final resp    = await client
              .send(request)
              .timeout(AppConfig.pingTimeout);
          final ok = resp.statusCode >= 200 && resp.statusCode < 300;
          _log(
            '  GET ${d.urlStream} → HTTP ${resp.statusCode} ${ok ? "✓ Stream disponible" : "— no disponible"}',
            ok,
          );
          client.close();
          if (ok) {
            _log('  Content-Type: ${resp.headers["content-type"] ?? "desconocido"}', null);
          }
        } on TimeoutException {
          _log('  → TIMEOUT al conectar al stream', false);
        } catch (e) {
          _log('  → ERROR: $e', false);
        }
      }
      _log('─────────────────────────────', null);
    }

    _log('✓ Diagnóstico completo — relay NO fue activado', true);
    setState(() => _running = false);
  }

  void _log(String msg, bool? ok) =>
      setState(() => _logs.add(_DiagLog(msg, ok)));

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
                if (l.ok == true)  col = C.green;
                if (l.ok == false) col = C.red;
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
// WIDGETS REUTILIZABLES
// ════════════════════════════════════════════════════════════════
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
  const _DeleteDialog(
      {required this.nombre, required this.onConfirm});

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: C.card,
        shape: const RoundedRectangleBorder(borderRadius: R.md),
        title: const Text('Eliminar dispositivo',
            style: TextStyle(color: C.t1, fontSize: 16)),
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
