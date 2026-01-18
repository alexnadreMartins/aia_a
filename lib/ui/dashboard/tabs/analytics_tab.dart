import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../logic/firestore_service.dart';
import '../dialogs/photographer_details_dialog.dart';
import '../dialogs/project_details_dialog.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _projects = [];
  Map<String, String> _photographerMappings = {};
  
  // Filter State
  String _period = "Mensal"; // Semanal, Mensal, Anual
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  DateTime? _parseDate(dynamic input) {
    if (input == null) return null;
    if (input is DateTime) return input;
    if (input is Timestamp) return input.toDate();
    // Fallback for debugging
    if (input.runtimeType.toString() == 'Timestamp') {
       try {
          return (input as dynamic).toDate(); 
       } catch (_) {}
    }
    return null;
  }

  void _updateDateRange() {
    final now = DateTime.now();
    if (_period == "Semanal") {
      _startDate = now.subtract(const Duration(days: 7));
    } else if (_period == "Mensal") {
      _startDate = now.subtract(const Duration(days: 30));
    } else if (_period == "Anual") {
      _startDate = now.subtract(const Duration(days: 365));
    }
    _endDate = now;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // ... existing ...
    final projects = await FirestoreService().getProjectsInRange(_startDate, _endDate);
    final mappings = await FirestoreService().getPhotographerMappings();
    
    setState(() {
      _projects = projects;
      _photographerMappings = mappings;
      _isLoading = false;
    });
  }

  Future<void> _runConnectionTest() async {
    
    showDialog(
       context: context, 
       barrierDismissible: false,
       builder: (ctx) => const Center(child: CircularProgressIndicator())
    );
    
    final result = await FirestoreService().testConnection();
    
    if (mounted) {
       Navigator.pop(context); // Close loading
       showDialog(
         context: context,
         builder: (ctx) => AlertDialog(
            title: const Text("Resultado do Teste"),
            content: Text(result),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
            ],
         )
       );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // --- Aggregation Logic ---
    final companyMasterStats = <String, int>{}; // Company -> Album Count
    final companyEditorStats = <String, int>{}; // Company -> Photos Mounted
    final contractStats = <String, Map<String, dynamic>>{}; // Contract -> {status, projectCount}
    
    // Editor Ranking: User -> { totalProjects, totalPhotos, lastActive }
    final editorRanking = <String, Map<String, dynamic>>{};

    // Photographer Aggregation: Name -> { totalPhotos, projects: [ {name, contract, photos, score, events} ] }
    final photographerDetailedStats = <String, Map<String, dynamic>>{};
    
    // KPI Data
    int totalAlbums = 0;
    int totalPhotosGlobal = 0;

    for (var p in _projects) {
       final company = p['company'] ?? 'Unknown';
       final role = p['userCategory'] ?? 'Editor';
       final contract = p['contractNumber'] ?? 'N/A';
       final lastUser = p['lastUser'] ?? 'Unknown';
       
       // KPIs
       totalAlbums++;
       final phUsed = p['totalPhotosUsed'] as int? ?? 0;
       totalPhotosGlobal += phUsed;
       
       // Company Stats
       if (role == 'Master') {
          companyMasterStats[company] = (companyMasterStats[company] ?? 0) + 1;
       } else {
          companyEditorStats[company] = (companyEditorStats[company] ?? 0) + phUsed;
       }

       // Contract Stats
       if (!contractStats.containsKey(contract)) {
          contractStats[contract] = {'count': 0, 'lastUpdate': _parseDate(p['lastUpdated'])};
       }
       contractStats[contract]!['count'] += 1;

       // Editor Ranking
       if (!editorRanking.containsKey(lastUser)) {
           editorRanking[lastUser] = {
             'projects': 0,
             'photos': 0,
             'lastActive': _parseDate(p['lastUpdated'])
           };
       }
       editorRanking[lastUser]!['projects'] += 1;
       editorRanking[lastUser]!['photos'] += phUsed;
       // Keep most recent date
       final pDate = _parseDate(p['lastUpdated']);

       final currDate = (editorRanking[lastUser]!['lastActive'] as DateTime?);
       if (pDate != null && (currDate == null || pDate.isAfter(currDate))) {
          editorRanking[lastUser]!['lastActive'] = pDate;
       }

       // Photographer Stats
       final pStats = p['photographerStats'] as Map<String, dynamic>?;
       
       if (pStats != null && pStats.isNotEmpty) {
          // New Structure
          pStats.forEach((name, data) {
             final d = data as Map<String, dynamic>;
             final count = d['totalUsed'] as int? ?? 0;
             final listEvents = d['events'] as List?;
             final events = listEvents?.map((e) => e.toString()).toList() ?? [];
             
             double score = (count / 10.0).clamp(0.0, 10.0);

             if (!photographerDetailedStats.containsKey(name)) {
                photographerDetailedStats[name] = {'total': 0, 'projects': <Map<String, dynamic>>[]};
             }
             
             photographerDetailedStats[name]!['total'] = (photographerDetailedStats[name]!['total'] as int) + count;
             (photographerDetailedStats[name]!['projects'] as List).add({
                'projectName': p['name'],
                'contract': contract,
                'photosUsed': count,
                'events': events,
                'score': score
             });
          });
       } else {
          // Legacy Fallback
           final usedCounts = p['usedPhotoCounts'] as Map<String, dynamic>? ?? {};
           usedCounts.forEach((serial, count) {
              final name = _photographerMappings[serial] ?? "Serial: $serial";
              final c = count as int;
              
              if (!photographerDetailedStats.containsKey(name)) {
                photographerDetailedStats[name] = {'total': 0, 'projects': <Map<String, dynamic>>[]};
              }
              photographerDetailedStats[name]!['total'] = (photographerDetailedStats[name]!['total'] as int) + c;
              (photographerDetailedStats[name]!['projects'] as List).add({
                'projectName': p['name'],
                'contract': contract,
                'photosUsed': c,
                'events': <String>[],
                'score': (c / 10.0).clamp(0.0, 10.0)
             });
           });
       }
    }
    
    // Sort Photographers
    final sortedPhotographers = photographerDetailedStats.entries.toList()
      ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

    // Sort Editors (by photos)
    final sortedEditors = editorRanking.entries.toList()
      ..sort((a, b) => (b.value['photos'] as int).compareTo(a.value['photos'] as int));

    // Sort Project History (Time Descending)
    final sortedProjects = List<Map<String, dynamic>>.from(_projects);
    sortedProjects.sort((a, b) {
       final da = _parseDate(a['lastUpdated']);
       final db = _parseDate(b['lastUpdated']);

       if (da == null) return 1;
       if (db == null) return -1;
       return db.compareTo(da);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          
          // KPI
          Row(
            children: [
              Expanded(child: _buildKPICard("Total Álbuns", "$totalAlbums", Icons.book, Colors.blueAccent)),
              const SizedBox(width: 20),
              Expanded(child: _buildKPICard("Total Fotos", "$totalPhotosGlobal", Icons.photo_library, Colors.greenAccent)),
              const SizedBox(width: 20),
              Expanded(child: _buildKPICard("Contratos Ativos", "${contractStats.length}", Icons.assignment, Colors.orangeAccent)),
            ],
          ),
          
          const SizedBox(height: 30),
          
          // --- Charts ---
          _buildSectionTitle("Produção Global", Icons.bar_chart),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildBarChart(companyMasterStats, "Álbuns (Master)", Colors.blueAccent)),
              const SizedBox(width: 20),
              Expanded(child: _buildBarChart(companyEditorStats, "Fotos Editadas", Colors.purpleAccent)),
            ],
          ),
          
          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 20),
          
          // --- Rankings Row ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Expanded(
                 flex: 3,
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     _buildSectionTitle("Ranking de Fotógrafos", Icons.camera_alt),
                     const SizedBox(height: 10),
                     _buildPhotographerList(sortedPhotographers),
                   ],
                 ),
               ),
               const SizedBox(width: 20),
               Expanded(
                 flex: 2,
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      _buildSectionTitle("Ranking de Editores", Icons.person_outline),
                      const SizedBox(height: 10),
                      _buildEditorRankingList(sortedEditors),
                   ],
                 ),
               )
            ],
          ),

          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 20),

          // --- Project History ---
          _buildSectionTitle("Histórico de Projetos", Icons.history),
          const SizedBox(height: 10),
          _buildProjectHistoryTable(sortedProjects),
          
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Analytics Pro", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.wifi_tethering, color: Colors.white54),
              tooltip: "Testar Conexão",
              onPressed: _runConnectionTest,
            ),
            const SizedBox(width: 16),
            DropdownButton<String>(
              value: _period,
              dropdownColor: const Color(0xFF2C2C2C),
              style: const TextStyle(color: Colors.white),
              items: ["Semanal", "Mensal", "Anual"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _period = v);
                  _updateDateRange();
                }
              },
            ),
          ],
        )
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBarChart(Map<String, int> data, String yLabel, Color barColor) {
    if (data.isEmpty) return Container(
       height: 200, 
       decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
       child: const Center(child: Text("Sem dados", style: TextStyle(color: Colors.white54)))
    );
    
    final keys = data.keys.toList();
    final maxValue = data.values.fold(0, (p, c) => c > p ? c : p).toDouble();
    
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(yLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(height: 10),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxValue * 1.2) > 0 ? maxValue * 1.2 : 10,
                 barTouchData: BarTouchData(
                   touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.blueGrey,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                         return BarTooltipItem(
                            "${keys[group.x.toInt()]}\n${rod.toY.toInt()}",
                            const TextStyle(color: Colors.white),
                         );
                      },
                   ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (double value, TitleMeta meta) {
                         if (value.toInt() >= keys.length) return const Text('');
                         return Padding(
                           padding: const EdgeInsets.only(top: 8.0),
                           child: Text(keys[value.toInt()], style: const TextStyle(color: Colors.white70, fontSize: 10)),
                         );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 10)))),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barGroups: List.generate(keys.length, (i) {
                   return BarChartGroupData(
                     x: i,
                     barRods: [
                       BarChartRodData(
                         toY: data[keys[i]]!.toDouble(),
                         color: barColor,
                         width: 16,
                         borderRadius: BorderRadius.circular(2),
                       )
                     ],
                   );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotographerList(List<MapEntry<String, Map<String, dynamic>>> sortedList) {
    if (sortedList.isEmpty) return const Text("Sem dados de fotos.", style: TextStyle(color: Colors.white54));
    
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sortedList.length > 20 ? 20 : sortedList.length, 
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (ctx, index) {
           final entry = sortedList[index];
           final name = entry.key;
           final total = entry.value['total'];
           final projects = entry.value['projects'] as List<Map<String, dynamic>>;
           
           return ListTile(
             contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
             leading: CircleAvatar(
               backgroundColor: index < 3 ? Colors.amber : Colors.blueGrey,
               radius: 14,
               child: Text((index + 1).toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
             ),
             title: Text(name, style: const TextStyle(color: Colors.white)),
             trailing: Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Text("$total Fotos", style: const TextStyle(color: Colors.greenAccent)),
                 const SizedBox(width: 10),
                 const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white54)
               ],
             ),
             onTap: () async {
                final result = await showDialog(
                  context: context,
                  builder: (context) => PhotographerDetailsDialog(
                    photographerName: name,
                    totalPhotos: total,
                    projects: projects,
                  )
                );
                
                if (result == true) {
                   _loadData();
                }
             },
           );
        },
      ),
    );
  }

  Widget _buildEditorRankingList(List<MapEntry<String, dynamic>> sortedList) {
     if (sortedList.isEmpty) return const Text("Sem dados de editores.", style: TextStyle(color: Colors.white54));
     
     return Container(
       decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12)),
       child: ListView.separated(
         shrinkWrap: true,
         physics: const NeverScrollableScrollPhysics(),
         itemCount: sortedList.length > 10 ? 10 : sortedList.length,
         separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
         itemBuilder: (ctx, index) {
            final entry = sortedList[index];
            final name = entry.key;
            final data = entry.value as Map<String, dynamic>;
            final photos = data['photos'];
            final projects = data['projects'];
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                 backgroundColor: index == 0 ? Colors.purpleAccent : Colors.grey[800],
                 radius: 14,
                 child: Text("${index+1}", style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
              title: Text(name, style: const TextStyle(color: Colors.white)),
              subtitle: Text("$projects Projetos", style: const TextStyle(color: Colors.white54, fontSize: 10)),
              trailing: Text("$photos Fotos", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            );
         },
       ),
    );
  }

  Widget _buildProjectHistoryTable(List<Map<String, dynamic>> projects) {
     if (projects.isEmpty) return const Text("Histórico vazio.", style: TextStyle(color: Colors.white54));

     return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(8)),
        child: Theme(
           data: Theme.of(context).copyWith(dividerColor: Colors.white10),
           child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.black12),
              columns: const [
                 DataColumn(label: Text("Data", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Projeto", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Usuário", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Contrato", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Lâminas", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Fotos", style: TextStyle(color: Colors.white70))),
                 DataColumn(label: Text("Tempo", style: TextStyle(color: Colors.white70))),
              ],
              rows: projects.take(15).map((p) {
                 final date = _parseDate(p['lastUpdated']);
                 final fmtDate = date != null ? DateFormat('dd/MM HH:mm').format(date) : "-";
                 final durationSeconds = p['totalEditingTimeSeconds'] as int? ?? p['totalEditingTime'] as int? ?? 0;
                 final durationStr = "${(durationSeconds / 60).toStringAsFixed(0)} min";
                 final pageCount = p['pageCount'] as int? ?? 0;
                 
                 return DataRow(
                    onSelectChanged: (_) {
                       showDialog(
                         context: context, 
                         builder: (ctx) => ProjectDetailsDialog(projectData: p)
                       );
                    },
                    cells: [
                    DataCell(Text(fmtDate, style: const TextStyle(color: Colors.white54, fontSize: 10))),
                    DataCell(Text(p['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12))),
                    DataCell(Text(p['lastUser'] ?? '-', style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12))),
                    DataCell(Text(p['contractNumber'] ?? '-', style: const TextStyle(color: Colors.white54, fontSize: 12))),
                    DataCell(Text("$pageCount", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                    DataCell(Text("${p['totalPhotosUsed'] ?? 0}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12))),
                    DataCell(Text(durationStr, style: const TextStyle(color: Colors.white54, fontSize: 10))),
                 ]);
              }).toList(),
           ),
        ),
     );
  }
}
