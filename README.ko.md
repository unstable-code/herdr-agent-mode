# herdr-agent-mode

[English](README.md) | **한국어**

[Claude Code](https://claude.com/claude-code) 페인이 지금 어떤 권한 모드로 돌고 있는지를
에이전트 사이드바에 표시하는 [herdr](https://herdr.dev) 플러그인.

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
  바로 부른다. 즉 이 플러그인에는 herdr 이벤트 훅도, 데몬도 필요 없다 — Claude 훅이 곧 이벤트다.
- **훅은 넷을 등록하고**, 그중 셋이 모드를 실어 온다.

  | 훅 | 언제 | 무엇을 보고하나 |
  |---|---|---|
  | `UserPromptSubmit` | 프롬프트를 보낼 때 | 그 프롬프트를 보내는 모드 |
  | `PreToolUse` | 도구 호출 직전마다 | 턴이 도는 동안의 모드 |
  | `Stop` | 턴이 끝날 때 | 페인이 남는 모드 |
  | `SessionEnd` | Claude 종료·`/clear`·`/resume` | 두 토큰을 지운다 — 에이전트가 사라졌으므로 |

- **모드를 안 싣는 이벤트는 토큰을 건드리지 않는다.** Claude 는 시간이 지나며 필드를 더한다. 그 필드가 없는
  미래의 이벤트가 아직 맞는 값을 지워 버려서는 안 된다.
- **모든 실패는 조용하다.** herdr 가 없든, `jq` 가 없든, herdr 밖의 페인이든, 페이로드가 깨졌든 훅은 0으로
  끝나고 아무것도 보고하지 않는다. stderr 에 뭔가 쓰는 훅은 사용자가 신경 써야 하는 훅이고, 여기서 하는
  일 중 세션을 방해할 만큼 중요한 것은 없다 — 최악이라야 사이드바에 직전 모드가 남을 뿐이다.

## 못 하는 것

**사이드바가 보여주는 것은 그 페인이 마지막으로 뭔가 한 시점의 모드이지, 지금 이 순간의 설정이 아니다.**
Claude Code 에는 모드 변경으로 발생하는 훅 이벤트가 없고, 세션이 놀고 있는 동안에는 훅이 돌지 않는다.
그래서 모드를 바꾸고 아무것도 시키지 않으면 다음 프롬프트까지 옛 값이 그대로 보인다. 실제로 그 창은 짧다 —
보통 뭔가 시키려고 모드를 바꾸니까. 그래도 있는 것은 있는 것이고, 이 표시는 "지금 무엇으로 설정돼 있나"
보다 "무엇으로 돌고 있었나" 에 답한다는 점은 알고 쓰는 편이 낫다.

`dontAsk` 와 `bypassPermissions` 는 `shift+tab` 순환에 아예 없다. 세션을 시작할 때 정해진다
(`claude --permission-mode …`, `--dangerously-skip-permissions`, 설정의 `defaultMode`). 그래서 이 둘은
늦을 것 자체가 없다.

## 요구사항

- herdr ≥ 0.9.0 (Linux / macOS)
- Claude Code, 쓰기 가능한 `~/.claude/settings.json`
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

다른 훅과 설정은 건드리지 않는다. 자기 항목은 명령 문자열이 아니라 마커 주석으로 식별하므로, 플러그인이
옮겨간 뒤(오늘은 링크한 작업트리, 내일은 설치본) 다시 설치해도 옛 항목이 남지 않는다 — 남으면 Claude 가
도구 호출마다 없는 명령을 부르게 된다. `uninstall` 이 되돌리고, `status` 가 몇 개 등록돼 있는지 알려
준다. 돌고 있는 Claude 세션도 재시작 없이 반영된다.

등록되는 명령은 자기 존재 검사를 달고 간다.

```sh
p='/path/to/herdr-agent-mode/bin/report'; [ -x "$p" ] || exit 0; exec "$p"  # herdr-agent-mode
```

Claude 는 훅 명령을 `/bin/sh` 로 돌리는데, 이 실패는 스크립트가 조용히 빠지기 **전에** 일어난다. 그래서
이 기기에 없는 경로가 등록돼 있으면 매 턴마다 `No such file or directory` 가 네 번씩 찍힌다. 드문 일이
아니다 — `~/.claude/settings.json` 은 보통 여러 기기가 공유하는 dotfiles 트리로의 심링크이고, install
액션을 돌린 기기는 그중 하나뿐이다.

⚠️ 모든 기기에서 같은 방식으로 설치할 것. `herdr plugin install` 은 플러그인 id 만으로 만든 디렉터리에
넣는다 — 접미사가 `sha256(id)` 의 앞 6바이트라 커밋도 호스트명도 들어가지 않아, 경로가 어디서나 같고
업데이트해도 유지된다. `herdr plugin link` 는 작업트리가 있는 자리에 쓰므로, 공유 설정 파일이 기기마다
어긋나는 원인이 된다.

마지막으로 토큰을 사이드바에 올린다. 토큰은 둘이고, 행은 하나만 써도 되고 둘 다 써도 된다.

| 토큰 | 값 | 쓰임 |
|---|---|---|
| `$mode` | 글리프 한 칸: `▏▎▍▌▋█` | 폭이 없는 행 |
| `$mode_label` | 단어: `plan`·`deny`·`manual`·`edits`·`auto`·`bypass` | 폭이 되는 행 |

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", { token = "$mode", fg = "#999999", rules = [
    { equals = "▌", fg = "#AF87FF" },
    { equals = "▏", fg = "#48968C" },
    { equals = "▋", fg = "#FFC107" },
    { equals = "█", fg = "#FF5555", bold = true },
    { equals = "▎", fg = "#FF5555" },
  ] }, "workspace", "tab", "agent"],
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
아이콘 옆 한 칸이 끝에서 잘린 단어보다 낫다는 판단이다.

글리프가 없는 모드(Claude 가 나중에 추가하는 것)는 두 토큰 모두 단어로 나간다. 규칙 없는 글리프는 그냥
회색 막대라 다른 모드처럼 보이지만, 글자는 눈에 띄기 때문이다.

## 액션

| 액션 | 하는 일 |
|---|---|
| `install` | `~/.claude/settings.json` 에 Claude 훅을 등록 |
| `uninstall` | 다시 제거 |
| `status` | 자기 훅이 몇 개 등록돼 있는지, 어디에 있는지 |
| `clear` | 토큰이 붙은 모든 페인에서 두 토큰을 제거 |

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
| 실제 Claude Code 2.1.285 에 대고 | `permission_mode` 가 `UserPromptSubmit`·`PreToolUse`·`Stop` 에 있고 `Notification` 에는 없음. 설정에 넣은 훅이 세션 재시작 없이 적용됨 |

## 제3자 저작물

이 플러그인은 herdr(Apache-2.0)를 대상으로 한다. herdr 의 코드나 바이너리를 재배포하지 않는다. 모드 이름과
세 가지 색은 Claude Code 자신의 값으로, 동작 중인 설치본에서 읽어 그 표시에 맞춘 것이며 Claude Code 의
코드를 포함하지 않는다.

## 라이선스

[MIT](LICENSE)
