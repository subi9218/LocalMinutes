import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import '../constants/app_build_config.dart';

/// 모델 파일 다운로드 서비스
///
/// - dart:io HttpClient 사용 (추가 패키지 없음)
/// - 리다이렉트 자동 추적 (HuggingFace CDN)
/// - HuggingFace Bearer 토큰 지원
/// - 진행률 / 속도 콜백
/// - 취소 지원 (cancel())
/// - 임시 파일(.tmp) → 완료 후 이름 변경 (부분 다운로드 방지)
class ModelDownloadService {
  StreamSubscription<List<int>>? _subscription;
  IOSink? _sink;
  bool _cancelled = false;

  /// 진행 중인 다운로드의 completer — cancel()에서 즉시 완료시키기 위함
  Completer<void>? _activeCompleter;

  bool get isCancelled => _cancelled;

  /// 파일 다운로드
  ///
  /// [url]: 다운로드 URL
  /// [destPath]: 최종 저장 경로
  /// [bearerToken]: HuggingFace 인증 토큰 (없으면 null)
  /// [onProgress]: (received, total, speedMBps) — total=-1이면 미확인
  Future<void> download({
    required String url,
    required String destPath,
    String? bearerToken,

    /// 미리 알려진 모델 크기(바이트) — 디스크 공간 사전 검사용. 0이면 검사 생략.
    int expectedBytes = 0,
    void Function(int received, int total, double speedMBps)? onProgress,
  }) async {
    _cancelled = false;
    final uri = _parseDownloadUri(url);

    // 디스크 공간 사전 검사 — 모델 크기 + 여유 200MB 미만이면 즉시 실패
    if (expectedBytes > 0) {
      try {
        final destDir = Directory(destPath).parent;
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        // df -k로 사용 가능 공간(KB) 조회
        final df = await Process.run('df', ['-k', destDir.path]);
        if (df.exitCode == 0) {
          final lines = (df.stdout ?? '').toString().split('\n');
          if (lines.length >= 2) {
            final cols = lines[1].split(RegExp(r'\s+'));
            // df -k 출력: Filesystem 1024-blocks Used Available Capacity ...
            if (cols.length >= 4) {
              final availKb = int.tryParse(cols[3]) ?? -1;
              if (availKb > 0) {
                final availBytes = availKb * 1024;
                final required = expectedBytes + 200 * 1024 * 1024;
                if (availBytes < required) {
                  final neededMb = ((required - availBytes) / 1024 / 1024)
                      .ceil();
                  throw ModelDownloadException.diskSpace(
                    '저장 공간이 부족합니다.\n'
                    '필요한 모델 크기: 약 ${_fmtBytes(expectedBytes)}\n'
                    '현재 사용 가능: ${_fmtBytes(availBytes)}\n'
                    '추가 필요: 약 ${neededMb}MB\n\n'
                    '불필요한 파일을 정리하거나 저장 공간을 확보한 뒤 다시 시도하세요.',
                  );
                }
              }
            }
          }
        }
      } on ModelDownloadException {
        rethrow;
      } catch (_) {
        // df 호출 실패 시는 무시하고 계속 진행 (디스크 검사는 베스트 에포트)
      }
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 60);

    File? tempFile;
    IOSink? sink;

    try {
      final response = await _getWithRedirects(client, uri, bearerToken);

      // 상태 코드 확인
      if (response.statusCode == 401) {
        throw ModelDownloadException.authRequired(
          AppBuildConfig.appStoreComplianceMode
              ? '모델 제공 사이트에서 접근 확인이 필요한 파일입니다.\n'
                    '모델 페이지에서 사용 조건을 확인한 뒤 다시 시도하세요.'
              : '로그인이 필요한 모델입니다.\n'
                    '모델 페이지에서 사용 동의 또는 접근 조건을 확인한 뒤 다시 시도하세요.',
        );
      }
      if (response.statusCode == 403) {
        throw ModelDownloadException.authRequired(
          AppBuildConfig.appStoreComplianceMode
              ? '모델 파일 접근 권한을 확인할 수 없습니다.\n'
                    '모델 제공 페이지에서 사용 조건을 확인한 뒤 다시 시도하세요.'
              : '모델 파일 접근 권한이 없습니다.\n'
                    '모델 페이지에서 사용 약관과 접근 조건을 확인한 뒤 다시 시도하세요.',
        );
      }
      if (response.statusCode == 404) {
        throw const ModelDownloadException.httpError(
          '모델 파일을 찾을 수 없습니다.\n'
          '다운로드 URL이 바뀌었을 수 있습니다. URL을 확인한 뒤 다시 시도하세요.',
        );
      }
      if (response.statusCode == 429) {
        throw const ModelDownloadException.serverUnavailable(
          '다운로드 요청이 너무 많아 잠시 제한되었습니다.\n'
          '몇 분 뒤 다시 시도하세요.',
        );
      }
      if (response.statusCode >= 500) {
        throw ModelDownloadException.serverUnavailable(
          '모델 서버가 일시적으로 응답하지 않습니다. (HTTP ${response.statusCode})\n'
          '잠시 후 다시 시도하세요.',
        );
      }
      if (response.statusCode != 200) {
        throw ModelDownloadException.httpError(
          '다운로드를 시작하지 못했습니다. (HTTP ${response.statusCode})\n'
          '네트워크 상태와 다운로드 URL을 확인한 뒤 다시 시도하세요.',
        );
      }

      final total = response.contentLength; // -1 이면 미확인
      final tempPath = '$destPath.tmp';
      tempFile = File(tempPath);
      await tempFile.parent.create(recursive: true);

      sink = tempFile.openWrite();
      _sink = sink;

      int received = 0;
      var lastTick = DateTime.now();
      int lastReceived = 0;

      final completer = Completer<void>();
      _activeCompleter = completer;

      // 스톨 감시 — 본문 수신이 일정 시간(45초) 멈추면 중단시킨다.
      // (connectionTimeout/idleTimeout은 본문 중간 정체를 끊지 못함)
      var lastProgressAt = DateTime.now();
      Timer? stallTimer;
      stallTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (completer.isCompleted) {
          stallTimer?.cancel();
          return;
        }
        final stalledFor = DateTime.now().difference(lastProgressAt);
        if (stalledFor >= const Duration(seconds: 45)) {
          stallTimer?.cancel();
          _subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              const ModelDownloadException.networkError(
                '다운로드가 멈춰 응답이 없습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
              ),
            );
          }
        }
      });

      _subscription = response.listen(
        (chunk) {
          if (_cancelled) {
            _subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const ModelDownloadException.cancelled());
            }
            return;
          }

          sink!.add(chunk);
          received += chunk.length;
          lastProgressAt = DateTime.now();

          // 500ms마다 진행률 콜백
          final now = DateTime.now();
          final ms = now.difference(lastTick).inMilliseconds;
          if (ms >= 500) {
            final speed = (received - lastReceived) / ms * 1000 / (1024 * 1024);
            onProgress?.call(received, total, speed);
            lastTick = now;
            lastReceived = received;
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      try {
        await completer.future;
      } finally {
        stallTimer.cancel();
      }

      await sink.flush();
      await sink.close();
      _sink = null;

      if (_cancelled) {
        await tempFile.delete().catchError((_) => tempFile!);
        throw const ModelDownloadException.cancelled();
      }

      if (total > 0 && received < total) {
        throw ModelDownloadException.networkError(
          '다운로드가 중간에 끊겼습니다.\n'
          '${_fmtBytes(received)} / ${_fmtBytes(total)}까지만 받았습니다. '
          '네트워크 상태를 확인한 뒤 다시 시도하세요.',
        );
      }

      // 임시 파일 → 최종 파일로 이름 변경
      final destFile = File(destPath);
      if (await destFile.exists()) await destFile.delete();
      await tempFile.rename(destPath);
      onProgress?.call(received, total < 0 ? received : total, 0);
    } catch (e) {
      // 정리
      await sink?.close().catchError((_) {});
      _sink = null;
      final tp = '$destPath.tmp';
      await File(tp).delete().catchError((_) => File(tp));

      if (e is ModelDownloadException) rethrow;
      if (e is SocketException) {
        throw ModelDownloadException.networkError(
          '네트워크 연결에 실패했습니다.\n'
          '인터넷 연결 또는 방화벽/VPN 설정을 확인한 뒤 다시 시도하세요.\n\n'
          '상세: ${e.message}',
        );
      }
      if (e is HandshakeException) {
        throw ModelDownloadException.networkError(
          '보안 연결에 실패했습니다.\n'
          '네트워크 프록시, VPN, 회사 보안 프로그램이 다운로드를 막는지 확인하세요.\n\n'
          '상세: $e',
        );
      }
      if (e is FileSystemException) {
        final code = e.osError?.errorCode;
        if (code == 28) {
          throw ModelDownloadException.diskSpace(
            '저장 공간이 부족해서 모델 파일을 저장하지 못했습니다.\n'
            '디스크 공간을 확보한 뒤 다시 시도하세요.',
          );
        }
        if (code == 13 || code == 1) {
          throw ModelDownloadException.permission(
            '모델 폴더에 파일을 저장할 권한이 없습니다.\n'
            '앱을 다시 실행하거나, 설정에서 저장 위치 권한을 확인한 뒤 다시 시도하세요.',
          );
        }
        throw ModelDownloadException.fileSystem(
          '모델 파일을 저장하지 못했습니다.\n'
          '저장 위치와 디스크 상태를 확인한 뒤 다시 시도하세요.\n\n'
          '상세: ${e.message}',
        );
      }
      throw ModelDownloadException.networkError(
        '다운로드 중 오류가 발생했습니다.\n'
        '네트워크 상태를 확인한 뒤 다시 시도하세요.\n\n'
        '상세: $e',
      );
    } finally {
      client.close(force: true);
      _subscription = null;
      _activeCompleter = null;
    }
  }

  /// ZIP 파일을 다운로드한 뒤 [extractDir]에 압축 해제한다.
  ///
  /// Core ML의 `.mlmodelc`는 디렉터리 번들이라 일반 파일 다운로드만으로는
  /// 사용할 수 없다. 다운로드는 기존 임시 파일/취소/공간 검사 흐름을 재사용하고,
  /// 압축 해제 후 [markerPath]가 생겼는지 확인한다.
  Future<void> downloadAndExtractZip({
    required String url,
    required String destZipPath,
    required String extractDir,
    required String markerPath,
    String? bearerToken,
    int expectedBytes = 0,
    void Function(int received, int total, double speedMBps)? onProgress,
  }) async {
    await download(
      url: url,
      destPath: destZipPath,
      bearerToken: bearerToken,
      expectedBytes: expectedBytes > 0 ? expectedBytes * 2 : 0,
      onProgress: onProgress,
    );

    try {
      final marker = FileSystemEntity.typeSync(markerPath);
      if (marker != FileSystemEntityType.notFound) {
        if (marker == FileSystemEntityType.directory) {
          await Directory(markerPath).delete(recursive: true);
        } else {
          await File(markerPath).delete();
        }
      }
      await Directory(extractDir).create(recursive: true);
      // ~1.2GB 압축 해제를 메인 아이솔레이트에서 동기로 풀면 UI가 멈추므로
      // 백그라운드 아이솔레이트로 분리한다. extractFileToDisk는
      // package:archive/archive_io.dart의 최상위 함수라 Isolate.run에서 호출 가능.
      await Isolate.run(() => extractFileToDisk(destZipPath, extractDir));
      final extracted = FileSystemEntity.typeSync(markerPath);
      if (extracted == FileSystemEntityType.notFound) {
        throw ModelDownloadException.fileSystem(
          '가속팩 압축을 풀었지만 필요한 파일을 찾지 못했습니다.\n'
          '다운로드 파일이 손상되었을 수 있습니다. 다시 시도하세요.',
        );
      }

      // archive 패키지는 개별 파일 쓰기 실패를 조용히 삼키므로, 마커가
      // 존재해도 내용이 비었을 수 있다. 기본 무결성 검사로 부분/손상 해제를 잡는다.
      var contentOk = false;
      if (extracted == FileSystemEntityType.directory) {
        await for (final entity
            in Directory(markerPath).list(recursive: true)) {
          if (entity is File && await entity.length() > 0) {
            contentOk = true;
            break;
          }
        }
      } else {
        contentOk = await File(markerPath).length() > 0;
      }
      if (!contentOk) {
        // 부분 해제된 마커 제거 후 실패 처리
        if (extracted == FileSystemEntityType.directory) {
          await Directory(markerPath).delete(recursive: true).catchError(
            (_) => Directory(markerPath),
          );
        } else {
          await File(markerPath).delete().catchError((_) => File(markerPath));
        }
        throw const ModelDownloadException.fileSystem(
          '가속팩 압축 해제가 불완전합니다. 파일이 손상되었을 수 있으니 다시 시도하세요.',
        );
      }

      // 압축 해제 성공 — 더 이상 필요 없는 원본 zip(~1.2GB)을 정리한다.
      // (예전엔 남겨둬서 사용자 디스크를 영구히 점유했다)
      await File(destZipPath).delete().catchError((_) => File(destZipPath));
    } on ModelDownloadException {
      rethrow;
    } catch (e) {
      throw ModelDownloadException.fileSystem(
        '가속팩 압축 해제 중 오류가 발생했습니다.\n'
        '저장 공간과 모델 폴더 권한을 확인한 뒤 다시 시도하세요.\n\n'
        '상세: $e',
      );
    }
  }

  /// 진행 중인 다운로드 취소
  void cancel() {
    _cancelled = true;
    _subscription?.cancel();
    _sink?.close().catchError((_) {});
    // 구독을 취소하면 더 이상 청크 콜백이 오지 않으므로, 진행 중인
    // download()의 `await completer.future`가 영원히 멈춘다. 직접 완료시켜
    // finally 정리(client.close, .tmp 삭제)가 실행되게 한다.
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.completeError(const ModelDownloadException.cancelled());
    }
  }

  /// HuggingFace 리다이렉트 (최대 5회) 추적
  Future<HttpClientResponse> _getWithRedirects(
    HttpClient client,
    Uri uri,
    String? bearerToken, {
    int maxRedirects = 5,
  }) async {
    var currentUri = uri;
    for (var i = 0; i < maxRedirects; i++) {
      final req = await client.getUrl(currentUri);
      if (bearerToken != null) {
        req.headers.set('Authorization', 'Bearer $bearerToken');
      }
      req.headers.set('User-Agent', 'LocalMinutes/1.0');

      final res = await req.close();

      // 리다이렉트 처리
      if (res.statusCode == 301 ||
          res.statusCode == 302 ||
          res.statusCode == 303 ||
          res.statusCode == 307 ||
          res.statusCode == 308) {
        final location = res.headers.value('location');
        if (location == null) break;
        await res.drain<void>(); // 리다이렉트 응답 버리기
        currentUri = currentUri.resolve(location);
        continue;
      }

      return res;
    }
    throw const ModelDownloadException.networkError(
      '다운로드 주소가 너무 많이 이동했습니다.\n'
      '다운로드 URL을 확인한 뒤 다시 시도하세요.',
    );
  }

  Uri _parseDownloadUri(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const ModelDownloadException.invalidUrl(
        '다운로드 URL이 비어 있습니다.\n'
        '기본 URL로 되돌리거나 올바른 주소를 입력하세요.',
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const ModelDownloadException.invalidUrl(
        '다운로드 URL 형식이 올바르지 않습니다.\n'
        'https:// 로 시작하는 전체 주소를 입력하세요.',
      );
    }
    return uri;
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(0)}MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }
}

