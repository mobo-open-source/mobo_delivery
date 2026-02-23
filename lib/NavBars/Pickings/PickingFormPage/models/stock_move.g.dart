// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stock_move.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StockMoveAdapter extends TypeAdapter<StockMove> {
  @override
  final int typeId = 5;

  @override
  StockMove read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StockMove(
      id: fields[0] as int,
      productId: (fields[1] as List?)?.cast<dynamic>(),
      productUomQty: fields[2] as double,
      productUomId: fields[8] as int?,
      quantity: fields[3] as double,
      pickingId: (fields[4] as List?)?.cast<dynamic>(),
      locationId: (fields[5] as List?)?.cast<dynamic>(),
      lotId: (fields[6] as List?)?.cast<dynamic>(),
      quantityProductUom: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, StockMove obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.productUomQty)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.pickingId)
      ..writeByte(5)
      ..write(obj.locationId)
      ..writeByte(6)
      ..write(obj.lotId)
      ..writeByte(7)
      ..write(obj.quantityProductUom)
      ..writeByte(8)
      ..write(obj.productUomId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockMoveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
