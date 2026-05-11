class AppBuildConfig {
  AppBuildConfig._();

  /// App Store submission safe mode.
  ///
  /// Default is true so normal release builds do not expose Calendar
  /// AppleEvents or other review-sensitive features.
  static const bool appStoreComplianceMode = bool.fromEnvironment(
    'APP_STORE_COMPLIANCE_MODE',
    defaultValue: true,
  );

  /// Internal/dev builds may opt in with:
  /// --dart-define=APP_STORE_COMPLIANCE_MODE=false

  /// Calendar integration uses Calendar.app AppleEvents, so it is disabled in
  /// App Store mode. Re-enable only for internal builds that carry matching
  /// Info.plist usage strings and AppleEvent entitlements.
  static const bool enableCalendarIntegration =
      !appStoreComplianceMode &&
      bool.fromEnvironment('ENABLE_CALENDAR_INTEGRATION', defaultValue: false);
}
