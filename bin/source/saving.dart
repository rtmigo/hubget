import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kt_dart/collection.dart';
import 'package:path/path.dart' as pathlib;

import 'gh_api.dart';
import 'sha.dart';

void require(bool condition, String Function() message) {
  if (!condition) {
    throw Exception(message());
  }
}

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Если пути [parent] и [child] одинаковы, возвращает `null`. Иначе полагаем,
/// что [child] расположен непосредственно внутри [parent] и возвращаем
/// локальное имя [child].
String? _childName(Endpoint parent, Endpoint child) {
  final parentSegments = Uri.parse(parent.string).pathSegments;
  final childSegments = Uri.parse(child.string).pathSegments;

  if (_listsEqual(parentSegments, childSegments)) {
    return null;
  }

  require(childSegments.length == parentSegments.length + 1,
      () => "Unexpected length: $parentSegments $childSegments");
  require(
      _listsEqual(childSegments.take(childSegments.length - 1).toList(),
          parentSegments),
      () => "Unexpected lhs: $parentSegments $childSegments");

  return childSegments.last;
}

Uint8List _getFileContent(GithubFsEntry entry) {
  // контент может быт уже внутри entry (в виде base64), а может и не быть.

  if (entry.type != GithubFsEntryType.file) {
    throw ArgumentError(entry.type);
  }
  final String theBase64;
  if (entry.contentBase64 != null) {
    theBase64 = entry.contentBase64!;
  } else {
    // TODO
    // я не уверен насчёт больших файлов: возможно, там тоже не будет контента
    theBase64 = getEntries(entry.endpoint).toList().single.contentBase64!;
  }

  return base64.decode(theBase64.replaceAll('\n', ''));
}

void _updateFile(GithubFsEntry entry, File target) {
  //print("Want save ${entry.endpoint.string} to $target");
  print("* Remote: ${entry.endpoint.string}");
  print("  Local: ${target.path}");
  if (target.existsSync() &&
      target.statSync().size == entry.size &&
      fileToGhSha(target) == entry.sha) {
    print("  The file is up to date (not modified)");
  } else {
    final parentDir = Directory(pathlib.dirname(target.path));
    parentDir.createSync(recursive: true);
    target.writeAsBytesSync(_getFileContent(entry));
    print("  File updated");
  }
}

void updateDir(Endpoint ep, Directory target) {
  _updateDirRecursive(ep, target, KtSet<String>.empty());
}

/// Аргумент [processed] нужен только для того, чтобы предотвратить
/// бесконечную рекурсию по ошибке.
void _updateDirRecursive(
    Endpoint sourcePath, Directory target, KtSet<String> processed) {
  // TODO Проверять sha каталогов (не только файлов)

  if (processed.contains(sourcePath.string)) {
    throw ArgumentError("This endpoint already processed.");
  }
  for (final entry in getEntries(sourcePath)) {
    final childName = _childName(sourcePath, entry.endpoint);

    final targetBasename = childName ?? entry.name;
    final targetPath = pathlib.join(target.path, targetBasename);

    switch (entry.type) {
      case GithubFsEntryType.dir:
        _updateDirRecursive(entry.endpoint, Directory(targetPath),
            processed.plusElement(sourcePath.string));
        break;
      case GithubFsEntryType.file:
        _updateFile(entry, File(targetPath));
        break;
      default:
        throw ArgumentError.value(entry.type);
    }
  }
}