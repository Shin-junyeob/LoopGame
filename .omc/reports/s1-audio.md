# S1 오디오 엔진 Go/No-Go 보고

기준: 계획서 §2 G2(2026-11-03 개정: 앱이 쓰는 시간 P95 ≤ 10 ms, 원래는 전체 P95 ≤ 20 ms), G4(기기 iPhone 15 Pro / iPad Air 5), §6 S1 Go 항목.

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| (1) | 분할 렌더 vs 한 번에 렌더 비트 동일 (10분 × 8트랙 × BPM 60/70/97/160) | **GO** | `RendererTests.splitRenderIsBitIdenticalToOneShot(bpm:)` 4 cases 통과 (19.0 s) |
| (2) | hostTime→frame, 44.1↔48k 재앵커, 리샘플 길이 | **GO** | `ClockTests.hostTimeToFrameAppleSiliconTimebase`, `hostTimeToFrameNanosecondTimebase`, `reanchorPreservesTickPositionWithinOneFrame(bpm:)` 4 cases, `loopStartsMatchOracleFor10Minutes(bpm:sampleRate:)` 8 cases, `everyTickFrameIsExactFloor` 8 cases, `noOverflowAt10MinBpm160At48k`; `RendererTests.loopStartsLandOnClockFrames(bpm:)` 4 cases, `resampleLength(rates:length:)` 15 cases 전부 통과 |
| (3') | 에포크 회수 경합 | **GO** | `AtomicSwapTests.oldStateFreedOnlyAtEpochCPlus2`, `renderReadingOldPointerAcrossSwapKeepsItAlive`, `engineStoppedSwapFreesImmediately` 통과 |
| (3) | 앱이 쓰는 지연 P95 ≤ 10 ms (실기기, G2 개정) | **GO** — iPhone 15 Pro P95 7.79 ms / iPad Air 5 P95 7.56 ms | 아래 실측 결과 |
| (4) | 8트랙 60초 CPU < 30%, 언더런 0 (실기기) | **GO** — iPhone 15 Pro 11.79% / iPad Air 5 3.98%, 언더런 둘 다 0 | 아래 실측 결과 |

실행 출력(`cd LoopCore && swift test`, 2026-11-03): `Test run with 37 tests in 0 suites passed after 19.007 seconds.` / `Test Suite 'All tests' passed`

## 실측 결과 (iPhone 15 Pro, iOS 27.0.1, 2026-11-03)

설정: 48 kHz, ioBuffer 128프레임(2.67 ms), outputLatency 15.77 ms(기본 스피커).

| 회차 | 구간 | n | P50 | P95 | max |
|---|---|---|---|---|---|
| 1차 | 전체 프록시(터치→스피커) | 629 | 127.5 | 167.3 | 197.3 |
| 2차 | 전체 프록시 | 635 | 42.9 | 50.3 | 53.0 |
| 2차 | 터치 전달(UITouch.timestamp→touchesBegan) | 635 | 20.1 | 27.3 | 31.5 |
| 2차 | **앱이 쓰는 시간**(전체−전달−outputLatency) | 635 | 6.57 | **7.79** | 7.94 |

- 1차 원인: 패드가 `ScrollView` 안에 있어 `delaysContentTouches`가 touchesBegan을 늦춤. 패드를 밖으로 빼자 2차에서 전체 P95 167 → 50 ms (`7d67ad6`).
- iOS 몫(터치 전달 최소 13.5 ms + 스피커 15.8 ms)만으로 20 ms를 넘으므로 원래 G2는 달성 불가 → 사용자 결정으로 G2를 앱 몫 기준으로 개정.
- CPU(1차 로그): 8트랙 60초 평균 렌더 CPU 11.79%(버퍼 시간 대비), 언더런 0, 콜백 22,519회.
- 루프백(선택)은 아직 안 함. 앱 몫은 프록시 계산이라 `mHostTime` 의미가 틀리면 함께 틀림 — 체감상 늦다면 루프백으로 확인.

## 실측 결과 (iPad Air 5, 2026-11-03)

설정: 48 kHz, ioBuffer 128프레임(2.67 ms), outputLatency 5.69 ms(기본 스피커).

| 구간 | n | P50 | P95 | max |
|---|---|---|---|---|
| 전체 프록시(터치→스피커) | 698 | 22.14 | 29.64 | 32.88 |
| 터치 전달 | 698 | 9.19 | 16.93 | 20.91 |
| **앱이 쓰는 시간** | 698 | 6.42 | **7.56** | 7.69 |

- CPU: 8트랙 60초 평균 3.98%, 언더런 0, 콜백 22,502회.
- 첫 실행 때 Xcode ▶ 빌드는 성공했지만 설치가 안 됨(기기 준비 중으로 추정) → `xcodebuild -allowProvisioningUpdates` + `devicectl device install`로 설치.

**S1 종합: GO** (자동 항목 + 두 기기 실측. 루프백은 미실시 — 앱 몫이 프록시 계산이라 체감이 늦으면 확인)

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
