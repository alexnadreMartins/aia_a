import 'package:flutter/material.dart';
import '../../../logic/firestore_service.dart';

class PhotographerDetailsDialog extends StatefulWidget {
  final String photographerName;
  final int totalPhotos;
  final List<Map<String, dynamic>> projects; // List of {projectName, contract, photosUsed, events: [], score}

  const PhotographerDetailsDialog({
    super.key,
    required this.photographerName,
    required this.totalPhotos,
    required this.projects,
  });

  @override
  State<PhotographerDetailsDialog> createState() => _PhotographerDetailsDialogState();
}

class _PhotographerDetailsDialogState extends State<PhotographerDetailsDialog> {
  bool _isEditing = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.photographerName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveMapping() async {
      final newName = _nameController.text.trim();
      if (newName.isEmpty || newName == widget.photographerName) {
         setState(() => _isEditing = false);
         return;
      }
      
      // Infer Serial
      String serial = widget.photographerName;
      if (serial.startsWith("Serial: ")) {
          serial = serial.replaceAll("Serial: ", "").trim();
      } else if (serial.startsWith("Model_")) {
          // Keep as is, it's a model-based serial
      } else {
          // Strategy: Try to find keys for this value?
          try {
            final mappings = await FirestoreService().getPhotographerMappings();
            final keys = mappings.entries.where((e) => e.value == widget.photographerName).map((e) => e.key).toList();
            
            if (keys.isNotEmpty) {
               // Update ALL keys
               for (var k in keys) {
                  await FirestoreService().saveMapping(k, newName);
               }
               if (mounted) Navigator.pop(context, true);
               return;
            }
          } catch (e) {
             debugPrint("Error resolving mapping: $e");
          }
      }

      await FirestoreService().saveMapping(serial, newName);
      if (mounted) Navigator.pop(context, true);
  }

  Color _getScoreColor(double? score) {
    if (score == null) return Colors.grey;
    if (score >= 9.0) return Colors.green;
    if (score >= 7.0) return Colors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate global score
    double totalScore = 0;
    if (widget.projects.isNotEmpty) {
       totalScore = widget.projects.fold(0.0, (sum, p) => sum + (p['score'] as double? ?? 0)) / widget.projects.length;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.camera_alt, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Expanded(
            child: _isEditing 
             ? TextField(
                 controller: _nameController, 
                 autofocus: true,
                 decoration: const InputDecoration(hintText: "Nome do Fotógrafo"),
                 onSubmitted: (_) => _saveMapping(),
               )
             : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.photographerName),
                  Text("Total: ${widget.totalPhotos} fotos | Nota Geral: ${totalScore.toStringAsFixed(1)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
          ),
          IconButton(
             icon: Icon(_isEditing ? Icons.check : Icons.edit, color: _isEditing ? Colors.green : Colors.grey),
             onPressed: () {
                if (_isEditing) {
                   _saveMapping();
                } else {
                   setState(() => _isEditing = true);
                }
             },
          )
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            // Header Row
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black12,
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text("Projeto / Contrato", style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("Fotos", style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text("Eventos", style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text("Nota", style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 5),
            
            // List
            Expanded(
              child: ListView.separated(
                itemCount: widget.projects.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final p = widget.projects[index];
                  final events = (p['events'] as List?)?.join(", ") ?? "-";
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3, 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['projectName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(p['contract'] ?? '-', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          )
                        ),
                        Expanded(flex: 1, child: Text("${p['photosUsed']}")),
                        Expanded(flex: 2, child: Text(events, style: const TextStyle(fontSize: 12))),
                        Expanded(
                          flex: 1, 
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getScoreColor(p['score']),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (p['score'] as double).toStringAsFixed(1), 
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          )
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
         TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Fechar"))
      ],
    );
  }
}
