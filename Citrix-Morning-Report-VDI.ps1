 <#
 Version Control:
 11/26/2018 -Added Event Viewer Function
 11/27/2018 -Corrected Maint mode function
 12/27/2018 -Added App-V Log checks
 01/15/2019 -Performance improvements in Get-RDSGracePeriod and Check-AppVLogs
 03/05/2019 -Updated Check-AppVLogs to work with App-V Scheduler 2.5 and 2.6
 03/05/2019 -Updated Get-RDSGracePeriod to not warn on 0 days, since that's now a success condition with working RDS licensing
 03/26/2019 -Added GPO Checks
 04/08/2019 -Updated App-V Checks
 06/19/2019 -updated GPO-Check function to include 'registered' for the get-brokermachine
 08/18/2022 - Added Get-XDAuthentication  -ProfileName "CloudAdmin"
 08/18/2022 - changed uptime greater than value from 24 hours to 30 days (720 Hours)
 08/18/2022 - Changed Get-BrokerDesktop to Get-BrokerMachine (supports -SessionSupport)
 08/18/2022 - set so uptime only looks at MultiSession delivery groups (exclude VDI's) -SessionSupport MultiSession
04/23 - had to comment out the Parameter(Mandatory=$true) was still prompting me for parameters even though I already specifried them
04/11/2023 - JT added section for showing computers in draining mode. will restart computers that are not in use (available) 
07/29/2024  - Created VDI report. will automatically take VDI out of maintenance mode.
#>g

 Param(
   #             [Parameter(Mandatory=$True,Position=1)]
                [string[]]$DeliveryControllers = "sbctxcloud-p05",
  #              [Parameter(Mandatory=$True)]
                [string]$LogDir = "\\nam\wardfs\citrix\.GITHUB\Logs\VDIReport",
                [string]$MaintTag = "None",
                [string]$DeliveryController = "sbctxcloud-p05",
                [ValidateSet($True,$False)]
                [Switch]$Email,
                [Switch]$LogOnly,
                [String]$SMTPserver = "webmail.zimmer.com",
                [string[]]$ToAddress = "MG-Global-Citrix-Infrastructure@zimmerbiomet.com",
                [string]$FromAddress = "ControlUp@zimmerbiomet.com"
                )

cls
asnp citrix*
Get-XDAuthentication  -ProfileName "Prod"

$script:bad=0

#Defines log path
$firstcomp = Get-Date
$filename = $firstcomp.month.ToString() + "-" + $firstcomp.day.ToString() + "-" + $firstcomp.year.ToString() + "-" + $firstcomp.hour.ToString() + "-" + $firstcomp.minute.ToString() + ".txt"
$outputloc = $LogDir + "\" + $filename

$hostname = hostname
#$DeliveryControllers = sbctxcloud-p05
Start-Transcript -Path $outputloc

Write-Host "-"

############ List Unregistered Machines ###########
Function ListUnregs
    {
        
        Write-Host "****************************************************"
       
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Unregistered Servers in " $DeliveryController ":" -ForegroundColor Green
                    $unregs = Get-BrokerMachine -SessionSupport MultiSession -AdminAddress $DeliveryController -MaxRecordCount 5000 -PowerState On -PowerActionPending $false -RegistrationState Unregistered | Sort-Object DNSName
                        foreach ($unreg in $unregs)
                            {
                                #write-host $unreg.dnsname
                                if ($unreg.SummaryState -like 'Available' -or $unreg.SummaryState -like 'Unregistered')
                                    {
                                        
                                        Try
                                            {
                                                if (!($LogOnly)){New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action Reset -MachineName $unreg.HostedMachineName -like 'usctx-gen*' | Out-Null}
                                                Write-host $unreg.DNSName.Split(".",2)[0] " (Force Restarting)"
                                            }
                                        Catch
                                            {
                                                Write-host $unreg.DNSName.Split(".",2)[0] " (Unable to Force Restart)"
                                            }
                                    }
                                else
                                    {
                                        Write-host $unreg.DNSName.Split(".",2)[0] " (Users Logged in, Can't Restart)"
                                    }
                                
                            }
                    if ($unregs){$script:bad=1}
                Write-host " "
                }#End Foreach Delivery Group
       Write-Host "****************************************************"
    }
############ END List Unregistered Machines ###########

