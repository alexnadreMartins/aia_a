import 'package:flutter/material.dart';

class ProjectDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> projectData;

  const ProjectDetailsDialog({super.key, required this.projectData});

  @override
  Widget build(BuildContext context) {
    final name = projectData['name'] ?? 'Sem Nome';
    final contract = projectData['contractNumber'] ?? '-';
    final company = projectData['company'] ?? 'Unknown';
    final totalPhotos = projectData['totalPhotosUsed'] ?? 0;
    
    // Parse Photographer Stats
    final statsMap = projectData['photographerStats'] as Map<String, dynamic>? ?? {};
    final photographers = statsMap.entries.toList();
    // Sort by count desc
    photographers.sort((a, b) {
       final cA = a.value['totalUsed'] as int? ?? 0;
       final cB = b.value['totalUsed'] as int? ?? 0;
       return cB.compareTo(cA);
    });

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Contrato: $contract | Empresa: $company", style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            const Divider(),
            const SizedBox(height: 10),
            const Text("Produção por Fotógrafo", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: photographers.isEmpty 
              ? const Center(child: Text("Sem dados detalhados.", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  itemCount: photographers.length,
                  itemBuilder: (ctx, index) {
                     final entry = photographers[index];
                     final pName = entry.key;
                     final data = entry.value as Map<String, dynamic>;
                     final count = data['totalUsed'] ?? 0;
                     final eventsOp = data['events'] as List?;
                     final events = eventsOp?.join(", ") ?? "";
                     
                     return ListTile(
                       leading: CircleAvatar(
                         backgroundColor: Colors.blueGrey,
                         radius: 12,
                         child: Text("${index+1}", style: const TextStyle(fontSize: 10, color: Colors.white)),
                       ),
                       title: Text(pName, style: const TextStyle(fontWeight: FontWeight.w500)),
                       subtitle: events.isNotEmpty ? Text("Eventos: $events", style: const TextStyle(fontSize: 10, color: Colors.white54)) : null,
                       trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text("$count Fotos", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                       ),
                     );
                  },
                ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar"))
      ],
    );
  }
}
