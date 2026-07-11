# PixelForge Plugin Development

PixelForge v1 plugins are trusted GDScript code. They are not sandboxed and run with the user's permissions. Declare every capability in `permissions`, avoid secrets, and never imply that the declaration is enforced isolation.

## Start from the template

1. Copy `templates/plugin_template/` outside the application project.
2. Change `plugin.json.id` to a unique snake_case id and update name/version/author.
3. Namespace node types with that id. The included invert node demonstrates ports and synchronous execution.
4. Test as a directory by copying it to the folder shown by **File > Plugin Manager > Open Plugin Folder**.
5. Package it:

```bash
./scripts/pack_plugin.sh /path/to/my_plugin /tmp/my_plugin.pck
```

The output filename must match the manifest id. The packer forces every resource below `res://plugins/{id}/`; PixelForge rejects mismatched roots.

## Manifest

Required fields are `id`, `name`, `version`, `api_version`, `min_app_version`, and `entry`. `permissions` may include `network`, `filesystem_read`, or `filesystem_write`; these are disclosure only.

## PFPluginAPI v1

- `register_node_type(type, Script)` — the script must extend `PFNode` and return the identical type.
- `register_provider(PFProvider)` — implements Provider API v1.
- `register_pipeline_step(id, Script)` — adds a custom processing capability.
- `register_palette(id, value)` / `register_style_preset(id, Dictionary)`.
- `register_menu_item(path, Callable)`.
- `register_exporter(id, value)`.

Every successful registration is recorded in the plugin's private ledger. Disable, unload, or reload reverses the ledger in reverse order. A removed node type becomes a ghost when its graph is resolved again; its JSON remains intact and recovers after reinstall.

## Failure behavior

Invalid JSON, missing fields, incompatible versions, wrong entry types, duplicate registrations, and invalid scripts are isolated to that plugin and shown in Plugin Manager. One failure must not prevent PixelForge startup.
