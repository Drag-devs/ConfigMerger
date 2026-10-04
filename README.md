# ConfigMerger

A Windows PowerShell GUI for merging an existing `key = value` configuration file into a newer configuration template without losing the settings you choose to retain.

ConfigMerger uses the new template as the output structure. It preserves the template's comments, sections, ordering, line-ending style, and final-newline state while selectively carrying over values from the existing config.

## Screenshots

### Merge summary

![ConfigMerger main window showing a successful merge summary](https://github.com/user-attachments/assets/e2cd9715-9121-49e3-9812-a87c17ebdf66)

### Changed-setting review

![ConfigMerger review dialog comparing existing values with template defaults](https://github.com/user-attachments/assets/a42f0960-7fdb-4e4a-b4ac-5abb14a2c617)

## Features

- Windows Forms interface with file browsers for existing config, new template, and output path.
- Default output path is the existing config filename with `.merged` appended.
- Optional custom output filename and location.
- Review dialog for settings whose existing values differ from the template defaults.
- Per-setting checkbox selection, plus Check all and Uncheck all actions.
- Side-by-side, scrollable full-value comparison for long settings.
- Clear merge summary of retained overrides, template defaults accepted, new settings, and removed settings.
- Preserves comments, blank lines, section layout, ordering, line endings, and final-newline state from the new template.
- Reads valid UTF-8 config files and writes UTF-8 output without a BOM.
- Rejects duplicate setting keys to prevent ambiguous merges.
- Recognizes both `#` and `;` comment lines.

## Requirements

- Windows
- Windows PowerShell 5.1 or PowerShell 7+
- Valid UTF-8 configuration files

The script automatically relaunches in an STA Windows PowerShell process when required for the UI.

## Run

From PowerShell in the repository directory:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ConfigMerger.ps1
```

If your execution policy already allows local scripts, this also works:

```powershell
.\ConfigMerger.ps1
```

## How It Merges

1. Select the existing config file.
2. Select the new config template.
3. Optionally change the output path. Otherwise, ConfigMerger uses `<existing-config>.merged`.
4. Keep **Review changed settings before merge** enabled to choose each changed existing value.
5. Click **Merge configs**.
6. In the review dialog, checked rows retain the existing value; unchecked rows use the new template default.
7. Click **Apply selection** to write the merged config and view its summary.

| Setting state | Output behavior |
| --- | --- |
| Exists only in the existing config | Omitted from output |
| Exists only in the new template | Added with template default |
| Exists in both with the same value | Kept unchanged |
| Exists in both with different values | Existing value when checked; template default when unchecked |

## Important Behavior

- The new template controls the final file structure. Comments and sections from the existing config are not copied into the output.
- The selected output path may be an existing file, including either input file. Choosing such a path overwrites that file.
- Config files with duplicate active setting keys are rejected. Resolve duplicates before merging.
- Configuration files must be valid UTF-8. Output is always UTF-8 without a BOM.

## Supported Config Syntax

ConfigMerger expects active settings in this form:

```ini
Example.Setting = value
```

Hash and semicolon comment lines are ignored:

```ini
# This is a comment
; This is also a comment
Example.Setting = value
```

## License

Released under [The Unlicense](LICENSE). You may use, copy, modify, distribute, and sell this software for any purpose without attribution or other restrictions.
