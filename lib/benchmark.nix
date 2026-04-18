{
  lib,
  pkgs,
  taskModule,
}:

{
  packages ? [ ],
  commands,
  package ? pkgs.hyperfine,
  runs ? null,
  minRuns ? null,
  maxRuns ? null,
  warmup ? null,
  setup ? null,
  prepare ? null,
  cleanup ? null,
  exportJson ? null,
  exportMarkdown ? null,
  exportCsv ? null,
  parameterScan ? null,
  ...
}@args:

assert lib.assertMsg (
  runs == null || (minRuns == null && maxRuns == null)
) "mkBenchmarkTask: 'runs' and 'minRuns'/'maxRuns' are mutually exclusive";

let
  esc = lib.escapeShellArg;

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

  commandFlags = lib.concatMap (
    c:
    lib.optionals (c.name != null && parameterScan == null) [
      "-n"
      (esc c.name)
    ]
    ++ [ (esc (lib.trim c.command)) ]
  ) normalized;
in
builtins.removeAttrs args [
  "packages"
  "commands"
  "package"
  "runs"
  "minRuns"
  "maxRuns"
  "warmup"
  "setup"
  "prepare"
  "cleanup"
  "exportJson"
  "exportMarkdown"
  "exportCsv"
  "parameterScan"
]
// {
  raw = true;
  packages = packages ++ [ package ];
  command = lib.concatStringsSep " " (
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
      (esc (lib.trim setup))
    ]
    ++ lib.optionals (prepare != null) [
      "--prepare"
      (esc (lib.trim prepare))
    ]
    ++ lib.optionals (cleanup != null) [
      "--cleanup"
      (esc (lib.trim cleanup))
    ]
    ++ lib.optionals (exportJson != null) [
      "--export-json"
      (esc exportJson)
    ]
    ++ lib.optionals (exportMarkdown != null) [
      "--export-markdown"
      (esc exportMarkdown)
    ]
    ++ lib.optionals (exportCsv != null) [
      "--export-csv"
      (esc exportCsv)
    ]
    ++ lib.optionals (parameterScan != null) (
      [
        "--parameter-scan"
        (esc parameterScan.var)
        (toString parameterScan.min)
        (toString parameterScan.max)
      ]
      ++ lib.optionals (parameterScan ? step) [
        "--parameter-step-size"
        (toString parameterScan.step)
      ]
    )
    ++ commandFlags
  );
}
