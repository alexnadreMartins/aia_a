import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../../../models/company_model.dart';
import '../../../logic/firestore_service.dart';

class AccessControlTab extends StatefulWidget {
  const AccessControlTab({super.key});

  @override
  State<AccessControlTab> createState() => _AccessControlTabState();
}

class _AccessControlTabState extends State<AccessControlTab> {
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

  Future<void> _toggleUserBlock(AiaUser user) async {
    final updated = AiaUser(
      id: user.id,
      name: user.name,
      role: user.role,
      company: user.company,
      email: user.email,
      password: user.password,
      fullName: user.fullName,
      albumsPerHourGoal: user.albumsPerHourGoal,
      photosPerHourGoal: user.photosPerHourGoal,
      isBlocked: !user.isBlocked,
    );
    await FirestoreService().saveUser(updated);
    _loadData();
  }

  Future<void> _toggleCompanyBlock(Company company) async {
    final updated = Company(
      id: company.id,
      name: company.name,
      contactName: company.contactName,
      contactInfo: company.contactInfo,
      city: company.city,
      state: company.state,
      country: company.country,
      isBlocked: !company.isBlocked,
    );
    await FirestoreService().saveCompany(updated);
    
    // Optional: Block all users of this company?
    // For now, the login logic should check checking User.isBlocked OR User.company.isBlocked
    _loadData();
  }

  // NOTE: Real "Delete" is dangerous. For now, we just show dialog.
  // Implementing soft delete or hard delete requires caution.
  // Requirement was "delete users".
  Future<void> _deleteUser(AiaUser user) async {
      // In a real app, you'd delete from Auth too. Here just Firestore.
      // FirestoreService doesn't have delete yet. We can implement or just simulate.
      // Let's assume we just Block for safety, or we need to add delete method.
      // For this step, I'll stick to Blocking as the primary control mechanism
      // and add a TODO for hard delete if they really push for it, 
      // or actually implement delete in Service if essential.
      // User asked to "delete user". I should add deleteUser to service.
      await FirestoreService().deleteUser(user.id);
      _loadData();
  }
  
   Future<void> _deleteCompany(Company company) async {
      await FirestoreService().deleteCompany(company.id);
      _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: "Usuários"),
              Tab(text: "Empresas"),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildUsersList(),
                _buildCompaniesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final u = _users[index];
        return Card(
          color: u.isBlocked ? Colors.red.withOpacity(0.3) : Colors.white10,
          child: ListTile(
            leading: Icon(u.isBlocked ? Icons.block : Icons.check_circle, 
                color: u.isBlocked ? Colors.red : Colors.green),
            title: Text("${u.name} (${u.fullName})", style: const TextStyle(color: Colors.white)),
            subtitle: Text("Empresa: ${u.company}", style: const TextStyle(color: Colors.white70)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: u.isBlocked ? "Desbloquear" : "Bloquear",
                  icon: Icon(u.isBlocked ? Icons.lock_open : Icons.lock, color: Colors.amber),
                  onPressed: () => _toggleUserBlock(u),
                ),
                IconButton(
                  tooltip: "Deletar",
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(u.name, () => _deleteUser(u)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompaniesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _companies.length,
      itemBuilder: (context, index) {
        final c = _companies[index];
        return Card(
          color: c.isBlocked ? Colors.red.withOpacity(0.3) : Colors.white10,
          child: ListTile(
            leading: Icon(c.isBlocked ? Icons.domain_disabled : Icons.domain, 
                color: c.isBlocked ? Colors.red : Colors.blue),
            title: Text(c.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text("Cidade: ${c.city}", style: const TextStyle(color: Colors.white70)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                   tooltip: c.isBlocked ? "Desbloquear" : "Bloquear",
                  icon: Icon(c.isBlocked ? Icons.lock_open : Icons.lock, color: Colors.amber),
                  onPressed: () => _toggleCompanyBlock(c),
                ),
                IconButton(
                  tooltip: "Deletar",
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(c.name, () => _deleteCompany(c)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(String name, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text("Tem certeza que deseja deletar '$name'? Esta ação é irreversível."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
             style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
             onPressed: () {
               Navigator.pop(ctx);
               onConfirm();
             }, 
             child: const Text("Deletar", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }
}
