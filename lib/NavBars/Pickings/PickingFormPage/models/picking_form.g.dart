// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'picking_form.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PickingFormAdapter extends TypeAdapter<PickingForm> {
  @override
  final int typeId = 1;

  @override
  PickingForm read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PickingForm(
      id: fields[0] as int,
      name: fields[1] as String,
      partnerId: (fields[2] as List?)?.cast<dynamic>(),
      pickingTypeId: (fields[3] as List?)?.cast<dynamic>(),
      scheduledDate: fields[4] as String?,
      dateDeadline: fields[5] as String?,
      dateDone: fields[6] as String?,
      productsAvailability: fields[7] as String?,
      origin: fields[8] as String?,
      state: fields[9] as String,
      note: fields[10] as String?,
      moveType: fields[11] as String?,
      userId: (fields[12] as List?)?.cast<dynamic>(),
      groupId: (fields[13] as List?)?.cast<dynamic>(),
      companyId: (fields[14] as List?)?.cast<dynamic>(),
      returnCount: fields[15] as int,
      returnIds: (fields[16] as List?)?.cast<int>(),
      showCheckAvailability: fields[17] as bool,
      pickingTypeCode: fields[18] as String?,
      locationIdInt: fields[19] as int?,
      locationDestIdInt: fields[20] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, PickingForm obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.partnerId)
      ..writeByte(3)
      ..write(obj.pickingTypeId)
      ..writeByte(4)
      ..write(obj.scheduledDate)
      ..writeByte(5)
      ..write(obj.dateDeadline)
      ..writeByte(6)
      ..write(obj.dateDone)
      ..writeByte(7)
      ..write(obj.productsAvailability)
      ..writeByte(8)
      ..write(obj.origin)
      ..writeByte(9)
      ..write(obj.state)
      ..writeByte(10)
      ..write(obj.note)
      ..writeByte(11)
      ..write(obj.moveType)
      ..writeByte(12)
      ..write(obj.userId)
      ..writeByte(13)
      ..write(obj.groupId)
      ..writeByte(14)
      ..write(obj.companyId)
      ..writeByte(15)
      ..write(obj.returnCount)
      ..writeByte(16)
      ..write(obj.returnIds)
      ..writeByte(17)
      ..write(obj.showCheckAvailability)
      ..writeByte(18)
      ..write(obj.pickingTypeCode)
      ..writeByte(19)
      ..write(obj.locationIdInt)
      ..writeByte(20)
      ..write(obj.locationDestIdInt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickingFormAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
