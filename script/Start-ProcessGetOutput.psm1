﻿<#
    Author: @strontic20
    Website: strontic.com
    Github: github.com/strontic/xcyclopedia
    Synopsis: Execute specified file and gather the stdout, stderr, and children processes.
    License: MIT License; Copyright (c) 2020 strontic
#>

function Start-ProcessGetOutput {

    param (
        [string]$filepath,
        [string]$commandline,
        [bool]$takescreenshot = $false,
        [string]$screenshotpath,
        [bool]$start_process_verbose = $false,
        [bool]$get_handles = $false
    )

    # set vars null
    $stdout = $stderr = $process_children = $process_complete = $handle_results = $process_modules = $process_window_title = $null

    # initialize process_obj
    $process_obj = [PSCustomObject]@{        
            stdout = $null
            stderr = $null
            pid = $null
            children = $null
            handles = $null
            modules = $null
            window_title = $null
    }

    # initialize process parameters
    $psi = New-object System.Diagnostics.ProcessStartInfo 
    $psi.CreateNoWindow = $true 
    $psi.UseShellExecute = $false 
    $psi.RedirectStandardOutput = $true 
    $psi.RedirectStandardError = $true 
    $psi.FileName = "$filepath" 
    $psi.Arguments = @("$commandline") 
    $process = New-Object System.Diagnostics.Process 
    $process.StartInfo = $psi 
    
    # start process
    try { 
        $process.Start() | Out-Null
        Write-Host "--> Start: Success ($filepath $commandline)"
    }
    catch {
        Write-Host "Start: FAILED ($filepath $commandline)"
        if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
        Return $null
    }

    # Get Standard Out and Error
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()

    # Get process modules
    $process_modules = $process.Modules.FileName

    # Wait for exit. Maximum wait is 3 seconds
    $process_complete = $process.WaitForExit(2000)

    # Get process main window title
    $process_window_title = $process.MainWindowTitle

    # Get children processes (living children only)
    $process_children = Get-WmiObject win32_process | Where-Object {$_.ParentProcessId -eq $process.Id}

    # GET HANDLES - If process is still running then get file handles (if get_handles is enabled)    
    if($get_handles -AND (-NOT $process_complete)) {
        
        try { $handle_results = Start-Handles -handles_process_id $process.Id } 
        catch { 
            Write-Host "Handles: FAILED. Fatal Error."
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
        }

    }
    
    # GET SCREENSHOT - If process is still running then start screenshot process (if screenshots enabled)
    if($takescreenshot -AND (-NOT $process_complete)) {
        
        try { Start-Screenshot -screenshot_process_id $process.Id } 
        catch { 
            Write-Host "Screenshot: FAILED. Fatal Error."
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
        }

    }

    # kill the process if still running
    if (-NOT $process_complete) { 
        try { $process.Kill() }
        catch{
            write-host "----> Stop: FAILED. ($filepath $commandline)"
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
        } 
    }

    # stop any children processes
    Stop-Processes -processes_to_stop $process_children

    # get results
    $process_obj.stdout = $stdout.Result
    $process_obj.stderr = $stderr.Result
    $process_obj.pid = $process.Id
    if($handle_results) { $process_obj.handles = $handle_results }
    if($process_modules) { $process_obj.modules = $process_modules }
    if($process_window_title) { $process_obj.window_title = $process_window_title }
    if($process_children.Name) { $process_obj.children = $process_children.Name }

    # dispose of process
    $process.Dispose()

    Return $process_obj

}

