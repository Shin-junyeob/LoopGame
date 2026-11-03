# Deep Interview Spec: 초보자용 스테이지형 음악 루프 게임 (iOS)

## Metadata
- Interview ID: 8f3c2a1e-music-loop-game
- Rounds: 20 (+ Round 0 topology)
- Final Ambiguity Score: 9.4%
- Type: greenfield
- Generated: 2026-11-03
- Threshold: 0.1
- Threshold Source: 사용자 지정 (settings 미지정, 기본값 0.2)
- Initial Context Summarized: no
- Status: PASSED (pending approval)

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.93 | 0.40 | 0.372 |
| Constraint Clarity | 0.90 | 0.30 | 0.270 |
| Success Criteria | 0.88 | 0.30 | 0.264 |
| **Total Clarity** | | | **0.906** |
| **Ambiguity** | | | **0.094** |

## Topology
| Component | Status | Description | Coverage |
|-----------|--------|-------------|----------|
| 자유 연주 | active | BPM·악기·음색을 골라 패드/건반 연주. 처음부터 열림 | AC 1–4 |
| 루프 스테이션 | active | 루프 녹음·반복·최대 8트랙 겹치기, 곡 자동 구성 | AC 5–9 |
| 초보자 가이드 | active | 다음 악기 추천 + 녹음 직후 AI 보정안 비교 선택 (온디바이스 AI) | AC 10–13 |
| 스테이지 진행 | active | 18개 스테이지, 각각 따라 치기 → 만들기 | AC 14–17 |
| 곡 저장·공유 | active | 앱 내 저장, 오디오 파일 내보내기, CloudKit 공개 갤러리 + 좋아요·랭킹 | AC 18–23 |

## Goal
음악을 전혀 모르는 사람이 18개 스테이지를 따라 치고 만들면서 드럼→베이스→코드→멜로디를 쌓는 법을 익히고, 마지막에 인트로·본론·아웃트로가 있는 1분 이상의 곡을 완성해 오디오로 내보내거나 공개 갤러리에 올릴 수 있는 무료 iOS 게임. 자유 창작 모드는 처음부터 열려 있고, 이 모드에서도 AI가 다음 악기를 추천하고 어긋난 연주를 살짝 고친 버전을 제안한다.

## Constraints
- 플랫폼: 아이폰 + 아이패드(아이패드는 넓은 레이아웃), iOS 17 이상, Swift
- 그래픽: 2D SpriteKit(연출). 오디오는 AVAudioEngine
- 수익: 완전 무료(결제·광고 없음)
- 악기: 4역할(드럼 킷 / 베이스 / 피아노(코드) / 신스 리드) × 각 2~3 음색
- 소리 출처: 상업 앱에 사용 가능한 무료 라이선스 샘플(CC0 등)만 사용
- 루프: BPM은 곡마다 고정(범위 60~160), 루프 길이는 트랙마다 1/2/4/8마디, 4/4박자
- 보정·추천: 기기 안 AI(온디바이스 모델, 예: Core ML)가 박자·음 보정과 다음 악기 추천을 모두 담당
- 네트워크: 갤러리·랭킹 외에는 전부 오프라인 동작
- 계정: Game Center + 자체 닉네임. 로그인은 갤러리 업로드·랭킹에만 필요
- 공유 백엔드: CloudKit 공개 DB(별도 서버 운영 없음)

## Non-Goals
- 인앱 구매, 광고, 구독
- 서버 AI·클라우드 생성 모델
- 자유 길이 루프, 4/4 외 박자
- 사용자가 구간을 처음부터 배치하는 편집기(자동 구성을 고치는 것만)
- SNS용 영상 내보내기
- 장르별 월드
- 8개를 넘는 악기 역할

## Acceptance Criteria
### 자유 연주
- [ ] 1. 4역할 × 2~3음색을 고를 수 있고, BPM 60~160을 설정할 수 있다
- [ ] 2. 패드·건반 터치 후 소리가 나기까지 20ms 이내(실기기 측정)
- [ ] 3. 아이폰과 아이패드에서 각각 맞춘 레이아웃으로 동작한다
- [ ] 4. 모든 샘플에 대해 출처·라이선스 목록이 저장소에 있고, 전부 상업 사용이 가능하다

