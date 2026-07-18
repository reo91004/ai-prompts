# First-Trigger Miss: Diagnosis, Recovery, And Warm-Up Contract

**Scope**: measurements where an external scope (e.g. PicoScope) is armed for a
block capture and the MCU (e.g. a ChipWhisperer target) then raises a short GPIO
trigger pulse. The worked numbers below are from a PicoScope 3000a + CW308
STM32F4 rig; the reasoning and checklist transfer to any arm-then-trigger setup.

**Status of the claim**: the first-capture miss and same-session retry recovery
are confirmed by toggle. The exact driver/device readiness stage that is late is
inference, not a confirmed cause — do not promote it.

## 1. Symptom

Suspect a first-acquisition trigger miss (not a USB-permission or firmware
failure) when all of these hold together:

- scope and target open successfully;
- firmware erase, program, and readback verify succeed;
- the target command ACK arrives normally;
- only the **first** trace returns after roughly `auto_trigger_ms`;
- the trigger channel's peak-to-peak swing is far below a normal pulse;
- re-arming the scope and resending the same command in the **same process**
  yields a normal trace.

Reference failure signature:

```text
auto trigger:       5,000 ms
failed swing:       16.98 mV     (noise-level buffer, correctly rejected)
quality threshold:  200 mV
normal swing:       390.56 mV
```

Lowering the swing gate to accept the `16.98 mV` buffer is not a fix — it turns a
noise-only auto-trigger buffer into a false "success".

A nonzero lock-command ACK status (e.g. `11`) after firmware upload is a
different failure (a packed-ternary / HWT semantic failure before the trigger),
not this symptom — diagnose that separately.

## 2. Reproduce with a toggle

- **Fail condition**: `capture_quality_retries: 0` exposes the first miss
  immediately. LLM-run and human-terminal receipts record the same signature
  (same swing, same exit code) apart from start time — so shell/PTY/USB-permission
  differences are ruled out as the cause.
- **Recovery condition**: keep identical hardware settings and payload, allow one
  quality retry (`capture_quality_retries: 1`). The retry consumes the failed
  attempt's ACK, re-arms, resends the same command, and returns a clean trace
  (e.g. 2/2 accepted, swing ≥ 390 mV, overflow 0, readback exact).

Toggle conclusion: **the first capture transaction is missed and a same-session
re-arm recovers it.** Which internal readiness stage is late stays unconfirmed.

## 3. Why a later trigger can succeed

Host order is: set buffer → RunBlock() → send serial command → wait/fetch → consume
ACK. A command that raises the trigger immediately on handler entry races the
scope's readiness; a command that decodes/packs first raises the trigger later and
tends to land after the scope is ready. Historical first-trace 5 s delays track
this (immediate-trigger routes hit it most, late-trigger routes least). This
supports a first-arm settling race but does not confirm causation. Note: running a
separate CLI twice mixes scope close/open and reflash — order-effect tests must
stay inside one process and one rig session.

## 4. Immediate recovery (diagnostic only)

For a diagnostic or short health smoke, `capture_quality_retries: 1` is enough:
on a quality failure only, consume the ACK, re-arm, resend the same command, and
recheck quality. Do not retry scope-open failures, capture timeouts, or missing
ACKs. This is fine to confirm the rig works, but a legacy summary that does not
record the rejected physical execution must not be used as claim-bearing evidence.

## 5. Safe solution for claim-bearing acquisition — audit-only warm-up

Do not handle the first-arm miss with a label-dependent hidden retry. Instead, at
each acquisition session start, run one predetermined warm-up whose policy and
inputs are fixed in advance and never conditioned on the label, key, query ID,
target output, swing, or capture result.

- Every discarded capture is a trigger-high physical execution: count it in the
  ledger and physical budget. Never hide warm-up / rejected / abandoned attempts
  to keep only successes.
- Record the session-start warm-up row as `eligible=false`,
  `reason=first_arm_warmup`, preserving attempt index, command/query identity, ACK
  result, observed trigger swing, power/trigger quality, and overflow regardless
  of outcome.
- After the warm-up, do a deterministic reset/prezero before preparing the first
  eligible query, so warm-up side effects do not leak into it.
