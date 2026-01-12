import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class RapidDiagrammingDialog extends StatefulWidget {
  final Function(String mode, String? batchPath) onStart;

  const RapidDiagrammingDialog({super.key, required this.onStart});

  @override
  State<RapidDiagrammingDialog> createState() => _RapidDiagrammingDialogState();
}

class _RapidDiagrammingDialogState extends State<RapidDiagrammingDialog> {
  String _mode = 'individual'; // individual, batch
  String? _selectedBatchPath;
  String? _customTemplatePath;
  bool _useAutoSelect = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: Text("Diagramação Rápida", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // MODE
              const Text("Modo de Operação:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildOption(
                 title: "Individual (Projeto Atual)",
                 subtitle: "Usa as fotos já carregadas neste projeto.",
                 value: "individual",
                 icon: Icons.photo_library
              ),
              const SizedBox(height: 8),
              _buildOption(
                 title: "Em Lote (Processar Pasta Pai)",
                 subtitle: "Processa subpastas criando um projeto por aluno.",
                 value: "batch",
                 icon: Icons.folder_copy
              ),
              
              if (_mode == 'batch') ...[
                 const SizedBox(height: 12),
                 const Text("Pasta de Origem (Lote):", style: TextStyle(color: Colors.white54, fontSize: 12)),
                 const SizedBox(height: 4),
                 _buildPathSelector(
                   value: _selectedBatchPath,
                   placeholder: "Selecione a pasta pai...",
                   onTap: _pickBatchFolder
                 ),
              ],

              const Divider(color: Colors.white24, height: 32),

              // OPTIONS
              const Text("Configurações:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              // Template Gallery
              const Text("Galeria de Templates (Padrão: Documents/AiaAlbum/Templates):", style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
               _buildPathSelector(
                 value: _customTemplatePath,
                 placeholder: "Usar Padrão",
                 onTap: _pickTemplateFolder,
                 icon: Icons.snippet_folder,
               ),
               
               const SizedBox(height: 16),
               
               // Auto Select
               SwitchListTile(
                 contentPadding: EdgeInsets.zero,
                 title: const Text("Usar Seleção Automática (IA)", style: TextStyle(color: Colors.white)),
                 subtitle: const Text("Filtra fotos repetidas/ruins antes de diagramar.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                 value: _useAutoSelect, 
                 activeColor: Colors.amberAccent,
                 onChanged: (v) => setState(() => _useAutoSelect = v)
               ),

            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text("Cancelar", style: TextStyle(color: Colors.white54))
        ),
        ElevatedButton.icon(
           style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
           ),
           onPressed: (_mode == 'batch' && _selectedBatchPath == null) ? null : () {
              // Pass values back
              // We need to update callback signature or use a Map/Object
              // Let's assume onStart handles extra args or we ignore for now and update MainWindow next
              // Actually we must update signature first or this won't compile? 
              // Dart is dynamic-ish but strong mode. 
              // We will update logic in main_window to match.
              // For now, let's pass to onStart as: mode, batchPath, templatePath, useAutoSelect
              // But onStart is defined as (String mode, String? batchPath).
              // We should change the widget definition too.
              Navigator.pop(context, {
                 'mode': _mode,
                 'batchPath': _selectedBatchPath,
                 'templatePath': _customTemplatePath,
                 'useAutoSelect': _useAutoSelect
              });
           },
           icon: const Icon(Icons.flash_on),
           label: const Text("Iniciar"),
        )
      ],
    );
  }
  
  Widget _buildPathSelector({String? value, required String placeholder, required VoidCallback onTap, IconData icon = Icons.folder_open}) {
      return Row(
       children: [
         Expanded(
           child: InkWell(
             onTap: onTap,
             child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
               decoration: BoxDecoration(
                 color: Colors.black26,
                 borderRadius: BorderRadius.circular(4),
                 border: Border.all(color: Colors.white12),
               ),
               child: Text(
                 value ?? placeholder,
                 style: TextStyle(color: value != null ? Colors.white : Colors.white38, fontSize: 13),
                 overflow: TextOverflow.ellipsis,
               ),
             ),
           ),
         ),
         const SizedBox(width: 8),
         IconButton(
            icon: Icon(icon, color: Colors.amberAccent),
            onPressed: onTap,
         ),
       ],
     );
  }
  
  Widget _buildOption({required String title, required String subtitle, required String value, required IconData icon}) {
     final isSelected = _mode == value;
     return InkWell(
       onTap: () => setState(() => _mode = value),
       borderRadius: BorderRadius.circular(8),
       child: Container(
         padding: const EdgeInsets.all(12),
         decoration: BoxDecoration(
           color: isSelected ? Colors.amberAccent.withOpacity(0.1) : Colors.transparent,
           border: Border.all(
              color: isSelected ? Colors.amberAccent : Colors.white10,
              width: isSelected ? 2 : 1
           ),
           borderRadius: BorderRadius.circular(8),
         ),
         child: Row(
           children: [
              Icon(icon, color: isSelected ? Colors.amber : Colors.white38, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      Text(title, style: TextStyle(color: isSelected ? Colors.amber : Colors.white, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                   ],
                ),
              ),
              if (isSelected) const Icon(Icons.check_circle, color: Colors.amber, size: 20),
           ],
         ),
       ),
     );
  }

  Future<void> _pickBatchFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() => _selectedBatchPath = result);
    }
  }
  
  Future<void> _pickTemplateFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() => _customTemplatePath = result);
    }
  }
}
