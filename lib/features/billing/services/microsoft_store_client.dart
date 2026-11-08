import 'package:flutter/services.dart';

class MicrosoftProduct {
  const MicrosoftProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.period,
    required this.owned,
  });
  final String id, title, price, period;
  final bool owned;
  factory MicrosoftProduct.fromMap(Map<dynamic, dynamic> data) =>
      MicrosoftProduct(
        id: data['id'] as String,
        title: data['title'] as String,
        price: data['price'] as String,
        period: data['period'] as String,
        owned: data['owned'] == true,
      );
}

abstract interface class MicrosoftStoreClient {
  Future<List<MicrosoftProduct>> products(String monthlyId, String annualId);
  Future<String> purchase(String id);
  Future<String> purchaseKey(String ticket, String publisherUserId);
}

class WindowsMicrosoftStoreClient implements MicrosoftStoreClient {
  static const _channel = MethodChannel('ripot/microsoft_store');
  @override
  Future<List<MicrosoftProduct>> products(
    String monthlyId,
    String annualId,
  ) async {
    final values = await _channel.invokeListMethod<dynamic>('products', {
      'monthlyId': monthlyId,
      'annualId': annualId,
    });
    return (values ?? [])
        .map((v) => MicrosoftProduct.fromMap(v as Map))
        .toList();
  }

  @override
  Future<String> purchase(String id) async =>
      await _channel.invokeMethod<String>('purchase', {'id': id}) ?? 'error';
  @override
  Future<String> purchaseKey(String ticket, String publisherUserId) async =>
      await _channel.invokeMethod<String>('purchaseKey', {
        'serviceTicket': ticket,
        'publisherUserId': publisherUserId,
      }) ??
      '';
}
