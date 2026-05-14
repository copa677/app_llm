import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_llama/flutter_llama.dart';

class LlmService {
  final FlutterLlama _llama = FlutterLlama.instance;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final _responseController = StreamController<String>.broadcast();
  Stream<String> get responseStream => _responseController.stream;

  // URL del API Gateway
  static const String _baseUrl = "https://serverlest-topicos-gateway-8zoia048.uc.gateway.dev";
  
  static const String modelPath = "/storage/emulated/0/Models/qwen2.5-3b-instruct-q4_0.gguf";

  Future<bool> initModel() async {
    if (_isLoaded) return true;

    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        print("❌ ERROR: El archivo no existe en $modelPath");
        return false;
      }

      print("✅ Cargando modelo: $modelPath (${await file.length()} bytes)");

      final config = LlamaConfig(
        modelPath: modelPath,
        nThreads: 4,
        nGpuLayers: 0,
        contextSize: 2048,
        batchSize: 512,
        useGpu: false,
        verbose: false,
      );

      final success = await _llama.loadModel(config);
      _isLoaded = success;
      return success;
    } catch (e) {
      print("❌ Error cargando modelo: $e");
      return false;
    }
  }

  String _buildSystemPrompt() {
    return (
        "Eres un asistente experto en APIs. Tu tarea es convertir instrucciones de usuario en lenguaje natural "
        "a una LISTA de objetos JSON para un sistema de gestión.\n\n"
        "CATÁLOGO DE MÓDULOS Y ENDPOINTS (USA SOLO ESTOS):\n"
        "- Módulo 'usuarios': Endpoints [/usuario/listar, /usuario/crear, /usuario/actualizar, /usuario/obtener/{id}]\n"
        "- Módulo 'inventario' (Para productos/stock): Endpoints [/inventario/listar, /inventario/crear, /inventario/aumentar_stock, /inventario/disminuir_stock, /inventario/obtener/{id}]\n"
        "- Módulo 'ventas': Endpoints [/venta/crear, /venta/crear_detalle_venta, /venta/anular_detalle_venta]\n"
        "- Módulo 'compras': Endpoints [/compra/crear, /detalle_compra/crear, /compra/listar/{id}]\n\n"
        "REGLAS DE ORO:\n"
        "1. Si el usuario pide 'productos', USA EL MÓDULO 'inventario'.\n"
        "2. Campos de usuario: USA 'email' y 'password'.\n"
        "3. Devuelve SIEMPRE una lista [{}, {}].\n"
        "4. NO agregues texto extra.\n\n"
        "Ejemplo:\n"
        "Usuario: 'Lista los productos'\n"
        "Respuesta: [{\"module\": \"inventario\", \"operation\": \"listar\", \"method\": \"GET\", \"endpoint\": \"/inventario/listar\", \"data\": {}}]"
    );
  }

  Future<void> generateResponse(String prompt) async {
    if (!_isLoaded) {
      _responseController.add("Error: Modelo no cargado.");
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      final systemPrompt = _buildSystemPrompt();
      final fullPrompt = "<|im_start|>system\n$systemPrompt<|im_end|>\n<|im_start|>user\n$prompt<|im_end|>\n<|im_start|>assistant\n[";
      
      print("🧠 IA procesando comando: $prompt");

      final params = GenerationParams(
        prompt: fullPrompt,
        temperature: 0.1, // Muy baja para máxima fidelidad JSON
        topP: 0.9,
        maxTokens: 1024,
      );

      String fullResponse = "[";
      
      await for (final token in _llama.generateStream(params)) {
        if (token.isNotEmpty) {
          fullResponse += token;
          _responseController.add(token); 
        }
      }

      print("🏁 Respuesta completa recibida. Procesando tareas reales...");
      
      // Ejecución real de tareas contra el Backend
      await _executeRealTasks(fullResponse);

    } catch (e) {
      print("❌ Error en generación: $e");
      _responseController.add("\nError: $e");
    }
  }

  Future<void> _executeRealTasks(String jsonResponse) async {
    try {
      final startIndex = jsonResponse.indexOf('[');
      final endIndex = jsonResponse.lastIndexOf(']') + 1;
      final cleanJson = jsonResponse.substring(startIndex, endIndex);
      
      final List<dynamic> tasks = json.decode(cleanJson);
      
      _responseController.add("\n\n⚙️ **Ejecutando tareas en el servidor...**\n");

      for (var task in tasks) {
        final String module = task['module'] ?? 'desconocido';
        final String operation = task['operation'] ?? 'acción';
        final String method = task['method'] ?? 'GET';
        final String endpoint = task['endpoint'] ?? '';
        final Map<String, dynamic> data = Map<String, dynamic>.from(task['data'] ?? {});

        _responseController.add("\n⏳ Procesando $operation en $module...");

        try {
          final response = await _performHttpRequest(method, endpoint, data);
          
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final dynamic decodedResponse = json.decode(response.body);
            final prettyData = const JsonEncoder.withIndent('  ').convert(decodedResponse);
            
            _responseController.add("\n✅ **Éxito:** $operation completado.");
            _responseController.add("\n```json\n$prettyData\n```\n");
          } else {
            _responseController.add("\n❌ **Error (${response.statusCode}):** No se pudo completar $operation.");
            _responseController.add("\n`Detalle: ${response.body}`\n");
          }
        } catch (e) {
          _responseController.add("\n❌ **Fallo de conexión:** $e");
        }
      }

      _responseController.add("\n🏁 **Todas las tareas procesadas.**");
      
    } catch (e) {
      print("⚠️ Error procesando la lista de tareas: $e");
      _responseController.add("\n⚠️ Hubo un error al interpretar las tareas de la IA.");
    }
  }

  Future<http.Response> _performHttpRequest(String method, String endpoint, Map<String, dynamic> data) async {
    final url = Uri.parse("$_baseUrl$endpoint");
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode(data);

    switch (method.toUpperCase()) {
      case 'POST':
        return await http.post(url, headers: headers, body: body);
      case 'PUT':
        return await http.put(url, headers: headers, body: body);
      case 'DELETE':
        return await http.delete(url, headers: headers, body: body);
      case 'GET':
      default:
        var getUrl = url;
        if (data.isNotEmpty && method.toUpperCase() == 'GET') {
          getUrl = url.replace(queryParameters: data.map((k, v) => MapEntry(k, v.toString())));
        }
        return await http.get(getUrl, headers: headers);
    }
  }

  void dispose() {
    _llama.unloadModel();
    _responseController.close();
    _isLoaded = false;
  }
}