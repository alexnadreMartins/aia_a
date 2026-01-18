import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../../../models/company_model.dart';
import '../../../logic/firestore_service.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  List<AiaUser> _users = [];
  List<Company> _companies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final users = await FirestoreService().getUsers();
    final companies = await FirestoreService().getCompanies();
    setState(() {
      _users = users;
      _companies = companies;
      _isLoading = false;
    });
  }

  void _showEditDialog([AiaUser? user]) {
    final idCtrl = TextEditingController(text: user?.id);
    final nameCtrl = TextEditingController(text: user?.name);
    final emailCtrl = TextEditingController(text: user?.email);
    final passCtrl = TextEditingController(text: user?.password);
    final fullNameCtrl = TextEditingController(text: user?.fullName);
    
    // Default to first company or "Default" if list empty
    String selectedCompany = user?.company ?? (_companies.isNotEmpty ? _companies.first.name : "Default");
    // Ensure selected company actually exists in list (or is manual input if old data)
    if (_companies.isNotEmpty && !_companies.any((c) => c.name == selectedCompany)) {
       // If stored company not in list, maybe it was a text input before. Keep it or reset?
       // Let's keep it if we can find it by ID, otherwise default.
       // Simplifying: Just let user picking from dropdown for NEW/EDIT.
       if (_companies.any((c) => c.name == user?.company)) {
          selectedCompany = user!.company;
       } else {
          selectedCompany = _companies.first.name;
       }
    }

    String role = user?.role ?? "Editor";
    final albumGoalCtrl = TextEditingController(text: (user?.albumsPerHourGoal ?? 5).toString());
    final photoGoalCtrl = TextEditingController(text: (user?.photosPerHourGoal ?? 100).toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(user == null ? "Novo Usuário" : "Editar Usuário"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   TextField(controller: idCtrl, decoration: const InputDecoration(labelText: "Username (ID)"), enabled: user == null),
                   const SizedBox(height: 10),
                   TextField(controller: fullNameCtrl, decoration: const InputDecoration(labelText: "Nome Completo")),
                   TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome Exibição (Apelido)")),
                   const SizedBox(height: 16),
                   TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "E-mail (Login)")),
                   TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Senha"), obscureText: true),
                   const SizedBox(height: 16),
                   if (_companies.isEmpty)
                      const Text("Nenhuma empresa cadastrada!", style: TextStyle(color: Colors.red))
                   else
                      DropdownButtonFormField<String>(
                        value: selectedCompany,
                        items: _companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                        onChanged: (v) => setState(() => selectedCompany = v!),
                        decoration: const InputDecoration(labelText: "Empresa"),
                      ),
                   
                   const SizedBox(height: 16),
                   DropdownButtonFormField<String>(
                     value: role,
                     items: const [
                       DropdownMenuItem(value: "Master", child: Text("Master (Diagramação)")),
                       DropdownMenuItem(value: "Editor", child: Text("Editor (Tratamento/Montagem)")),
                     ],
                     onChanged: (v) => setState(() => role = v!),
                     decoration: const InputDecoration(labelText: "Função"),
                   ),
                   const SizedBox(height: 16),
                   if (role == "Master")
                      TextField(controller: albumGoalCtrl, decoration: const InputDecoration(labelText: "Meta: Álbuns/Hora"), keyboardType: TextInputType.number),
                   if (role == "Editor")
                      TextField(controller: photoGoalCtrl, decoration: const InputDecoration(labelText: "Meta: Fotos/Hora"), keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () async {
                  if (idCtrl.text.isEmpty) return;
                  
                  String? authId;
                  if (user == null && passCtrl.text.isNotEmpty && emailCtrl.text.isNotEmpty) {
                    try {
                      authId = await FirestoreService().createAuthUser(emailCtrl.text.trim(), passCtrl.text.trim());
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro Auth: $e")));
                      return; // Stop if Auth creation fails
                    }
                  }

                  final newUser = AiaUser(
                    id: authId ?? idCtrl.text.trim(), // Use Auth ID if available
                    name: nameCtrl.text.trim().isEmpty ? idCtrl.text : nameCtrl.text.trim(),
                    fullName: fullNameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                    role: role,
                    company: selectedCompany,
                    albumsPerHourGoal: int.tryParse(albumGoalCtrl.text) ?? 5,
                    photosPerHourGoal: int.tryParse(photoGoalCtrl.text) ?? 100,
                    isBlocked: user?.isBlocked ?? false,
                  );
                  await FirestoreService().saveUser(newUser);
                  if (mounted) Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text("Salvar"),
              )
            ],
          );
        }
      )
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
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final u = _users[index];
          return Card(
            color: u.isBlocked ? Colors.red.withOpacity(0.2) : Colors.white10,
            child: ListTile(
              leading: Icon(u.role == "Master" ? Icons.engineering : Icons.edit, color: Colors.blueAccent),
              title: Text("${u.name} (${u.fullName})", style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                "${u.role} @ ${u.company}\nLogin: ${u.email}",
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit, color: Colors.white54),
                onPressed: () => _showEditDialog(u),
              ),
            ),
          );
        },
      ),
    );
  }
}
