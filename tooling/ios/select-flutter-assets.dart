// Select iOS resources from Flutter's staged framework before it is embedded.
// Use the same manifest codec as Flutter so Unicode keys, variants and DPRs
// remain exactly what the engine expects.
import 'dart:io';
import 'dart:typed_data';

import 'package:standard_message_codec/standard_message_codec.dart';

void main(List<String> args) {
  final root = Directory(args.single);
  const skill = 'assets/skills/pet-theme';
  final file = File('${root.path}/AssetManifest.bin');
  const codec = StandardMessageCodec();
  final manifest =
      codec.decodeMessage(ByteData.sublistView(file.readAsBytesSync())) as Map;
  final oldLength = manifest.length;
  manifest.removeWhere((key, _) => (key as String).startsWith('$skill/'));
  final directory = Directory('${root.path}/$skill');
  final hasFiles = directory.existsSync();
  if (!hasFiles && manifest.length == oldLength) return;
  if (manifest.length != oldLength) {
    final bytes = codec.encodeMessage(manifest)!;
    final temp = File('${file.path}.tmp');
    temp.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    temp.renameSync(file.path);
  }
  if (hasFiles) directory.deleteSync(recursive: true);
  stdout.writeln('updated');
}
