# Leader contributor guidance

Godot is the authoritative world simulator. Models choose goals and skills; Luau methods request world operations. Keep model intent separate from verified world results. See ARCHITECTURE.md and services/skill-runtime/luau_sdk.md.

## Code Review Rules

### World facts and information boundaries

Flag changes that grant unseen world knowledge, treat private thoughts as public speech, or change inventory/ownership/needs based only on model text. Require actual world operations and outcomes; do not loosen collision/contact rules to make an individual skill pass.

### Skill verification and cancellation

Flag publishing a skill version different from the tested version, bypassing capability checks, or allowing cancelled/timed-out jobs to install or continue actions. Keep generated code in the restricted runtime and preserve fixed dependency versions.

### Local services and credentials

Flag committed credentials, account exports, runtime histories, or exposing local service endpoints publicly. Tests should not invoke paid providers without explicit selection. Distinguish offline tests, real-model results and visual validation.

Use targeted tests. Windows Godot 4.6.2 is the primary game runtime; cloud Linux review cannot establish Windows/VR behavior without corresponding evidence. Do not claim visual or microphone validation from static analysis.
