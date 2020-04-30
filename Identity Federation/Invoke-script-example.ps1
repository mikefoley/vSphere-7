param(
        [Parameter(Mandatory=$true)][string]$vc_server,
        [Parameter(Mandatory=$true)][String]$vc_username = "administrator@vsphere.local",
        [Parameter(Mandatory=$true)][String]$vc_password = "VMware1!",
        [Parameter(Mandatory=$true)][String]$CISserverUsername = "administrator@vsphere.local",
        [Parameter(Mandatory=$true)][String]$CISserverPassword = "VMware1!",
        [Parameter()][String]$users_base_dn = "CN=Users,DC=lab1,DC=local",
        [Parameter()][String]$groups_base_dn = "DC=lab1,DC=local",
        [Parameter()][String]$adusername = "CN=Administrator,CN=Users,DC=lab1,DC=local",
        [Parameter()][String]$adpasswordstring = "VMware1!",
        [Parameter()][String]$server_endpoint1 = "ldaps://mgt-dc-01.lab1.local:636",
        [Parameter()][String]$server_endpoint2,
        [Parameter()][String]$DstPath = "/root"


)

Write-Host "Generate a file to upload to VCSA"
$file2copy = @"
testfile
"@

Write-Host "Upload certificate to VCSA"
Copy-VMGuestFile -VM $vc_server -Source $file2copy -Destination $DstPath -LocalToGuest -GuestCredential $Cred -Force

Write-Host "Create Script to run on VCSA to load cert into Java keystore.  This is necessary in vSphere 7 because the federated identity code uses this keystore."
$scriptblock = @"
echo foobar > x.tmp
"@

Write-Host "Run the script on VC"
if($vc_server) {
$sInvoke = @{
    VM            = $vc_server
    ScriptType    = 'Bash'
    ScriptText    = $ExecutionContext.InvokeCommand.ExpandString($scriptblock)
    GuestUser     = $vc_username
    GuestPassword = ConvertTo-SecureString -String $vc_password -AsPlainText -Force
}
Invoke-VMScript @sInvoke

else {
    Write-Host "`nUnable to find VCSA named $vc_server"
}
}