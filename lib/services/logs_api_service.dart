// lib/services/logs_api_service.dart
// Gestation (Inclusion Criteria) Screening Log + Log of All Births.

import 'api_client.dart';

class LogsApiService {
  LogsApiService._();
  static final LogsApiService instance = LogsApiService._();

  Future<List<Map<String, dynamic>>> listGaChecks() async {
    final data = await ApiClient.instance.getList('/ga-check/');
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listGaCheckGap() async {
    final data = await ApiClient.instance.getList('/ga-check/gap');
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createGaCheck(Map<String, dynamic> payload) {
    return ApiClient.instance.post('/ga-check/', body: payload);
  }

  Future<Map<String, dynamic>> updateGaCheck(
    int id,
    Map<String, dynamic> payload,
  ) {
    return ApiClient.instance.put('/ga-check/$id', body: payload);
  }

  Future<Map<String, dynamic>> linkGaCheck(int id, String screeningId) {
    return ApiClient.instance.patch(
      '/ga-check/$id/link',
      body: {'screening_id': screeningId},
    );
  }

  Future<List<Map<String, dynamic>>> listBirths() async {
    final data = await ApiClient.instance.getList('/birth-log/');
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createBirth(Map<String, dynamic> payload) {
    return ApiClient.instance.post('/birth-log/', body: payload);
  }

  Future<Map<String, dynamic>> updateBirth(
    int id,
    Map<String, dynamic> payload,
  ) {
    return ApiClient.instance.put('/birth-log/$id', body: payload);
  }
}
