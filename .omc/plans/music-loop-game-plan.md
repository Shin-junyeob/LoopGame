# 계획: 초보자용 스테이지형 음악 루프 게임 (iOS)

- 상태: **pending approval**
- 합의: Architect APPROVE_WITH_CHANGES(반영 완료) / Critic APPROVE, 2026-11-03
- 모드: RALPLAN-DR SHORT, Final
- 입력 스펙: `.omc/specs/deep-interview-music-loop-game.md` (AC 1~23 그대로 유지)
- 작성: 2026-11-03

---

## 1. Requirements Summary

무료 iOS 게임(iPhone+iPad, iOS 17+, Swift). 생초보가 18개 스테이지(따라 치기 → 만들기)로 드럼→베이스→코드→멜로디를 쌓고, 인트로·본론·아웃트로가 있는 1분 이상 곡을 완성해 m4a/wav로 내보내거나 CloudKit 공개 갤러리에 올린다.

- 자유 연주: 4역할 × 2~3음색, BPM 60~160, 터치→소리 20ms 이내
- 루프 스테이션: 트랙 ≤8, 트랙별 1/2/4/8마디, 4/4, 곡당 BPM 고정, 10분 재생 드리프트 0, 자동 구성 + 구간별 트랙 on/off
- 온디바이스 AI: 녹음 직후 보정안 1~2개 비교 선택, 다음 악기 추천, 오프라인
- 스테이지 18개: 판정 ±50~100ms, 70% 이상 + 만들기 과제 완료 시 클리어. 자유 창작은 처음부터 열림
- 저장·공유: 앱 내 저장/재편집, 오디오 내보내기, CloudKit 갤러리(좋아요·인기 랭킹·신고·차단·본인 삭제), Game Center + 닉네임 필터
- 환경 사실: 작업 폴더에 `.omc/`만 있음, git 아님, **Xcode 미설치**(CLT + Swift 6.4.2, Testing.framework 있음, XCTest 없음)

## 2. 사용자 확인 게이트 (Phase 1 시작 전, 계획이 대신 정하지 않음)

| ID | 결정할 것 | 영향 |
|---|---|---|
| G1 | R6 해석: 보정·추천 **결과를 학습 모델이 실제로 정해야** 하는가? 아니면 규칙이 후보를 만들고 모델은 고르기만 해도 되는가? (후자는 R6에서 거절한 "순수 규칙"과 사실상 같다는 지적이 있음) | AI 방식 B3a / B3b / B1 선택(§3-b) |
| G2 | AC2 20ms를 **전 탭 최대값**으로 볼지, **P95**로 볼지 | AC2 합격선 |
| G3 | AC11 "음 100%가 현재 코드·음계 안"을 **모든 음이 코드톤**으로 볼지, **모든 음이 음계 안 + 강박만 코드톤**으로 볼지 | Corrector 제약, AC11 테스트 |
| G4 | 측정 기기(지원 최저 1대 + 최신 1대) 모델명 | AC2·6 측정, S1 |
| G5 | §5의 18개 스테이지 과제 표 초안 승인/수정 | stages.json, AC14~15 |
| G6 | Recommender가 S2 기준(§6 S2)에 실패하면: 고정 순서 규칙 기준선으로 출시(R6 완화)할지, B1 등 추가 시도로 일정을 늘릴지 | AC12 충족 방식, 일정 |

ADR(§9)은 G1~G3 답에 따라 갈라진다.

### 게이트 결정 (사용자, 2026-11-03)
- **G1 → B3b**: 학습 모델(n-gram)이 음계·격자 제약 안에서 음과 위치를 직접 정한다. B3a 기각. B3b가 ablation에 실패하면 B1 검토
- **G2 → (2026-11-03 개정) 앱이 쓰는 시간 P95 ≤ 10ms** — 터치가 앱에 도착한 뒤 소리가 오디오 장치로 넘어가기까지(= 전체 프록시 − 터치 전달 − outputLatency). G4 기기마다. 전체(손가락→스피커)와 iOS 몫(터치 전달·outputLatency)은 기록만 함. 이유: iPhone 15 Pro 실측에서 iOS 몫만으로 20ms를 넘음(스피커 outputLatency 15.8ms + 터치 전달 최소 13.5ms) → 원래 정의(전체 ≤ 20ms)는 앱으로 달성 불가. 리듬 판정 공정성은 스테이지 1 오프셋 보정이 담당. (원래: 전체 P95 ≤ 20ms)
- **G3 → 모든 음은 음계 안 + 강박(1·3박) 음은 코드톤**. 드럼에는 적용 안 함
- **G4 → iPhone 15 Pro(A17 Pro), iPad Air 5세대(M1)**. 둘 다 최신급이라 iOS 17 최저 사양 기기(XS/11급) 성능은 검증 안 됨 → 리스크로 수용
- **G5 → §5 표 초안 그대로 승인**
- **G6 → Recommender가 S2에 실패하거나 평가 불가(n<30)면 고정 순서 규칙으로 v1 출시**, 갤러리에 올라온 곡의 트랙 추가 순서로 데이터를 모아 업데이트 때 모델로 교체. 보정 AI(B3b)는 v1에 그대로 출시
- **G7 비용 (2026-11-03) → 무료로 개발, Apple Developer Program($99/년) 결제는 출시 직전에 결정.** Phase 0~4는 무료 개인 팀(내 기기 설치, 7일마다 재서명, 기기 3대·기기당 앱 3개)으로 진행. CloudKit·Game Center가 필요한 S3·Phase 5는 결제 결정 뒤로 이동. 결제하지 않기로 하면 갤러리·랭킹·Game Center 없이 개인 기기용으로 남김

