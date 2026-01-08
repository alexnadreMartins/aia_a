import 'package:flutter/material.dart';
import '../../logic/auto_diagramming_service.dart';

class DiagramProgressOverlay extends StatelessWidget {
  const DiagramProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DiagramProgress>(
      stream: AutoDiagrammingService().progressStream,
      initialData: DiagramProgress(),
      builder: (context, snapshot) {
        final state = snapshot.data!;
        if (state.status == DiagramStatus.idle || state.status == DiagramStatus.completed || state.status == DiagramStatus.cancelled) {
          // Typically we hide this overlay if idle, but maybe the parent widget controls the visibility?
          // We will assume the parent removes this widget if not needed, 
          // OR this widget returns SizedBox.shrink()
          if (state.status == DiagramStatus.idle) return const SizedBox.shrink();
        }

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF252525).withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Diagramação Automática", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  // Progress Bar (Total folders)
                  LinearProgressIndicator(
                    value: state.totalProgress,
                    backgroundColor: Colors.white10,
                    color: Colors.deepPurpleAccent,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 8),
                  
                  // Text Metrics
                  _buildMetricRow("Pasta Atual:", state.currentFolder),
                  _buildMetricRow("Pastas Encontradas:", "${state.totalCount}"),
                  _buildMetricRow("Processadas:", "${state.processedCount}"),
                  _buildMetricRow("Diagramadas:", "${state.totalPhotosDiagrammed} fotos"),
                  
                  const SizedBox(height: 20),
                  
                  // Status & Controls
                  if (state.status == DiagramStatus.paused)
                    Center(
                       child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                          child: const Text("PAUSADO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                       ),
                    ),
                    
                  if (state.status == DiagramStatus.completed)
                     const Center(child: Text("Processo Concluído!", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                  
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                       if (state.status != DiagramStatus.completed) ...[
                         TextButton(
                           onPressed: () => AutoDiagrammingService().cancel(),
                           child: const Text("Cancelar", style: TextStyle(color: Colors.redAccent)),
                         ),
                         const SizedBox(width: 8),
                         if (state.status == DiagramStatus.paused)
                             ElevatedButton.icon(
                                icon: const Icon(Icons.play_arrow),
                                label: const Text("Resume"),
                                onPressed: () => AutoDiagrammingService().resume(),
                             )
                         else
                             OutlinedButton.icon(
                                icon: const Icon(Icons.pause, size: 16),
                                label: const Text("Pausar"),
                                onPressed: () => AutoDiagrammingService().pause(),
                             ),
                       ] else 
                         ElevatedButton(
                            child: const Text("Fechar"),
                            onPressed: () {
                               // Close the overlay? Or trigger a callback?
                               // For now, setting status to idle hides it according to logic above?
                               // No, logic above hides if idle.
                               // We need a proper close.
                               // Actually service doesn't reset to idle automatically.
                               // Let's reset via Cancel/Close (logic reuse)
                               AutoDiagrammingService().cancel(); // Reset to idle/cancelled
                            }
                         )
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
