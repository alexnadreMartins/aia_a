import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Atalhos & Guia de Gestos", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      indicatorColor: Colors.blue,
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      tabs: [
                        Tab(text: "Touch & Wacom (Caneta)"),
                        Tab(text: "Teclado & Mouse"),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildTouchGuide(),
                          _buildKeyboardGuide(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTouchGuide() {
    return ListView(
      children: [
        _buildSectionTitle("Modo Touch / Wacom (Tablet)"),
        _buildItem(Icons.touch_app, "Arrastar para Rolar", "Use a caneta/dedo para arrastar qualquer lista ou a tela principal, como num celular."),
        _buildItem(Icons.zoom_in, "Zoom e Pan", "Use gesto de pinça para zoom. Arraste com dois dedos (ou ferramenta Pan) para mover a tela."),
        _buildItem(Icons.swipe, "Trocar Fotos (Swap)", "Segure uma foto por 2 segundos. Um fantasma aparecerá. Arraste e solte sobre outra foto para trocar."),
        _buildItem(Icons.select_all, "Multi-Seleção Touch", "Ative o botão 'Select' na barra inferior. Toque nas fotos para selecionar várias."),
        const Divider(color: Colors.grey),
        _buildSectionTitle("Barra de Ferramentas Touch"),
        _buildItem(Icons.check_circle_outline, "Modo Seleção", "Ativa/Desativa seleção múltipla por toque."),
        _buildItem(Icons.delete, "Excluir", "Remove os itens selecionados."),
        _buildItem(Icons.copy, "Duplicar", "Duplica a foto selecionada."),
        _buildItem(Icons.undo, "Desfazer / Refazer", "Controla o histórico de ações."),
        _buildItem(Icons.rotate_right, "Rotação", "Gira a foto selecionada 90 graus."),
      ],
    );
  }

  Widget _buildKeyboardGuide() {
    return ListView(
      children: [
        _buildSectionTitle("Geral"),
        _buildShortcut("Delete", "Excluir Foto Selecionada"),
        _buildShortcut("Shift + Delete", "Excluir Página Inteira"),
        _buildShortcut("Ctrl + Z", "Desfazer"),
        _buildShortcut("Ctrl + Shift + Z", "Refazer"),
        const Divider(color: Colors.grey),
        _buildSectionTitle("Edição"),
        _buildShortcut("Setas", "Mover Foto (Ajuste Fino)"),
        _buildShortcut("Ctrl + Setas", "Mover Conteúdo (Crop Interno)"),
        _buildShortcut("Ctrl + , / .", "Enviar p/ Trás / Trazer p/ Frente"),
        const Divider(color: Colors.grey),
        _buildSectionTitle("Seleção"),
        _buildShortcut("Ctrl + Click", "Seleção Múltiplas Fotos/Páginas"),
        _buildShortcut("Ctrl + A", "Selecionar Tudo (no Browser)"),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(desc, style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcut(String keys, String action) {
     return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
            child: Text(keys, style: GoogleFonts.firaCode(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Text(action, style: GoogleFonts.inter(color: Colors.grey[300], fontSize: 15)),
        ],
      ),
    );
  }
}
