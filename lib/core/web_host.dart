import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Hosted mode: a small web server on the host device. It serves the web
/// client (the app built for the browser, packaged as
/// assets/webclient/webclient.zip by tool/build_webclient.sh) and upgrades
/// `/ws` to a WebSocket that joins the game like an app player.
class WebClientServer {
  final HttpServer _server;
  final Map<String, List<int>> _files;
  final List<String> urls;

  WebClientServer._(this._server, this._files, this.urls);

  static const _zipAsset = 'assets/webclient/webclient.zip';

  static Future<WebClientServer> start({
    required int port,
    required void Function(WebSocket ws) onSocket,
  }) async {
    final zipBytes = (await rootBundle.load(_zipAsset)).buffer.asUint8List();
    final files = <String, List<int>>{};
    for (final f in ZipDecoder().decodeBytes(zipBytes)) {
      if (f.isFile) files[f.name] = f.content as List<int>;
    }
    if (!files.containsKey('index.html')) {
      throw StateError('web client zip has no index.html');
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final web = WebClientServer._(server, files, await _localUrls(port));
    server.listen((req) async {
      try {
        if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
          onSocket(await WebSocketTransformer.upgrade(req));
        } else {
          web._serveFile(req);
        }
      } catch (_) {
        try { await req.response.close(); } catch (_) {}
      }
    }, onError: (_) {});
    return web;
  }

  void _serveFile(HttpRequest req) {
    var path = Uri.decodeComponent(req.uri.path);
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty) path = 'index.html';
    final bytes = _files[path];
    final res = req.response;
    if (bytes == null || path.contains('..')) {
      res.statusCode = HttpStatus.notFound;
      res.close();
      return;
    }
    res.headers.contentType = _contentType(path);
    // index.html must never be cached (new build = new client)
    res.headers.set(HttpHeaders.cacheControlHeader,
        path == 'index.html' ? 'no-cache' : 'max-age=3600');
    res.add(bytes);
    res.close();
  }

  static ContentType _contentType(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'html': return ContentType.html;
      case 'js':   return ContentType('application', 'javascript', charset: 'utf-8');
      case 'mjs':  return ContentType('application', 'javascript', charset: 'utf-8');
      case 'json': return ContentType.json;
      case 'wasm': return ContentType('application', 'wasm');
      case 'png':  return ContentType('image', 'png');
      case 'ico':  return ContentType('image', 'x-icon');
      case 'otf':  return ContentType('font', 'otf');
      case 'ttf':  return ContentType('font', 'ttf');
      case 'ogg':  return ContentType('audio', 'ogg');
      case 'css':  return ContentType('text', 'css', charset: 'utf-8');
      default:     return ContentType.binary;
    }
  }

  /// Local IPv4 addresses (WiFi / hotspot) browsers on the same network can use.
  static Future<List<String>> _localUrls(int port) async {
    final out = <String>[];
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          final private = ip.startsWith('192.168.') || ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (!a.isLoopback && private) out.add('http://$ip:$port');
        }
      }
    } catch (_) {}
    // Home WiFi / Android hotspot (192.168.x) first; VPN-style ranges last
    int rank(String u) => u.contains('//192.168.') ? 0 : u.contains('//10.') ? 1 : 2;
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  Future<void> stop() => _server.close(force: true);
}
