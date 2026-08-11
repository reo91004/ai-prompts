# Delegated Task And Result Contract

Every field below earns its place by catching a specific mistake: a child that edits files it should not, reports done without evidence, or floods the parent with raw output. Do not add a field that only records process — if you cannot name the mistake it catches, leave it out.

## Task Packet

Every delegated task must contain:

- `objective`: one bounded deliverable;
- `agent`: the exact role name requested, or `main` when no child is used;
- `allowed_scope`: files, systems, data, and actions the child may inspect or change;
- `forbidden_scope`: explicit exclusions and protected state;
- `write_permission`: `read-only`, or the exact writable paths;
- `acceptance_criteria`: observable conditions and the deterministic evidence that proves them;
- `return_mode`: `concise_summary` or `full_result`.

Two children may not own the same deliverable. A child must stop before acting outside its packet.

High-volume work (large test suites, log mining, wide greps, document retrieval, large diffs) defaults to `return_mode: concise_summary`: the child writes raw output to an artifact and returns only the synthesis plus the path back to it, so delegation actually isolates context instead of relaying thousands of lines into the parent.

Select the role through the runtime's exact agent selector; a task label does not select a role. Never describe a generic child as the configured specialist — when the runtime hides the selector or the model controls, report that limitation instead of assuming the role took effect.

Run `scripts/detect_resources.sh` before a spawn wave and treat its `agent_slots` as a ceiling on how many children start. The snapshot governs the wave; it does not need to be copied into every packet.

## Long-Running Work

Any child command expected to run long (training, synthesis, capture, large trace preprocessing) declares before launch:

- `command`: the exact long-running command;
- `expected_artifacts`: paths the command should produce or extend;
- `checkpoint_path`: where resumable state is written, or `none`;
- `resume_command`: how to continue from the checkpoint, or `none`.

Keep routine progress in durable logs and checkpoints. Surface a model-visible event only for completion, failure, a permission request, confirmed sustained no-progress, or a resource or equipment emergency. Elapsed time or a wait timeout alone never fails or cancels a declared command. Before stopping anything, checkpoint, preserve logs and partial artifacts, and attempt graceful termination first.

## Result

Every child result must contain:

- `status`: `PASS`, `FAIL`, `BLOCKED`, or a specific `RESOURCE_*` status;
- `evidence`: artifact-specific observations supporting the status, with paths the parent can inspect instead of re-reading raw output;
- `commands`: commands with exit codes, including failed and unavailable checks;
- `artifacts`: created or inspected artifact paths;
- `remaining_risks`: unresolved risks, any deviation from the packet, and dependent work that stays blocked.

A result is incomplete if a required field is absent. A resource or tool failure must remain visible and cannot be converted to `PASS` by omission or reviewer judgment.
