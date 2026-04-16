{
  lib,
  pkgs,
  taskModule,
}:

{
  # task
  packages ? [ ],

  # hyperfine
  commands, # string, or list of strings, or list of { command, name? }
  package ? pkgs.hyperfine,
  runs ? null,
  minRuns ? null,
  maxRuns ? null,
  warmup ? null,
  setup ? null,
  prepare ? null,
  cleanup ? null,
  shell ? null,
  exportJson ? null,
  exportMarkdown ? null,
  exportCsv ? null,
  status ? null,
  parameterScan ? null, # { var, min, max, step? }
  reference ? null,
  referenceName ? null,
}:

assert lib.assertMsg (
  runs == null || (minRuns == null && maxRuns == null)
) "mkBenchmarkTask: 'runs' and 'minRuns'/'maxRuns' are mutually exclusive";

let
  escapeCmd = cmd: "'${lib.replaceStrings [ "'" ] [ "'\"'\"'" ] (lib.trim cmd)}'";

  normalizeCommand =
    cmd:
    if builtins.isString cmd then
      {
        command = cmd;
        name = null;
      }
    else
      cmd;

  normalized =
    if builtins.isString commands then
      [
        {
          command = commands;
          name = null;
        }
      ]
    else
      map normalizeCommand commands;

  commandFlags =
    if parameterScan != null then
      map (c: escapeCmd c.command) normalized
    else
      lib.concatMap (
        c:
        lib.optionals true (
          lib.optionals (c.name != null) [ "-n '${c.name}'" ] ++ [ (escapeCmd c.command) ]
        )
      ) normalized;
in
{
  raw = true;

  packages = packages ++ [ package ];

  command = lib.concatStringsSep " " (
    lib.filter (s: s != "") (
      [ (lib.getExe package) ]
      ++ lib.optionals (runs != null) [
        "--runs"
        (toString runs)
      ]
      ++ lib.optionals (minRuns != null) [
        "--min-runs"
        (toString minRuns)
      ]
      ++ lib.optionals (maxRuns != null) [
        "--max-runs"
        (toString maxRuns)
      ]
      ++ lib.optionals (warmup != null) [
        "--warmup"
        (toString warmup)
      ]
      ++ lib.optionals (setup != null) [
        "--setup"
        (lib.trim setup)
      ]
      ++ lib.optionals (prepare != null) [
        "--prepare"
        (lib.trim prepare)
      ]
      ++ lib.optionals (cleanup != null) [
        "--cleanup"
        (lib.trim cleanup)
      ]
      ++ lib.optionals (shell != null) [
        "--shell"
        shell
      ]
      ++ lib.optionals (exportJson != null) [
        "--export-json"
        exportJson
      ]
      ++ lib.optionals (exportMarkdown != null) [
        "--export-markdown"
        exportMarkdown
      ]
      ++ lib.optionals (exportCsv != null) [
        "--export-csv"
        exportCsv
      ]
      ++ lib.optionals (parameterScan != null) (
        [
          "-P"
          parameterScan.var
          (toString parameterScan.min)
          (toString parameterScan.max)
        ]
        ++ lib.optionals (parameterScan ? step) [
          "--parameter-step-size"
          (toString parameterScan.step)
        ]
      )
      ++ lib.optionals (reference != null) [
        "--reference"
        reference
      ]
      ++ lib.optionals (referenceName != null) [
        "--reference-name"
        referenceName
      ]
      ++ commandFlags
    )
  );
}
