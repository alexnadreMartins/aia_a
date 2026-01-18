import 'package:flutter/material.dart';
import '../../../models/company_model.dart';
import '../../../logic/firestore_service.dart';

class CompaniesTab extends StatefulWidget {
  const CompaniesTab({super.key});

  @override
  State<CompaniesTab> createState() => _CompaniesTabState();
}

class _CompaniesTabState extends State<CompaniesTab> {
  List<Company> _companies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    final list = await FirestoreService().getCompanies();
    setState(() {
      _companies = list;
      _isLoading = false;
    });
  }

  void _showEditDialog([Company? company]) {
    final nameCtrl = TextEditingController(text: company?.name);
    final contactNameCtrl = TextEditingController(text: company?.contactName);
    final contactInfoCtrl = TextEditingController(text: company?.contactInfo);
    final cityCtrl = TextEditingController(text: company?.city);
    final stateCtrl = TextEditingController(text: company?.state);
    final countryCtrl = TextEditingController(text: company?.country);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(company == null ? "Nova Empresa" : "Editar Empresa"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome da Empresa")),
               const SizedBox(height: 10),
               TextField(controller: contactNameCtrl, decoration: const InputDecoration(labelText: "Nome do Contato")),
               TextField(controller: contactInfoCtrl, decoration: const InputDecoration(labelText: "Info Contato (Email/Tel)")),
               const SizedBox(height: 10),
               Row(
                 children: [
                   Expanded(child: TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: "Cidade"))),
                   const SizedBox(width: 8),
                   Expanded(child: TextField(controller: stateCtrl, decoration: const InputDecoration(labelText: "Estado"))),
                 ],
               ),
               TextField(controller: countryCtrl, decoration: const InputDecoration(labelText: "País")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              
              final newCompany = Company(
                id: company?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text.trim(),
                contactName: contactNameCtrl.text.trim(),
                contactInfo: contactInfoCtrl.text.trim(),
                city: cityCtrl.text.trim(),
                state: stateCtrl.text.trim(),
                country: countryCtrl.text.trim(),
                isBlocked: company?.isBlocked ?? false,
              );
              
              try {
                await FirestoreService().saveCompany(newCompany);
                if (mounted) {
                  Navigator.pop(ctx);
                  _loadCompanies();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Empresa salva com sucesso!"), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao salvar: $e"), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text("Salvar"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _companies.length,
        itemBuilder: (context, index) {
          final c = _companies[index];
          return Card(
             color: c.isBlocked ? Colors.red.withOpacity(0.2) : Colors.white10,
             child: ListTile(
               leading: const Icon(Icons.business, color: Colors.blueAccent),
               title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
               subtitle: Text(
                 "Contato: ${c.contactName} (${c.contactInfo})\nLocal: ${c.city}/{c.state} - ${c.country}",
                 style: const TextStyle(color: Colors.white70),
               ),
               trailing: IconButton(
                 icon: const Icon(Icons.edit, color: Colors.white54),
                 onPressed: () => _showEditDialog(c),
               ),
             ),
          );
        },
      ),
    );
  }
}