- Treat a scope reconnect, acquisition reconfigure, or firmware flash as a new
  epoch and apply the same fixed one-shot re-warm, also counted as a
  `first_arm_warmup` physical execution. Never switch this on or off based on
  results.
- A native command that consumes prepared query or session state must not be
  silently resent through `capture_quality_retries`; a needed re-run appears as a
  separate physical execution under the attempt policy.
- Fixed order: `open → audit-only warm-up → reset/prezero → prepare actual query →
  eligible capture`. Implementations that skip this order or loop until a trace
  passes are forbidden. If warm-up/re-warm exhausts the cap, fail the block/session
  rather than hiding attempts.

### Full-window coverage is a separate gate

A valid warm-up does not guarantee the sample buffer contains the whole trigger
pulse. A buffer that is high from the rising edge to the end (no falling edge, no
post-low) does not prove full operation coverage — widen the window / adjust
timebase and pre-trigger until the complete pulse (rising, falling, post-low) sits
inside the buffer, and record the real interval, sample count, and duration in
provenance. Warm-up closes first-arm miss and physical accounting; window coverage
closes full-operation coverage — they are different problems.

## 6. Continue / stop rules

- If hardware capture and acceptance evidence both PASS, continue to the planned
  next implementation, measurement, analysis, and documentation without waiting
  for re-approval.
- Fix trivial, non-semantic errors (formatting, lint, path) and continue; these do
  not count as hardware retries.
- On a major logical error that threatens experiment validity or claim integrity,
  stop immediately and preserve the error and artifacts — do not reclassify it as
  trivial or route around it with a retry.
- On a hardware capture quality failure, preserve the failed artifact and ledger
  row first; allow at most the one pre-declared retry, recorded as a separate
  attempt through reset/prezero and query re-prep.
- Two consecutive quality failures → stop immediately. Never loop until success or
  hide a native resend inside `capture_quality_retries`.

## 7. Common wrong fixes

- lowering the trigger-swing gate (accepts a noise-only auto-trigger buffer);
- increasing auto-trigger time (a missed edge never returns; only failure is
  delayed);
- unbounded retries (hides physical budget and failure rate);
- resending a state-consuming native command as a quality retry (hides
  query/session consumption);
- saving only successful traces (erases the real physical-execution count and rig
  instability);
- reading a separate-CLI sequence as a state experiment (close/open/reflash is not
  a same-session comparison);
- blaming LLM permissions when open/program/fetch already succeeded.

## 8. Claim boundary

Allowed, at most:

> On this rig a fresh-process first immediate-trigger capture can be missed, and a
> single same-session quality retry recovered a normal trigger with exact
> readback.

Converted in a claim-bearing session to an audit-only warm-up plus a full-window
check, this stays an acquisition claim — not leakage, D2/D3, or recovery.

Not yet allowed: naming a specific driver function/thread as the cause; asserting a
minimal settle delay; claiming a hidden-retry legacy capture satisfies physical
accounting; or reading a short diagnostic run as leakage/recovery evidence.

## 9. Reuse checklist

- [ ] confirmed the failure time equals auto-trigger time;
- [ ] separated device-open, firmware-verify, ACK, and capture-quality failures;
- [ ] compared the trigger-channel raw swing against a normal run;
- [ ] ran a retry 0/1 (or warm-up off/on) toggle with the same payload;
- [ ] tested order effects in one rig session, not separate processes;
- [ ] recorded rejected/warm-up attempts in the physical ledger;
- [ ] applied the fixed one-shot warm-up at session start and after
      reconnect/reconfigure/flash, independent of results;
- [ ] did a deterministic reset/prezero after warm-up before the real query;
- [ ] used no hidden `capture_quality_retries` for a state-consuming native command;
- [ ] kept hardware quality retries ≤ the pre-declared one, preserving each failed
      artifact;
- [ ] stopped on two consecutive quality failures and on any major logical error;
- [ ] fixed only trivial non-semantic errors before continuing;
- [ ] fixed the threshold unit and confirmed the actual SDK argument;
- [ ] limited the success claim to health/acquisition scope.
