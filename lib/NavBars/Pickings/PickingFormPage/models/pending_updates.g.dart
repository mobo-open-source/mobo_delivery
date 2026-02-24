// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_updates.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PendingUpdatesAdapter extends TypeAdapter<PendingUpdates> {
  @override
  final int typeId = 7;

  @override
  PendingUpdates read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingUpdates(
      pickingId: fields[0] as int,
      pickingData: (fields[1] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, PendingUpdates obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.pickingId)
      ..writeByte(1)
      ..write(obj.pickingData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingUpdatesAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
