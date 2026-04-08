import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../session/company_session_manager.dart';

class CompanyProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _companies = [];
  int? _selectedCompanyId;
  List<int> _selectedAllowedCompanyIds = [];
  bool _loading = false;
  bool _switching = false;
  String? _error;

  List<Map<String, dynamic>> get companies => _companies;
  int? get selectedCompanyId => _selectedCompanyId;
  List<int> get selectedAllowedCompanyIds => _selectedAllowedCompanyIds;
  bool get isLoading => _loading;
  bool get isSwitching => _switching;
  String? get error => _error;

  Map<String, dynamic>? get selectedCompany {
    if (_selectedCompanyId == null) return null;
    try {
      return _companies.firstWhere((c) => c['id'] == _selectedCompanyId);
    } catch (e) {
      return null;
    }
  }

  Future<void> setAllowedCompanies(List<int> allowedIds) async {
    final availableIds = _companies.map((c) => c['id'] as int).toSet();
    final filtered = allowedIds
        .where((id) => availableIds.contains(id))
        .toList();

    if (_selectedCompanyId != null && !filtered.contains(_selectedCompanyId)) {
      filtered.add(_selectedCompanyId!);
    }
    _selectedAllowedCompanyIds = filtered;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_allowed_company_ids',
      _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
    );

    if (_selectedCompanyId != null) {
      await CompanySessionManager.updateCompanySelection(
        companyId: _selectedCompanyId!,
        allowedCompanyIds: _selectedAllowedCompanyIds,
      );
    }
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  Future<void> initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final session = await CompanySessionManager.getCurrentSession();

      if (session == null || session.userId == null) {
        _companies = [];
        _selectedCompanyId = null;
        _loading = false;
        notifyListeners();
        return;
      }

      final userRes = await CompanySessionManager.safeCallKwWithoutCompany({
        'model': 'res.users',
        'method': 'read',
        'args': [
          [session.userId],
          ['company_id', 'company_ids'],
        ],
        'kwargs': {},
      });

      List<int> companyIds = [];
      int? currentCompanyId;
      if (userRes is List && userRes.isNotEmpty) {
        final row = userRes.first as Map<String, dynamic>;
        if (row['company_ids'] is List) {
          final raw = row['company_ids'] as List;
          companyIds = raw.whereType<int>().toList();
        }
        if (row['company_id'] is List &&
            (row['company_id'] as List).isNotEmpty) {
          currentCompanyId = (row['company_id'] as List).first as int?;
        }
      }

      if (companyIds.isEmpty) {
        _companies = [];
        _selectedCompanyId = currentCompanyId;
        _loading = false;
        notifyListeners();
        return;
      }

      final companiesRes = await CompanySessionManager.safeCallKwWithoutCompany({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', companyIds],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name asc',
        },
      });

      final serverCompanies = (companiesRes is List)
          ? companiesRes.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (serverCompanies.isNotEmpty) {
        _companies = serverCompanies;
      } else {
        _companies = [];
      }

      final prefs = await SharedPreferences.getInstance();
      final restoredId = prefs.getInt('selected_company_id');

      await prefs.remove('pending_company_id');

      final restoredAllowed =
          prefs
              .getStringList('selected_allowed_company_ids')
              ?.map((e) => int.tryParse(e) ?? -1)
              .where((e) => e > 0)
              .toList() ??
          [];

      int? desiredId =
          restoredId ??
          currentCompanyId ??
          (companyIds.isNotEmpty ? companyIds.first : null);
      _selectedCompanyId = desiredId;

      List<int> defaultAllowed = companyIds;
      final restoredValid = restoredAllowed
          .where((id) => companyIds.contains(id))
          .toList();
      _selectedAllowedCompanyIds = restoredValid.isNotEmpty
          ? restoredValid
          : defaultAllowed;

      if (_selectedCompanyId != null &&
          !_selectedAllowedCompanyIds.contains(_selectedCompanyId)) {
        _selectedAllowedCompanyIds = [
          ..._selectedAllowedCompanyIds,
          _selectedCompanyId!,
        ];
      }

      if (_selectedCompanyId == null ||
          !companyIds.contains(_selectedCompanyId)) {
        if (companyIds.isNotEmpty) {
          _selectedCompanyId = companyIds.first;
        }
      }

      if (_selectedCompanyId != null &&
          !_selectedAllowedCompanyIds.contains(_selectedCompanyId)) {
        _selectedAllowedCompanyIds = [
          ..._selectedAllowedCompanyIds,
          _selectedCompanyId!,
        ];
      }

      final prefs2 = await SharedPreferences.getInstance();
      if (_selectedCompanyId != null) {
        await prefs2.setInt('selected_company_id', _selectedCompanyId!);
      }
      await prefs2.setStringList(
        'selected_allowed_company_ids',
        _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
      );

      if (_selectedCompanyId != null) {
        await CompanySessionManager.updateCompanySelection(
          companyId: _selectedCompanyId!,
          allowedCompanyIds: _selectedAllowedCompanyIds,
        );
      }
    } catch (e) {
      if (_companies.isEmpty) {
        _error = e.toString();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCompaniesList() async {
    _loading = true;
    notifyListeners();

    try {
      final list = await CompanySessionManager.getAllowedCompaniesList();
      if (list.isNotEmpty) {
        _companies = list;
      }
    } catch (_) {
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> switchCompany(int companyId) async {
    if (_selectedCompanyId == companyId) return true;

    try {
      _switching = true;
      _error = null;
      notifyListeners();

      _selectedCompanyId = companyId;

      if (!_selectedAllowedCompanyIds.contains(companyId)) {
        _selectedAllowedCompanyIds = [..._selectedAllowedCompanyIds, companyId];
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('selected_company_id', companyId);
      await prefs.setStringList(
        'selected_allowed_company_ids',
        _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
      );

      await prefs.remove('pending_company_id');

      await CompanySessionManager.updateCompanySelection(
        companyId: companyId,
        allowedCompanyIds: _selectedAllowedCompanyIds,
      );

      await refreshCompaniesList();

      HapticFeedback.lightImpact();
      return true;
    } catch (e) {
      _error = e.toString();
      HapticFeedback.vibrate();
      notifyListeners();
      return false;
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  Future<void> toggleAllowedCompany(int companyId) async {
    if (_selectedAllowedCompanyIds.contains(companyId)) {
      if (companyId == _selectedCompanyId) {
        return;
      }
      _selectedAllowedCompanyIds = _selectedAllowedCompanyIds
          .where((id) => id != companyId)
          .toList();
    } else {
      _selectedAllowedCompanyIds = [..._selectedAllowedCompanyIds, companyId];
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_allowed_company_ids',
      _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
    );

    if (_selectedCompanyId != null) {
      await CompanySessionManager.updateCompanySelection(
        companyId: _selectedCompanyId!,
        allowedCompanyIds: _selectedAllowedCompanyIds,
      );
    }

    HapticFeedback.selectionClick();
    notifyListeners();
  }

  Future<void> selectAllCompanies() async {
    final allIds = _companies.map((c) => c['id'] as int).toList();
    await setAllowedCompanies(allIds);
  }

  Future<void> deselectAllCompanies() async {
    if (_selectedCompanyId != null) {
      await setAllowedCompanies([_selectedCompanyId!]);
    }
  }

  bool isCompanyAllowed(int companyId) {
    return _selectedAllowedCompanyIds.contains(companyId);
  }
}
