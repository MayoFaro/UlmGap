// Implémentation non-web de core/download.dart : jamais appelée en pratique
// (le bouton d'export n'existe que si `kIsWeb`), gardée pour que le code
// compile sur Android/iOS.
void downloadTextFile(String filename, String content) {}
