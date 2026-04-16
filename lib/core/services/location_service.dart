import 'dart:convert';

import 'package:flutter/services.dart';

class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  static const String _assetPath = 'assets/data/india_states_cities.json';

  Future<void>? _loadFuture;
  List<String> _states = const [];
  Map<String, List<String>> _stateCityMap = const {};

  Future<void> load() {
    return _loadFuture ??= _loadInternal();
  }

  Future<void> _loadInternal() async {
    final jsonString = await rootBundle.loadString(_assetPath);
    final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    final stateItems = (jsonMap['states'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    final states = <String>[];
    final stateCityMap = <String, List<String>>{};

    for (final item in stateItems) {
      final stateName = (item['name'] as String? ?? '').trim();
      if (stateName.isEmpty) continue;

      final cities =
          (item['cities'] as List<dynamic>? ?? const [])
              .map((city) => city.toString().trim())
              .where((city) => city.isNotEmpty)
              .toList()
            ..sort();

      states.add(stateName);
      stateCityMap[stateName] = cities;
    }

    states.sort();
    _states = List.unmodifiable(states);
    _stateCityMap = Map.unmodifiable(stateCityMap);
  }

  List<String> getStates() => _states;

  List<String> getCities(String state) =>
      List.unmodifiable(_stateCityMap[state] ?? const []);
}
