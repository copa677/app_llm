import 'package:flutter/material.dart';

// Modelo para manejar los mensajes
class ChatMessage {
  final String text;
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
  final List<ChatMessage> _messages = [
    ChatMessage(text: "Hola, soy Gemma. ¿En qué puedo ayudarte hoy?", isUser: false),
  ];

  void _handleSend() {
    if (_controller.text.trim().isEmpty) return;
    
    setState(() {
      // Añadimos el mensaje del usuario
      _messages.add(ChatMessage(text: _controller.text, isUser: true));
      
      // Simulamos respuesta de la IA (esto lo conectaremos después al modelo real)
      _messages.add(ChatMessage(text: "Recibido. Estoy procesando tu consulta...", isUser: false));
      
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gemma AI Chat"),
        centerTitle: true,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Lista de mensajes con Scroll
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

          // Input de texto
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
        child: Text(
          message.text,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Escribe un mensaje...",
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
            onPressed: _handleSend,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
