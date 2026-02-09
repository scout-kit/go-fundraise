import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:go_fundraise/features/fundraiser/screens/fundraiser_list_screen.dart';
import 'package:go_fundraise/features/import/screens/import_screen.dart';
import 'package:go_fundraise/features/pickup/screens/pickup_search_screen.dart';
import 'package:go_fundraise/features/pickup/screens/customer_detail_screen.dart';
import 'package:go_fundraise/features/pickup/screens/items_sheet_screen.dart';
import 'package:go_fundraise/features/photo/screens/photo_gallery_screen.dart';
import 'package:go_fundraise/features/export/screens/export_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Enable URL updates for push/pop navigation (not just go)
  GoRouter.optionURLReflectsImperativeAPIs = true;

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const FundraiserListScreen(),
      ),
      GoRoute(
        path: '/import',
        name: 'import',
        builder: (context, state) => const ImportScreen(),
      ),
      GoRoute(
        path: '/fundraiser/:fundraiserId',
        name: 'pickup',
        builder: (context, state) {
          final fundraiserId = state.pathParameters['fundraiserId']!;
          return PickupSearchScreen(fundraiserId: fundraiserId);
        },
        routes: [
          GoRoute(
            path: 'customer/:customerId',
            name: 'customer-detail',
            builder: (context, state) {
              final fundraiserId = state.pathParameters['fundraiserId']!;
              final customerId = state.pathParameters['customerId']!;
              return CustomerDetailScreen(
                fundraiserId: fundraiserId,
                customerId: customerId,
              );
            },
          ),
          GoRoute(
            path: 'photos',
            name: 'photos',
            builder: (context, state) {
              final fundraiserId = state.pathParameters['fundraiserId']!;
              return PhotoGalleryScreen(fundraiserId: fundraiserId);
            },
          ),
          GoRoute(
            path: 'export',
            name: 'export',
            builder: (context, state) {
              final fundraiserId = state.pathParameters['fundraiserId']!;
              return ExportScreen(fundraiserId: fundraiserId);
            },
          ),
          GoRoute(
            path: 'items',
            name: 'items-sheet',
            builder: (context, state) {
              final fundraiserId = state.pathParameters['fundraiserId']!;
              return ItemsSheetScreen(fundraiserId: fundraiserId);
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});
