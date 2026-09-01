---
tool: colima
category: virtualization
man_section: 1
related: [docker, limactl, nerdctl]
last_used: 2026-08-31
tags: [tool, macos, container, vm, isolation]
---

# `colima`

## Purpose
macOS에서 리눅스 VM 을 띄우고 그 안에 컨테이너 런타임을 구동한 뒤, **VM 안의 데몬을 호스트의 `docker` 명령에 연결해주는** 얇은 래퍼. 이름은 **Co**ntainers on **Li**nux on **Ma**c.

## Full Signature
```
colima <command> [flags]
colima -p <profile> <command> [flags]      # 프로파일 = 독립된 VM
```

## 왜 VM 이 필요한가

컨테이너는 **리눅스 커널 기능**이다 — namespace, cgroup, capability. macOS 에는 리눅스 커널이 없다. 따라서 커널을 어디선가 가져와야 하고, **유일한 방법이 VM 이다.**

> macOS 의 모든 Docker 솔루션(Docker Desktop, OrbStack, colima, Podman Desktop)은 예외 없이 리눅스 VM 을 띄운다. **차이는 "VM 을 쓰느냐"가 아니라 "얼마나 잘 숨기느냐"뿐이다.**

```
macOS (XNU)
├── limactl hostagent            ← colima 가 부리는 VM 관리자 (Lima 프로젝트)
└── Virtualization.framework VM  ← 애플이 제공하는 하이퍼바이저
    ├── /usr/bin/dockerd         ← 진짜 데몬은 여기서 돈다
    └── containerd-shim-runc-v2  ← 개별 컨테이너 실행기
```

**colima 자체는 아무것도 안 한다.** `limactl` 을 시켜 VM 을 띄우고, 배포판·런타임을 설치하고, 소켓을 연결한다. 그 과정을 한 줄로 묶은 것이 전부다.

## 파일 배치 — 관리의 출발점

| 경로 | 정체 |
|---|---|
| `~/.colima/<profile>/colima.yaml` | **네가 편집하는 설정 파일** |
| `~/.colima/_lima/colima/lima.yaml` | colima 가 위에서 생성한 lima 설정. **직접 고치지 마라 — 재생성된다** |
| `~/.colima/_lima/colima/disk` | VM 디스크. **sparse file** (apparent ≫ 실점유) |
| `~/.colima/_lima/colima/ha.stderr.log` | ⭐ **VM 이 안 뜰 때 여기부터** |
| `~/.colima/<profile>/docker.sock` | 호스트 `docker` 가 말을 거는 유닉스 소켓 |

## Common Commands

| 명령 | 하는 일 | 남는 것 / 사라지는 것 |
|---|---|---|
| `colima start` | VM 기동 (~20초). `colima.yaml` 을 읽는다 | |
| `colima stop` | VM 정지, CPU/RAM 반납 | 디스크·이미지·볼륨 **보존** |
| `colima restart` | stop + start | |
| `colima status` | 현재 프로파일 상태 | |
| `colima list` | **모든 프로파일** (정지된 것 포함) | |
| `colima delete` | ⚠️ **VM 디스크까지 삭제** | 설정만 남고 이미지 전부 소멸 → 재빌드 필요 |
| `colima ssh [-- cmd]` | VM 안으로 접속 / 명령 실행 | |
| `colima prune` | **다운로드 캐시** 정리 (VM 디스크 아님) | |
| `colima template` | 새 프로파일의 기본 템플릿 편집 | |

## `start` 의 주요 플래그

