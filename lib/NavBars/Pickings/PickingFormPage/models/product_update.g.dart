// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_update.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductUpdatesAdapter extends TypeAdapter<ProductUpdates> {
  @override
  final int typeId = 9;

  @override
  ProductUpdates read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProductUpdates(
      pickingId: fields[0] as int,
      productData: (fields[1] as Map).cast<String, dynamic>(),
      pickingName: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ProductUpdates obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.pickingId)
      ..writeByte(1)
      ..write(obj.productData)
      ..writeByte(2)
      ..write(obj.pickingName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductUpdatesAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