############ List Machines in Maint Mode ###########
Function MaintMode
    {
        Write-Host "****************************************************"
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines in Maint Mode in " $DeliveryController ":" -ForegroundColor Green
                    $maints = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -IsPhysical $False | Sort-Object DNSName | Where-Object {$_.HostedMachineName -like 'usctx-gen*'}
                        foreach ($maint in $maints)
                            {
                                if ($maint.Tags -like "$MaintTag*")
                                    {
                                    Write-host $maint.DNSName.Split(".",2)[0] "(Tagged for Maintenance Mode)"
                                            if (!($LogOnly))    
                                               {        
                                                    Try
                                                        {
                                                            Set-BrokerMachine -MachineName $maint.MachineName -InMaintenanceMode $True
                                                        }
                                                    Catch
                                                        {
                                                           Write-host $maint.DNSName.Split(".",2)[0] "(Unable to Enable Maintenance Mode)"
                                                        }
                                                } 
                                    if ($maint){$script:bad = '1'}
				    }
                                elseif ($maint.Tags -notcontains "$MaintTag*" -and $maint.InMaintenanceMode -eq "True")
                                   {
                                        Write-host $maint.DNSName.Split(".",2)[0] " (hi)"
                                        if (!($LogOnly))
                                            {
                                                
                                                Try
                                                    {
                                                        Set-BrokerMachine -MachineName $maint.MachineName -InMaintenanceMode $false
                                                    }
                                                Catch
                                                    {
                                                        Write-host $maint.DNSName.Split(".",2)[0] "(Unable to Disable Maintenance Mode"
                                                    } 
                                            }
                                   }
                                
                            }
                Write-host " "
                }
      Write-Host "****************************************************"
    }
############ END List Machines in Maint Mode ###########

############ List Bad Power States ###########
Function PowerState
    {
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines with Bad Power States in " $DeliveryController ":" -ForegroundColor Green
                    $pstates = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 | Sort-Object DNSName
                        foreach ($pstate in $pstates)
                            {
                                if ($pstate.PowerState -ne 'Off' -and $pstate.PowerState -ne 'On' -and $pstate.PowerState -ne 'Unmanaged')
                                    {
                                        Write-host $pstate.DNSName.Split(".",2)[0] $pstate.powerstate
                                        if ($pstates){$script:bad=1}
                                    }
                            }
                    
                Write-host " "
                }
        Write-Host "****************************************************"    
    }
############ END List Bad Power States ###########

############ List Pending Updates ###########
 Function PendingUpdates
    {
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines with Pending Updates in " $DeliveryController ":" -ForegroundColor Green
                    $pupdates = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 -ProvisioningType MCS | Sort-Object DNSName
                        foreach ($pupdate in $pupdates)
                            {
                                #Write-host $pupdate.DNSName.Split(".",2)[0] $pupdate.ImageOutOfDate
                                if ($pupdate.ImageOutOfDate -eq $True)
                                    {
                                        Write-host $pupdate.DNSName.Split(".",2)[0] $pupdate.ImageOutOfDate
                                        if ($pupdates){$script:bad=1}
                                    }
                            }
                    
                Write-host " "
                }
        Write-Host "****************************************************"    
    }
############ END List Pending Updates ###########


############ Email SMTP ###########
Function Email
    {
        if ($script:bad -eq '1')
            {
                $results = (Get-Content -Path $outputloc -raw)
            }
        else
            {
                $results = "Citrix VDI Report is Clean.  Check log for details ($LogDir)."
            }
        $smtpserver = $SMTPserver
        $msg = New-Object Net.Mail.MailMessage
        $smtp = New-Object net.Mail.SmtpClient($smtpserver)
        $msg.From = $FromAddress
        Foreach ($to in $Toaddress){$msg.To.Add($to)}
        $msg.Subject = "**Citrix VDI Report - $($DeliveryControllers)**"
        $msg.body = "$results"
        #$msg.Attachments.Add($att)
        $smtp.Send($msg)
    }

############ END Email SMTP ###########



###### Call out Functions ############


ListUnregs

$now = Get-Date -Format s
write-host "- $now"

ListOff

$now = Get-Date -Format s
write-host "- $now"

MaintMode

$now = Get-Date -Format s
write-host "- $now"


PendingUpdates

$now = Get-Date -Format s
write-host "- $now"



$now = Get-Date -Format s
write-host "- $now"

Get-MoveLogs

$now = Get-Date -Format s
write-host "- $now"





####################### Get Elapsed Time of Script ###########
$lastcomp = Get-date
$diff = ($lastcomp - $firstcomp)

Write-Host This Script took $diff.Minutes minutes and $diff.Seconds seconds to complete.
# Write-Host "This Script Runs at 4:00AM from ($hostname)"


##############################################################

Stop-Transcript

if ($Email) {Email}

###### END Call out Functions ############
