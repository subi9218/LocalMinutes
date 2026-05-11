import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/constants/app_build_config.dart';
import 'package:local_minutes/core/constants/app_constants.dart';
import 'package:local_minutes/core/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app store compliance mode is enabled by default', () async {
    expect(AppBuildConfig.appStoreComplianceMode, isTrue);
    expect(AppSettings.availableLlmModelIds, ['gemma4_e2b', 'qwen25_7b']);
  });

  test('init rewrites unsupported LLM selection to safe default', () async {
    SharedPreferences.setMockInitialValues({
      'selectedLlmModel': 'unsupported_model',
      'autoAddToCalendar': true,
    });

    await AppSettings.init();

    expect(
      AppSettings.instance.selectedLlmModel,
      AppSettings.defaultLlmModelId,
    );
    expect(
      AppSettings.instance.rawSelectedLlmModelForDiagnostics,
      AppSettings.defaultLlmModelId,
    );
    expect(
      AppSettings.instance.currentLlmModelFile,
      AppConstants.llmModelFileGemma4E2B,
    );
    expect(AppSettings.instance.autoAddToCalendar, isFalse);
  });
}
