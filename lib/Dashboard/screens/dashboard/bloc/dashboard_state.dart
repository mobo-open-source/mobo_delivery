import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Immutable state class for the DashboardBloc.
///
/// Holds all UI-relevant data for the main dashboard screen:
///   • Loading status
///   • Currently selected bottom navigation tab
///   • User profile basics (name, email, avatar bytes)
///   • List of navigation pages/tabs configuration
///
/// Uses [Equatable] for efficient state comparison in BlocBuilder.
/// All fields are immutable; use [copyWith] to create updated instances.
class DashboardState extends Equatable {
  final bool isLoading;
  final int currentIndex;
  final String? userName;
  final String? mail;
  final Uint8List? profilePicBytes;

  /// Configuration of all bottom navigation tabs/pages.
  ///
  /// Each map should contain at minimum:
  ///   - 'title': String – AppBar title
  ///   - 'label': String – Bottom nav label
  ///   - 'icon': IconData – Bottom nav icon
  ///   - 'route': Widget? – The page widget (null for "More"/special tabs)
  final List<Map<String, dynamic>> pages;

  const DashboardState({
    this.isLoading = false,
    this.currentIndex = 0,
    this.userName,
    this.mail,
    this.profilePicBytes,
    this.pages = const [],
  });

  /// Creates a new instance with some fields replaced while keeping others unchanged.
  ///
  /// Typical usage in Bloc:
  /// ```dart
  /// emit(state.copyWith(
  ///   isLoading: true,
  ///   profilePicBytes: newBytes,
  /// ));
  /// ```
  DashboardState copyWith({
    bool? isLoading,
    int? currentIndex,
    String? userName,
    String? mail,
    Uint8List? profilePicBytes,
    List<Map<String, dynamic>>? pages,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      currentIndex: currentIndex ?? this.currentIndex,
      userName: userName ?? this.userName,
      mail: mail ?? this.mail,
      profilePicBytes: profilePicBytes ?? this.profilePicBytes,
      pages: pages ?? this.pages,
    );
  }

  /// List of properties used for equality comparison.
  ///
  /// Important: [Uint8List] is compared by reference (identity),
  /// not by content. If you need deep byte equality, consider using
  /// a hash or a custom wrapper class in the future.
  @override
  List<Object?> get props =>
      [isLoading, currentIndex, userName, mail, profilePicBytes, pages];
}