### 루프 스테이션
- [ ] 5. 트랙마다 1/2/4/8마디 길이로 녹음해 반복시킬 수 있다
- [ ] 6. 최대 8트랙을 동시에 재생할 수 있다
- [ ] 7. 8트랙을 10분간 재생해도 박자 밀림이 0이다(샘플 단위 정확, 자동 테스트)
- [ ] 8. 만든 루프들로 인트로→본론→아웃트로를 자동 구성해 1분 이상의 곡을 만든다
- [ ] 9. 자동 구성된 구간 중 원하는 구간만 바꿀 수 있다(어떤 트랙을 넣고 뺄지)

### 초보자 가이드 (온디바이스 AI)
- [ ] 10. 녹음 직후 '내 연주'와 'AI가 고친 버전' 1~2개를 들어보고 하나를 골라 루프에 넣는다
- [ ] 11. AI 보정 결과가 자동 측정 지표를 통과한다: 음 100%가 현재 코드·음계 안, 박자 격자 오차가 원본보다 감소, 원본과의 유사도가 기준 이상(수치는 계획 단계에서 확정)
- [ ] 12. 현재 곡의 트랙 구성을 보고 다음에 쌓을 악기를 추천한다(온디바이스, 오프라인)
- [ ] 13. AI는 기기 안에서만 동작한다(네트워크 차단 상태에서 동작 확인)

### 스테이지 진행
- [ ] 14. 아래 18개 스테이지가 있다: ① 메트로놈 따라 탭 ② 킥 4비트 ③ 킥+스네어 ④ 하이햇 8비트 ⑤ 첫 드럼 루프 ⑥ BPM 바꿔보기 ⑦ 베이스 근음 ⑧ 베이스 리듬 ⑨ 베이스 루프 ⑩ 코드 하나 ⑪ 4코드 진행 ⑫ 코드 루프 ⑬ 음계 안에서 치기 ⑭ 짧은 멜로디 ⑮ 멜로디 루프 + AI 보정 고르기 ⑯ 음색 바꿔보기 ⑰ 루프 길이 섞기 ⑱ 곡 완성(자동 구성 + 수정)
- [ ] 15. 각 스테이지는 따라 치기(타이밍 판정) → 만들기 순서이고, 둘 다 해야 클리어된다
- [ ] 16. 따라 치기 판정은 ±50~100ms 범위이며, 70% 이상 맞혀야 통과한다(판정 로직 단위 테스트)
- [ ] 17. 자유 창작은 스테이지 진행과 관계없이 처음부터 사용할 수 있다

### 곡 저장·공유
- [ ] 18. 곡을 앱 안에 저장하고 다시 열어 이어서 편집할 수 있다
- [ ] 19. 곡을 오디오 파일(m4a/wav)로 내보내 공유 시트로 보낼 수 있다
- [ ] 20. CloudKit 공개 갤러리에 곡을 올리고 둘러보고 들을 수 있다
- [ ] 21. 좋아요와 랭킹(인기순)이 있다
- [ ] 22. 앱스토어 심사 규정 1.2 대응: 신고·차단·본인 곡 삭제 기능이 있다
- [ ] 23. Game Center 로그인 + 자체 닉네임을 쓰고, 부적절한 닉네임을 필터링한다

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| '게임'이라 부르면 게임 요소가 있다 | Round 8 본질 관점: 점수·목표가 하나도 없었음 | 스테이지형 게임으로 재정의, 스테이지 덩어리 추가 |
| 초보자가 곡 구간을 직접 배치한다 | Round 4 반대 관점 | 자동 구성 + 살짝 수정 |
| 박자 보정은 규칙만으로 충분하다 | Round 6 단순화 관점 제안 | 사용자 판단으로 보정·추천 전부 AI |
| 보정은 실시간으로 들어간다 | Round 1 | 녹음 직후 비교 선택 |
| 생초보 대상이면 판정이 너그러워야 한다 | Round 14 | 리듬게임 수준으로 엄격하게. 앞쪽 스테이지는 낮은 BPM으로 난이도 조절 |

