# Merges values from an existing config into a new config template.
# The output uses the existing config's directory and filename with .merged appended.

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $powershellExe -ArgumentList '-NoProfile', '-STA', '-File', "`"$PSCommandPath`""
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Read-Utf8TextFile([string]$Path) {
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)

    try {
        return [System.IO.File]::ReadAllText($Path, $encoding)
    }
    catch [System.Text.DecoderFallbackException] {
        throw "Config file is not valid UTF-8: $Path"
    }
}

function Parse-Config([string]$Path) {
    $map = [ordered]@{}
    $content = Read-Utf8TextFile $Path
    $settingPattern = '(?m)^[ \t]*(?<Key>[^#;\s=]+)[ \t]*=[ \t]*(?<Value>[^\r\n]*)'

    foreach ($match in [System.Text.RegularExpressions.Regex]::Matches($content, $settingPattern)) {
        $key = $match.Groups['Key'].Value

        if ($map.Contains($key)) {
            throw "Duplicate setting key in config file: $key ($Path)"
        }

        $map[$key] = $match.Groups['Value'].Value.TrimEnd()
    }

    return $map
}

function Get-MergedOutputPath([string]$ExistingConfig) {
    $directory = [System.IO.Path]::GetDirectoryName($ExistingConfig)
    $fileName = [System.IO.Path]::GetFileName($ExistingConfig)
    return [System.IO.Path]::Combine($directory, "$fileName.merged")
}

function Write-Utf8NoBomFile([string]$Path, [string]$Content) {
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Output file was written with a UTF-8 BOM, which is not allowed: $Path"
    }
}

function Select-ExistingValuesToKeep([object[]]$ChangedKeys, [System.Collections.IDictionary]$OldValues, [System.Collections.IDictionary]$NewValues) {
    if ($ChangedKeys.Count -eq 0) {
        return @()
    }

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'Review changed settings'
    $dialog.StartPosition = 'CenterParent'
    $dialog.MinimumSize = [System.Drawing.Size]::new(960, 600)
    $dialog.Size = [System.Drawing.Size]::new(1120, 700)
    $dialog.BackColor = [System.Drawing.Color]::White

    $instructionsLabel = [System.Windows.Forms.Label]::new()
    $instructionsLabel.Text = 'Checked rows keep the existing config value. Unchecked rows use the new template default.'
    $instructionsLabel.Dock = 'Top'
    $instructionsLabel.AutoSize = $true
    $instructionsLabel.Padding = [System.Windows.Forms.Padding]::new(12, 12, 12, 8)

    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.MultiSelect = $true
    $grid.SelectionMode = 'FullRowSelect'
    $grid.ReadOnly = $false
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.AutoSizeRowsMode = 'AllCells'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = 'FixedSingle'
    $grid.ShowCellToolTips = $true
    $grid.DefaultCellStyle.Font = [System.Drawing.Font]::new('Cascadia Mono', 8.5)

    $keepColumn = [System.Windows.Forms.DataGridViewCheckBoxColumn]::new()
    $keepColumn.Name = 'Keep'
    $keepColumn.HeaderText = 'Keep existing'
    $keepColumn.FillWeight = 16

    $keyColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
    $keyColumn.Name = 'Key'
    $keyColumn.HeaderText = 'Setting key'
    $keyColumn.ReadOnly = $true
    $keyColumn.FillWeight = 24

    $existingColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
    $existingColumn.Name = 'ExistingValue'
    $existingColumn.HeaderText = 'Existing value'
    $existingColumn.ReadOnly = $true
    $existingColumn.FillWeight = 30
    $existingColumn.DefaultCellStyle = [System.Windows.Forms.DataGridViewCellStyle]::new()
    $existingColumn.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    $templateColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
    $templateColumn.Name = 'TemplateValue'
    $templateColumn.HeaderText = 'Template default'
    $templateColumn.ReadOnly = $true
    $templateColumn.FillWeight = 30
    $templateColumn.DefaultCellStyle = [System.Windows.Forms.DataGridViewCellStyle]::new()
    $templateColumn.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    [void]$grid.Columns.Add($keepColumn)
    [void]$grid.Columns.Add($keyColumn)
    [void]$grid.Columns.Add($existingColumn)
    [void]$grid.Columns.Add($templateColumn)

    foreach ($key in $ChangedKeys) {
        $rowIndex = $grid.Rows.Add()
        $grid.Rows[$rowIndex].Cells['Keep'].Value = $true
        $grid.Rows[$rowIndex].Cells['Key'].Value = $key
        $grid.Rows[$rowIndex].Cells['ExistingValue'].Value = [string]$OldValues[$key]
        $grid.Rows[$rowIndex].Cells['TemplateValue'].Value = [string]$NewValues[$key]
    }

    $grid.Add_CellToolTipTextNeeded({
        param($sender, $e)

        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0) {
            return
        }

        $columnName = $sender.Columns[$e.ColumnIndex].Name
        if ($columnName -eq 'ExistingValue' -or $columnName -eq 'TemplateValue') {
            $cellValue = $sender.Rows[$e.RowIndex].Cells[$e.ColumnIndex].Value
            if ($null -ne $cellValue) {
                $e.ToolTipText = [string]$cellValue
            }
        }
    })

    $reviewPanel = [System.Windows.Forms.Panel]::new()
    $reviewPanel.Dock = 'Fill'

    $detailsPanel = [System.Windows.Forms.TableLayoutPanel]::new()
    $detailsPanel.Dock = 'Bottom'
    $detailsPanel.Height = 220
    $detailsPanel.Padding = [System.Windows.Forms.Padding]::new(6)
    $detailsPanel.ColumnCount = 2
    $detailsPanel.RowCount = 2
    [void]$detailsPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 50))
    [void]$detailsPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 50))
    [void]$detailsPanel.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
    [void]$detailsPanel.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))

    $existingDetailsLabel = [System.Windows.Forms.Label]::new()
    $existingDetailsLabel.Text = 'Existing value'
    $existingDetailsLabel.Dock = 'Top'
    $existingDetailsLabel.AutoSize = $true
    $existingDetailsLabel.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 4)

    $existingDetailsTextBox = [System.Windows.Forms.TextBox]::new()
    $existingDetailsTextBox.Dock = 'Fill'
    $existingDetailsTextBox.Multiline = $true
    $existingDetailsTextBox.ReadOnly = $true
    $existingDetailsTextBox.ScrollBars = 'Both'
    $existingDetailsTextBox.WordWrap = $false
    $existingDetailsTextBox.Font = [System.Drawing.Font]::new('Cascadia Mono', 9)
    $existingDetailsTextBox.BackColor = [System.Drawing.Color]::White

    $templateDetailsLabel = [System.Windows.Forms.Label]::new()
    $templateDetailsLabel.Text = 'Template default'
    $templateDetailsLabel.Dock = 'Top'
    $templateDetailsLabel.AutoSize = $true
    $templateDetailsLabel.Padding = [System.Windows.Forms.Padding]::new(8, 6, 8, 4)

    $templateDetailsTextBox = [System.Windows.Forms.TextBox]::new()
    $templateDetailsTextBox.Dock = 'Fill'
    $templateDetailsTextBox.Multiline = $true
    $templateDetailsTextBox.ReadOnly = $true
    $templateDetailsTextBox.ScrollBars = 'Both'
    $templateDetailsTextBox.WordWrap = $false
    $templateDetailsTextBox.Font = [System.Drawing.Font]::new('Cascadia Mono', 9)
    $templateDetailsTextBox.BackColor = [System.Drawing.Color]::White

    $detailsPanel.Controls.Add($existingDetailsLabel, 0, 0)
    $detailsPanel.Controls.Add($templateDetailsLabel, 1, 0)
    $detailsPanel.Controls.Add($existingDetailsTextBox, 0, 1)
    $detailsPanel.Controls.Add($templateDetailsTextBox, 1, 1)
    $reviewPanel.Controls.Add($grid)
    $reviewPanel.Controls.Add($detailsPanel)

    $updateSelectedValueDetails = {
        if ($grid.SelectedRows.Count -eq 0) {
            $existingDetailsLabel.Text = 'Existing value'
            $templateDetailsLabel.Text = 'Template default'
            $existingDetailsTextBox.Text = ''
            $templateDetailsTextBox.Text = ''
            return
        }

        $selectedRow = $grid.SelectedRows[0]
        $selectedKey = [string]$selectedRow.Cells['Key'].Value
        $existingDetailsLabel.Text = "Existing value - $selectedKey"
        $templateDetailsLabel.Text = "Template default - $selectedKey"
        $existingDetailsTextBox.Text = [string]$selectedRow.Cells['ExistingValue'].Value
        $templateDetailsTextBox.Text = [string]$selectedRow.Cells['TemplateValue'].Value
    }

    $grid.Add_SelectionChanged($updateSelectedValueDetails)
    if ($grid.Rows.Count -gt 0) {
        $grid.Rows[0].Selected = $true
        & $updateSelectedValueDetails
    }

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Dock = 'Bottom'
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.Padding = [System.Windows.Forms.Padding]::new(12, 8, 12, 12)
    $buttonPanel.AutoSize = $true
    $buttonPanel.WrapContents = $false

    $okButton = [System.Windows.Forms.Button]::new()
    $okButton.Text = 'Apply selection'
    $okButton.AutoSize = $true

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = 'Cancel'
    $cancelButton.AutoSize = $true

    $keepAllButton = [System.Windows.Forms.Button]::new()
    $keepAllButton.Text = 'Check all'
    $keepAllButton.AutoSize = $true

    $useTemplateButton = [System.Windows.Forms.Button]::new()
    $useTemplateButton.Text = 'Uncheck all'
    $useTemplateButton.AutoSize = $true

    $buttonPanel.Controls.Add($okButton)
    $buttonPanel.Controls.Add($cancelButton)
    $buttonPanel.Controls.Add($useTemplateButton)
    $buttonPanel.Controls.Add($keepAllButton)

    $keepAllButton.Add_Click({
        foreach ($row in $grid.Rows) {
            $row.Cells['Keep'].Value = $true
        }
    })

    $useTemplateButton.Add_Click({
        foreach ($row in $grid.Rows) {
            $row.Cells['Keep'].Value = $false
        }
    })

    $okButton.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $cancelButton.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton
    $dialog.Controls.Add($reviewPanel)
    $dialog.Controls.Add($buttonPanel)
    $dialog.Controls.Add($instructionsLabel)

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $selectedKeys = @()

    foreach ($row in $grid.Rows) {
        if ($row.Cells['Keep'].Value -eq $true) {
            $selectedKeys += [string]$row.Cells['Key'].Value
        }
    }

    return $selectedKeys
}

function Merge-ConfigFiles([string]$ExistingConfig, [string]$NewConfig, [object[]]$KeysToKeepFromExisting, [string]$OutputConfigPath = $null) {
    if (-not (Test-Path -LiteralPath $ExistingConfig -PathType Leaf)) {
        throw "Existing config was not found: $ExistingConfig"
    }

    if (-not (Test-Path -LiteralPath $NewConfig -PathType Leaf)) {
        throw "New config was not found: $NewConfig"
    }

    $old = Parse-Config $ExistingConfig
    $new = Parse-Config $NewConfig
    $removedKeys = @($old.Keys | Where-Object { -not $new.Contains($_) })
    $addedKeys = @($new.Keys | Where-Object { -not $old.Contains($_) })
    $sharedKeys = @($new.Keys | Where-Object { $old.Contains($_) })
    $unchangedKeys = @($new.Keys | Where-Object { $old.Contains($_) -and $old[$_] -eq $new[$_] })
    $changedKeys = @($new.Keys | Where-Object { $old.Contains($_) -and $old[$_] -ne $new[$_] })

    if ($null -eq $KeysToKeepFromExisting) {
        $KeysToKeepFromExisting = $sharedKeys
    }

    $keysToKeepLookup = @{}

    foreach ($key in $KeysToKeepFromExisting) {
        $keysToKeepLookup[[string]$key] = $true
    }

    $retainedChangedKeys = @($changedKeys | Where-Object { $keysToKeepLookup.ContainsKey($_) })
    $templateChangedKeys = @($changedKeys | Where-Object { -not $keysToKeepLookup.ContainsKey($_) })
    if ([string]::IsNullOrWhiteSpace($OutputConfigPath)) {
        $outputConfig = Get-MergedOutputPath $ExistingConfig
    }
    else {
        $outputConfig = $OutputConfigPath.Trim()
    }

    $newContent = Read-Utf8TextFile $NewConfig
    $settingPattern = '(?m)^(?<Prefix>[ \t]*(?<Key>[^#;\s=]+)[ \t]*=[ \t]*)(?<Value>[^\r\n]*)'
    $output = [System.Text.RegularExpressions.Regex]::Replace($newContent, $settingPattern, {
        param($match)

        $key = $match.Groups['Key'].Value
        if ($old.Contains($key) -and $keysToKeepLookup.ContainsKey($key)) {
            return "$($match.Groups['Prefix'].Value)$($old[$key])"
        }

        return $match.Value
    })

    Write-Utf8NoBomFile $outputConfig $output

    return [pscustomobject]@{
        OutputConfig = $outputConfig
        AddedKeys = $addedKeys
        ChangedKeys = $changedKeys
        NewValues = $new
        OldValues = $old
        RetainedChangedKeys = $retainedChangedKeys
        RemovedKeys = $removedKeys
        SharedKeys = $sharedKeys
        TemplateChangedKeys = $templateChangedKeys
        UnchangedKeys = $unchangedKeys
    }
}

function Add-Section([System.Text.StringBuilder]$Builder, [string]$Heading, [object[]]$Keys, [scriptblock]$FormatKey) {
    [void]$Builder.AppendLine("$Heading ($($Keys.Count))")

    if ($Keys.Count -eq 0) {
        [void]$Builder.AppendLine('  None')
    }
    else {
        foreach ($key in $Keys) {
            [void]$Builder.AppendLine((& $FormatKey $key))
        }
    }

    [void]$Builder.AppendLine()
}

function Format-MergeSummary($Result) {
    $summary = [System.Text.StringBuilder]::new()
    [void]$summary.AppendLine('Merge complete')
    [void]$summary.AppendLine("Output: $($Result.OutputConfig)")
    [void]$summary.AppendLine("Retained existing overrides: $($Result.RetainedChangedKeys.Count)")
    [void]$summary.AppendLine("Unchanged shared settings: $($Result.UnchangedKeys.Count)")
    [void]$summary.AppendLine("Changed settings using template defaults: $($Result.TemplateChangedKeys.Count)")
    [void]$summary.AppendLine("New template settings: $($Result.AddedKeys.Count)")
    [void]$summary.AppendLine("Removed existing settings: $($Result.RemovedKeys.Count)")
    [void]$summary.AppendLine()

    Add-Section $summary 'Retained existing values that differ from template defaults' $Result.RetainedChangedKeys {
        param($key)
        "  $key`r`n    Existing value: $($Result.OldValues[$key])`r`n    Template default: $($Result.NewValues[$key])"
    }

    Add-Section $summary 'Changed settings using template defaults' $Result.TemplateChangedKeys {
        param($key)
        "  $key`r`n    Existing value (not kept): $($Result.OldValues[$key])`r`n    Template default used: $($Result.NewValues[$key])"
    }

    Add-Section $summary 'New settings using template defaults' $Result.AddedKeys {
        param($key)
        "  $key = $($Result.NewValues[$key])"
    }

    Add-Section $summary 'Removed settings not written' $Result.RemovedKeys {
        param($key)
        "  $key = $($Result.OldValues[$key])"
    }

    return $summary.ToString()
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Config Merge'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = [System.Drawing.Size]::new(760, 560)
$form.Size = [System.Drawing.Size]::new(860, 680)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

$layout = [System.Windows.Forms.TableLayoutPanel]::new()
$layout.Dock = 'Fill'
$layout.Padding = [System.Windows.Forms.Padding]::new(18)
$layout.ColumnCount = 3
$layout.RowCount = 6
[void]$layout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$layout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::AutoSize))
[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
$form.Controls.Add($layout)

$existingLabel = [System.Windows.Forms.Label]::new()
$existingLabel.Text = 'Existing config'
$existingLabel.AutoSize = $true
$existingLabel.Anchor = 'Left'

$existingTextBox = [System.Windows.Forms.TextBox]::new()
$existingTextBox.Dock = 'Fill'
$existingTextBox.Text = (Get-Location).Path

$existingBrowseButton = [System.Windows.Forms.Button]::new()
$existingBrowseButton.Text = 'Browse...'
$existingBrowseButton.AutoSize = $true

$newLabel = [System.Windows.Forms.Label]::new()
$newLabel.Text = 'New config'
$newLabel.AutoSize = $true
$newLabel.Anchor = 'Left'

$newTextBox = [System.Windows.Forms.TextBox]::new()
$newTextBox.Dock = 'Fill'
$newTextBox.Text = (Get-Location).Path

$newBrowseButton = [System.Windows.Forms.Button]::new()
$newBrowseButton.Text = 'Browse...'
$newBrowseButton.AutoSize = $true

$outputLabel = [System.Windows.Forms.Label]::new()
$outputLabel.Text = 'Output'
$outputLabel.AutoSize = $true
$outputLabel.Anchor = 'Left'

$outputTextBox = [System.Windows.Forms.TextBox]::new()
$outputTextBox.Dock = 'Fill'
$outputTextBox.BackColor = [System.Drawing.Color]::White

$outputBrowseButton = [System.Windows.Forms.Button]::new()
$outputBrowseButton.Text = 'Browse...'
$outputBrowseButton.AutoSize = $true

$reviewCheckBox = [System.Windows.Forms.CheckBox]::new()
$reviewCheckBox.Text = 'Review changed settings before merge'
$reviewCheckBox.AutoSize = $true
$reviewCheckBox.Checked = $true
$reviewCheckBox.Anchor = 'Left'

$mergeButton = [System.Windows.Forms.Button]::new()
$mergeButton.Text = 'Merge configs'
$mergeButton.AutoSize = $true
$mergeButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$mergeButton.ForeColor = [System.Drawing.Color]::White
$mergeButton.FlatStyle = 'Flat'

$statusLabel = [System.Windows.Forms.Label]::new()
$statusLabel.AutoSize = $true
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$statusLabel.Text = 'Select the existing and new config files.'

$resultsTextBox = [System.Windows.Forms.TextBox]::new()
$resultsTextBox.Dock = 'Fill'
$resultsTextBox.Multiline = $true
$resultsTextBox.ReadOnly = $true
$resultsTextBox.ScrollBars = 'Both'
$resultsTextBox.WordWrap = $false
$resultsTextBox.Font = [System.Drawing.Font]::new('Cascadia Mono', 9)
$resultsTextBox.BackColor = [System.Drawing.Color]::White

$layout.Controls.Add($existingLabel, 0, 0)
$layout.Controls.Add($existingTextBox, 1, 0)
$layout.Controls.Add($existingBrowseButton, 2, 0)
$layout.Controls.Add($newLabel, 0, 1)
$layout.Controls.Add($newTextBox, 1, 1)
$layout.Controls.Add($newBrowseButton, 2, 1)
$layout.Controls.Add($outputLabel, 0, 2)
$layout.Controls.Add($outputTextBox, 1, 2)
$layout.Controls.Add($outputBrowseButton, 2, 2)
$layout.Controls.Add($reviewCheckBox, 0, 3)
$layout.SetColumnSpan($reviewCheckBox, 3)
$layout.Controls.Add($mergeButton, 0, 4)
$layout.Controls.Add($statusLabel, 1, 4)
$layout.SetColumnSpan($statusLabel, 2)
$layout.Controls.Add($resultsTextBox, 0, 5)
$layout.SetColumnSpan($resultsTextBox, 3)

$fileFilter = 'Config files (*.conf;*.dist;*.txt;*.merged;*.bak)|*.conf;*.dist;*.txt;*.merged;*.bak|All files (*.*)|*.*'

$selectFile = {
    param([System.Windows.Forms.TextBox]$Target)

    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter = $fileFilter
    $dialog.CheckFileExists = $true
    $dialog.FileName = $Target.Text

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dialog.FileName
    }
}

$existingBrowseButton.Add_Click({ & $selectFile $existingTextBox })
$newBrowseButton.Add_Click({ & $selectFile $newTextBox })

$outputPathIsCustomized = $false
$isUpdatingOutputPathText = $false

$selectOutputPath = {
    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Filter = $fileFilter
    $dialog.AddExtension = $true
    $dialog.OverwritePrompt = $false

    if (-not [string]::IsNullOrWhiteSpace($outputTextBox.Text)) {
        $dialog.FileName = $outputTextBox.Text.Trim()
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $isUpdatingOutputPathText = $true
        $outputTextBox.Text = $dialog.FileName
        $isUpdatingOutputPathText = $false
        $outputPathIsCustomized = $true
    }
}

$outputBrowseButton.Add_Click({ & $selectOutputPath })

$updateOutputPath = {
    if (-not $outputPathIsCustomized) {
        $isUpdatingOutputPathText = $true

        if ([string]::IsNullOrWhiteSpace($existingTextBox.Text)) {
            $outputTextBox.Text = ''
        }
        else {
            $outputTextBox.Text = Get-MergedOutputPath $existingTextBox.Text.Trim()
        }

        $isUpdatingOutputPathText = $false
    }
}

$outputTextBox.Add_TextChanged({
    if (-not $isUpdatingOutputPathText) {
        $outputPathIsCustomized = $true
    }
})

$existingTextBox.Add_TextChanged($updateOutputPath)
& $updateOutputPath

$mergeButton.Add_Click({
    try {
        $existingConfigPath = $existingTextBox.Text.Trim()
        $newConfigPath = $newTextBox.Text.Trim()
        $oldValues = Parse-Config $existingConfigPath
        $newValues = Parse-Config $newConfigPath
        $changedKeys = @($newValues.Keys | Where-Object { $oldValues.Contains($_) -and $oldValues[$_] -ne $newValues[$_] })
        $hasChangedSharedSettings = $changedKeys.Count -gt 0
        $keysToKeep = $null

        if ($reviewCheckBox.Checked -and $hasChangedSharedSettings) {
            $keysToKeep = Select-ExistingValuesToKeep $changedKeys $oldValues $newValues

            if ($null -eq $keysToKeep) {
                $statusLabel.Text = 'Merge canceled.'
                $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 80, 20)
                return
            }
        }

        $customOutputPath = $outputTextBox.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($customOutputPath)) {
            $parentDirectory = [System.IO.Path]::GetDirectoryName($customOutputPath)
            if (-not [string]::IsNullOrWhiteSpace($parentDirectory) -and -not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
                throw "Output directory does not exist: $parentDirectory"
            }
        }

        $result = Merge-ConfigFiles $existingConfigPath $newConfigPath $keysToKeep $customOutputPath

        $resultsTextBox.Text = Format-MergeSummary $result
        if ($reviewCheckBox.Checked -and -not $hasChangedSharedSettings) {
            $statusLabel.Text = "Merged successfully (no changed shared settings to review): $($result.OutputConfig)"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 98, 140)
        }
        else {
            $statusLabel.Text = "Merged successfully: $($result.OutputConfig)"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 68)
        }
    }
    catch {
        $resultsTextBox.Text = "Merge failed`r`n`r`n$($_.Exception.Message)"
        $statusLabel.Text = 'Merge failed. Review the message below.'
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 35, 24)
    }
})

[void]$form.ShowDialog()