function Stop-Processes($processes_to_stop) {
    
    # purpose: stop processes using array of process objects

    foreach ($process_to_stop in $processes_to_stop) {
        $process_to_stop_name = $process_to_stop.Name

        # Skip critical process "MpCmdRun.exe", to avoid pause of script execution
        if ($process_to_stop_name -eq "MpCmdRun.exe") {
            Write-Host "----> Stop Sub-Process: Skipped critical process $process_to_stop_name"
            Continue
        }
		
        # Skip process "powershell.exe", to avoid halt of script execution
        if ($process_to_stop_name -eq "powershell.exe") {
            Write-Host "----> Stop Sub-Process: Skipped critical process $process_to_stop_name"
            Continue
        }
		
		# Skip process "powershell_ise.exe", to avoid halt of script execution
        if ($process_to_stop_name -eq "powershell_ise.exe") {
            Write-Host "----> Stop Sub-Process: Skipped critical process $process_to_stop_name"
            Continue
        }
		
		#Skip process "explorer.exe", to avert system instability
        if ($process_to_stop_name -eq "explorer.exe") {
            Write-Host "----> Stop Sub-Process: Skipped critical process $process_to_stop_name"
            Continue
        }
		
		#Skip process "winlogon.exe", to avert system instability
        if ($process_to_stop_name -eq "winlogon.exe") {
            Write-Host "----> Stop Sub-Process: Skipped critical process $process_to_stop_name"
            Continue
        }

        try {
            Stop-Process -Id $process_to_stop.ProcessId -ea silentlycontinue -Confirm:$false
            Write-Host "----> Stop Sub-Process: Success ($process_to_stop_name)"
        }
        catch {
            Write-Host "----> Stop Sub-Process: FAILED ($process_to_stop_name)"
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
        }
    }
}

function Start-Screenshot {

    # purpose: take a screenshot using imported module, Get-Screenshot

    param ([int]$screenshot_process_id)

    # Check if the Get-Screenshot module is loaded. If not, load it.
    if (-NOT (Get-Module Get-Screenshot)) {
        Write-Host "----> Screenshot: INFO. Module Not Loaded. Loading NOW...."
        try {
            Import-LocalModule Get-Screenshot
            if(Get-Module Get-Screenshot) { Write-Host "------> Screenshot Module Load: Success" } 
            else {
                Write-Host "------> Screenshot Module Load: FAILED. Reason Unknown."
                Return
            }
        }
        catch {
            Write-Host "------> Screenshot Module Load: FAILED. Fatal Error."
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
            Return
        }
    }

    # Take Screenshot
    try {
        Get-Screenshot -processid $screenshot_process_id -save_path "$screenshotpath"
        Write-Host "----> Screenshot: Success ($filepath)"
    }
    catch {
        write-host "----> Screenshot: FAILED ($filepath)"
        if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
    }
}

function Start-Handles {

    # purpose: get list of file handles using imported module, Get-Handles

    param ([int]$handles_process_id)

    $script_dir = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent

    # Check if the Get-Handles module is loaded. If not, load it.
    if (-NOT (Get-Module Get-Handles)) {
        Write-Host "----> Handles: INFO. Module Not Loaded. Loading NOW...."
        try {
            Import-LocalModule Get-Handles
            if(Get-Module Get-Handles) { Write-Host "------> Handles Module Load: Success" }
            else {
                Write-Host "------> Handles Module Load: FAILED. Reason Unknown."
                Return
            }
        }
        catch {
            Write-Host "------> Handles Module Load: FAILED. Fatal Error."
            if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
            Return
        }
    }

    # Get the handles
    try {
        $start_handles_results = Get-Handles -handles_process_id $handles_process_id -handle_exe_path "$script_dir\bin\sysinternals\handle\handle64.exe" 
        Write-Host "----> Handles: Success"
    }
    catch {
        write-host "----> Handles: FAILED"
        if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
    }

    return $start_handles_results
}

function Import-LocalModule ([string]$module_name) {
    #Import specified module in current local directory
    $script_dir = $null
    $script_dir = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent
    try { Remove-Module $module_name -ErrorAction SilentlyContinue } catch {}
    try { Import-Module "$script_dir\$module_name" }
    catch {
        write-host "Failed to load $module_name module"
        if($start_process_verbose) { Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red -BackgroundColor Black } #verbose output
    }
}

Export-ModuleMember -function Start-ProcessGetOutput