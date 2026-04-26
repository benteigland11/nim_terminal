
## Cartograph

When trying to fix things, always look to modify an existing widget or add a widget. Don't rely on glue code to fix bugs. Glue code is config, not logic.

Widget library manager. Widgets are reusable code modules with tests,
examples, and metadata. Installed widgets live under `cg/<widget_id>/`.

widget_id format: `<domain>-<name>-<language>` (e.g. `backend-retry-backoff-python`)

When using `cartograph create`, only provide the name. The `--domain` and
`--language` flags are prepended and appended automatically.
Example: `cartograph create retry-backoff --domain backend --language python`
creates `backend-retry-backoff-python`.

### Domains

    backend    Request handling, APIs, databases, queues, caching
    data       Transformation, parsing, serialization, pipelines, file I/O
    ml         Model loading, inference, embeddings, training utilities
    security   Authentication, authorization, encryption, input sanitization
    infra      Deployment, config management, logging, monitoring, health checks
    frontend   UI rendering, templating, client-side logic
    universal  Pure utilities with no domain dependency (string ops, retry, math, date handling)
    modeling   Parametric and generative representations of physical or visual things — 3D geometry, surfaces, shapes, simulations
    rtl        Register-transfer level hardware design — synthesizable digital logic modules

### Config keys  (set with: cartograph config <key> <value>)

    auto-publish       Auto-publish to cloud on every checkin  (default: False)
    visibility         Default visibility for published widgets  (default: public)
    governance         Default contribution governance model  (default: protected)
    cloud              Enable cloud registry integration  (default: True)
    auto-update        Check for new Cartograph CLI releases and recommend upgrades  (default: True)
    show-unavailable   Show widgets for languages not installed on this machine  (default: True)
    publish-registry   Default registry prefix for --publish on local widgets (e.g. myorg). Defaults to the public registry (cg) if not set.  (default: —)

### Commands

All commands run from your project root. Widgets install to `cg/` in the
current directory (or the directory specified by `--target`).

**Use widgets**

    search <query> [--domain DOMAIN] [--language LANGUAGE] [--top-k 10]
      Search the widget library

    inspect <widget_id> [--source] [--all-versions] [--reviews] [--version VERSION]
      Show widget details

    install <widget_id> [--target .] [--version VERSION]
      Install a widget into your project

    uninstall <widget_dir>
      Remove a widget from your project

    upgrade <widget_dir> [--version VERSION]
      Upgrade an installed widget to the latest version

    status [widget_dir] [--page 1] [--size 20] [--all]
      Check installed widget(s) - omit widget_dir to scan all

    rate <widget_id> <score> [--comment COMMENT]
      Rate a widget (local dir path or @handle/widget-id for cloud)


**Build widgets**

    create <widget_id> [--language angular|javascript|nim|openscad|php|python|systemverilog|typescript] [--domain backend|data|frontend|infra|ml|modeling|rtl|security|universal] [--name NAME] [--target .]
      Scaffold a new widget

    rename <widget_id> [--name NAME] [--domain backend|data|frontend|infra|ml|modeling|rtl|security|universal] [--target .]
      Rename a scaffolded widget's slug or domain (pre-checkin, Python-only)

    validate [path] [--lib]
      Run the validation pipeline on a widget

    checkin [path] [--reason REASON] [--bump minor] [--publish] [--override-warnings] [--override-reason OVERRIDE_REASON]
      Check a widget into the library (--publish to also publish)

    rollback <widget_id> [--version VERSION] [--reason REASON]
      Roll back a widget to a previous version (local + cloud)

    delete <widget_id> [--confirm]
      Remove a widget from the library (and cloud if published)


**Cloud registry**

    cloud publish [widget_id] [path] [--lib] [--visibility public|private] [--governance open|protected] [--override-warnings] [--override-reason OVERRIDE_REASON]
      Publish a widget to the cloud registry

    cloud adopt <local_id> <cloud_id> [--force]
      Link a local widget to its cloud counterpart

    cloud unpublish <widget_id> [--confirm]
      Remove a widget from the cloud (keeps local)

    cloud settings <widget_id> [--governance open|protected] [--visibility public|private]
      View or change a cloud widget's settings

    cloud sync [--dry-run]
      Sync library with cloud (higher version wins, both directions)

    cloud proposals [widget_id] [proposal_id] [--accept] [--reject] [--reason REASON] [--diff]
      List, accept, or reject proposals


**Config**

    registry [action] [url] [--prefix PREFIX] [reg_prefix]
      Manage additional widget registries

    config [key] [value] [--json]
      View or change settings (config [key] [value])

    rules [action] [--language LANGUAGE] [--global project] [--confirm] [--content CONTENT] [--from-file FROM_FILE] [--json]
      List and manage custom validation rules

    workflow [name] [source] [extra]
      List, view, or create workflows

    setup [--agent claude|codex|gemini|antigravity|cursor] [--file FILE] [--print] [--workflow WORKFLOW] [--overwrite]
      Set up Cartograph for your AI agent (auto-detects and appends)

    login [--token TOKEN] [--registry REGISTRY]
      Authenticate with the Cartograph cloud registry

    logout
      Remove stored cloud credentials

    whoami
      Show current authenticated user

    dashboard [--port 0] [--set-port SET_PORT] [--stop]
      Open local widget dashboard in browser

    export [--output OUTPUT]
      Export widget library as a zip file

    import <path> [--force]
      Import widgets from a zip file into the library

    stats
      Show library statistics

    doctor
      Check language engine dependencies
