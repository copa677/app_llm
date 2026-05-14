import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_llama/flutter_llama.dart';

class LlmService {
  final FlutterLlama _llama = FlutterLlama.instance;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final _responseController = StreamController<String>.broadcast();
  Stream<String> get responseStream => _responseController.stream;

  // Ruta del modelo
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
        nThreads: 4, // Ajustado para móviles
        nGpuLayers: 0, // Por defecto 0 para evitar fallos en dispositivos sin GPU compatible
        contextSize: 2048,
        batchSize: 512,
        useGpu: false, // Por defecto false para mayor compatibilidad inicial
        verbose: false,
      );

      final success = await _llama.loadModel(config);

      if (success) {
        // Delay de seguridad para que los canales de eventos se estabilicen
        await Future.delayed(const Duration(milliseconds: 500));
        _isLoaded = true;
        return true;
      } else {
        print("❌ Error: No se pudo cargar el modelo con flutter_llama");
        return false;
      }
    } catch (e) {
      print("❌ Error cargando Llama: $e");
      return false;
    }
  }

  // System Prompt extraído de tus configuraciones
  String _buildSystemPrompt() {
    return (
        "Eres un asistente experto en APIs. Tu tarea es convertir instrucciones de usuario en lenguaje natural "
        "a una LISTA de objetos JSON para un sistema de gestión.\n\n"
        "Reglas:\n"
        "1. Identifica todas las acciones solicitadas por el usuario.\n"
        "2. Para cada acción, identifica el módulo, operación, método y endpoint correctos.\n"
        "3. Devuelve SIEMPRE una lista [{}, {}] incluso si solo hay una acción.\n"
        "4. NO agregues explicaciones, solo devuelve el array JSON.\n\n"
        "Ejemplo:\n"
        "Usuario: 'Crea el usuario Pepe y luego lista el inventario'\n"
        "Respuesta: [{\"module\": \"usuarios\", \"operation\": \"crear\", \"method\": \"POST\", \"endpoint\": \"/usuario/crear\", \"data\": {\"nombre\": \"Pepe\"}}, {\"module\": \"inventario\", \"operation\": \"listar\", \"method\": \"GET\", \"endpoint\": \"/inventario/listar\", \"data\": {}}]"
    );
  }

  Future<void> generateResponse(String prompt) async {
    if (!_isLoaded) {
      _responseController.add("Error: Modelo no cargado.");
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      // Construimos el prompt complejo con el prefijo forzado "["
      final systemPrompt = _buildSystemPrompt();
      final fullPrompt = "<|im_start|>system\n$systemPrompt<|im_end|>\n<|im_start|>user\n$prompt<|im_end|>\n<|im_start|>assistant\n[";
      
      print("🧠 IA procesando comando: $prompt");

      final params = GenerationParams(
        prompt: fullPrompt,
        temperature: 0.2, // Temperatura baja para mayor precisión en JSON
        topP: 0.9,
        maxTokens: 1024,
      );

      String fullResponse = "["; // Empezamos con el prefijo que ya le dimos
      
      await for (final token in _llama.generateStream(params)) {
        if (token.isNotEmpty) {
          fullResponse += token;
          // Mostramos el progreso técnico en el chat si quieres, 
          // pero por ahora lo guardamos para procesarlo al final.
          _responseController.add(token); 
        }
      }

      print("🏁 Respuesta completa recibida: $fullResponse");
      
      // Simulación de procesamiento de tareas
      await _simulateTaskExecution(fullResponse);

    } catch (e) {
      print("❌ Error en generación: $e");
      _responseController.add("\nError: $e");
    }
  }

  // Función para simular el procesamiento de los JSONs
  Future<void> _simulateTaskExecution(String jsonResponse) async {
    try {
      // Intentamos limpiar la respuesta por si la IA agregó algo fuera de los corchetes
      final startIndex = jsonResponse.indexOf('[');
      final endIndex = jsonResponse.lastIndexOf(']') + 1;
      final cleanJson = jsonResponse.substring(startIndex, endIndex);
      
      // Parseamos y formateamos el JSON para que se vea "bonito"
      final dynamic parsedJson = json.decode(cleanJson);
      final encoder = const JsonEncoder.withIndent('  ');
      final prettyJson = encoder.convert(parsedJson);

      _responseController.add("\n\n📦 **Estructura de Tareas Identificada:**\n```json\n$prettyJson\n```\n");
      
      _responseController.add("\n⚙️ **Procesando tareas detectadas...**\n");
      await Future.delayed(const Duration(seconds: 1));

      _responseController.add("✅ Simulación: Acciones registradas con éxito.\n");
      _responseController.add("📡 *Backend: Serverlest_Topicos listo para integración.*");
      
    } catch (e) {
      print("⚠️ No se pudo formatear el JSON: $e");
    }
  }

  void dispose() {
    _llama.unloadModel();
    _responseController.close();
    _isLoaded = false;
  }
}