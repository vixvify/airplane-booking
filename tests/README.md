# Tests and regression coverage

Run the core suite on Linux inside a dedicated IPC namespace with writable `/ipc`:

```bash
bash scripts/test.sh
```

On Windows, the root README describes running the project in one Docker container. The shell script tests use a mock Docker executable, so they do not need a running Docker Engine.

## Audited bugs

| Bug | Regression | Expected result |
| --- | --- | --- |
| Shared request/response routing stalls under load | `regression_tests.sh`: 200 concurrent RESERVE requests | All complete without transport failures and sync mode has one winner |
| Starting another server destroys the active queue | `regression_tests.sh`: duplicate server; `integration_tests.sh`: crash recovery | Duplicate exits unsuccessfully; original reservation survives; stale queue can be recovered after SIGKILL |
| Long commands execute a truncated prefix | `regression_tests.sh`: invalid 129-byte and valid 127-byte command | Reject the full invalid input and preserve seat state |
| Overflow in a seat list accepts a valid prefix | `unit_tests.cpp`, `regression_tests.sh`: RESERVE/CANCEL in both modes | Reject overflow without changing any seat |
| Concurrent script reports success after a subprocess fails | `script_tests.sh`: container readiness, snapshot, stream and client failures | Nonzero exit, no success announcement, and failure recorded in evidence |
| Container wrapper breaks when Docker executable path contains spaces | `script_tests.sh`: mock Docker under a path containing spaces | Docker calls retain correct argument boundaries |
| Make does not rebuild changed sources/headers | `build_tests.sh`: isolated copied source tree | Changes rebuild dependent binaries; unchanged build is a no-op |
| QUIT with extra arguments closes the client | `regression_tests.sh`: invalid QUIT, STATUS, valid QUIT | Invalid QUIT returns usage and keeps the session open |

Additional checks cover all client commands, validation, ownership, multi-seat transactions, the three experiment modes, stable load-test client IDs and seat mappings, IPC timeouts and cleanup, concurrent sessions, and Demo 1.

Script tests also verify that the concurrent experiment accepts a configurable client count and all four commands while Demo 1 remains fixed at five clients. `tui_tests.sh` simulates key presses, checks command selection, menu navigation and editable values, verifies alternate-screen transitions, keeps action logs in the normal scrollback buffer, and prevents regressions that clear or redraw the complete screen after every key press.

## Container smoke suite

`make test-container` starts one isolated container and checks all three experiment configurations, a custom worker count, client command flow, load-test throughput, and Demo 1. The test stops only its uniquely named container when it exits.

The core suite stores its transcript under `results/tests/suite/<UTC timestamp>/test-output.log`. Integration, regression, build, script and container smoke outputs each have their own category under `results/tests/`.

CI builds the image, runs the core suite, runs the container smoke suite, and uploads `results/` even when a test fails.