## 3. RALPLAN-DR 요약

### Principles
1. **위험한 것부터 증명**: 오디오 지연/드리프트, AI 품질·데이터 라이선스, CloudKit 권한 모델은 앱 UI보다 먼저 스파이크로 go/no-go
2. **플랫폼 독립 로직은 `LoopCore` Swift Package로**: Xcode 없이 `swift test`(Swift Testing)로 검증
3. **최소 구현**: 서버 없음, 구현이 하나뿐인 프로토콜 금지. 재생·내보내기는 같은 렌더 함수
4. **수치로 합격**: 모든 AC는 숫자 또는 자동 테스트로 판정
5. **라이선스는 파일 단위로 추적**: 샘플·학습 데이터 모두 같은 규칙, 테스트가 누락을 잡음

### Decision Drivers (상위 3)
1. 샘플 단위 정확성 + 20ms 지연(AC2·7) — 리듬 판정의 전제
2. AI 결과가 AC11 지표를 통과 + 상업 사용 가능한 학습 데이터 + R6(사용자 결정) 존중
3. 1인 개발 + CLI 에이전트 실행 — 텍스트로 관리되는 프로젝트, Xcode 없이 테스트되는 코어

### Viable Options

**(a) UI 레이어**

| 옵션 | 장점 | 단점 |
|---|---|---|
| **A1. SwiftUI 앱 + 연출만 SpriteKit(`SpriteView`) + 입력은 UIKit 터치** ✅ | 목록·폼·갤러리·iPad 레이아웃 기본 제공, 접근성, 코드 최소. 패드/건반/스테이지 입력은 `UIViewRepresentable`·`SKView` 터치로 `UITouch.timestamp` 확보 | 세 체계 혼용(경계: 입력 뷰 1종, `SpriteView` 1곳) |
| A2. 전부 SpriteKit | 연출 일관성 | 목록/텍스트 입력/공유 시트/iPad 레이아웃 직접 구현 → 코드 수 배, 접근성 없음 |

A2 기각: 화면 대부분이 목록·폼. SwiftUI 제스처는 터치 타임스탬프를 주지 않으므로 입력만 UIKit.

**(b) 온디바이스 AI** — G1 답에 따라 선택

| 옵션 | 장점 | 단점 |
|---|---|---|
| B3a. 규칙이 후보(약한/강한 격자 스냅+음계 스냅) 생성, n-gram이 순위만 | 가장 단순, 결정적 | 모델이 결과 내용을 바꾸지 못함 → G1 엄격 해석 시 R6 위반(B2와 동등) |
| B3b. n-gram이 **음별 배치·음높이를 직접 디코딩**(제약 빔 서치: 각 원본 음 주변 ±1/8박·±2반음 중 음계/코드 마스크 통과 후보, 음 삭제·추가 허용). 토큰 = 역할별 (마디 내 16분 위치, 음정 역할은 직전 음과의 음계 도수 간격 / 드럼은 패드 종류). 빔 상태에 원본 대비 음 개수 변화를 들고 다니며 ±20% 밖 경로는 가지치기 | 모델이 결과를 좌우 → R6 충족, 가중치 JSON(≤1MB)이라 `swift test`로 검증, 하드 제약은 마스크로 보장 | 표현력 상한, B1과 같은 코퍼스가 필요(데이터 부족 위험은 동일, 필요량은 더 적음) |
| B1. 소형 Core ML 시퀀스 모델 | 표현력 최고 | 같은 코퍼스로 학습 시 데이터 부족 영향이 더 큼, 음계 보장에 같은 마스크 필요, Python(coremltools) 학습 파이프라인 추가. 런타임은 `MLModel.compileModel`로 Xcode 비의존 |
| (B2. 순수 규칙) | — | R6 위반으로 기각 |

계획자 권고: G1이 엄격 해석이면 **B3b**, 완화 해석이면 B3a. B1은 S2에서 B3b가 ablation(§4 S2)에 실패할 때만.
공통 런타임: 후보 3~5개 생성 → `Metrics`로 필터 → 통과한 것 중 F1 상위 1~2개 표시. 통과 0개면 원본만 보여 주고 "이번엔 보정안이 없어요" 안내(필터를 거치지 않은 후보는 절대 표시 안 함). 이 비율을 S2 지표로 잼(holdout ≤ 5%).

**(c) 오디오 스케줄링**

| 옵션 | 장점 | 단점 |
|---|---|---|
| **C1. 자체 샘플 카운터 렌더러 + `AVAudioSourceNode`** ✅ | 정수 유리수 프레임 계산으로 드리프트 0 보장, 렌더 함수가 순수 Swift라 `swift test`로 10분 렌더·분할 렌더 비트 일치 검증, 내보내기 공용 | 믹서·보이스 풀 직접 작성, 실시간 안전 규칙 필수 |
| C2. `AVAudioPlayerNode.scheduleBuffer(at:)` | Apple API | 엔진 시간 의존 → 오프라인 단위 테스트 불가 |
| C3. `AVAudioSequencer` + `AVAudioUnitSampler` | 기성 시퀀서 | 트랙별 길이 혼합·런타임 편집 번거로움, 샘플 정확성 자동 증명 불가 |

C2·C3 기각: AC7을 기기 없이 자동 테스트로 증명할 수 없음.

