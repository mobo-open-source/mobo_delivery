import 'package:hive_ce/hive.dart';

/// A file/signature attachment captured while offline, queued in Hive and
/// replayed (uploaded to the picking's chatter as an `ir.attachment`) by
/// `PendingSyncService` once connectivity returns.
class PendingAttachment {
  final int pickingId;
  final String mimeType;
  final String base64File;
  final String fileName;
  final String? pickingName;

  PendingAttachment({
    required this.pickingId,
    required this.mimeType,
    required this.base64File,
    required this.fileName,
    this.pickingName,
  });
}

/// Hand-written Hive adapter (typeId 11) so no build_runner pass is needed.
class PendingAttachmentAdapter extends TypeAdapter<PendingAttachment> {
  @override
  final int typeId = 11;

  @override
  PendingAttachment read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return PendingAttachment(
      pickingId: fields[0] as int,
      mimeType: fields[1] as String,
      base64File: fields[2] as String,
      fileName: fields[3] as String,
      pickingName: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PendingAttachment obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.pickingId)
      ..writeByte(1)
      ..write(obj.mimeType)
      ..writeByte(2)
      ..write(obj.base64File)
      ..writeByte(3)
      ..write(obj.fileName)
      ..writeByte(4)
      ..write(obj.pickingName);
  }
}