// ── 예외 ──────────────────────────────────────────────────────────────────────

enum ModelDownloadErrorCode {
  authRequired,
  httpError,
  networkError,
  serverUnavailable,
  diskSpace,
  permission,
  fileSystem,
  invalidUrl,
  cancelled,
}

class ModelDownloadException implements Exception {
  final ModelDownloadErrorCode code;
  final String message;
  const ModelDownloadException({required this.code, required this.message});
  const ModelDownloadException.authRequired(this.message)
    : code = ModelDownloadErrorCode.authRequired;
  const ModelDownloadException.httpError(this.message)
    : code = ModelDownloadErrorCode.httpError;
  const ModelDownloadException.networkError(this.message)
    : code = ModelDownloadErrorCode.networkError;
  const ModelDownloadException.serverUnavailable(this.message)
    : code = ModelDownloadErrorCode.serverUnavailable;
  const ModelDownloadException.diskSpace(this.message)
    : code = ModelDownloadErrorCode.diskSpace;
  const ModelDownloadException.permission(this.message)
    : code = ModelDownloadErrorCode.permission;
  const ModelDownloadException.fileSystem(this.message)
    : code = ModelDownloadErrorCode.fileSystem;
  const ModelDownloadException.invalidUrl(this.message)
    : code = ModelDownloadErrorCode.invalidUrl;
  const ModelDownloadException.cancelled([this.message = '다운로드가 취소되었습니다.'])
    : code = ModelDownloadErrorCode.cancelled;

  bool get needsAuth => code == ModelDownloadErrorCode.authRequired;
  bool get isCancelled => code == ModelDownloadErrorCode.cancelled;
  bool get canRetry =>
      code != ModelDownloadErrorCode.cancelled &&
      code != ModelDownloadErrorCode.invalidUrl;

  @override
  String toString() => message;
}