**(d) 프로젝트 생성** — **XcodeGen(`project.yml`)** ✅. GUI `.xcodeproj`는 에이전트가 pbxproj를 직접 편집해야 해서 기각.

## 4. 디렉토리 구조 (제안)

```
game/
  project.yml
  LoopCore/                        # Swift Package, swift test (Swift Testing)
    Package.swift
    Sources/CAtomic/               # stdatomic.h 포인터 교체 C shim (swift-atomics 의존성 대신)
    Sources/LoopCore/
      Song.swift        # Song(schemaVersion)/LoopTrack/Note/Section, Codable
      Theory.swift      # 음계·코드, 마스크
      Clock.swift       # 정수 유리수 프레임 계산, hostTime→frame 변환, 재앵커
      Renderer.swift    # RenderState 스냅샷 + 보이스 풀, UnsafeBufferPointer만
      Timing.swift      # 판정, 오프셋 보정(상한)
      Arranger.swift
      Corrector.swift   # 후보 생성(G1 결과에 따라 B3a/B3b) + Metrics 필터
      Recommender.swift
      Metrics.swift
      Stages.swift      # stages.json 로드 + 만들기 과제 판정
      Resources/stages.json, model/*.json
    Tests/LoopCoreTests/
  App/
    LoopGameApp.swift
    AudioHost.swift     # AVAudioEngine, AVAudioSourceNode, 앵커 기록, 구성 변경 재앵커, 링버퍼
    SampleBank.swift    # 로드 시 엔진 샘플레이트로 리샘플(AVAudioConverter)
    TouchPadView.swift  # UIViewRepresentable, UITouch.timestamp 전달
    Views/ FreePlay, LoopStation, Compare, Arrange, Songs, Stage(+StageScene), Gallery, Credits, Settings(데이터 삭제)
    Cloud/ Gallery.swift, Player.swift
    Resources/Samples/<role>/<timbre>/*.caf, banned_words.txt
  licenses.json                    # 샘플+학습 데이터 단일 목록 → LICENSES.md·크레딧 화면 생성 원본
  tools/train/train.py             # uv, 코퍼스 → model/*.json, 패턴 단위 train/holdout 분할
  data/corpus/
```

## 5. 스테이지 과제 표 초안 (G5 확인 대상)

판정: |Δ| ≤ 50ms Perfect, ≤ 100ms Good, 그 외 Miss. **틀린 패드/음높이로 친 것은 Miss**(드럼은 패드, 음정 악기는 음높이·코드 패드 일치). 통과 = (Perfect+Good)/전체 ≥ 0.70.

| # | 이름 | 따라 치기 | BPM | 만들기 과제(클리어 술어) |
|---|---|---|---|---|
| 1 | 메트로놈 따라 탭 | 4분음 8마디, 아무 패드 | 70 | 오프셋 측정 저장 + 1마디 탭 루프 녹음 |
| 2 | 킥 4비트 | 킥 4분음 4마디 | 70 | 킥 ≥4개인 1마디 루프 |
| 3 | 킥+스네어 | 킥 1·3박, 스네어 2·4박 | 75 | 킥·스네어 각 ≥2개 루프 |
| 4 | 하이햇 8비트 | 하이햇 8분음 | 75 | 하이햇 ≥8개 포함 루프 |
| 5 | 첫 드럼 루프 | 킥·스네어·햇 2마디 | 80 | 3종 포함 2마디 드럼 트랙 |
| 6 | BPM 바꿔보기 | 5번 패턴 | 90 | 곡 BPM 변경 후 드럼 루프 재생 |
| 7 | 베이스 근음 | C 근음 4분음 | 80 | 베이스 1마디 루프 |
| 8 | 베이스 리듬 | 근음 8분 리듬 | 85 | 베이스 2마디, 음 ≥6 |
| 9 | 베이스 루프 | C-G-Am-F 근음 4마디 | 85 | 드럼+베이스 트랙(베이스 4마디) |
| 10 | 코드 하나 | C 코드 4분음 | 85 | 코드 1마디 루프 |
| 11 | 4코드 진행 | C-G-Am-F 마디당 1회 | 90 | 4코드 4마디 트랙 |
| 12 | 코드 루프 | 코드 리듬 패턴 | 90 | 드럼+베이스+코드 3트랙 |
| 13 | 음계 안에서 치기 | C장조 음계 오르내리기 | 95 | 음계 밖 음 0인 1마디 리드 |
| 14 | 짧은 멜로디 | 2마디 멜로디 | 95 | 멜로디 2마디, 음 ≥4 |
| 15 | 멜로디 루프 + AI | 4마디 멜로디 | 100 | 녹음 → 보정안 비교 → 하나 골라 추가 |
| 16 | 음색 바꿔보기 | 기존 패턴, 다른 음색 | 100 | 트랙 하나 음색 변경 |
| 17 | 루프 길이 섞기 | 1마디 드럼 + 4마디 코드 | 105 | 마디 길이가 다른 트랙 ≥2종 |
| 18 | 곡 완성 | 본론 드럼 패턴 | 110 | 자동 구성 + 구간 1개 이상 수정, 60초 이상 |

## 6. Phased Implementation Steps

### Phase 0 — 환경 + 게이트
- G1~G5 답 받기(§2). G4 기기 확보
- Xcode 설치, `sudo xcode-select -s /Applications/Xcode.app`, `xcodebuild -license accept`, iOS 17+ 런타임
- `brew install xcodegen`, `git init`, `.gitignore`(DerivedData, 생성된 `*.xcodeproj`)
- `LoopCore` 골격 + Swift Testing 테스트 1개
- **수락**: Xcode 없이 `swift test` 통과 / `xcodegen && xcodebuild build` 성공(시뮬레이터 이름은 `xcrun simctl list devices available`에서 조회)

