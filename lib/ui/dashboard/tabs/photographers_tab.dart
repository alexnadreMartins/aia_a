import 'package:flutter/material.dart';
import '../../../logic/firestore_service.dart';

class PhotographersTab extends StatefulWidget {
  const PhotographersTab({super.key});

  @override
  State<PhotographersTab> createState() => _PhotographersTabState();
}

class _PhotographersTabState extends State<PhotographersTab> {
  Map<String, String> _mappings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMappings();
  }

  Future<void> _loadMappings() async {
    setState(() => _isLoading = true);
    final map = await FirestoreService().getPhotographerMappings();
    setState(() {
      _mappings = map;
      _isLoading = false;
    });
  }

  void _showEditDialog([String? initialSerial, String? initialName]) {
    final serialCtrl = TextEditingController(text: initialSerial);
    final nameCtrl = TextEditingController(text: initialName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mapear Câmera -> Fotógrafo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             const Text("Associe um Serial ou Modelo de câmera (ex: 'Canon EOS 5D_123456') ao nome do fotógrafo correto."),
             const SizedBox(height: 16),
             TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: "Serial / Chave da Câmera"), enabled: initialSerial == null),
             TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome do Fotógrafo")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
               if (serialCtrl.text.isNotEmpty && nameCtrl.text.isNotEmpty) {
                  await FirestoreService().saveMapping(serialCtrl.text.trim(), nameCtrl.text.trim());
                  if (mounted) Navigator.pop(ctx);
                  _loadMappings();
               }
            },
            child: const Text("Salvar"),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final entries = _mappings.entries.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: entries.isEmpty 
          ? const Center(child: Text("Nenhum mapeamento cadastrado.", style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  color: Colors.white10,
                  child: ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.orangeAccent),
                    title: Text("Câmera: ${entry.key}", style: const TextStyle(color: Colors.white)),
                    subtitle: Text("Fotógrafo: ${entry.value}", style: const TextStyle(color: Colors.white70)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54),
                      onPressed: () => _showEditDialog(entry.key, entry.value),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
