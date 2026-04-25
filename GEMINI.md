# Project Gemini Mandates

## Widget Contribution Workflow
- **Validation First**: ALWAYS use `cartograph validate` for incremental testing and debugging of widget changes.
- **Verification Mandate**: DO NOT use `cartograph checkin` until a feature or fix has been empirically verified to work as expected on the target hardware (especially for performance-sensitive rendering or driver-level logic).
- **Consistency**: Maintain self-contained widgets (no inter-widget dependencies) as required by the Cartograph architecture.
