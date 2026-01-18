import 'package:flutter/material.dart';
import '../../models/event_config.dart';
import '../../logic/firestore_service.dart';

class EventConfigDialog extends StatefulWidget {
  const EventConfigDialog({super.key});

  @override
  State<EventConfigDialog> createState() => _EventConfigDialogState();
}

class _EventConfigDialogState extends State<EventConfigDialog> {
  late Map<int, TextEditingController> _controllers;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await FirestoreService().getEventConfig();
    setState(() {
      _controllers = {};
      // Ensure we have at least 1-15 slots for convenience
      for (int i = 1; i <= 15; i++) {
        _controllers[i] = TextEditingController(text: config.eventMap[i] ?? "");
      }
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    final map = <int, String>{};
    _controllers.forEach((key, controller) {
      if (controller.text.isNotEmpty) {
        map[key] = controller.text;
      }
    });

    await FirestoreService().saveEventConfig(EventConfig(eventMap: map));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Configuração de Prefixos de Eventos"),
      content: SizedBox(
        width: 400,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                   const Text(
                     "Associe o número (prefixo do arquivo: 1_IMG...) ao nome do evento.",
                     style: TextStyle(fontSize: 12, color: Colors.grey),
                   ),
                   const SizedBox(height: 10),
                   Expanded(
                     child: ListView.builder(
                       itemCount: 15,
                       itemBuilder: (context, index) {
                         final id = index + 1;
                         return Row(
                           children: [
                             SizedBox(
                               width: 40, 
                               child: Text("$id.", style: const TextStyle(fontWeight: FontWeight.bold))
                             ),
                             Expanded(
                               child: TextField(
                                 controller: _controllers[id],
                                 decoration: InputDecoration(
                                   hintText: "Ex: Foto Convite",
                                   isDense: true,
                                   contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                 ),
                               ),
                             ),
                           ],
                         );
                       },
                     ),
                   ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancelar")),
        ElevatedButton(onPressed: _save, child: const Text("Salvar")),
      ],
    );
  }
}
