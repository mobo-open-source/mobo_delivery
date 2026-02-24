// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_picking.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReturnPickingAdapter extends TypeAdapter<ReturnPicking> {
  @override
  final int typeId = 14;

  @override
  ReturnPicking read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReturnPicking(
      id: fields[0] as int,
      pickingId: fields[1] as int,
      name: fields[2] as String,
      partnerId: fields[3] as int,
      scheduledDate: fields[4] as String,
      origin: fields[5] as String,
      state: fields[6] as String,
      data: (fields[7] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, ReturnPicking obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.pickingId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.partnerId)
      ..writeByte(4)
      ..write(obj.scheduledDate)
      ..writeByte(5)
      ..write(obj.origin)
      ..writeByte(6)
      ..write(obj.state)
      ..writeByte(7)
      ..write(obj.data);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReturnPickingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
