import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/llm_service.dart';

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final LlmService _llmService = LlmService();
  final List<ChatMessage> _messages = [];
  
  bool _isInitializing = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _setupModel();
    _listenToResponses();
  }

  void _listenToResponses() {
    _llmService.responseStream.listen((token) {
      if (token.isEmpty) return;

      setState(() {
        int lastIndex = _messages.length - 1;
        if (lastIndex >= 0 && !_messages[lastIndex].isUser) {
          _messages[lastIndex].text += token;
        }
        
        // Si el token indica el fin o simplemente queremos dejar de generar
        // Nota: Algunas librerías envían un token vacío o específico al terminar
        if (token.contains("<end_of_turn>") || token.contains("</span>")) {
           _isGenerating = false;
        }
      });
    });
  }

  Future<void> _setupModel() async {
    // 1. Pedir permisos de almacenamiento
    var status = await Permission.manageExternalStorage.request();
    
    if (status.isGranted) {
      // 2. Inicializar el modelo
      bool success = await _llmService.initModel();
      if (success) {
        setState(() {
          _messages.add(ChatMessage(text: "¡Gemma está lista! ¿Qué quieres consultar?", isUser: false));
          _isInitializing = false;
        });
      } else {
        _showError("No se pudo cargar el modelo. Verifica que el archivo esté en la ruta correcta.");
      }
    } else {
      _showError("Se necesitan permisos de almacenamiento para cargar el modelo.");
    }
  }

  void _showError(String error) {
    setState(() {
      _messages.add(ChatMessage(text: "Error: $error", isUser: false));
      _isInitializing = false;
    });
  }

  Future<void> _handleSend() async {
    if (_controller.text.trim().isEmpty || _isGenerating) return;
    
    String userPrompt = _controller.text;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: userPrompt, isUser: true));
      // Añadimos la burbuja vacía para la respuesta de la IA
      _messages.add(ChatMessage(text: "", isUser: false));
      _isGenerating = true;
    });

    try {
      await _llmService.generateResponse(userPrompt);
    } catch (e) {
      setState(() {
        _messages.last.text = "Error: $e";
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  void dispose() {
    _llmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gemma AI Local"),
        centerTitle: true,
        actions: [
          if (_isInitializing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildChatBubble(message);
              },
            ),
          ),
          if (_isGenerating)
            const LinearProgressIndicator(minHeight: 2),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser 
              ? Theme.of(context).colorScheme.primary 
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
          ),
        ),
        child: SelectableText(
          message.text.isEmpty && !isUser ? "..." : message.text,
          style: TextStyle(
            color: isUser 
                ? Theme.of(context).colorScheme.onPrimary 
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_isInitializing && !_isGenerating,
              decoration: InputDecoration(
                hintText: _isInitializing ? "Cargando cerebro..." : "Escribe un mensaje...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: (_isInitializing || _isGenerating) ? null : _handleSend,
            icon: _isGenerating 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
