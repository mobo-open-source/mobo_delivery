// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'operation_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OperationTypeAdapter extends TypeAdapter<OperationType> {
  @override
  final int typeId = 10;

  @override
  OperationType read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OperationType(
      id: fields[0] as int,
      name: fields[1] as String,
      defaultLocationSrcId: fields[2] as int?,
      defaultLocationDestId: fields[3] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, OperationType obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.defaultLocationSrcId)
      ..writeByte(3)
      ..write(obj.defaultLocationDestId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
