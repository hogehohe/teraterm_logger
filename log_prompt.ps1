param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$DefaultRoot,

    [string]$CategoriesPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-SafeFileNamePart {
    param(
        [string]$Text,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        $safe = $Fallback
    }
    else {
        $safe = $Text.Trim()
    }

    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($char, '_')
    }

    $safe = [regex]::Replace($safe, '\s+', '_')
    $safe = [regex]::Replace($safe, '_+', '_').Trim('_')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return $Fallback
    }

    return $safe
}

function Get-UniqueFileName {
    param(
        [string]$Folder,
        [string]$FileName
    )

    $candidate = $FileName
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    for ($i = 1; $i -le 999; $i++) {
        $path = Join-Path $Folder $candidate
        if (-not [System.IO.File]::Exists($path)) {
            return $candidate
        }

        $candidate = '{0}_{1:D3}{2}' -f $stem, $i, $extension
    }

    return $FileName
}

if (-not [System.IO.Directory]::Exists($DefaultRoot)) {
    $DefaultRoot = [Environment]::GetFolderPath('MyDocuments')
}

if ([string]::IsNullOrWhiteSpace($DefaultRoot) -or -not [System.IO.Directory]::Exists($DefaultRoot)) {
    $DefaultRoot = $env:TEMP
}

$categories = @('test', 'verification', 'install', 'investigation', 'work', 'other')
if ($CategoriesPath -and [System.IO.File]::Exists($CategoriesPath)) {
    $loadedCategories = [System.IO.File]::ReadAllLines($CategoriesPath, [System.Text.Encoding]::UTF8) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() }

    if ($loadedCategories.Count -gt 0) {
        $categories = $loadedCategories
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Tera Term Auto Logger'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(620, 188)
$form.TopMost = $true

$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Text = 'Folder'
$folderLabel.Location = New-Object System.Drawing.Point(16, 20)
$folderLabel.Size = New-Object System.Drawing.Size(88, 22)
$form.Controls.Add($folderLabel)

$folderText = New-Object System.Windows.Forms.TextBox
$folderText.Location = New-Object System.Drawing.Point(112, 18)
$folderText.Size = New-Object System.Drawing.Size(392, 24)
$folderText.Text = $DefaultRoot
$form.Controls.Add($folderText)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Location = New-Object System.Drawing.Point(512, 16)
$browseButton.Size = New-Object System.Drawing.Size(88, 28)
$form.Controls.Add($browseButton)

$categoryLabel = New-Object System.Windows.Forms.Label
$categoryLabel.Text = 'Sub item'
$categoryLabel.Location = New-Object System.Drawing.Point(16, 64)
$categoryLabel.Size = New-Object System.Drawing.Size(88, 22)
$form.Controls.Add($categoryLabel)

$categoryBox = New-Object System.Windows.Forms.ComboBox
$categoryBox.Location = New-Object System.Drawing.Point(112, 60)
$categoryBox.Size = New-Object System.Drawing.Size(180, 24)
$categoryBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$categoryBox.Items.AddRange($categories)
$categoryBox.SelectedIndex = 0
$form.Controls.Add($categoryBox)

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text = 'File name'
$fileLabel.Location = New-Object System.Drawing.Point(16, 108)
$fileLabel.Size = New-Object System.Drawing.Size(88, 22)
$form.Controls.Add($fileLabel)

$fileText = New-Object System.Windows.Forms.TextBox
$fileText.Location = New-Object System.Drawing.Point(112, 104)
$fileText.Size = New-Object System.Drawing.Size(488, 24)
$form.Controls.Add($fileText)

$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = 'OK'
$okButton.Location = New-Object System.Drawing.Point(416, 148)
$okButton.Size = New-Object System.Drawing.Size(88, 28)
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Location = New-Object System.Drawing.Point(512, 148)
$cancelButton.Size = New-Object System.Drawing.Size(88, 28)
$form.Controls.Add($cancelButton)

function Update-GeneratedFileName {
    $folder = $folderText.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($folder)) {
        $folder = $DefaultRoot
    }

    $project = Split-Path -Path $folder -Leaf
    $project = Get-SafeFileNamePart -Text $project -Fallback 'project'
    $category = Get-SafeFileNamePart -Text ([string]$categoryBox.SelectedItem) -Fallback 'work'
    $date = Get-Date -Format 'yyyyMMdd'
    $fileName = '{0}_{1}_{2}.log' -f $date, $project, $category

    if ([System.IO.Directory]::Exists($folder)) {
        $fileName = Get-UniqueFileName -Folder $folder -FileName $fileName
    }

    $fileText.Text = $fileName
}

$folderText.Add_Leave({ Update-GeneratedFileName })
$categoryBox.Add_SelectedIndexChanged({ Update-GeneratedFileName })

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select log folder'
    $dialog.SelectedPath = $folderText.Text

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $folderText.Text = $dialog.SelectedPath
        Update-GeneratedFileName
    }
})

$okButton.Add_Click({
    $folder = $folderText.Text.Trim()
    $fileName = $fileText.Text.Trim()

    if (-not [System.IO.Directory]::Exists($folder)) {
        [void][System.Windows.Forms.MessageBox]::Show($form, 'Folder does not exist.', 'Tera Term Auto Logger')
        return
    }

    if ([string]::IsNullOrWhiteSpace($fileName)) {
        [void][System.Windows.Forms.MessageBox]::Show($form, 'File name is empty.', 'Tera Term Auto Logger')
        return
    }

    if ($fileName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        [void][System.Windows.Forms.MessageBox]::Show($form, 'File name contains invalid characters.', 'Tera Term Auto Logger')
        return
    }

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($fileName))) {
        $fileName = "$fileName.log"
    }

    $fullPath = Join-Path $folder $fileName
    if ([System.IO.File]::Exists($fullPath)) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $form,
            'File already exists. Overwrite it?',
            'Tera Term Auto Logger',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    [System.IO.File]::WriteAllText($OutputPath, $fullPath + [Environment]::NewLine, [System.Text.Encoding]::Default)
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})

$cancelButton.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

$form.AcceptButton = $okButton
$form.CancelButton = $cancelButton

Update-GeneratedFileName

if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

exit 2
