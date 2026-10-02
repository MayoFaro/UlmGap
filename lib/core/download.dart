// Téléchargement d'un fichier texte côté client (Task 12 : export CSV du
// relevé des vols facturés). Import conditionnelle : implémentation réelle
// sur le web (download_web.dart), no-op ailleurs (download_stub.dart). Le
// bouton d'export n'existe que si `kIsWeb`, donc l'implémentation mobile
// n'est jamais appelée en pratique ; elle n'existe que pour la compilation.
import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

void downloadTextFile(String filename, String content) => impl.downloadTextFile(filename, content);
