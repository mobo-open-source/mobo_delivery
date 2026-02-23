// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'move_line.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MoveLineAdapter extends TypeAdapter<MoveLine> {
  @override
  final int typeId = 13;

  @override
  MoveLine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MoveLine(
      id: fields[0] as int,
      pickingId: fields[1] as int,
      data: (fields[2] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, MoveLine obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.pickingId)
      ..writeByte(2)
      ..write(obj.data);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveLineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
