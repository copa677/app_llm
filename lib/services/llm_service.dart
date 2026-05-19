import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
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
        contextSize: 8192,
        batchSize: 8192,
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

  String? _extractActionJson(String response) {
    try {
      final actionIndex = response.indexOf('Acción:');
      if (actionIndex == -1) return null;
      
      final jsonStart = response.indexOf('{', actionIndex);
      if (jsonStart == -1) return null;
      
      int bracketCount = 0;
      int jsonEnd = -1;
      for (int i = jsonStart; i < response.length; i++) {
        if (response[i] == '{') bracketCount++;
        if (response[i] == '}') {
          bracketCount--;
          if (bracketCount == 0) {
            jsonEnd = i;
            break;
          }
        }
      }
      
      if (jsonEnd != -1) {
        return response.substring(jsonStart, jsonEnd + 1);
      }
    } catch (e) {
      print("❌ Error extrayendo JSON de acción: $e");
    }
    return null;
  }

  Future<List<Map<String, String>>> _parseOpenApi() async {
    try {
      final String yamlText = await rootBundle.loadString('lib/assets/openapi.yaml');
      final List<Map<String, String>> endpoints = [];
      final lines = yamlText.split('\n');
      
      String? currentPath;
      String? currentMethod;
      String? currentSummary;
      List<String> currentBlock = [];
      
      for (var line in lines) {
        final trimmed = line.trim();
        if (line.startsWith('  /') && line.endsWith(':')) {
          if (currentPath != null && currentMethod != null && currentBlock.isNotEmpty) {
            endpoints.add({
              'path': currentPath,
              'method': currentMethod,
              'summary': currentSummary ?? '',
              'yaml': currentBlock.join('\n'),
            });
          }
          currentPath = line.substring(2, line.length - 1).trim();
          currentMethod = null;
          currentSummary = null;
          currentBlock = [line];
        } else if (currentPath != null) {
          currentBlock.add(line);
          if (line.startsWith('    get:') || line.startsWith('    post:') || line.startsWith('    put:') || line.startsWith('    delete:')) {
            currentMethod = trimmed.substring(0, trimmed.length - 1).toUpperCase();
          } else if (trimmed.startsWith('summary:')) {
            currentSummary = trimmed.substring(8).trim();
          }
        }
      }
      
      if (currentPath != null && currentMethod != null && currentBlock.isNotEmpty) {
        endpoints.add({
          'path': currentPath,
          'method': currentMethod,
          'summary': currentSummary ?? '',
          'yaml': currentBlock.join('\n'),
        });
      }
      
      return endpoints;
    } catch (e) {
      print("❌ Error parseando openapi.yaml: $e");
      return [];
    }
  }

  Future<String> _getFilteredEndpointsAsYaml(String query) async {
    final endpoints = await _parseOpenApi();
    final lowerQuery = query.toLowerCase();
    
    bool matchUsuarios = lowerQuery.contains('usu') || lowerQuery.contains('user');
    bool matchInventario = lowerQuery.contains('prod') || lowerQuery.contains('stock') || lowerQuery.contains('inven') || lowerQuery.contains('articulo');
    bool matchVentas = lowerQuery.contains('vent') || lowerQuery.contains('clien');
    bool matchCompras = lowerQuery.contains('compr') || lowerQuery.contains('prove') || lowerQuery.contains('insum');
    
    // Si no coincide con ninguna palabra clave de operaciones, no inyectamos endpoints (evita saturar el contexto)
    bool matchAll = false;
    
    final List<String> filteredYamlBlocks = [];
    
    for (var endpoint in endpoints) {
      final path = endpoint['path'] ?? '';
      bool isMatched = false;
      
      if (matchAll) {
        isMatched = true;
      } else {
        if (matchUsuarios && path.contains('/usuario')) isMatched = true;
        if (matchInventario && path.contains('/inventario')) isMatched = true;
        if (matchVentas && path.contains('/venta')) isMatched = true;
        if (matchCompras && (path.contains('/compra') || path.contains('/detalle_compra'))) isMatched = true;
      }
      
      if (isMatched) {
        filteredYamlBlocks.add(endpoint['yaml'] ?? '');
      }
    }
    
    return filteredYamlBlocks.join('\n\n');
  }

  String _buildReActSystemPrompt(String filteredEndpointsYaml) {
    return (
      "Eres un agente inteligente experto en APIs y bases de datos.\n"
      "Tu tarea es ayudar al usuario resolviendo sus peticiones usando exclusivamente los endpoints de la API descritos abajo.\n\n"
      "ENDPOINTS DISPONIBLES (YAML):\n"
      "$filteredEndpointsYaml\n\n"
      "Sigue estrictamente el patrón ReAct (Reasoning and Acting). Por cada turno, tu respuesta debe consistir de una de las dos opciones de formato:\n\n"
      "OPCIÓN 1 (Si necesitas ejecutar una llamada a la API):\n"
      "Pensamiento: [Tu razonamiento del paso actual y por qué necesitas ejecutar la acción]\n"
      "Acción: {\"method\": \"MÉTODO_HTTP\", \"endpoint\": \"/ruta\", \"data\": { ... datos en JSON ... }}\n\n"
      "OPCIÓN 2 (Si ya terminaste o no requieres más acciones):\n"
      "Pensamiento: [Tu razonamiento final]\n"
      "Respuesta Final: [Tu respuesta descriptiva y explicada al usuario con los resultados obtenidos]\n\n"
      "REGLAS CRÍTICAS:\n"
      "1. Genera una sola 'Acción' por paso. Al generarla, detente inmediatamente escribiendo la palabra 'Observación:'. El sistema la ejecutará y te dará una 'Observación:'. No inventes la 'Observación:'.\n"
      "2. Respeta estrictamente los nombres de parámetros de la especificación YAML entregada (por ejemplo, en /inventario/disminuir_stock se usa 'producto_id', pero en /inventario/aumentar_stock se usa 'id').\n"
      "3. Si un endpoint requiere un parámetro en el path (como {id}), reemplaza '{id}' en el endpoint de la Acción con el número real (por ejemplo: /usuario/obtener/3).\n"
      "4. Sé preciso y cauteloso. Si un ID es desconocido, puedes listar primero para buscarlo antes de proceder."
    );
  }

  Future<void> generateResponse(String prompt) async {
    if (!_isLoaded) {
      _responseController.add("Error: Modelo no cargado.");
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      print("🔍 RAG: Cargando y filtrando endpoints...");
      final filteredEndpointsText = await _getFilteredEndpointsAsYaml(prompt);

      final systemPrompt = _buildReActSystemPrompt(filteredEndpointsText);
      
      // Construimos el historial conversacional inicial para el bucle ReAct
      String conversationHistory = "<|im_start|>system\n$systemPrompt<|im_end|>\n<|im_start|>user\n$prompt<|im_end|>\n<|im_start|>assistant\n";
      
      bool finished = false;
      int maxSteps = 5;
      int step = 0;

      _responseController.add("\n⚙️ **Iniciando asistente de consulta (Qwen)...**\n");

      while (!finished && step < maxSteps) {
        step++;
        print("🧠 ReAct Paso $step...");
        _responseController.add("\n⚙️ **Procesando consulta (Paso $step)...**\n");

        final params = GenerationParams(
          prompt: conversationHistory,
          temperature: 0.1, // Muy baja para evitar alucinaciones
          topP: 0.9,
          maxTokens: 512,
          stopSequences: const ["Observación:", "<|im_start|>", "<|im_end|>"],
        );

        String stepResponse = "";
        bool isStreamingFinalResponse = false;
        int finalResponseIndex = -1;
        
        await for (final token in _llama.generateStream(params)) {
          if (token.isNotEmpty) {
            stepResponse += token;
            
            if (!isStreamingFinalResponse) {
              finalResponseIndex = stepResponse.indexOf("Respuesta Final:");
              if (finalResponseIndex != -1) {
                isStreamingFinalResponse = true;
                final prefixLength = finalResponseIndex + "Respuesta Final:".length;
                if (stepResponse.length > prefixLength) {
                  _responseController.add(stepResponse.substring(prefixLength));
                }
              }
            } else {
              _responseController.add(token);
            }
          }
        }

        // Limpieza de cualquier stop sequence que se haya colado al final del texto acumulado
        int cutoffIndex = stepResponse.length;
        if (stepResponse.contains("Observación:")) {
          final idx = stepResponse.indexOf("Observación:");
          if (idx < cutoffIndex) cutoffIndex = idx;
        }
        if (stepResponse.contains("<|im_start|>")) {
          final idx = stepResponse.indexOf("<|im_start|>");
          if (idx < cutoffIndex) cutoffIndex = idx;
        }
        if (stepResponse.contains("<|im_end|>")) {
          final idx = stepResponse.indexOf("<|im_end|>");
          if (idx < cutoffIndex) cutoffIndex = idx;
        }
        
        final cleanStepResponse = stepResponse.substring(0, cutoffIndex);

        // Agregamos la respuesta generada limpia al historial
        conversationHistory += cleanStepResponse;

        if (cleanStepResponse.contains("Respuesta Final:")) {
          finished = true;
          print("🏁 ReAct completado con éxito.");
          break;
        } else if (stepResponse.contains("Acción:")) {
          final actionJsonStr = _extractActionJson(stepResponse);
          if (actionJsonStr != null) {
            try {
              final Map<String, dynamic> action = json.decode(actionJsonStr);
              final String method = action['method'] ?? 'GET';
              final String endpoint = action['endpoint'] ?? '';
              final Map<String, dynamic> data = Map<String, dynamic>.from(action['data'] ?? {});

              // Mostrar información amigable al usuario en lugar de JSON de la petición
              if (method.toUpperCase() == 'GET') {
                _responseController.add("\n🔌 **Consultando información al servidor...**\n");
              } else {
                _responseController.add("\n🔌 **Enviando datos al servidor...**\n");
                if (data.isNotEmpty) {
                  data.forEach((key, value) {
                    _responseController.add("🔹 **$key:** $value\n");
                  });
                }
              }

              final observation = await _executeAction(actionJsonStr);
              
              // Verificar si la respuesta del servidor es exitosa
              bool isSuccess = true;
              if (observation.toLowerCase().contains("fallo") || observation.toLowerCase().contains("error")) {
                isSuccess = false;
              } else {
                try {
                  final decoded = json.decode(observation);
                  if (decoded is Map && decoded['ok'] == false) {
                    isSuccess = false;
                  }
                } catch (_) {}
              }

              if (isSuccess) {
                _responseController.add("\n✅ **Petición HTTP realizada con éxito.**\n");
              } else {
                _responseController.add("\n❌ **Error al procesar la petición HTTP.**\n");
              }

              // Añadimos la observación para la siguiente ronda de pensamiento
              conversationHistory += "\nObservación: $observation\n<|im_start|>assistant\n";
            } catch (e) {
              _responseController.add("\n❌ **Error al procesar los datos de la acción.**\n");
              finished = true;
            }
          } else {
            _responseController.add("\n⚠️ Error: La Acción generada no tiene un JSON estructurado válido.\n");
            finished = true;
          }
        } else {
          // Si no generó ni Acción ni Respuesta Final, asumimos fin por seguridad
          finished = true;
        }
      }

      if (step >= maxSteps) {
        _responseController.add("\n⚠️ Se alcanzó el número máximo de pasos de razonamiento.");
      }

    } catch (e) {
      print("❌ Error en generación ReAct: $e");
      _responseController.add("\nError en bucle de razonamiento: $e");
    }
  }

  Future<String> _executeAction(String jsonStr) async {
    try {
      final Map<String, dynamic> action = json.decode(jsonStr);
      final String method = action['method'] ?? 'GET';
      final String endpoint = action['endpoint'] ?? '';
      final Map<String, dynamic> data = Map<String, dynamic>.from(action['data'] ?? {});

      final response = await _performHttpRequest(method, endpoint, data);
      
      final dynamic decodedResponse = json.decode(response.body);
      final prettyData = const JsonEncoder.withIndent('  ').convert(decodedResponse);
      return prettyData;
    } catch (e) {
      return "Fallo en ejecución: $e";
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