## Risks (계획 단계에서 반드시 다룰 것)
1. **온디바이스 AI 학습** — 학습 데이터(상업 사용 가능한 MIDI 데이터셋 등)의 확보·라이선스와 모델 학습 작업이 가장 큰 리스크. 자동 측정 지표(AC 11)로 합격 여부를 판단
2. **엄격한 판정 vs 생초보** — 리듬게임 수준 판정이 이탈을 부를 수 있음. 스테이지별 BPM 곡선으로 완화
3. **공개 갤러리 운영** — 신고 처리·차단은 출시 후 지속적인 운영 부담

## Technical Context (greenfield)
- 개발 환경: Swift 6.3.3(Command Line Tools)만 있음. **Xcode 미설치** — 빌드·시뮬레이터·제출에 필수
- 출시: Apple Developer Program($99/년) 필요(개발·시뮬레이터 테스트는 불필요)
- 후보 기술: AVAudioEngine(AVAudioUnitSampler, 샘플 단위 스케줄링), SpriteKit/SwiftUI, Core ML, CloudKit 공개 DB, GameKit(Game Center)

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| Instrument | core | role(drum/bass/keys/lead) | has many Timbre |
| Timbre | supporting | name, samples, license | belongs to Instrument |
| LoopTrack | core | instrument, timbre, bars(1/2/4/8), notes | belongs to Song |
| Song | core | bpm, tracks(≤8), sections | has many LoopTrack, Section |
| Section | supporting | kind(intro/main/outro), active tracks | belongs to Song (자동 생성) |
| BPM | value | 60~160 | Song attribute |
| CorrectionSuggestion | core | original, variants(1~2), metrics | produced by AIModel for LoopTrack |
| AIModel | external(on-device) | correction, recommendation | produces CorrectionSuggestion, recommends Instrument |
| Stage | core | index(1~18), follow-along pattern, build task | has ClearCondition |
| ClearCondition | supporting | timing window ±50~100ms, pass 70%, build done | belongs to Stage |
| SharedSong | core | song audio, owner, likes, reports | published Song in CloudKit |
| Ranking | supporting | likes order | over SharedSong |
| Player | supporting | Game Center id, nickname | owns SharedSong |

## Ontology Convergence
| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 5 | 5 | - | - | - |
| 3 | 6 | 1 | 0 | 5 | 83% |
| 6 | 7 | 0 | 0 | 7 | 100% |
| 8 | 10 | 2 | 0 | 8 | 80% |
| 13 | 11 | 1 | 0 | 10 | 91% |
| 20 | 13 | 2 | 0 | 11 | 85% |

## Interview Transcript
<details>
<summary>Q&A (20 rounds)</summary>

- R0 구성: 4덩어리 확인 + 악기 쌓기 추천, 조화롭지 않으면 고친 예시를 선택하게
- R1 보정 시점 → 녹음 직후 비교 선택 (71%→64%)
- R2 대상 기기 → 아이폰 + 아이패드 (60%)
- R3 성공 기준 → 구간 있는 1분 이상 곡까지 (53%)
- R4 곡 구성(반대 관점) → 자동 구성 + 살짝 수정 (45%)
- R5 판단 방식 → 기기 안 AI (43%)
- R6 AI 범위(단순화 관점) → 보정·추천 전부 AI (41%)
- R7 내보내기 → 오디오 파일, 앱 안 저장, 다른 사용자와 공유 (37%)
- R8 정체성(본질 관점) → 스테이지형 게임 (46%, 덩어리 추가)
- R9 클리어 조건 → 따라 치기 + 만들기 (40%)
- R10 스테이지 구성 → 15~20개로 잘게 (36%)
- R11 수익 → 완전 무료 (33%)
- R12 소리 출처 → 무료 라이선스 샘플 (30%)
- R13 공유 → 갤러리 + 좋아요·랭킹 (28%)
- R14 판정 → 리듬게임 수준 (25%)
- R15 AI 합격선 → 자동 측정 지표 (23%)
- R16 루프 단위 → 루프마다 1/2/4/8마디 (20%)
- R17 악기 → 기본 4종 + 음색 변형 (18%)
- R18 소리 품질 → 20ms / 드리프트 0 / 8트랙 (15%)
- R19 계정·범위 → iOS17+, Game Center + 자체 닉네임, 오프라인 (12%)
- R20 스테이지 목록 → 18개 확정, 자유 창작은 처음부터 (9.4%)
</details>