| 플래그 | 뜻 | 주의 |
|---|---|---|
| `-c, --cpus N` | CPU 개수 | 실행 중 변경 불가 → `stop` 먼저 |
| `-m, --memory N` | GiB (소수 가능) | 위와 동일 |
| `-d, --disk N` | GiB | **늘리기만 된다.** 줄이려면 `delete` 후 재생성 |
| `-a, --arch` | `aarch64` / `x86_64` | 비네이티브면 `vz` 불가 |
| `-t, --vm-type` | `vz` / `qemu` / `krunkit` | `vz`=Virtualization.framework, 네이티브 전용·빠름 |
| `-V, --mount PATH[:w]` | 마운트할 호스트 경로. `:w`=쓰기 가능 | **`none` 으로 전면 비활성화 가능** |
| `--mount-type` | `virtiofs` / `sshfs` / `9p` | vz 에서는 virtiofs 가 기본·최속 |
| `-r, --runtime` | `docker` / `containerd` / `incus` | |
| `-e, --edit` | 기동 전 `colima.yaml` 을 `$EDITOR` 로 연다 | |
| `-p, --profile` | **모든 명령에 붙는 전역 플래그** | 프로파일 = 독립 VM |
| `--save-config` | **기본 true** — 준 플래그가 yaml 에 영구 반영 | 일회성이면 `--save-config=false` |
| `-f, --foreground` | 포그라운드 실행 | 부팅 실패 진단에 유용 |
| `-v, --verbose` | 상세 로그 | |

## Idiomatic Examples

### 일상 사이클
```bash
colima start
docker context ls          # colima * 인지 확인 ← 생략하면 나중에 이상한 에러로 만난다
# ... 작업 ...
colima stop
```

### 리소스 변경 (실행 중엔 안 먹는다)
```bash
colima stop
colima start --cpu 6 --memory 8
```

### 프로파일로 다른 아키텍처 VM 병행
```bash
colima start -p x86 --arch x86_64 --vm-type qemu --cpu 4 --memory 4
colima list
docker context use colima-x86
```

### 마운트 범위 좁히기 (기본은 홈 전체 rw)
```bash
colima stop
colima start --mount "$HOME/Developer/workspace:w"

# 반드시 검증
colima ssh -- ls ~                      # 홈이 안 보여야 성공
colima ssh -- mount | grep virtiofs     # 실제 마운트 목록
```

### VM 내부 진단
```bash
colima ssh -- df -h                     # VM 디스크 여유  ← macOS df 로는 안 보인다
colima ssh -- free -h                   # VM 메모리
colima ssh -- systemctl status docker   # 데몬 살아있나
tail -f ~/.colima/_lima/colima/ha.stderr.log
```

## Pitfalls

> [!warning] Common Mistakes
> 1. ⭐ **정지하면 `docker` 가 전부 실패한다.** VM 이 없으면 소켓도 없다. 컨텍스트가 `default`(`unix:///var/run/docker.sock`, 존재하지 않음)로 되돌아가 `Cannot connect to the Docker daemon` 이 뜬다. **진단은 `docker context ls` 하나면 된다.**
> 2. ⭐ **`docker system prune -a` 가 베이스 이미지를 지운다.** `-a` 는 "어떤 컨테이너도 쓰지 않는 이미지"를 전부 삭제한다. 컨테이너를 `--rm` 으로 돌리면 종료 시점에 이미지를 붙잡는 컨테이너가 **하나도 없으므로**, 직접 빌드한 이미지가 통째로 날아가고 재빌드해야 한다. → **`docker builder prune` 또는 `docker image prune` 을 기본으로.**
> 3. **`--save-config` 가 기본 켜져 있다.** 한 번 `--cpu 8` 로 띄우면 그 뒤로 계속 8이다.
> 4. **실행 중 리소스 변경은 무시된다.** `stop` → `start` 가 필요하다.
> 5. **디스크는 축소 불가.** `docker system prune` 을 해도 sparse 파일 크기는 안 줄어든다 — 한 번 커진 sparse 파일은 작아지지 않는다. 진짜 회수는 `delete` 후 재생성뿐.
> 6. **`~/.colima/_lima/.../lima.yaml` 직접 편집은 헛수고다.** colima 가 매 기동마다 `colima.yaml` 에서 재생성한다.
> 7. **`colima ssh -- cmd` 의 `--` 를 빼먹으면** 뒤따르는 `-h` 같은 플래그를 colima 가 자기 것으로 가로챈다.

## Edge Cases

