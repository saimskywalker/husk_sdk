/// Build Flutter plugins with or without a closed-source native SDK.
///
/// Most people use the command line tool (`dart run husk_sdk`). This
/// library exposes the same pieces for scripts and tests: load a
/// `HuskSpec`, plan the generated files with `planFiles` and write them
/// with `applyPlan`, inspect vendor binaries, and build the `doctor` /
/// `check` report with `diagnose`.
library;

export 'src/cli.dart' show exitOk, exitProblems, exitUsage, runCli;
export 'src/diagnose.dart' show diagnose, platforms;
export 'src/inspect/aar.dart' show AarInfo, inspectAar;
export 'src/inspect/macho.dart' show Linkage, detectLinkage;
export 'src/inspect/plist.dart' show parsePlist;
export 'src/inspect/xcframework.dart'
    show XcSlice, XcframeworkInfo, inspectXcframework;
export 'src/link.dart'
    show LinkResult, clearSwiftPmManifestCache, copyTree, link, unlink;
export 'src/names.dart' show dropDirName, normalizeRelative;
export 'src/output.dart'
    show
        BlockEdit,
        FileOutcome,
        FileStatus,
        InsertAt,
        OwnedFile,
        PlanException,
        PlannedFile,
        applyPlan,
        generatedMarker;
export 'src/report.dart' show Finding, Level, Section;
export 'src/spec.dart'
    show
        AndroidSpec,
        DartSpec,
        HuskSpec,
        IosSpec,
        MavenSpec,
        SpecException,
        specFileName;
export 'src/templates.dart' show disableEnvVar, planFiles;
export 'src/version.dart' show packageVersion;
