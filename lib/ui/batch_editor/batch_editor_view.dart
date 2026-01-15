import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../logic/batch_scanner_service.dart';
import '../../models/batch_image_model.dart';
import '../editor/image_editor_view.dart';
import '../../logic/editor/editor_state.dart';
import '../../logic/batch_processor.dart';

class BatchEditorView extends StatefulWidget {
  const BatchEditorView({Key? key}) : super(key: key);

  @override
  State<BatchEditorView> createState() => _BatchEditorViewState();
}

class _BatchEditorViewState extends State<BatchEditorView> {
  String? _rootPath;
  List<BatchImage> _allImages = [];
  bool _isLoading = false;
  String _statusMessage = "";
  
  // Grouping
  String _groupBy = "none"; // none, date, camera
  Map<String, List<BatchImage>> _groupedImages = {};

  // Selection
  final Set<String> _selectedPaths = {};

  // Batches (Right Side)
  // Simple map: Batch Name -> List of Image Paths
  final Map<String, List<String>> _batches = {
    "Batch 1" : []
  };

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      
      // Ask User: All files or Only Used?
      bool? onlyUsed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
           title: const Text("Modo de Importação", style: TextStyle(color: Colors.white)),
           backgroundColor: const Color(0xFF333333),
           content: const Text(
             "Deseja importar todas as imagens da pasta ou apenas as que foram usadas nas páginas dos projetos (.alem)?",
             style: TextStyle(color: Colors.white70)
           ),
           actions: [
              TextButton(
                 onPressed: () => Navigator.pop(ctx, false), 
                 child: const Text("Todas as Imagens")
              ),
              FilledButton(
                 onPressed: () => Navigator.pop(ctx, true), 
                 child: const Text("Apenas Usadas no Álbum")
              ),
           ],
        )
      );
      
      if (onlyUsed == null) return; // Cancelled

      setState(() {
        _rootPath = selectedDirectory;
        _isLoading = true;
        _statusMessage = onlyUsed ? "Scanning project files..." : "Scanning all files...";
      });

      // 1. Scan Files
      final images = await BatchScannerService.scanDirectory(_rootPath!, onlyUsedInAlbums: onlyUsed);
      
      if (mounted) {
        setState(() {
          _allImages = images;
          _statusMessage = "Found ${images.length} images. Enriching Metadata...";
          _groupImages();
        });
      }

      // 2. Background Enrich (Lazy)
      BatchScannerService.enrichMetadata(images).then((enriched) {
         if (mounted) {
             setState(() {
                _allImages = enriched;
                _statusMessage = "Ready (${_allImages.length} images)";
                _groupImages(); // Re-group with new data
                _isLoading = false;
             });
         }
      });
    }
  }

  void _groupImages() {
     _groupedImages.clear();
     if (_groupBy == 'none') {
        _groupedImages['All Images'] = _allImages;
     } else if (_groupBy == 'date') {
        for (var img in _allImages) {
           String key = "Unknown Date";
           if (img.dateCaptured != null) {
              key = DateFormat('yyyy-MM-dd').format(img.dateCaptured!);
           }
           _groupedImages.putIfAbsent(key, () => []).add(img);
        }
     } else if (_groupBy == 'camera') {
        for (var img in _allImages) {
           String key = img.cameraModel ?? "Unknown Camera";
           _groupedImages.putIfAbsent(key, () => []).add(img);
        }
     } else if (_groupBy == 'tone') {
        for (var img in _allImages) {
           double b = img.brightness ?? 0.5;
           String key = "Médios";
           if (b < 0.3) key = "Sombras";
           else if (b > 0.7) key = "Luzes";
           _groupedImages.putIfAbsent(key, () => []).add(img);
        }
     }
     
     // Sort keys
     // Custom sort could be added here
  }
  
  void _addToBatch(String batchName) {
     if (_selectedPaths.isEmpty) return;
     setState(() {
        _batches[batchName]?.addAll(_selectedPaths);
        // Optional: clear selection?
        // _selectedPaths.clear(); 
     });
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added ${_selectedPaths.length} to $batchName")));
  }

  void _openEditor() async {
     if (_selectedPaths.isEmpty) return;
     final selectedList = _selectedPaths.toList();
     
     final result = await Navigator.push(context, MaterialPageRoute(
        builder: (c) => ImageEditorView(
           paths: selectedList, 
           initialIndex: 0, 
           batchMode: true
        )
     ));
     
     if (result != null && result is Map<String, ImageAdjustments>) {
        setState(() {
           _allImages = _allImages.map((img) {
              if (result.containsKey(img.path)) {
                 return img.copyWith(adjustments: result[img.path]);
              }
              return img;
           }).toList();
           _groupImages();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ajustes aplicados a ${result.length} imagens!")));
     }
  }
  
  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text("Editor em Lote"),
        backgroundColor: const Color(0xFF2C2C2C),
        actions: [
           if (_isLoading)
             Center(child: Padding(
               padding: const EdgeInsets.only(right: 16.0),
               child: Text(_statusMessage, style: const TextStyle(fontSize: 12, color: Colors.amber)),
             )),
           IconButton(
             icon: const Icon(Icons.create_new_folder),
             onPressed: _pickFolder,
             tooltip: "Select Folder",
           ),
        ],
      ),
      body: Row(
        children: [
           // LEFT: Library
           Expanded(
             flex: 3,
             child: Column(
               children: [
                 // Toolbar
                 Container(
                   height: 50,
                   color: const Color(0xFF252525),
                   child: Row(
                     children: [
                        const SizedBox(width: 16),
                        const Text("Agrupar por: ", style: TextStyle(color: Colors.white70)),
                        DropdownButton<String>(
                           value: _groupBy,
                           dropdownColor: const Color(0xFF333333),
                           style: const TextStyle(color: Colors.white),
                           items: const [
                              DropdownMenuItem(value: "none", child: Text("Nenhum")),
                              DropdownMenuItem(value: "date", child: Text("Data")),
                              DropdownMenuItem(value: "camera", child: Text("Câmera")),
                              DropdownMenuItem(value: "tone", child: Text("Tom (Histograma)")),
                           ],
                           onChanged: (val) {
                             if (val != null) {
                               setState(() {
                                 _groupBy = val;
                                 _groupImages();
                               });
                             }
                           },
                        ),
                        const Spacer(),
                        if (_selectedPaths.isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(right: 16.0),
                             child: ElevatedButton.icon(
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text("EDITAR SELEÇÃO"),
                                style: ElevatedButton.styleFrom(
                                   backgroundColor: Colors.amber[800],
                                   foregroundColor: Colors.white,
                                ),
                                onPressed: _openEditor,
                             ),
                           ),
                        Text("${_selectedPaths.length} selecionados", style: const TextStyle(color: Colors.white54)),
                        const SizedBox(width: 16),
                     ],
                   ),
                 ),
                 
                 // Grid Content
                 Expanded(
                   child: _buildGallery(),
                 ),
               ],
             ),
           ),
           
           // VERTICAL DIVIDER
           const VerticalDivider(width: 1, color: Colors.white24),
           
           // RIGHT: Batches
           Expanded(
             flex: 1,
             child: Container(
               color: const Color(0xFF222222),
               child: Column(
                 children: [
                    Container(
                      height: 50,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: [
                          const Text("Listas de Salvamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.greenAccent),
                            onPressed: () {
                               setState(() {
                                  _batches["Nova Lista ${_batches.length + 1}"] = [];
                               });
                            },
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _batches.keys.length,
                        itemBuilder: (ctx, index) {
                           String name = _batches.keys.elementAt(index);
                           List<String> items = _batches[name]!;
                           
                           return Card(
                             color: const Color(0xFF333333),
                             margin: const EdgeInsets.all(8),
                             child: Column(
                               children: [
                                  ListTile(
                                    title: Text(name, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text("${items.length} itens", style: const TextStyle(color: Colors.white54)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.download_rounded, color: Colors.blueAccent),
                                      onPressed: () {
                                         _addToBatch(name);
                                      },
                                      tooltip: "Add Selected Images Here",
                                    ),
                                  ),
                                  // Preview first few?
                                  if (items.isNotEmpty)
                                    SizedBox(
                                      height: 60,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: items.length > 5 ? 5 : items.length,
                                        itemBuilder: (ctx, i) {
                                           return Padding(
                                             padding: const EdgeInsets.all(4.0),
                                             child: Image.file(
                                               File(items[i]), 
                                               width: 50, height: 50, 
                                               fit: BoxFit.cover,
                                               cacheWidth: 100, // Optimization
                                             ),
                                           );
                                        },
                                      ),
                                    )
                               ],
                             ),
                           );
                        },
                      ),
                    ),
                    
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.run_circle),
                        label: Text(_isProcessing ? "PROCESSANDO (${(_progress * 100).toInt()}%)" : "PROCESSAR LOTES"),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: _isProcessing ? Colors.grey : Colors.amber[800],
                           foregroundColor: Colors.white,
                           minimumSize: const Size(double.infinity, 50)
                        ),
                        onPressed: _isProcessing ? null : _runBatchProcessing,
                      ),
                    )
                 ],
               ),
             ),
           ),
        ],
      ),
    );
  }

  // Processing Logic
  bool _isProcessing = false;
  double _progress = 0.0;
  
  Future<void> _runBatchProcessing() async {
     // 1. Gather Images from all batches
     List<BatchImage> toProcess = [];
     
     for (var batchName in _batches.keys) {
        final paths = _batches[batchName]!;
        for (var path in paths) {
           // Find the image object (with edits)
           try {
              final img = _allImages.firstWhere((i) => i.path == path);
              toProcess.add(img);
           } catch (_) {}
        }
     }
     
     if (toProcess.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nenhuma imagem nas listas de salvamento.")));
        return;
     }

     // 2. Confirm Overwrite
     final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
           backgroundColor: const Color(0xFF333333),
           title: const Text("Confirmar Alterações", style: TextStyle(color: Colors.white)),
           content: const Text(
             "ATENÇÃO: Esta ação irá SUBSTITUIR os arquivos originais com as edições aplicadas.\n\nEssa ação não pode ser desfeita. Deseja continuar?",
             style: TextStyle(color: Colors.white70),
           ),
           actions: [
              TextButton(
                 onPressed: () => Navigator.pop(ctx, false),
                 child: const Text("Cancelar"),
              ),
              FilledButton(
                 style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                 onPressed: () => Navigator.pop(ctx, true),
                 child: const Text("SUBSTITUIR ARQUIVOS"),
              ),
           ],
        ),
     );
     
     if (confirm != true) return;
     
     setState(() {
        _isProcessing = true;
        _progress = 0.0;
     });
     
     // 3. Run (null outputDir = overwrite)
     final stream = BatchProcessor.processBatch(toProcess, null);
     int total = toProcess.length;
     
     await for (int completed in stream) {
        if (mounted) {
           setState(() {
              _progress = completed / total;
           });
        }
     }
     
     if (mounted) {
        setState(() {
           _isProcessing = false;
           _progress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sucesso! $total imagens foram atualizadas.")));
        
     }
  }

  Widget _buildGallery() {
     if (_allImages.isEmpty) {
        return const Center(child: Text("Selecione uma pasta para começar", style: TextStyle(color: Colors.white54)));
     }
     
     // Use CustomScrollView with Slivers for grouping support
     List<Widget> slivers = [];
     
     _groupedImages.forEach((groupName, images) {
         slivers.add(
            SliverToBoxAdapter(
               child: Container(
                 margin: const EdgeInsets.only(top: 8),
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                 decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2C),
                    border: Border(left: BorderSide(color: Colors.amberAccent, width: 4))
                 ),
                 child: Row(
                    children: [
                       Checkbox(
                          value: images.every((img) => _selectedPaths.contains(img.path)),
                          activeColor: Colors.amber,
                          onChanged: (val) {
                             setState(() {
                                if (val == true) {
                                   _selectedPaths.addAll(images.map((e) => e.path));
                                } else {
                                   _selectedPaths.removeAll(images.map((e) => e.path));
                                }
                             });
                          }
                       ),
                       Text(
                         "$groupName (${images.length})", 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                       ),
                    ],
                 ),
               ),
            )
         );
         
         slivers.add(
            SliverGrid(
               delegate: SliverChildBuilderDelegate(
                 (ctx, index) {
                    final img = images[index];
                    final isSelected = _selectedPaths.contains(img.path);
                    
                    return GestureDetector(
                       onTap: () {
                          setState(() {
                             if (isSelected) {
                                _selectedPaths.remove(img.path);
                             } else {
                                _selectedPaths.add(img.path);
                             }
                          });
                       },
                       child: Stack(
                         fit: StackFit.expand,
                         children: [
                            Image.file(
                               File(img.path),
                               fit: BoxFit.cover,
                               cacheWidth: 200, // CRITICAL FOR PERFORMANCE
                            ),
                            if (img.adjustments != null)
                               const Positioned(
                                 top: 4, right: 4,
                                 child: CircleAvatar(radius: 6, backgroundColor: Colors.greenAccent, child: Icon(Icons.edit, size: 8, color: Colors.black)),
                               ),
                            if (isSelected)
                              Container(
                                color: Colors.blueAccent.withOpacity(0.4),
                                child: const Center(child: Icon(Icons.check, color: Colors.white, size: 30)),
                              ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                 color: Colors.black54,
                                 padding: const EdgeInsets.all(2),
                                 child: Text(
                                   img.cameraModel ?? "", 
                                   style: const TextStyle(color: Colors.white, fontSize: 10),
                                   textAlign: TextAlign.center,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                              ),
                            )
                         ],
                       ),
                    );
                 },
                 childCount: images.length,
               ),
               gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.0,
               ),
            )
         );
     });
  
     return CustomScrollView(slivers: slivers);
  }
}
