import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';

/// Provider for all fundraisers list
final fundraisersProvider = StreamProvider<List<Fundraiser>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllFundraisers();
});

/// Provider for a single fundraiser by ID
final fundraiserProvider =
    FutureProvider.family<Fundraiser?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.getFundraiserById(id);
});

/// Provider for fundraiser statistics
final fundraiserStatsProvider =
    StreamProvider.family<FundraiserStats, String>((ref, fundraiserId) {
  final db = ref.watch(databaseProvider);
  return db.watchFundraiserStats(fundraiserId);
});

/// Provider for fundraiser operations
final fundraiserServiceProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return FundraiserService(db);
});

class FundraiserService {
  final AppDatabase _db;

  FundraiserService(this._db);

  Future<void> deleteFundraiser(String id) async {
    await _db.deleteFundraiser(id);
  }
}