### Phase 1 — 스파이크 (go/no-go, 병렬)

**S1 오디오** (`Clock`, `Renderer`, `CAtomic`, `AudioHost`, `TouchPadView`)
- 프레임 계산: 음 위치는 정수 틱(PPQ 480). 프레임 = `tick × sr × 60 / (bpm × 480)`을 정수 유리수로 계산(분자·분모 Int64, 마지막에 한 번 floor). 매 이벤트마다 절대 틱에서 계산, 누적 반올림 금지
- 실시간 안전: 불변 `RenderState` 스냅샷(트랙 버퍼 = 미리 할당한 `UnsafeBufferPointer`)을 C shim 원자 포인터로 교체. 회수: 렌더 콜백은 **매 콜백 끝에** epoch 카운터를 release로 증가, 렌더는 콜백 시작에 포인터를 acquire로 읽음. 메인은 acq_rel `exchange`로 포인터를 교체한 **뒤에** 카운터 C를 acquire로 읽고, 이후 읽은 카운터 ≥ C+2일 때만 옛 상태 해제(엔진 정지 상태면 즉시 해제). 보이스 풀(64개 선할당)은 렌더 스레드 소유이고 스냅샷에 넣지 않음. 렌더 경로에 Swift 배열·클래스·클로저·existential·할당·락 금지. 샘플은 로드 때 엔진 샘플레이트로 리샘플
- 시계 매핑: 렌더 콜백마다 (`mHostTime`, `mSampleTime`) 앵커 기록. `UITouch.timestamp`(초) → mach hostTime(`mach_timebase_info`) → 프레임 = 앵커 프레임 + Δhost×sr. 판정용 위치 = 그 프레임 − L×sr + 사용자 오프셋. **L(지연 보정 상수)은 하드코딩 공식(예: ioBufferDuration 차감)이 아니라 기기별 루프백 측정값**(측정 전 초기값은 `outputLatency`). `mHostTime`의 의미(버퍼 출력 시각인지)는 S1에서 루프백으로 확인
- 재앵커: `AVAudioEngineConfigurationChange`·라우트 변경·샘플레이트 변경 시 엔진 재구성, 음악 위치(틱)를 보존해 새 샘플레이트 프레임으로 환산. 샘플레이트가 바뀌면(44.1k↔48k) 메인 스레드에서 SampleBank 전체를 새 레이트로 다시 리샘플해 새 `RenderState`로 교체
- 지연 측정: 실제 `ioBufferDuration`·`outputLatency` 로그 + 앱 내부 대리 지표(터치 → 이벤트가 렌더된 버퍼 출력 시각) 500탭. **외부 마이크 루프백**: 기기별 50탭을 외부 녹음기로 녹음(탭 소리 ↔ 출력음). 대리 지표와 평균 차 ≤ 3ms면 대리 지표로 판정, **> 3ms면 루프백 측정값이 합격/불합격 값**
- **Go**: (1) 10분·8트랙·BPM 60/70/97/160, 무작위 버퍼(64~4096) 분할 렌더와 단일 렌더가 **비트 동일**, 루프 시작 프레임이 정수 공식과 일치 (2) hostTime→frame 변환·재앵커 단위 테스트 통과(44.1k↔48k 전환 후 틱 위치 오차 ≤ 1프레임, SampleBank 재리샘플 후 샘플 길이 = 원본 길이×새 레이트/원 레이트 ±1) (3') epoch 회수 테스트: 교체 직후 카운터가 C+1이면 해제 안 함, C+2면 해제, 그리고 "렌더가 옛 포인터를 읽음 → 메인 exchange → 메인이 C 읽음 → 렌더 콜백 끝 증가(C+1)" 순서를 재현해 이 시점에 해제되지 않음을 확인 (3) G4 기기에서 지연이 G2 정의로 ≤ 20ms (4) 8트랙 60초 평균 CPU < 30%, 언더런 0
- **No-go**: 버퍼 128프레임 재시도, 그래도 초과면 사용자에게 보고(AC를 조용히 완화하지 않음)

**S2 AI** (`Corrector`, `Recommender`, `Metrics`, `tools/train/`)
- 라이선스: 샘플·데이터 공통 허용 = {CC0, CC-BY-4.0, self}. Groove MIDI Dataset(CC BY 4.0)은 **드럼만** 해당 → 베이스·코드·멜로디는 자작 패턴(역할별 ≥100개, 1~8마디). Lakh 등 불명확 데이터 금지. CC-BY 항목이 하나라도 있으면 크레딧 화면 필수
- 분할: **패턴 단위**로 train 80% / holdout 20%를 먼저 나눈 뒤 지터 생성(누수 방지). holdout 패턴 × 지터(±10~80ms 가우시안, 음 10% ±1~2반음 오류, 5% 누락/추가) = 300개
- 드럼은 음높이 무관 지표만(격자 오차, 온셋 F1, 음 개수)
- Recommender 데이터: 사용자가 자작 완성곡 ≥40개를 만들 때 트랙을 추가한 순서를 (곡 상태 → 다음 역할) 쌍으로 기록, 라벨러는 작곡자(사용자). 표본이 작으므로 **곡 단위 5-fold 교차검증**(같은 곡의 상태가 학습·평가에 섞이지 않게). 기준선 = 고정 순서 드럼→베이스→코드→멜로디. 모델이 기준선을 넘을 수 있는 곳 = 기준선이 틀리는 상태(순서를 벗어난 곡, 같은 역할 레이어 추가, 마디 길이 구성에 따른 선택)
- **Go**:
  - 하드 지표(G3 정의의 음계/코드 제약, 음 개수 변화 ≤ 20%) holdout 100%
  - 통계 지표(격자 오차 감소, 유사도 F1) holdout 항목의 ≥ 95% 통과 + 평균 F1 약한 ≥ 0.85, 강한 ≥ 0.65
  - Ablation: B3b가 규칙 기준선(격자 스냅+최근접 음계)보다 **정답(지터 전 패턴) 복원 F1**이 높고, paired bootstrap 95% CI 하한 > 0 (B3a 선택 시 생략)
  - 보정안 없음(통과 후보 0개) 비율 ≤ 5%
  - Recommender: 기준선이 틀리는 상태 부분집합(표본 ≥ 30)에서 top-1 ≥ 60% **그리고** 전체 top-1 ≥ 80% 및 ≥ 기준선 (5-fold CV 평균). 실패 시 처리는 G6
  - 기준선이 틀리는 상태가 30개 미만이면 평가 불가 → G6으로 넘김(선택지: 사용자가 순서를 벗어난 곡을 더 만든다 / 실패로 본다)
  - 모델 파일 ≤ 1MB, 보정 1회(후보 5개+필터) ≤ 50ms(G4 최저 기기)
- **No-go**: n-gram 차수·스무딩 조정 → 그래도 실패면 B1 시도 여부를 사용자에게 확인

**S3 CloudKit 설계 + Dashboard 스파이크** (Developer Program 필요 — G7에 따라 **Phase 5 시작 전, 결제 결정 뒤**로 이동. Phase 3의 `Song` JSON `schemaVersion`은 그대로 넣어 둠)
- 레코드:
  - `SharedSong`(title, nickname, audio CKAsset m4a, song JSON CKAsset): 작성자만 쓰기
  - `SongStats`(songRef, likeCount): 인증 사용자 쓰기. 랭킹 정렬용일 뿐이며 위조 가능성은 v1에서 수용
  - `Like` / `Report`: recordName = `<userRecordID>_<songID>`(사용자당 1개로 중복 차단), songRef(`.deleteSelf`)
- 신원 = CloudKit `userRecordID`(Game Center는 표시·로그인 확인용)
- 좋아요 카운터 증가는 `serverRecordChanged` 시 재시도 최대 3회
- **숨김 판정은 `SongStats`를 쓰지 않음**: 목록에 뜬 곡들의 `Report`를 `songRef IN [...]`로 일괄 조회(참조 100개씩 나눠 조회)해 곡별 Report 레코드 수(= 서로 다른 신고자 수) ≥ 3이면 숨김. 판정은 클라이언트
- 인덱스: `likeCount` sortable, `songRef`·`recordName` queryable
- Dashboard 체크리스트(수동): 보안 역할 설정, 인덱스, Development→**Production 스키마 배포**
- **Go**: 기기 2대에서 타인 `SharedSong` 수정 거부, 같은 사용자의 중복 Like/Report 거부, **타인이 `SongStats`를 바꿔도 숨김 상태 불변**, 본인 곡 삭제 시 다른 사용자가 만든 Like/Report까지 `.deleteSelf`로 지워지는지 확인. 안 지워지면 SongStats/Like/Report 조회 결과를 존재하는 `SharedSong` 참조로만 걸러냄(고아 레코드 무해화)

### Phase 2 — 코어 로직 (`LoopCore`)
- `Song` Codable 왕복 + `schemaVersion`, 트랙 ≤ 8, BPM 60~160, 마디 {1,2,4,8} 검증
- `Timing`: §5 규칙, 한 입력은 한 노트에만 매칭, 사용자 오프셋 **±150ms 상한**(초과값은 클램프)
- `Arranger`: 인트로(드럼+베이스) → 본론(전체, 반복) → 아웃트로(트랙 하나씩 빼기), 총 ≥ 60초가 되게 반복 횟수 계산
- `Stages`: G5 확정 표 → stages.json, 과제 술어
- **수락**: `swift test` 전체 통과

### Phase 3 — 앱: 자유 연주 · 루프 스테이션 · AI 비교 · 저장/내보내기
- `TouchPadView` 기반 패드/건반, 녹음(카운트인 1마디), `CompareView`(원본 + 통과 후보 1~2, 0개면 원본 + "보정안 없음"), `ArrangeView`(구간별 트랙 토글), 저장(Application Support, 곡별 JSON)
- 내보내기: `Renderer` 오프라인 렌더 → `AVAudioFile`(m4a AAC / wav) → `ShareLink`
- iPad: `horizontalSizeClass == .regular`면 2열
- `CreditsView`: `licenses.json`의 CC-BY 항목 표시
- 실녹음 30개: 사용자 + 초보 지인 ≥ 2명이 녹음. 하드 지표는 100% 게이트, 통계 지표는 보고만(게이트 아님)
- **수락**: AC1~6, 8~13, 18~19

### Phase 4 — 스테이지
- `StageView` = SwiftUI 셸 + `SpriteView(StageScene)`. 노트 위치는 **오디오 시계**(AudioHost 앵커에서 외삽한 현재 곡 프레임)로 계산, SpriteKit `update` 시간 미사용. 입력은 `SKView` 터치 → `UITouch.timestamp`
- 1번 스테이지 오프셋 측정, 설정에서 재측정. 진행 상태는 `UserDefaults`. 자유 창작은 항상 활성
- **수락**: AC14~17

### Phase 5 — 공유 · 계정 · 모더레이션 · 출시 준비
- **진입 조건(G7)**: 사용자가 Apple Developer Program 결제를 결정. 결정 후 S3 스파이크 → 아래 구현
- S3 설계대로 구현. 랭킹 = `likeCount` 내림차순 상위 100개를 받아 숨김·차단 작성자를 걸러냄. 걸러진 만큼 목록이 100개보다 짧아질 수 있음(v1 수용, 개수가 중요해지면 다음 페이지를 이어 받음)
- 차단: 작성자 `userRecordID`를 로컬 저장. 본인 곡 삭제: `SharedSong`+`SongStats` 삭제, Like/Report는 cascade 또는 S3 결과에 따른 존재 참조 필터
- 업로드 하루 5곡 제한(**클라이언트 전용**, 우회 가능함을 인지)
- Game Center 로그인 + 닉네임(2~12자). 금칙어 필터(ko/en, 공백·대소문자·자모 정규화 후 부분일치)는 **닉네임과 곡 제목** 모두에 적용. 닉네임 전역 중복 검사는 하지 않음(스펙에 없음)
- 모더레이션: `Report` 생성에 `CKQuerySubscription` → 개발자 기기로 푸시 + 매일 1회 Dashboard 확인. EULA에는 "신고 24시간 내 처리"와 무관용 조항
- 설정 > **"내 데이터 전체 삭제"**(5.1.1(v)): 로컬 곡·진행·닉네임 + 내 CloudKit 레코드(SharedSong, SongStats, Like, Report) 삭제
- Privacy Manifest
- **수락**: AC20~23. 네트워크를 끊어도 갤러리 외 전 기능 동작

## 7. Acceptance Criteria 매핑

| AC | 검증 | 합격 수치 |
|---|---|---|
| 1 | UI 테스트 + `Song` 검증 단위 테스트 | 4역할 각 2~3음색, BPM 59/161 거부, 60/160 허용 |
| 2 | G4 기기 실측(S1, 500탭 + 루프백 50탭/기기) | G2 정의로 ≤ 20ms. 판정 값 = 대리 지표(루프백과 평균 차 ≤ 3ms일 때) 또는 루프백 측정값(> 3ms일 때) |
| 3 | 시뮬레이터 스크린샷(iPhone SE·Pro Max·iPad 11") | 잘림/겹침 0, iPad는 2열 |
| 4 | 단위 테스트: 모든 샘플·데이터 파일이 `licenses.json`에 있고 license ∈ {CC0, CC-BY-4.0, self}, CC-BY 항목은 전부 크레딧에 표시 | 누락 0 |
| 5 | `Renderer`/`Clock` 단위 테스트 | 1/2/4/8마디 루프가 정수 공식 프레임으로 반복, hostTime→frame 변환 오차 ≤ 1프레임 |
| 6 | 단위 테스트 + G4 기기 | 8트랙 동시 렌더, 9번째 거부, **60초 평균 CPU < 30%**, 언더런 0 |
| 7 | 단위 테스트(S1 Go 1·2) | 분할/단일 렌더 비트 동일, 루프 시작 프레임 오차 0, 재앵커 후 틱 위치 ≤ 1프레임 |
| 8 | `Arranger` 단위 테스트 | intro→main→outro, 모든 BPM·루프 조합에서 ≥ 60.0초 |
| 9 | 단위 + 수동 | 한 구간 토글이 다른 구간에 영향 없음 |
| 10 | UI 테스트 + 수동 | 녹음 종료 후 ≤ 1초에 원본+후보 1~2개 재생, 선택한 것만 저장. 후보 0개는 원본 + "보정안 없음"(holdout 기준 ≤ 5%) |
| 11 | `Metrics` 단위 테스트(holdout 300) + 실녹음 30 보고 | ① G3 정의의 음계/코드 제약 100% ② 격자 오차: 약한 ≤ 원본×0.6, 강한 ≤ 원본×0.2(원본 ≤ 5ms면 악화 없음) ③ 유사도 F1(매칭 = 온셋 1/16음표 이내 & 음높이 ±2반음, 드럼은 온셋만): 약한 ≥ 0.80, 강한 ≥ 0.60 ④ 음 개수 변화 ≤ 20%. ①④는 100%, ②③은 ≥ 95% + 평균 기준. 런타임에서 화면에 보이는 후보는 항상 ①~④ 통과(필터) |
| 12 | `Recommender` 단위 테스트(곡 단위 5-fold CV) | 기준선이 틀리는 상태(n ≥ 30)에서 top-1 ≥ 60%, 전체 top-1 ≥ 80% 및 ≥ 기준선, 8트랙 가득이면 추천 없음. 미달 또는 해당 상태 < 30개(평가 불가)면 G6 |
| 13 | 비행기 모드 수동 + 정적 검사 | 동작, `LoopCore`에 `URLSession`/`CloudKit` 참조 0 |
| 14 | stages.json 단위 테스트 | 18개, G5 표와 순서·이름 일치 |
| 15 | 진행 로직 단위 테스트 | 따라 치기만/만들기만이면 미클리어, 둘 다 하면 클리어 |
| 16 | `Timing` 단위 테스트 | ±50/±50.1/±100/±100.1ms 경계, 0.69 실패·0.70 통과, 틀린 패드/음높이는 Miss, 중복 매칭 없음, 오프셋 ±150ms 클램프 |
| 17 | UI 테스트 | 새로 설치한 상태에서 자유 창작 진입 |
| 18 | Codable 왕복(`schemaVersion` 포함) + 재시작 후 수동 편집 | 왕복 후 동등 |
| 19 | 단위 + 수동(공유 시트) | 렌더 버퍼 길이 = 곡 길이(프레임 정확), wav 파일 길이 정확, m4a는 ±2112프레임(AAC priming/padding) |
| 20 | 기기 2대, CloudKit Production | 업로드 → 다른 기기에서 목록·재생 |
| 21 | 기기 2대 | 좋아요 1인 1회, 랭킹 likeCount 내림차순 |
| 22 | 수동 | 서로 다른 3명이 신고하면 숨김(Report 레코드 수 기준, SongStats 조작과 무관), 차단한 작성자 안 보임, 본인 곡 삭제(Like/Report 정리), EULA 동의, 신고 푸시 수신, 데이터 전체 삭제 |
| 23 | 필터 단위 테스트 + Game Center 수동 | 금칙어·변형을 닉네임·제목에서 100% 거부, 정상 문자열 통과 |

## 8. Risks and Mitigations

| 리스크 | 완화 |
|---|---|
| AI 학습 데이터 라이선스 | 단일 `licenses.json` 규칙, 드럼 외는 자작, CC-BY는 크레딧 화면, 불명확 데이터 금지 |
| R6 해석 불일치 → 출시 후 "AI가 아니다" | G1 게이트에서 먼저 결정, B3b ablation으로 모델 기여를 수치로 증명 |
| AI 품질 미달 | 하드 제약은 마스크·빔 가지치기로 보장, 런타임 Metrics 필터(통과 0개면 원본만), S2 조기 판정 |
| Recommender 라벨 부족(곡 40개 작업량) | Phase 1 시작 전 사용자 시간 확인(open question), 곡 단위 CV로 소표본 평가, 실패 시 처리는 G6 |
| 20ms 초과(기기·블루투스) | 실제 버퍼/지연 로그, 루프백으로 대리 지표 검증, 블루투스 감지 시 오프셋 자동 적용 + 안내 |
| 렌더 스레드 끊김 | RT 안전 규칙(§6 S1), 리뷰 체크 + Instruments 1회 |
| 엄격한 판정 vs 생초보 | 판정 창 유지, BPM 곡선 70→110, 무제한 재시도, 빠름/느림 평균 표시 |
| 갤러리 운영 | 신고 3명 자동 숨김, 신고 푸시 + 매일 확인, 24시간 대응 |
| App Store 1.2 / 5.1.1(v) | 신고·차단·삭제·EULA·제목/닉네임 필터·데이터 전체 삭제를 출시 체크리스트로 확인 |
| iCloud 계정 3개만 있으면 누구 곡이든 숨길 수 있음 | v1 수용 리스크. Report 생성 푸시로 개발자가 검토해 부당 신고는 Dashboard에서 삭제 |
| CloudKit 한계(위조 가능 카운터, 집계 불가, 쿼터) | SongStats는 좋아요 정렬에만 쓰고 위조 수용, 숨김은 Report 레코드 수로 판정, m4a 64kbps(1분 ≈ 0.5MB), 상위 100개만, 클라이언트 업로드 제한 |
| Game Center·iCloud 이중 계정 | 업로드 시점에만 확인, 원인별 안내 |

## 9. ADR (G1~G6 확정 반영)
- **Decision**: SwiftUI + `SpriteView` + UIKit 터치 입력 / 자체 정수 유리수 렌더러(`AVAudioSourceNode`, 원자 스냅샷) / XcodeGen + `LoopCore` / CloudKit SongStats 분리. AI: **B3b**(G1), B3b ablation 실패 → B1 검토. 지연 P95 ≤ 20ms(G2), 음계 안 + 강박 코드톤(G3), 측정 기기 iPhone 15 Pro·iPad Air 5(G4), §5 표 그대로(G5), Recommender 실패 시 고정 순서로 v1 출시 후 업데이트에서 교체(G6)
- **Drivers**: 샘플 정확성·지연, AI 지표 + 라이선스 + R6, CLI 1인 개발
- **Alternatives considered**: 전부 SpriteKit, B1/B2/B3a, PlayerNode 스케줄링, AVAudioSequencer, GUI Xcode 프로젝트, swift-atomics(C shim 쪽이 의존성 없음), 닉네임 전역 고유성
- **Why chosen**: 핵심 AC(2·5·7·11)를 기기 없이 자동 테스트로 증명할 수 있고, 코드·의존성이 가장 적음
- **Consequences**: 믹서·보이스·원자 교체를 직접 작성. 카운터 위조 가능(v1 수용). Recommender 라벨링은 사용자 작업. 3개 계정 신고로 숨김 가능(v1 수용). 랭킹 목록이 100개보다 짧을 수 있음
- **Follow-ups**: G1~G6 답 반영, S1~S3 결과로 ADR 확정, 위조가 문제 되면 서버 검증 재검토

## 10. Verification Steps
1. `cd LoopCore && swift test` — AC 4, 5, 7, 8, 9, 11, 12, 14, 15, 16, 18, 23(필터)
2. `SIM=$(xcrun simctl list devices available | grep -m1 iPhone | ...)`로 이름 조회 → `xcodegen && xcodebuild test -scheme App -destination "platform=iOS Simulator,name=$SIM"` — AC 1, 10, 17
3. G4 기기 측정 로그(S1, 루프백 포함) — AC 2, 6
4. 시뮬레이터 3종 스크린샷 — AC 3
5. 비행기 모드 시나리오 — AC 13
6. 기기 2대 CloudKit Production 시나리오 + Dashboard 체크리스트 — AC 20~22
7. 출시 전 1.2·5.1.1(v) 체크리스트 + TestFlight 1회

## 11. 변경 기록

### Revision 1
- 사용자 결정 사항 G1~G5를 게이트로 분리하고 ADR을 조건부로 바꿈. 18개 스테이지 과제 표 초안 추가
- AI: B3a/B3b 분리(B3a는 R6 위반 소지 명시), B1 장단점 공정하게 수정(학습은 Python, 런타임 Xcode 비의존). 런타임 Metrics 필터+폴백 추가. S2 go 기준을 하드 100%/통계 ≥95%+평균/ablation/추천 기준선 대비로 바꿈. 패턴 단위 분할, Recommender 데이터·라벨러 정의, 드럼은 음높이 무관 지표, 실녹음 30개 주체·게이트 범위 정의. `Corrector` 프로토콜 삭제
- 오디오: UIKit 터치 입력, hostTime→frame 시계 매핑과 테스트, 오디오 시계 기반 스테이지 연출. RT 안전(불변 스냅샷+C shim 원자 교체, 할당 금지, 보이스 풀, 로드 시 리샘플). 정수 유리수 프레임, 분할/단일 렌더 비트 일치, 재앵커 테스트
- AC2: 실제 버퍼/지연 로그 + 외부 루프백 보정. P95는 G2로 넘김
- CloudKit: SongStats 분리, Report recordName·3명 숨김, `userRecordID` 신원, 인덱스, Dashboard·Production 배포 체크리스트, S3 스파이크를 Phase 3 앞으로 이동, `schemaVersion`, 신고 구독 푸시, 닉네임 고유성 제거, 클라이언트 전용 업로드 제한 명시, 삭제 시 cascade
- App Store: 제목 필터, "내 데이터 전체 삭제". 라이선스 규칙 통일 + 크레딧 화면 AC4에 포함, Groove MIDI는 드럼만
- 판정: 오프셋 ±150ms 상한, 틀린 패드/음높이는 Miss. AC6은 60초 평균, AC19는 AAC ±2112프레임
- 환경: Swift 6.4.2로 수정, Swift Testing 고정, 시뮬레이터 이름은 `simctl`로 조회

### Revision 2
- 숨김 판정: 위조 가능한 `SongStats.reportCount` 대신 곡별 Report 레코드 수(서로 다른 신고자) ≥ 3. `reportCount`·`hidden` 인덱스 삭제, S3 Go에 "타인이 SongStats를 바꿔도 숨김 불변" 추가
- 보정 폴백: 필터 안 거친 강한 스냅 표시를 없앰. 통과 0개면 원본 + "보정안 없음", 그 비율을 S2 지표로(holdout ≤ 5%)
- Recommender: "+10%p" 대신 기준선이 틀리는 상태(n ≥ 30)에서 top-1 ≥ 60% + 전체 ≥ 기준선, 곡 단위 5-fold CV. 실패 처리는 새 게이트 G6
- RT 회수: 매 콜백 끝 epoch release 증가, 메인은 C+2 이후 해제(정지 시 즉시), acquire/release 명시, 보이스 풀은 렌더 스레드 소유. 회수 테스트 추가
- 시간축: 정수 틱(PPQ 480) + 정수 유리수 프레임. 샘플레이트 변경 시 SampleBank 전체 재리샘플 후 RenderState 교체, S1 테스트 추가
- 시계 매핑: 지연 보정 L은 루프백 측정값(ioBufferDuration 차감 하드코딩 삭제). 대리 지표와 루프백 차가 3ms를 넘으면 루프백 값으로 판정
- B3b: 토큰(역할별 16분 위치 + 음계 도수 간격 / 드럼 패드) 정의, 음 개수 ±20%를 빔 안에서 가지치기
- 삭제 cascade: 타인 레코드가 `.deleteSelf`로 안 지워지면 존재하는 SharedSong 참조로만 필터

### Final
- epoch 회수: acq_rel exchange 후 카운터 C를 읽도록 순서 고정, 그 경합 순서를 재현하는 테스트 추가
- Recommender: 기준선이 틀리는 상태 < 30개면 평가 불가 → G6
- AC7 용어 "박 위치" → "틱 위치"
- 랭킹: 상위 100개 받은 뒤 숨김·차단 필터, 목록이 짧아질 수 있음(v1 수용)
- 리스크: iCloud 계정 3개로 숨김 가능(v1 수용, 신고 푸시 검토로 완화)
- `songRef IN` 조회는 100개씩 나눠서
- ADR을 G1~G6 조건부로 정리, 합의 라인 추가

### 비용 결정 반영 (2026-11-03)
- G7 추가: 무료 개발, $99 결제는 출시 직전 결정. S3 CloudKit 스파이크를 Phase 3 전 → Phase 5 진입 시(결제 후)로 이동

### 게이트 결정 반영 (2026-11-03)
- G1~G6 사용자 답을 §2 "게이트 결정"과 ADR에 반영 (B3b / P95 / 음계+강박 코드톤 / iPhone 15 Pro·iPad Air 5 / 표 승인 / 고정 순서 v1 출시)
