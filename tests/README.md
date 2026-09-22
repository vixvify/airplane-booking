# Tests and regression coverage

Run on Linux with a writable `/ipc`, in a dedicated IPC namespace with no other reservation server:

```bash
bash scripts/test.sh
```

On Windows, use the Docker instructions in the root README. Git Bash can run
`bash tests/script_tests.sh` without a server; this tests shell behavior using a
mock transport, not a real Kubernetes cluster.

## The eight audited bugs

| Bug | Regression | Expected result |
| --- | --- | --- |
| Shared request/reply queue deadlocks under load | `regression_tests.sh`: 200 concurrent RESERVE requests | Separate shared request/response queues let all 200 complete with no transport failures and exactly one winner in sync mode |
| Starting another server destroys the active queue | `regression_tests.sh`: duplicate server; `integration_tests.sh`: crash recovery | Duplicate exits unsuccessfully; original reservation survives; stale queue can still be recovered after SIGKILL |
| Long commands execute a truncated prefix | `regression_tests.sh`: 129-byte invalid reservation and 127-byte valid command | Reject the entire long input, preserve seat state, continue the session |
| Overflow in a seat list accepts the valid prefix | `unit_tests.cpp`, `regression_tests.sh`: RESERVE/CANCEL in both modes | Reject overflow without changing any seat |
| Concurrent script reports success when a subprocess fails | `script_tests.sh`: each of five clients, preflight, snapshot and live log failures | Nonzero exit, no success announcement, failure recorded in evidence |
| Unquoted kubectl executable path | `script_tests.sh`: run all Kubernetes smoke flows through a mock under Program Files | Ready check, exec, load and log calls all work with spaces in the executable path |
| Make does not rebuild changed sources/headers | `build_tests.sh`: isolated copied source tree | Source edit rebuilds client; message header edit rebuilds all executables; unchanged build is a no-op |
| QUIT with extra arguments closes the client | `regression_tests.sh`: QUIT extra, then STATUS, then valid QUIT | Invalid QUIT returns usage and accepts STATUS; valid QUIT ends the session |

Additional checks cover all five commands, validation, ownership, multi-seat
transactions, the three experiment modes, fixed-seat and round-robin load,
IPC timeouts and cleanup, concurrent sessions sharing an owner ID, and Demo 1.

## Evidence and CI

`scripts/test.sh` creates a unique `results/suite-.../` folder and saves the
combined output in `test-output.txt`. The integration and regression helpers
also preserve server logs, client commands/responses and load-test results.
Demo folders contain separate client and server streams plus `summary.txt`.

CI builds the Docker image, runs this same suite with a 300-second limit, and
uploads the `results/` artifact even on failure. The Kubernetes smoke suite
against a real cluster remains opt-in (`make test-k8s`), since it recreates the
demo Pod.

Latest local verification: 2026-09-22, working tree on
`fix/system-regressions`: **68 checks passed** (13 unit/transaction, 4 IPC,
27 integration, 10 regression, 11 script, 3 build). The same 11 script checks
also passed under Windows Git Bash.

The final full run used Ubuntu WSL with isolated IPC via bubblewrap. Earlier
Docker test runs passed, but Docker Desktop could not start during the final
verification, so a final-image run and real Kubernetes deployment were not
repeated. GitHub-hosted CI has been configured but has not been triggered yet.
