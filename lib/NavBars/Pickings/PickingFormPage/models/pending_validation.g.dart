// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_validation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PendingValidationAdapter extends TypeAdapter<PendingValidation> {
  @override
  final int typeId = 6;

  @override
  PendingValidation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingValidation(
      pickingId: fields[0] as int,
      pickingData: (fields[1] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, PendingValidation obj) {
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
      other is PendingValidationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
