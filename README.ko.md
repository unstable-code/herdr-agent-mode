# herdr-agent-mode

[English](README.md) | **한국어**

[Claude Code](https://claude.com/claude-code) 페인이 지금 어떤 권한 모드로, [opencode](https://opencode.ai)
페인이 어떤 에이전트(Build·Plan …)로 돌고 있는지, 각각 어떤 모델로 얼마나 세게 추론하고 있는지를 에이전트
사이드바에 표시하는 [herdr](https://herdr.dev) 플러그인. 추론 강도는 herdr 의 `state_icon` 자리에 들어가는
상태 글리프의 모양으로 보이고, 색은 에이전트 상태를 따른다.

## 왜

herdr 는 에이전트가 *무엇을 하고 있는지*(작업 중·대기·차단)는 보여주지만, *어떤 조건으로* 하고 있는지는
보여주지 못한다. 모든 편집을 손으로 승인받고 있든 하나도 안 받고 있든 "Claude 작업 중" 은 똑같이 보인다.
그런데 페인에서 눈을 떼고 다른 일을 하러 가기 전에 알고 싶은 것이 바로 그 차이다.

모드는 하필 중요한 순간에 놓치기도 쉽다. 작업 도중 `shift+tab` 으로 바꾸는 세션별 설정이고, 지금 보고 있는
페인의 맨 아래에만 표시되며, 한 시간 전에 두고 온 세션은 그때 설정한 그대로 남아 있다. 페인이 열댓 개쯤
되면, 무인으로 돌고 있는 그 페인이 내가 그렇게 설정했다고 기억하는 페인이라는 보장이 없다.

## 어떻게 동작하나

- **값의 출처는 herdr 가 아니라 Claude Code 다.** Claude 훅이 stdin 으로 `permission_mode` 를 실어 오고,
  그것이 이 값이 나오는 유일한 곳이다 — 상태줄 페이로드에는 이 필드가 없다. 그래서 이 플러그인은 훅
  스크립트를 제공하고 `~/.claude/settings.json` 에 등록한다.
- **훅이 자기 페인을 직접 보고한다.** 훅은 페인 안에서 돌고, 그 환경에는 herdr 가 이미 넣어 둔
  `HERDR_PANE_ID`·`HERDR_SOCKET_PATH`·`HERDR_BIN_PATH` 가 있다. 그래서 `herdr pane report-metadata` 를
  바로 부른다. 데몬도 필요 없다 — Claude 훅이 곧 이벤트다. 예외는 상태 글리프(아래)뿐이다. herdr 만 아는
  상태가 필요해서 herdr 이벤트 훅에서 나온다.
- **훅은 다섯을 등록하고**, 그중 셋이 모드를, 하나가 모델을 실어 온다.

  | 훅 | 언제 | 무엇을 보고하나 |
  |---|---|---|
  | `SessionStart` | Claude 시작·`/clear`·`/resume` | 세션이 시작하는 모델 |
  | `UserPromptSubmit` | 프롬프트를 보낼 때 | 그 프롬프트를 보내는 모드 |
  | `PreToolUse` | 도구 호출 직전마다 | 턴이 도는 동안의 모드 |
  | `Stop` | 턴이 끝날 때 | 페인이 남는 모드, 그리고 응답을 쓴 모델 |
  | `SessionEnd` | Claude 종료·`/clear`·`/resume` | 모든 토큰을 지운다 — 에이전트가 사라졌으므로 |

- **`SessionStart` 이후의 모델은 transcript 에서 읽는다.** 다른 훅은 모델을 싣지 않지만, transcript 의
  assistant 기록마다 그 기록을 쓴 모델이 남는다. Claude 는 턴의 응답을 `Stop` 훅이 끝난 **뒤에** 거기
  쓰므로, 훅은 모드를 먼저 보고하고 응답이 기록되면 그 모델을 백그라운드에서 읽어 보고한다(1초도 안
  걸리고, 3초가 지나면 포기한다). 파일 전체가 아니라 끝부분만 읽는다 — 긴 세션의 transcript 는 수십 MB 다.
- **모델은 형식을 아는 경우에만 줄인다**: `claude-opus-5-5` → `opus 5.5`,
  `claude-haiku-4-5-20251001` → `haiku 4.5`. 그 밖의 id(opencode 의 로컬 모델, 다른 제공자의 모델)는
  추측으로 줄이지 않고 그대로 내보낸다.
- **이벤트가 싣지 않는 필드는 건드리지 않는다.** `SessionStart` 에는 모드가, 대부분의 훅에는 모델이 없는데,
  어느 쪽도 다른 쪽을 지워서는 안 된다. Claude 는 시간이 지나며 필드를 더하기도 한다. 그 필드가 없는 미래의
  이벤트가 아직 맞는 값을 지워 버려서는 안 된다.
- **모든 실패는 조용하다.** herdr 가 없든, `jq` 가 없든, herdr 밖의 페인이든, 페이로드가 깨졌든 훅은 0으로
  끝나고 아무것도 보고하지 않는다. stderr 에 뭔가 쓰는 훅은 사용자가 신경 써야 하는 훅이고, 여기서 하는
  일 중 세션을 방해할 만큼 중요한 것은 없다 — 최악이라야 사이드바에 직전 모드가 남을 뿐이다.

### opencode

opencode 에는 권한 모드 대신 **에이전트**가 있다(기본은 Build 와 Plan). 같은 두 토큰으로 보인다.

| 에이전트 | `$mode` | `$mode_label` |
|---|---|---|
| `plan` | `▏` — Claude plan 처럼 읽기만 한다 | `plan` |
| `build` | `▍` — Claude manual 처럼 권한을 묻는다 | `build` |
| 그 밖(사용자 정의 에이전트) | 그 이름 그대로 | 그 이름 그대로 |

- **opencode 2.x 의 TUI 플러그인이다.** `opencode/tui.js` 를 opencode 의 `cli.json` 에 있는 `"plugins"`
  목록에 등록한다. 서버 쪽 훅(`chat.message`)이 아닌 이유는, 일반 TUI 에서는 서버가 공유되거나 별도
  worker 에서 돌아 어느 페인인지 알 수 없기 때문이다. herdr 자신의 opencode 통합도 같은 이유로 TUI
  플러그인에서 보고한다.
- **값은 선택된 세션의 에이전트다**(`api.data.session.get(id).agent`). 바뀌면 `bin/publish` 를 실행해
  Claude 훅과 같은 `lib.sh` 코드로 보고한다 — 글리프 표·토큰 이름·seq 규칙이 두 에이전트에 한 벌뿐이다.
- **모델도 같은 세션의 것이다**(`.model.id`), `$model` 로 보인다. TUI 는 프롬프트에서 지금 고른 모델도
  읽을 수 있지만, 에이전트가 늦게 따라가므로(아래) 모델만 바로 따라가면 어느 메시지도 돈 적 없는 조합을
  보이게 된다.
- **variant 가 추론 강도다**(`.model.variant`). Claude 와 같이 `$effort` 로 보인다.
- **opencode 를 끝내면 모든 토큰을 지운다.** 세션이 없는 홈 화면에서도 지운다 — 보고할 것이 없다.

### 상태와 추론 강도

행의 첫 칸에 두 가지를 함께 담는다. 모양은 에이전트가 얼마나 세게 추론하는지를, 색은 어떤 상태인지를
나타낸다. 모양은 Claude Code 가 effort 단계마다 직접 그리는 글리프이고, opencode 의 variant 도 이름이 같다.

| Claude `effort` / opencode `variant` | 글리프 |
|---|---|
| `low` | `○` |
| `medium` | `◐` |
| `high` | `●` |
| `xhigh` | `◉` |
| `max` | `◈` |
| `none`(opencode, 추론 끔) | `◌` |
| 보고 없음, opencode `default`, 보고 경로가 없는 에이전트 | `state_icon` 과 같은 모양: working·blocked·done `●`, idle `○`, unknown `·` |
| 그 밖 | 그 단어 그대로 |

- **토큰 다섯 개 중 하나만 켠다**: `$state_working`·`$state_blocked`·`$state_done`·`$state_idle`·
  `$state_unknown`. 사이드바 규칙은 그 토큰 자신의 값만 보므로, 글리프 하나에 그 값에 없는 상태로 색을 입힐
  수는 없다. 대신 토큰 다섯 개를 나란히 두고 각자 `fg` 를 주면 된다 — 지금 상태의 토큰에만 값이 있고, 값이
  없는 사용자 정의 토큰은 아예 그려지지 않는다.
- **상태는 herdr 에서 온다.** 플러그인의 이벤트 훅(`bin/state`)이 herdr 가 감지하는 모든 에이전트에 대해
  보고한다 — 이 플러그인에 보고 경로가 없는 에이전트도 상태는 `state_icon` 모양으로 보인다. herdr 는 `done`
  과 `idle` 을 한 상태에서 파생하고(봤는가/안 봤는가), 페인을 보는 순간에는 상태 이벤트를 내지 않는다. 그래서
  포커스가 바뀔 때도 모든 페인을 다시 확인하고, 토큰이 어긋난 페인만 보고한다.
- **추론 강도는 에이전트에서 온다**(`$effort`, 에이전트가 부르는 이름 그대로). Claude 는 `PreToolUse` 와
  `Stop` 에 `effort.level` 로 싣고, effort 가 없는 모델(Haiku)에서는 빼므로 그때는 토큰을 지운다.
  `UserPromptSubmit` 과 `SessionStart` 에는 실리지 않는다.
- **에이전트 쪽 보고 경로는 상태를 쓰지 않는다.** herdr 에서 읽을 수는 있지만, herdr 자신의 Claude 통합이 같은
  Claude 이벤트에서 동시에 상태를 보고한다. 한발 일찍 읽은 상태 — 권한 프롬프트로 막 `blocked` 가 됐는데
  `working` — 는 다음 변화까지 화면에 남는다. 상태 보고는 별도의 metadata source 로 보낸다. herdr 는 source
  마다 seq 하나를 두고 그보다 오래된 보고를 통째로 버리기 때문이다.

## 못 하는 것

**사이드바가 보여주는 것은 그 페인이 마지막으로 뭔가 한 시점의 모드이지, 지금 이 순간의 설정이 아니다.**
Claude Code 에는 모드 변경으로 발생하는 훅 이벤트가 없고, 세션이 놀고 있는 동안에는 훅이 돌지 않는다.
그래서 모드를 바꾸고 아무것도 시키지 않으면 다음 프롬프트까지 옛 값이 그대로 보인다. 실제로 그 창은 짧다 —
보통 뭔가 시키려고 모드를 바꾸니까. 그래도 있는 것은 있는 것이고, 이 표시는 "지금 무엇으로 설정돼 있나"
보다 "무엇으로 돌고 있었나" 에 답한다는 점은 알고 쓰는 편이 낫다.

`dontAsk` 와 `bypassPermissions` 는 `shift+tab` 순환에 아예 없다. 세션을 시작할 때 정해진다
(`claude --permission-mode …`, `--dangerously-skip-permissions`, 설정의 `defaultMode`). 그래서 이 둘은
늦을 것 자체가 없다.

**opencode 도 같은 지연이 있다.** opencode 는 에이전트를 메시지를 보낼 때 세션에 기록한다. `shift+tab`
만 누르면 프롬프트의 표시만 바뀌고, 그 선택을 읽는 API 는 TUI 플러그인에 없다(모델과 variant 는 있다).
그래서 바꾼 에이전트는 다음 메시지를 보낼 때 사이드바에 나타난다.

**모델은 한 턴만큼 늦다.** Claude 의 `/model` 은 새 모델로 도는 첫 턴이 끝난 뒤에, opencode 의 모델 변경은
그 모델로 메시지를 보낸 뒤에 나타난다. 두 에이전트 모두 모델을 자기가 쓴 기록에 남기고, 바꾸는 순간 자체에
대한 이벤트는 없다.

**Claude 에서 바꾼 추론 강도는 턴이 끝날 때 글리프에 나타난다.** `/effort`(또는 모델 전환)는 다음
`PreToolUse` 나 `Stop` 에서 `$effort` 에 닿는다. 글리프는 다음 상태 변화 때, 그리고 늦어도 `Stop` 이 강도를
쓴 뒤에 다시 그려진다. 그래서 새 강도로 도는 첫 턴 동안에는 옛 모양이 남을 수 있다. 색은 언제나 지금
상태다. 도구 호출마다 다시 그리면 호출마다 백그라운드 실행이 하나씩 붙는다. 새 세션도 첫 턴이 끝나기
전까지는 `state_icon` 모양이다. opencode 는 바꾼 variant 가 메시지를 보내는 즉시 그려진다.

**색은 고정된 hex 값이고** 사이드바 설정에서 정한다. herdr 의 토큰 `fg` 는 `#RGB`·`#RRGGBB` 만 받으므로,
`state_icon` 처럼 터미널 테마를 따라가지 않는다. 접힌 사이드바와 space 행은 여전히 herdr 자신의 `state_icon` 을
쓴다. 플러그인 토큰이 닿지 않는 영역이다.

## 요구사항

- herdr ≥ 0.9.0 (Linux / macOS)
- Claude Code, 쓰기 가능한 `~/.claude/settings.json` — 그리고/또는
- opencode 2.x, 쓰기 가능한 `cli.json`(`$OPENCODE_CONFIG_DIR` 또는 `~/.config/opencode/`)
- herdr 서버의 `PATH` 에 `bash` 와 `jq`

## 설치

```sh
herdr plugin install unstable-code/herdr-agent-mode
```

개발 중에는 로컬 클론을 링크한다. 작업트리를 그대로 쓰므로 `git pull` 이 곧 업데이트다.

```sh
git clone https://github.com/unstable-code/herdr-agent-mode.git
herdr plugin link ./herdr-agent-mode
```

그다음 Claude 훅을 등록한다. `~/.claude/settings.json` 에 쓰는 일이라 저절로 일어나지 않고, 직접 부르는
액션으로 둔다.

```sh
herdr plugin action invoke unstable-code.herdr-agent-mode.install
```

다른 훅과 설정은 건드리지 않는다. 자기 항목은 명령 문자열이 아니라 마커 주석으로 식별하므로, 다시
설치하면 예전 항목을 바꿀 뿐 두 벌이 되지 않는다. `uninstall` 이 되돌리고(`herdr plugin uninstall` 은
이걸 하지 않으니 그 전에 돌린다), `status` 가 링크와 등록된 명령을 보여 준다. 돌고 있는 Claude 세션도 재시작 없이 반영된다.

같은 액션이 opencode 도 등록한다. `cli.json` 의 `"plugins"` 에 플러그인 상태 디렉터리의 링크
(`…/unstable-code.herdr-agent-mode/opencode`)를 더하고, 그 링크는 설치본의 `opencode/` 를 가리킨다 —
아래에서 설명하는 Claude 쪽 링크와 같은 이유다. herdr 자신의 `./herdr-opencode` 를 비롯한 다른 항목은
건드리지 않는다. 열려 있는 opencode 는 다음에 시작할 때 반영된다. 두 에이전트 중 설정 파일이 없는 쪽은
건너뛰고, 둘 다 없을 때만 실패한다. `cli.json` 에 주석이 있으면(JSONC) jq 로는 서식을 지킬 수 없어 손대지
않고, 직접 더할 경로를 알려 준다. `cli.json` 은 기기마다 따로 있으니 install 액션은 opencode 를 쓰는
기기마다 돌린다.

등록되는 명령은 설치본이 아니라 링크를 가리키고, 자기 존재 검사를 달고 간다.

```sh
p="$HOME"'/.local/state/herdr/plugins/unstable-code.herdr-agent-mode/bin/report'; [ -x "$p" ] || exit 0; exec "$p"  # herdr-agent-mode
```

링크는 플러그인의 상태 디렉터리에 있고, herdr 는 이 디렉터리를 플러그인 id 만으로 정한다. 링크는 지금
쓰는 설치본의 `bin/` 디렉터리를 가리킨다. herdr 0.9.5 부터는 설치와 `herdr plugin update` 가 매번 새
디렉터리(`…/github-installations/<id>-<해시>/<pid>-<n>/`)에 들어가므로, 설치본을 직접 가리키는 명령은 첫
업데이트에서 멈춘다 — 아래의 존재 검사 때문에 소리도 없이. 링크는 install 액션이 만들고, `[[startup]]`
훅이 다음 서버 시작 때 새 설치본으로 옮긴다. 둘 다 `settings.json` 은 건드리지 않으며, install 액션도
항목이 실제로 바뀔 때만 이 파일을 다시 쓴다.

Claude 는 훅 명령을 `/bin/sh` 로 돌리는데, 이 실패는 스크립트가 조용히 빠지기 **전에** 일어난다. 그래서
이 기기에 없는 경로가 등록돼 있으면 매 턴마다 `No such file or directory` 가 훅 수만큼 찍힌다. 드문 일이
아니다 — `~/.claude/settings.json` 은 보통 여러 기기가 공유하는 dotfiles 트리로의 심링크이고, install
액션을 돌린 기기는 그중 하나뿐이다.

링크 경로는 플러그인 id 와 홈 디렉터리로만 정해지므로, 여러 기기가 공유하는 `settings.json` 은 각 기기가
플러그인을 어떻게 설치했든 모두 같은 경로를 가리킨다. install 액션은 그중 한 기기에서만 돌리면 되고,
같은 파일을 공유하는 다른 기기는 herdr 서버가 다음에 뜰 때 startup 훅이 링크를 만든다. 링크가 없던 이전
버전, 또는 훅을 더 적게 등록하던 버전(`SessionStart` 는 모델과 함께 들어왔다)에서 올라왔다면 install 액션을
한 번 더 돌린다 — 옛 항목을 바꿔 주며, 그 전까지는 startup 훅이 그렇다는 알림을 띄운다.

마지막으로 토큰을 사이드바에 올린다. 행은 그중 어느 것을 써도 된다.

| 토큰 | 값 | 쓰임 |
|---|---|---|
| `$state_working` … `$state_unknown` | 추론 강도 글리프, 상태가 맞는 하나에만 | 첫 칸, `state_icon` 대신 |
| `$mode` | 글리프 한 칸: `▏▎▍▌▋█` | 폭이 없는 행 |
| `$mode_label` | 단어: `plan`·`deny`·`manual`·`edits`·`auto`·`bypass` | 폭이 되는 행 |
| `$model` | 모델: `opus 5.5`·`qwen3.6-35b-a3b` | 이름이 들어갈 폭이 있는 행 |
| `$effort` | 에이전트가 부르는 추론 강도: `high`·`none` | 단어로 보고 싶은 행 |

`$state_*` 다섯 개는 나란히 두고 각각 그 상태의 색을 준다. 아래 색은 herdr 기본 테마가 `state_icon` 에 쓰는
값이다.

```toml
[ui.sidebar.agents]
rows = [
  [{ token = "$state_working", fg = "#F9E2AF" }, { token = "$state_blocked", fg = "#F38BA8" },
   { token = "$state_done", fg = "#94E2D5" }, { token = "$state_idle", fg = "#A6E3A1" },
   { token = "$state_unknown", fg = "#6C7086" }, { token = "$mode", fg = "#999999", rules = [
    { equals = "▌", fg = "#AF87FF" },
    { equals = "▏", fg = "#48968C" },
    { equals = "▋", fg = "#FFC107" },
    { equals = "█", fg = "#FF5555", bold = true },
    { equals = "▎", fg = "#FF5555" },
  ] }, "workspace", "tab", "agent", "$model"],
  ["terminal_title_stripped"],
]
```

글리프의 두께는 그 모드가 통과시키는 양 순이다 — `▏` plan 은 읽기만, `█` bypass 는 아무것도 묻지 않는다.
그래서 막대는 같은 뜻을 색과 두께로 두 번 나른다. 멋이 아니라 필연이다. 사이드바 규칙은 **그 토큰 자신의
값**만 보므로, 모든 모드가 같은 막대였다면 색을 가를 근거가 없다. 덤으로 색이 안 보이는 상황에서도 읽힌다.

색은 Claude 가 페인 하단 모드 표시에 쓰는 값 그대로다 — accept edits `#AF87FF`, plan `#48968C`,
auto `#FFC107`(Claude 의 `warning` 토큰). manual 은 거기서 고유한 색 없이 본문색으로 그려지므로 여기서는
회색이고, 순환으로 닿을 수 없는 두 모드는 빨강으로 표시한다. Claude 의 라이트 테마에서 앞의 셋은
`#8700FF`·`#006666`·`#966C1E` 다.

⚠️ 폭이 넉넉하지 않다면 토큰을 행의 **맨 끝**에 둘 것. 행이 안 들어가면 herdr 는 가변 칸을 전부 끈 뒤
오른쪽부터 다시 켜므로 맨 왼쪽 칸이 가장 먼저 사라진다. 위 예시는 그 위험을 알고 감수한 것이다 — 상태
글리프 옆 한 칸이 끝에서 잘린 단어보다 낫다는 판단이다.

글리프가 없는 모드(Claude 가 나중에 추가하는 것)는 두 토큰 모두 단어로 나간다. 규칙 없는 글리프는 그냥
회색 막대라 다른 모드처럼 보이지만, 글자는 눈에 띄기 때문이다.

## 액션

| 액션 | 하는 일 |
|---|---|
| `install` | `~/.claude/settings.json` 에 Claude 훅을, opencode `cli.json` 에 TUI 플러그인을 등록하고, 이미 에이전트가 있는 페인에 상태 글리프를 그림 |
| `uninstall` | 다시 제거 |
| `status` | Claude 훅이 몇 개 등록돼 있는지, opencode 에 등록돼 있는지, 각각 어디에 있는지 |
| `clear` | 토큰이 붙은 모든 페인에서 이 플러그인의 토큰을 제거 |

각 액션은 herdr 알림으로 요약을 보고하고, 자세한 내용은 `herdr plugin log` 로 간다.

`clear` 는 훅은 두고 표시만 끄고 싶을 때, 그리고 `SessionEnd` 훅이 돌지 못한 채 Claude 세션이 끝난
페인(정상 종료가 아니라 강제 종료된 경우)을 정리할 때 쓴다. 페인 자체가 닫히면 할 일이 없다 — herdr 가
페인과 함께 토큰을 버린다.

## 설정

없다. 빠뜨린 것이 아니라 정한 것이다. 사이드바 규칙은 토큰 자신의 값을 보므로, 값의 모양을 바꾸는 설정은
사용자의 색 규칙을 조용히 무효로 만든다 — 그리고 규칙에 안 걸린 모드는 회색 막대라 "고장" 이 아니라
"manual" 처럼 보인다. 대신 두 모양을 토큰 둘로 함께 내보내고, 행이 원하는 쪽을 고른다.

## 검증

격리된 herdr 0.9.1 서버에서 훅 스크립트에 Claude Code 가 보내는 페이로드를 직접 먹이고, 남의 훅이 들어
있는 대역 `settings.json` 에 대고 확인했다.

| 항목 | 결과 |
|---|---|
| Claude 의 여섯 모드를 각각 보고 | `▍/manual`·`▌/edits`·`▏/plan`·`▋/auto`·`▎/deny`·`█/bypass` |
| 모르는 모드(`futureMode`) | 두 토큰 모두 그 단어로 |
| 모드를 안 싣는 이벤트(`Notification`) | 토큰 그대로 유지 |
| 깨진 JSON, 빈 stdin | 토큰 유지, 종료 코드 0, stderr 무출력 |
| herdr 밖에서 실행(`HERDR_ENV` 없음) | 종료 코드 0, 아무것도 보고 안 함 |
| `SessionEnd` | 두 토큰 삭제 |
| `clear` 액션 | `cleared 1 pane(s)`, 두 토큰 사라짐 |
| 옛 경로 항목이 남은 상태에서 `install` | 옛 항목 제거, 남의 훅과 herdr 자신의 `SessionStart` 및 무관한 설정은 그대로 |
| 등록된 명령을 `/bin/sh` 로 실행, 스크립트는 없는 상태 | 종료 코드 0, 아무 출력 없음 — 이슈 #1 이 보고한 경우 |
| 같은 조건에 플러그인 경로에 작은따옴표가 든 경우 | 쿼팅이 맞고 실행되며, `uninstall` 이 마커로 그대로 찾아낸다 |
| `uninstall` | 이 플러그인 항목만 사라짐 |
| 설치본을 직접 가리키던 항목 위에 install (herdr 0.9.5) | 옛 항목이 `p="$HOME"'/…/bin/report'` 로 바뀌고 `bin` 링크가 설치본을 가리킴. 다른 훅·설정은 그대로 |
| 바뀐 게 없는 상태에서 install 재실행 | `settings.json` 을 다시 쓰지 않음(mtime 동일) |
| 링크가 없는 기기에서 "업데이트": 다른 디렉터리에서 다시 등록하고 링크를 지운 뒤 서버 재시작 | `[[startup]]` 훅이 `settings.json` 의 항목을 보고 새 `bin/` 으로 링크를 만듦. `settings.json` 은 바이트 단위로 그대로 |
| 링크 이전의 옛 항목이 있는 채로 서버 시작 | 링크를 만들고 install 액션을 돌리라는 알림 한 번. 항목이 최신이면 알림 없음 |
| 처음 설치본을 지운 뒤 등록된 명령을 `/bin/sh` 로 `plan` 페이로드와 실행 | 링크를 거쳐 `▏`/`plan` 보고 (#2) |
| `uninstall` 후 재시작 | 훅과 함께 링크 제거, startup 훅이 다시 만들지 않음 |
| 상태 디렉터리가 `$HOME` 밖 | 명령에 절대경로로 기록 |
| 실제 Claude Code 2.1.285 에 대고 | `permission_mode` 가 `UserPromptSubmit`·`PreToolUse`·`Stop` 에 있고 `Notification` 에는 없음. 설정에 넣은 훅이 세션 재시작 없이 적용됨 |
| `cli.json` 에 herdr 항목이 있는 채로 install·재실행·uninstall (대역 파일) | 링크 항목이 끝에 더해지고, 재실행은 파일을 다시 쓰지 않으며, uninstall 후 원래 내용과 같음. `./herdr-opencode` 는 그대로 |
| 다른 상태 디렉터리에서 남은 옛 항목 | install 이 쓸어 내고 지금 링크 하나만 남김 |
| 주석이 든 `cli.json`(JSONC) | 손대지 않고 직접 더할 경로를 안내 |
| opencode 만 있는 기기 / 둘 다 없는 기기 | Claude 는 건너뛰고 opencode 만 등록 / 종료 코드 1 |
| opencode 링크를 지우고 startup 훅 명령(`hooks --relink`) 실행 | `cli.json` 의 항목을 보고 링크를 다시 만듦 |
| 실제 opencode 2.2.6 TUI 에 대고 | 홈 화면에서는 토큰 없음. Build 로 메시지 → `▍`/`build`, `shift+tab` 만 → 그대로, Plan 으로 메시지 → `▏`/`plan`, opencode 종료 → 두 토큰 삭제. 절대 경로로 등록한 플러그인 디렉터리가 로드됨 |
| 모델 id 줄이기 | `claude-opus-5-5` → `opus 5.5`, `claude-opus-5` → `opus 5`, `claude-haiku-4-5-20251001` → `haiku 4.5`, `claude-opus-5-5[1m]` → `opus 5.5[1m]`. `qwen3.6-35b-a3b`·`gpt-5.1`·`claude-3-5-sonnet-20241022` 는 그대로 |
| `SessionStart`(모델만), 이어서 `PreToolUse`(모드만) | 앞은 `$model` 만, 뒤는 모드만 보고하고 서로를 지우지 않음 |
| 이전 버전의 훅 넷 위에 install, 그 전의 서버 시작 | `SessionStart` 항목이 더해짐. 그 전까지 startup 훅이 install 액션을 돌리라고 알림 |
| 실제 Claude Code 2.1.330 에 대고 | `SessionStart` 에 `model` 이 있고 `permission_mode` 는 없음. `Stop` 에는 모델이 없고 transcript 에도 그 턴의 응답이 아직 없음 — 응답은 훅 시작 약 0.1초 뒤에 기록됨. 새 세션에 `SessionStart` 로 `haiku 4.5`, `/model sonnet` 뒤 첫 턴이 끝나자 `sonnet 5.5`, `/exit` 로 세 토큰 모두 삭제 |
| 실제 opencode 2.2.6 TUI 에 대고 | 메시지 → `▍`/`build` 와 `qwen3.6-35b-a3b`, 종료 → 세 토큰 삭제. 다른 모델로의 전환은 실측하지 않음 — 설정된 다른 모델이 유료 모델뿐이었다 |
| `clear` 액션 | 모드 토큰과 함께 `$model` 도 삭제. `$model` 만 붙은 페인도 대상 |
| 상태별 추론 강도 글리프 | 모든 상태에서 `low` `○`·`medium` `◐`·`high` `●`·`xhigh` `◉`·`max` `◈`·`none` `◌`. 없음이나 `default` 는 working·blocked·done `●`, idle `○`, unknown `·`. 모르는 단계는 그 단어 그대로 |
| 대역 페인에 `bin/state --all` | 토큰이 어긋난 페인만 보고: idle 페인에 남은 `done` 은 옮기고, 에이전트가 떠난 페인은 지우며, 맞는 페인과 일반 셸은 건드리지 않음. herdr 가 나중에 더할 상태(`thinking`)는 `$state_unknown` 으로 |
| 실제 Claude Code 2.1.330 에 대고 | `effort`(`{"level": …}`)는 `PreToolUse`·`Stop` 에 있고 `UserPromptSubmit` 과 Haiku 의 모든 이벤트에는 없음. Sonnet `medium`: `state_idle` → `state_working` `●`(아직 effort 없음) → `state_done` `◐`. `/effort low` 뒤 첫 도구 호출에서 `$effort` 가, 턴이 끝날 때 글리프가 `○` 로 바뀜 |
| 실제 herdr 0.9.5 에 대고 | 상태가 바뀔 때마다 이벤트 훅이 돎(회당 약 15ms). 페인을 봐서 `done` → `idle` 이 될 때는 상태 이벤트가 없었고 포커스 훅이 잡아냄(herdr 는 workspace·tab·pane 포커스 이벤트를 함께 내므로 `pane.focused` 하나만 쓴다). install 이 기존 에이전트 페인 전부에 `state_icon` 모양을 그림. 에이전트가 떠나면 전부 삭제 |
| 실제 opencode 2.2.6 TUI 에 대고 | `variant` `low` → `○`, ctrl+t 로 `medium` 으로 바꾸고 메시지를 보내자 `◐`. 종료하면 전부 삭제 |

## 제3자 저작물

이 플러그인은 herdr(Apache-2.0)를 대상으로 한다. herdr 의 코드나 바이너리를 재배포하지 않는다. 모드 이름과
세 가지 색은 Claude Code 자신의 값으로, 동작 중인 설치본에서 읽어 그 표시에 맞춘 것이며 Claude Code 의
코드를 포함하지 않는다.

## 라이선스

[MIT](LICENSE)