- **`mounts: []` 는 "마운트 없음"이 아니라 "기본값 사용"이다.** 실제 마운트는 lima 설정을 봐야 안다 — 기본은 **홈 디렉토리 전체 `writable: true`**. 컨테이너 `-v` 범위를 아무리 좁혀도 **VM 층에서는 홈 전체가 보인다**. 컨테이너 탈출 시 파일 접근 범위가 여기서 결정된다.
- **sparse file**: `ls -lh` 의 apparent size 와 `du -h` 의 실점유가 크게 다르다. 디스크 압박을 볼 땐 `du` 를 봐라.
- **`binfmt: true`** 면 VM 이 `qemu-x86_64` 등을 등록하므로 **비네이티브 아키텍처 컨테이너가 qemu-user 로 돈다.** 빠르지만 `ptrace`/`gdb` 가 불안정하다 — 디버깅이 목적이면 아키텍처 전용 프로파일이 낫다.
- 상시 데몬으로 등록하지 않으면(`brew services` 미사용) **재부팅 후 항상 정지 상태**다. 이건 버그가 아니라 선택이다 — 안 쓸 때 도는 VM 은 그 자체가 공격 표면이다.

## Related Tools

| Tool | Relationship |
|---|---|
| `docker` | colima 가 연결해주는 대상. CLI 는 껍데기, 데몬은 VM 안 |
| `limactl` | colima 가 내부적으로 부리는 VM 관리자. `limactl list`/`shell` 로 한 층 아래를 직접 볼 수 있다 |
| Docker Desktop / OrbStack | alternative — 같은 VM 구조, 상주 데몬·통합 기능이 더 많고 라이선스가 다르다 |

## Concepts This Implements
- [[Concepts/Linux/Setuid]] — `--security-opt no-new-privileges` 가 무력화하는 바로 그 권한 상승 경로
- [[Concepts/Linux/Process_Creation]] — 컨테이너가 결국 namespace 로 격리된 프로세스라는 점

## Quick Reference

```bash
colima start / stop / restart / status / list       # 생명주기
colima delete                                       # ⚠️ 디스크까지 삭제
docker context ls                                   # ⭐ 문제 생기면 여기부터
colima ssh -- df -h                                 # VM 디스크 (macOS df 로는 안 보임)
colima stop && colima start --cpu 6 --memory 8      # 리소스 변경
colima start -p NAME --arch x86_64 --vm-type qemu   # 다른 아키텍처 VM
colima start --mount "$HOME/work:w"                 # 마운트 범위 축소
docker builder prune                                # 안전한 정리 기본값
docker system df                                    # 무엇이 얼마나 먹나
```

> [!flashcard]
> **Q**: `colima stop` 후 `docker ps` 가 실패하는 이유와 진단 명령은?
> **A**: VM 이 없으면 `~/.colima/<profile>/docker.sock` 도 없다. CLI 는 멀쩡하고 말 걸 상대만 사라진 것. 컨텍스트가 `default` 로 되돌아간다 → `docker context ls` 로 확인, `colima start` 또는 `docker context use colima`.

> [!flashcard]
> **Q**: 직접 빌드한 이미지를 쓰는 환경에서 `docker system prune -a` 가 위험한 이유는?
> **A**: `-a` 는 컨테이너가 참조하지 않는 이미지를 전부 지운다. `--rm` 컨테이너는 종료 시 사라지므로 유휴 시점엔 참조가 0 → 베이스 이미지가 삭제되고 재빌드해야 한다.

---

## Background
Lima(**Li**nux **ma**chines) 프로젝트 위에 얹힌 래퍼로, Abiosoft 가 개발했다. Docker Desktop 의 대기업 유료화(2021) 이후 대안으로 확산됐다. Apache 2.0, 상주 프로세스가 `colima start` 중에만 존재하는 것이 설계 특징이다.

## External Refs
- `colima --help`, `colima start --help` (man page 는 제공되지 않는다)
- Lima: `limactl --help`
- GitHub: https://github.com/abiosoft/colima
