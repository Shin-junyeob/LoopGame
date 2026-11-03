# S1 오디오 엔진 Go/No-Go 보고

기준: 계획서 §2 G2(지연 P95 ≤ 20 ms), G4(기기 iPhone 15 Pro / iPad Air 5), §6 S1 Go 항목.

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| (1) | 분할 렌더 vs 한 번에 렌더 비트 동일 (10분 × 8트랙 × BPM 60/70/97/160) | **GO** | `RendererTests.splitRenderIsBitIdenticalToOneShot(bpm:)` 4 cases 통과 (19.0 s) |
| (2) | hostTime→frame, 44.1↔48k 재앵커, 리샘플 길이 | **GO** | `ClockTests.hostTimeToFrameAppleSiliconTimebase`, `hostTimeToFrameNanosecondTimebase`, `reanchorPreservesTickPositionWithinOneFrame(bpm:)` 4 cases, `loopStartsMatchOracleFor10Minutes(bpm:sampleRate:)` 8 cases, `everyTickFrameIsExactFloor` 8 cases, `noOverflowAt10MinBpm160At48k`; `RendererTests.loopStartsLandOnClockFrames(bpm:)` 4 cases, `resampleLength(rates:length:)` 15 cases 전부 통과 |
| (3') | 에포크 회수 경합 | **GO** | `AtomicSwapTests.oldStateFreedOnlyAtEpochCPlus2`, `renderReadingOldPointerAcrossSwapKeepsItAlive`, `engineStoppedSwapFreesImmediately` 통과 |
| (3) | 탭→소리 지연 P95 ≤ 20 ms (실기기) | **사용자 측정 대기** | 아래 절차 A |
| (4) | 8트랙 60초 CPU < 30%, 언더런 0 (실기기) | **사용자 측정 대기** | 아래 절차 B |

실행 출력(`cd LoopCore && swift test`, 2026-11-03): `Test run with 37 tests in 0 suites passed after 19.007 seconds.` / `Test Suite 'All tests' passed`

## 사용자 측정 절차

### 준비
1. `cd ~/Developer/work/game && xcodegen generate && open LoopGame.xcodeproj`
2. 타깃 LoopGame > Signing & Capabilities > Team 선택 (무료 개인 팀 가능).
3. iPhone 15 Pro를 연결해 선택, Release 구성으로 실행 (Product > Scheme > Edit Scheme > Run > Build Configuration = Release). 이후 iPad Air 5도 똑같이 반복.
4. 무음 스위치 해제, 음량 중간 이상, 저전력 모드 끔, 다른 앱 종료. 시뮬레이터 수치는 의미 없으니 쓰지 말 것.

### 절차 A: 지연 (항목 3)
1. 스파이크 화면에서 500탭 지연 테스트를 시작하고 500회 탭한다.
2. 끝나면 결과(앱 내 추정 평균/P95)를 확인하고 Export log로 로그를 내보낸다.
3. **외부 마이크 루프백(정답값)**: 두 번째 폰으로 영상/오디오 녹음을 켜고 측정 기기 화면 근처에 둔다(손가락 탭 소리와 스피커 소리가 모두 잡히는 위치). 50번 탭한다.
4. 녹음을 오디오 편집기(Audacity 등)에서 열어 각 탭의 탭 transient(손가락이 화면에 닿는 소리)와 출력 소리의 시작점 간격을 50개 잰다.
5. 루프백 평균이 앱 내 추정값과 3 ms 넘게 다르면 **루프백 값이 합격/불합격 기준값**이다. 그 값의 P95 ≤ 20 ms이면 통과.

### 절차 B: CPU/언더런 (항목 4)
1. 스파이크 화면에서 8트랙 CPU 테스트를 시작해 60초 돌린다.
2. 평균 CPU < 30%, 언더런(글리치) 0회를 확인한다. Export log로 로그 저장.

### 보고할 것
기기별: 앱 내 P95, 루프백 평균/P95, CPU 평균/최대, 언더런 수, 내보낸 로그 파일.

## 알려진 한계
- `mHostTime` 의미(렌더 호출 시각 vs 출력 시각)는 미확인. 실기기 지연값이 이 가정에 의존한다.
- 시뮬레이터 지연 수치는 의미 없음.
- 라이브 탭은 다음 버퍼 시작에서 소리 난다 (128 프레임 @48k = 2.67 ms 버퍼). 이 값이 지연에 포함됨.
