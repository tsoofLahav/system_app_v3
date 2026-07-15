import '../models/app_file.dart';

List<AppFile> rotateMainFilesLeft(List<AppFile> main) {
  if (main.length < 2) return List<AppFile>.from(main);
  return [...main.sublist(1), main.first];
}
