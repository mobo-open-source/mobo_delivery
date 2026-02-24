// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partner_details.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PartnerDetailsAdapter extends TypeAdapter<PartnerDetails> {
  @override
  final int typeId = 12;

  @override
  PartnerDetails read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PartnerDetails(
      id: fields[0] as int,
      address: fields[1] as String?,
      imageBase64: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PartnerDetails obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.address)
      ..writeByte(2)
      ..write(obj.imageBase64);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerDetailsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
