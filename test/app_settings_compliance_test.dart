import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/core/constants/app_build_config.dart';
import 'package:meeting_assistant2/core/constants/app_constants.dart';
import 'package:meeting_assistant2/core/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app store build excludes restricted model choices', () async {
    expect(AppBuildConfig.appStoreComplianceMode, isTrue);
    expect(AppBuildConfig.allowRestrictedModels, isFalse);
    expect(AppSettings.availableLlmModelIds, isNot(contains('exaone35_7b')));
  });

  test(
    'init rewrites persisted restricted LLM selection to safe default',
    () async {
      SharedPreferences.setMockInitialValues({
        'selectedLlmModel': 'exaone35_7b',
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
    },
  );

  test('restricted LLM file and URL helpers fall back in app store mode', () {
    expect(
      AppSettings.llmModelFileFor('exaone35_7b'),
      AppConstants.llmModelFileGemma4E2B,
    );
    expect(
      AppSettings.llmDownloadUrlFor('exaone35_7b'),
      AppConstants.llmDownloadUrlGemma4E2B,
    );
  });
}
