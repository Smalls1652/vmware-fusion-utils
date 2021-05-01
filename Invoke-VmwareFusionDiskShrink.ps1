<#PSScriptInfo

.VERSION 2021.05.00

.GUID a6b42bf3-6113-4cb5-ba59-e68cd1c1df59

.AUTHOR Tim Small

.COMPANYNAME Smalls.Online

.COPYRIGHT 2021

.TAGS vmware-fusion macos

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
 # 2021.05.00
    - Initial release.

.PRIVATEDATA

#>

<# 

.SYNOPSIS
 Shrink a VMWare Fusion VM's virtual disk.

.DESCRIPTION 
 Defrag and shrink a VMWare Fusion VM's virtual disk to reduce it's overall disk size. 

.PARAMETER VmPath
 The path to the VM's bundle file.

.EXAMPLE
 / > ./Invoke-VmwareFusionDiskShrink.ps1 -VmPath "./Virtual Machines/Ubuntu 20.04 LTS.vmwarevm/"
 
 Perform the shrink operation on a VM.

#> 
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateScript(
        {
            <#
                Test if the supplied VM path is actually valid, before executing the script.
            #>
            $vmPathInput = $PSItem
            $vmPathResolved = $null
            
            #Try to resolve the path
            try {
                $vmPathResolved = (Resolve-Path -Path $vmPathInput -ErrorAction "Stop").Path
            }
            catch {
                #If resolving the path fails, throw a 'FileNotFound' exception.
                throw [System.IO.FileNotFoundException]::new(
                    "The path could not be resolved.",
                    $vmPathInput
                )
            }

            #Get the object of the VmPath. This makes the regex test in the next step easier to set up and to see if it's actually a directory.
            $vmPathObj = Get-Item -Path $vmPathResolved

            #Run a regex test on the item object's 'Name' property to see if it ends with '.vmwarevm'. This is the common "extension" for a VMWare Fusion VM bundle.
            $vmPathBundleRegex = [System.Text.RegularExpressions.Regex]::new("^.+?(?'vmBundleExt'\.vmwarevm)$")
            $vmPathBundleTest = $vmPathBundleRegex.IsMatch($vmPathObj.Name)

            #Test to see if the VmPath is a directory AND if it passed the bundle regex test.
            switch (($vmPathObj.Attributes -eq [System.IO.FileAttributes]::Directory) -and ($vmPathBundleTest -eq $true)) {
                $false {
                    #If it failed both tests, throw an error that it's not a valid VMWare Fusion VM bundle.
                    throw [System.IO.FileFormatException]::new(
                        "The path is not a valid VMWare Fusion VM bundle.",
                        $vmPathResolved
                    )
                    break
                }

                Default {
                    #If it passed both tests, return 'true' to pass the validation script.
                    return $true
                }
            }
        }
    )]
    [string]$VmPath
)

<#
    We need to validate that VMWare Fusion is actually installed to the local system.

    If it's not installed, then this script won't work at all.
#>
Write-Verbose "Checking to see if VMWare Fusion is installed."
$vmwareFusionPath = "/Applications/VMware Fusion.app/"
switch (Test-Path -Path $vmwareFusionPath) {
    $false {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "VMWare Fusion could not be found in your Applications directory."
                ),
                "VmwareFusionAppNotFound",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $vmwareFusionPath
            )
        )
        break
    }

    Default {
        Write-Verbose "VMWare Fusion is installed on the local system."
        break
    }
}

<#
    - Internal script function:
        'AddTotalVmdkSize'

    - Purpose:
        Gets the total size of all the '.vmdk' files in the VM bundle.
#>
function AddTotalVmdkSize {
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Path
    )

    $vmTotalSize = 0
    foreach ($file in (Get-ChildItem -Path $Path | Where-Object { $PSItem.Extension -eq ".vmdk" })) {
        $vmTotalSize += $file.Length
    }

    return $vmTotalSize
}

#Create the full file path to the 'vmware-vdiskmanager' executable. This is what will be executed to defrag and shrink the VM disk file.
$diskMgrExecPath = Join-Path -Path $vmwareFusionPath -ChildPath "Contents/Library/vmware-vdiskmanager"

#Create the full file path to the VM's virtual disk file
$vmPathResolved = (Resolve-Path -Path $VmPath).Path
$vmDiskPath = Join-Path -Path $vmPathResolved -ChildPath "Virtual Disk.vmdk"

<#
    Test to make sure the VM's virtual disk file actually exists.

    The likelihood the file doesn't exist is very low, but the possibility is definitely there.
#>
switch (Test-Path -Path $vmDiskPath) {
    $false {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Virtual disk could not be found in the VMWare Fusion VM bundle."
                ),
                "VmDiskNotFound",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $vmDiskPath
            )
        )
        break
    }

    Default {
        Write-Verbose "Virtual disk was found at '$($vmDiskPath)'."
        break
    }
}

#Get the total size of the VM disk files (In GB) before the defrag/shrink operations.
$vmTotalSizeBefore = [System.Math]::Round(
    ((AddTotalVmdkSize -Path $vmPathResolved) / 1GB),
    2
)

#Run a defrag operation on the virtual disk.
switch ($PSCmdlet.ShouldProcess($vmDiskPath, "Defrag virtual disk")) {
    $true {
        Start-Process -FilePath $diskMgrExecPath -ArgumentList @("-d", "`"$($vmDiskPath)`"") -Wait -NoNewWindow -ErrorAction "Stop"
        break
    }
}

#Run a shrink operation on the virtual disk.
switch ($PSCmdlet.ShouldProcess($vmDiskPath, "Shrink virtual disk")) {
    $true {
        Start-Process -FilePath $diskMgrExecPath -ArgumentList @("-k", "`"$($vmDiskPath)`"") -Wait -NoNewWindow -ErrorAction "Stop"
        break
    }
}

#Get the total size of the VM disk files (In GB) after the defrag/shrink operations.
$vmTotalSizeAfter = [System.Math]::Round(
    ((AddTotalVmdkSize -Path $vmPathResolved) / 1GB),
    2
)

$savedSpace = $vmTotalSizeBefore - $vmTotalSizeAfter

#Return an object with results of the operation.
return [pscustomobject]@{
    "VmPath"         = $vmPathResolved;
    "BeforeSizeInGB" = $vmTotalSizeBefore;
    "AfterSizeInGB"  = $vmTotalSizeAfter
    "SpaceSavedInGB" = $savedSpace;
}