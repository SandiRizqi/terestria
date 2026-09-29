/// Nama basemap untuk PDF yang ditambahkan dari Analysis Report:
/// `"<project> · <judul>"`, dengan project = level pertama Analysis Report
/// (`AnalysisType.name`), agar di pemilih basemap jelas asal project-nya.
///
/// Tak dobel prefix bila judul sudah diawali nama project; spasi berlebih
/// dirapikan; salah satu kosong → pakai yang ada saja.
String analysisBasemapName(String? projectName, String title) {
  final project = _tidy(projectName ?? '');
  final judul = _tidy(title);
  if (project.isEmpty) return judul;
  if (judul.isEmpty) return project;
  if (judul.toLowerCase().startsWith(project.toLowerCase())) return judul;
  return '$project · $judul';
}

String _tidy(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
