# Options system (`nansen.options`)

This document describes the design of the options system in NANSEN: how
parameters for methods are defined, edited, saved and recorded together
with results. It covers the goals, the principles behind the design, prior
art that inspired it, the architecture, and a plan for migrating the rest
of NANSEN to it.

- [Motivation](#motivation)
- [Goals](#goals)
- [Principles](#principles)
- [Prior art](#prior-art)
- [Architecture](#architecture)
- [Usage](#usage)
- [File formats](#file-formats)
- [Migration plan](#migration-plan)
- [Open questions / future work](#open-questions--future-work)

## Motivation

The legacy system (`nansen.manage.OptionsManager`) has several problems:

- **No schema.** Options are plain structs. Types, allowed values, bounds
  and descriptions live in several places, or nowhere: `_` config fields for
  the UI, unused `V` validation structs, and `% comments` that are parsed
  with a fragile regex. There is no validation when options are edited or
  loaded.
- **Five ways to define defaults.** These are functions returning structs,
  session-method structs with `DefaultOptions`, `HasOptions` classes,
  `OptionsAdapter` classes, and `+presets` packages. `getFunctionType` needs
  a lot of special-case code to detect which one is in use.
- **No provenance.** Options saved with results (e.g. `NormcorreOptions`)
  have no NANSEN version, git commit or dependency versions. So you can't
  tell which code produced a result.
- **Silent drift.** Presets are copied into a `.mat` file on first use and
  then patched when the code changes. A change to a default value silently
  changes the options of every custom options set derived from it.
- **Opaque storage.** Everything for a method is kept in one binary
  `.mat` file, which can't be diffed, reviewed, shared or read from
  other languages.
- **Hard to evolve.** Renaming a parameter breaks saved options, because
  there is no versioning or migration.

## Goals

1. **Options have schemas.** Each parameter has a type, default,
   allowed values, bounds, units, description and UI hints, all defined in
   one place.
2. **Options are saved with provenance.** Results carry the complete
   options, the NANSEN version and git commit, the MATLAB and toolbox versions,
   and the versions of external dependencies.
3. **Options are easy to build and change.** A small, fluent API makes it
   easy to add parameters or change defaults. Versioned migrations keep
   saved profiles working.
4. **Multiple profiles per method.** Users can save many named profiles,
   derive profiles from presets or other profiles, and choose a default.

## Principles

These principles, mostly borrowed from reproducible data science and
experiment tracking, guided the design:

| Principle | How it is applied |
|---|---|
| **Single source of truth** | The schema, defined in code, is the only place where parameters are defined. The UI config, JSON Schema, docs table and validation are all generated from it. |
| **Record everything needed to reproduce** | Every run gets an `OptionsRecord`. It holds the *complete* resolved values, not a reference to a mutable profile and not just the overrides. It also holds a provenance snapshot of the code and environment. |
| **Never change results silently** | Profiles keep a snapshot of their resolved values. If inherited defaults change, resolving the profile warns and lists every changed value. Frozen profiles never change. |
| **Separate intent from state** | A profile stores *overrides* (what the user deliberately changed) plus a *snapshot* (what the values were). The record stores the final state. |
| **Fail fast** | Values are validated when a profile is created, loaded or overridden, not hours into a batch job. |
| **Separate result-affecting from operational parameters** | `Transient` parameters (verbosity, number of workers, …) are excluded from the options hash. |
| **Content-addressed identity** | A SHA-256 hash of the canonical, non-transient values identifies a configuration. Two results with the same hash were made with the same options, which is useful for caching and deduplication. |
| **Lineage per value** | The record says where each value came from: `defaults`, `preset:<name>`, `profile:<name>` or `runtime`. |
| **Explicit versioning and migrations** | Schemas use semantic versions. Migrations upgrade old profiles, and the upgrades are logged in the record. |
| **Human- and machine-readable formats** | Profiles and records are JSON. They are diffable, reviewable, easy to share through git or a project folder, and readable from Python. Schemas can be exported as standard JSON Schema. |
| **Backwards compatibility** | Legacy definitions are inferred into schemas automatically. The schema can produce the legacy structeditor format, and legacy custom options can be imported. |

## Prior art

| Tool | What we borrowed |
|---|---|
| **Hydra / OmegaConf** (Python) | Layered composition (defaults → config group → overrides) and runtime overrides using dotted names. The resolved config is saved automatically next to every output, together with the overrides used. |
| **Pydantic, traitlets, JSON Schema** | Typed schemas with validation, descriptions and defaults, exportable to a language-neutral schema format. |
| **Sacred, MLflow, Weights & Biases** | Capturing config, git commit, dirty state and dependency versions for every run. Using a hash of the config as the run identity. |
| **DVC `params.yaml`** | Only the parameters that affect a stage should invalidate its results, which is our `Transient` flag. Plain-text parameter files under version control. |
| **DataJoint (MATLAB/Python, neuroscience)** | Parameter sets identified by a hash (e.g. `ClusteringParamSet` in the DataJoint Elements) to prevent duplicates and link results to exact parameters. |
| **SpikeInterface** | Default parameters and their descriptions exposed per sorter. Each run writes a log with the parameters and the sorter version. |
| **CaImAn `CNMFParams`** | Parameters grouped by category with consistency checks. |
| **MATLAB `arguments` / `mustBe*` validators** | Our `Validator` attribute accepts `mustBe*` functions directly, as well as `@(x) assert(...)` style validators from legacy `V` structs. |
| **Semantic versioning, database migrations** | Versioned schemas with ordered, logged migration functions. |
| **W3C PROV / NWB** | Provenance as the entity (result), the activity (method + options) and the agent (user + code version). |

## Architecture

```
code/+nansen/+options/
├── Schema.m          Definition of all parameters of a method (+ presets, migrations)
├── Parameter.m       Definition of a single parameter (type, default, validation, UI hints)
├── Profile.m         A named set of options, stored as overrides + snapshot
├── ProfileStore.m    Saves/loads profiles as JSON files
├── Manager.m         Resolves options from layers, manages profiles
├── OptionsRecord.m   What is saved with results: values, sources, hash, provenance
├── Provenance.m      Captures NANSEN/MATLAB/dependency versions, git commit, system info
├── getSchema.m       Finds (or infers) the schema of a method
├── +migrate/         Helpers for writing migrations (renameField, removeField, convertValue)
└── +internal/        JSON codec, hashing, git info, struct utilities
```

### Resolution layers

```
 Schema defaults ──► Preset ──► User profile(s) ──► Runtime overrides ──► values + OptionsRecord
   (code)           (code)     (JSON, can chain)     (name-value pairs)
```

Each layer overrides values of the previous one. A user profile can have
another profile or a preset as its parent. The `OptionsRecord` stores the
source of each final value.

### Schema definition conventions

`nansen.options.getSchema(methodName)` finds a schema using these rules:

1. **Recommended:** a class with a static `getOptionsSchema()` method that returns a
   `nansen.options.Schema`.
2. Legacy (the schema is inferred and `IsInferred` is `true`):
   - a class with a static `getDefaultOptions()` (e.g. `HasOptions` subclasses)
   - a class with a static `getOptions()` (toolbox option adapters)
   - a function that returns an options struct (optionally in `DefaultOptions`)

   For legacy methods, `_` config fields become choices, sliders or
   internal/transient flags. `+presets` classes become schema presets, and
   trailing `% comments` become descriptions.

### Drift detection and frozen profiles

A profile stores `Overrides`, the values that differ from its parent, and a
`Snapshot`, all values at the time it was saved. When a profile is
resolved:

- **Normal profile:** inherited values come from the current
  defaults/parent. If they differ from the snapshot, a
  `NANSEN:Options:InheritedValuesChanged` warning lists every changed
  value. `refreshProfile` accepts the changes.
- **Frozen profile:** values come from the snapshot and never change.
  Parameters added later get their default values.

### Versioning rules for developers

- Increase the schema **patch** version for description or UI-only changes.
- Increase the **minor** version when you add parameters or change defaults.
- Increase the **major** version when you rename, remove or change the meaning
  of parameters, and add a migration:

```matlab
schema.addMigration('1.2.0', '2.0.0', @(S) nansen.options.migrate.renameField( ...
    S, 'windowSize', 'Baseline.windowSize'), 'Moved windowSize to Baseline group')
```

Migrations receive partial structs (profile overrides), so they must only
change fields that are present. The helpers in `nansen.options.migrate`
already do this.

## Usage

### Defining options for a method

```matlab
methods (Static)
    function schema = getOptionsSchema()
        schema = nansen.options.Schema(mfilename('class'), 'Version', '1.0.0', ...
            'Title', 'Compute Delta F over F', ...
            'Dependencies', {'CNMFSetParms'});   % record versions of these toolboxes

        schema.addParameter('baseline', 20, ...
            'Description', 'Percentile of the signal used as baseline (F0)', ...
            'Units', 'percentile', 'Min', 0, 'Max', 100, 'Integer', true)
        schema.addParameter('Run.numWorkers', 4, 'Transient', true)

        schema.addPreset('Fast', {'baseline', 10}, 'Quick preview settings')
    end
end
```

See `ophys.twophoton.process.signalExtraction.computeDff.getOptionsSchema`
for a complete example.

### Working with profiles

```matlab
m = nansen.options.Manager('ophys.twophoton.process.signalExtraction.computeDff');

m.listProfiles()                                   % Defaults, presets and user profiles
m.createProfile('Slow drift', {'correctBaseline', true}, ...
    'Description', 'For recordings with slow baseline drift')
m.setDefaultProfile('Slow drift')

[opts, record] = m.resolve();                      % default profile
[opts, record] = m.resolve('Slow drift', 'baseline', 10);   % + runtime override

opts = m.edit('Slow drift');                       % open options editor
m.updateProfile('Slow drift', opts)

m.compareProfiles('Defaults', 'Slow drift')
m.importLegacyOptions()                            % import from legacy OptionsManager
```

### Saving records with results

```matlab
[opts, record] = m.resolve(profileName);
result = runMethod(data, opts);
S = record.toStruct();              % plain struct, loadable without NANSEN
save(resultFile, 'result', 'S')     % or record.writeJson(sidecarFile)

% Later
record = nansen.options.OptionsRecord.fromStruct(S);
record.Provenance.Nansen.Commit
record.compare(otherRecord)          % which values differ?
record.isEquivalent(otherRecord)     % same (non-transient) options?
```

## File formats

Profiles are stored in `<location>/<methodName>/<profileName>.json`. The
default location is `nansen.localpath('custom_options')/profiles` for
NANSEN methods, and the project's `custom_options/profiles` folder for
project methods. Example:

```json
{
  "FormatVersion": "1.0",
  "Name": "Slow drift",
  "Description": "For recordings with slow baseline drift",
  "MethodName": "ophys.twophoton.process.signalExtraction.computeDff",
  "Type": "user",
  "Parent": "",
  "Frozen": false,
  "SchemaVersion": "1.0.0",
  "DefaultsHash": "9b64fd35…",
  "Created": "2024-05-01T10:00:00Z",
  "Modified": "2024-05-01T10:00:00Z",
  "CreatedBy": "username",
  "NansenVersion": "0.0.5",
  "Overrides": { "correctBaseline": true },
  "Snapshot": { "baseline": 20, "dffFcn": "dffClassic", "correctBaseline": true, "…": "…" }
}
```

Most values are stored as plain JSON. Values that plain JSON can't
represent exactly (NaN/Inf, matrices, column vectors, integer types, mixed
cell arrays, function handles) are written as tagged objects
(`{"nansen_type": …, "class": …, "size": …, "data": …}`) and restored
exactly when read.

`OptionsRecord` contains `MethodName`, `ProfileName`, `SchemaVersion`,
`Hash`, `Created`, `Values`, `RuntimeOverrides`, `Sources`, `MigrationLog`
and `Provenance`. `Provenance` holds:

- `Nansen`: `Version`, `Commit`, `Branch`, `RemoteUrl`, `IsDirty`, `Path`
- `Matlab`: `Version`, `Release`, `Toolboxes`
- `Dependencies`: `Name`, `FunctionName`, `Path`, `Commit`, `RemoteUrl`
- `Method`: `Name`, `FilePath`, `FileHash`
- `System`: `Computer`, `Hostname`, `User`

The git commit is read directly from `.git`, so git does not need to be
installed. Credentials in remote URLs are removed. The SHA-256 of the method's
source file identifies the exact code even when it has uncommitted changes.

## Migration plan

**Phase 1 (this change): core library**
- [x] `nansen.options` package: schema, profiles, JSON store, manager, records, provenance
- [x] Inference of schemas from all legacy option definitions (incl. `+presets`)
- [x] Generating the legacy structeditor format from schemas; importing legacy custom options
- [x] Example: `computeDff` defines `getOptionsSchema`, and a test checks that it matches the legacy defaults
- [x] Unit tests in `tests/options` (run with `runtests('tests/options')`)

**Phase 2: record options with results**
- [ ] In `nansen.DataMethod`, resolve options through `nansen.options.Manager` and
      keep the `OptionsRecord`. Save it with every output from `saveData`, as
      a sidecar `.json` file or a variable, and replace the ad-hoc
      `initializeOptions`/`*Options` variables in `MotionCorrection` and
      `RoiSegmentation`.
- [ ] Also record *derived* values (e.g. the toolbox options produced by
      `OptionsAdapter.convert`, which depend on the image size) in the record.
- [ ] Batch processor / pipelines: snapshot the resolved values when a job is
      queued, so editing a profile does not change queued jobs.

**Phase 3: user interface**
- [ ] Profile dropdown in the options editor backed by `nansen.options.Manager`
      (create, rename, delete, set default, compare).
- [ ] Show descriptions and units as tooltips in structeditor (it has no
      tooltip support yet), and support `Advanced` parameters.
- [ ] A warning dialog for `InheritedValuesChanged`, with "accept" and "keep old values"
      options.

**Phase 4: migrate methods**
- [ ] Add `getOptionsSchema` to session methods and toolbox wrappers. Convert
      `+presets` classes to `schema.addPreset`.
- [ ] Make `nansen.manage.OptionsManager` a thin adapter over
      `nansen.options.Manager`, then deprecate it.
- [ ] Update the session method templates.

**Phase 5: provenance hygiene**
- [ ] Make `nansen.version` consistent with `Contents.m` (currently 0.0.5 vs
      0.0.6) and bump it on each release/tag.
- [ ] Add versions or pinned commits to `nansen.setup.defaults.getAddonList`
      (there is already a TODO for this), so the environment can be recreated.
- [ ] Run `tests/` in CI (GitHub Actions supports MATLAB).

## Open questions / future work

- **Conditional parameters:** some parameters only matter when another is
  set (e.g. `correctionWindowSize` only if `correctBaseline`). An
  `EnabledIf` attribute would let the UI hide or disable them, and would
  document the dependency.
- **Cross-parameter constraints:** schema-level validators for constraints
  like `min < max`.
- **Data-dependent parameters:** parameters in physical units (seconds,
  microns) that are converted with the recording's metadata (frame rate, pixel
  size). The record should include both the given and the converted value.
- **Randomness:** methods with random initialization should expose a
  `randomSeed` parameter, so results are reproducible.
- **Input data provenance:** the options record describes *how* a result
  was made. Linking it to *what* it was made from (hashes or IDs of input
  files/variables) would complete the provenance graph.
- **Sharing profiles:** exporting/importing profile JSON files between users
  and projects, and promoting a user profile to a preset.
