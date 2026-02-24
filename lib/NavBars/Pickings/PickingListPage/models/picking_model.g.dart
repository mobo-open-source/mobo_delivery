// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'picking_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PickingAdapter extends TypeAdapter<Picking> {
  @override
  final int typeId = 0;

  @override
  Picking read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Picking(
      id: fields[0] as String,
      item: fields[1] as String,
      scheduledDate: fields[2] as String,
      deadlineDate: fields[3] as String,
      state: fields[4] as String,
      partner: fields[5] as String,
      origin: fields[6] as String,
      moveIds: (fields[7] as List)
          .map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      warehouseName: fields[8] as String,
      partnerId: fields[9] as String,
      pickingTypeCode: fields[10] as String,
      pickingTypeId: fields[11] as String,
      pickingTypeIdInt: fields[12] as String,
      productAvailability: fields[13] as String,
      returnCount: fields[14] as String,
      showCheckAvailability: fields[15] as String,
      locationIdInt: fields[16] as String,
      locationDestIdInt: fields[17] as String,
      moveType: fields[18] as String,
      userId: fields[19] as String,
      userIdInt: fields[20] as String,
      groupId: fields[21] as String,
      groupIdInt: fields[22] as String,
      companyId: fields[23] as String,
      companyIdInt: fields[24] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Picking obj) {
    writer
      ..writeByte(25)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.item)
      ..writeByte(2)
      ..write(obj.scheduledDate)
      ..writeByte(3)
      ..write(obj.deadlineDate)
      ..writeByte(4)
      ..write(obj.state)
      ..writeByte(5)
      ..write(obj.partner)
      ..writeByte(6)
      ..write(obj.origin)
      ..writeByte(7)
      ..write(obj.moveIds)
      ..writeByte(8)
      ..write(obj.warehouseName)
      ..writeByte(9)
      ..write(obj.partnerId)
      ..writeByte(10)
      ..write(obj.pickingTypeCode)
      ..writeByte(11)
      ..write(obj.pickingTypeId)
      ..writeByte(12)
      ..write(obj.pickingTypeIdInt)
      ..writeByte(13)
      ..write(obj.productAvailability)
      ..writeByte(14)
      ..write(obj.returnCount)
      ..writeByte(15)
      ..write(obj.showCheckAvailability)
      ..writeByte(16)
      ..write(obj.locationIdInt)
      ..writeByte(17)
      ..write(obj.locationDestIdInt)
      ..writeByte(18)
      ..write(obj.moveType)
      ..writeByte(19)
      ..write(obj.userId)
      ..writeByte(20)
      ..write(obj.userIdInt)
      ..writeByte(21)
      ..write(obj.groupId)
      ..writeByte(22)
      ..write(obj.groupIdInt)
      ..writeByte(23)
      ..write(obj.companyId)
      ..writeByte(24)
      ..write(obj.companyIdInt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
