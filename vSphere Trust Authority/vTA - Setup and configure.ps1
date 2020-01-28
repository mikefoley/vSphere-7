##
<#
.SYNOPSIS
    Sets up vSphere Trust Authority.
.DESCRIPTION
    Introduced in vSphere 7, vSphere Trust Authority is used to provide remote attestation of vSphere ESXi hosts.
    We use the terms "Green" and "Blue" sides. The Blue Side is the vTA infrastructure that is the  "most secure".
    The Green side is the "workload" clusters. These will be attested by the Blue side.

    This script configure vTA on both sides.

.EXAMPLE

.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
#>

# •	Enable the Trust Authority Administrator
# •	Collect Information About Hosts You Want to Be Trusted (the Trusted Hosts)
# •	Enable the Trusted State on the Trust Authority Cluster
# •	Import the Trusted Host Information to the Trust Authority Cluster
# •	Create the Key Provider on the Trust Authority Cluster
# •	Export the Trust Authority Cluster Information
# •	Import the Trust Authority Cluster Information to the Trusted Hosts
# •	Configure the Trusted Key Provider for Trusted Hosts


param(
        [Parameter(Mandatory=$true)][string]$vTA_vc_server,
        [Parameter(Mandatory=$true)][String]$vTA_vc_username,
        [Parameter(Mandatory=$true)][String]$vTA_vc_password,
        [Parameter(Mandatory=$true)][string]$Trusted_vc_server,
        [Parameter(Mandatory=$true)][String]$Trusted_vc_username,
        [Parameter(Mandatory=$true)][String]$Trusted_vc_password,
        [Parameter(Mandatory=$true)][String]$TrustedAdmin_username,
        [Parameter(Mandatory=$true)][String]$TrustedAdmin_password
)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

Connect-VIServer -server $Trusted_vc_server -User $TrustedAdmin_username -Password $TrustedAdmin_password

$VMHosts = Get-VMHost | Where {$_.ConnectionState -eq "Connected"}

#Loop through the lists of hosts and  export the vm host image DB
foreach ($VMHost in $VMHosts) {
    Export-VMHostImageDb -VMHost $vmhost -FilePath $temp\$VMHost.tgz
}
# To extract the Trusted Cluster vCenter Server principal information, run Export-TrustedPrincipal.
Export-TrustedPrincipal -FilePath $temp\principal.json

# Disconnect from the vCenter Server of the Trusted Cluster
Disconnect-VIServer -server * -Confirm:$false
# Connect to the vCenter Server of the Trust Authority Cluster
Connect-VIServer -server $vTA_vc_server -User $TrustedAdmin_username -Password $TrustedAdmin_password

# Check to see if the vTA cluster is in a disabled state before continuing. (Add code to check)
Get-TrustAuthorityCluster #where state is disabled
$vTA = Get-TrustAuthorityCluster 'vTA Cluster'
# Enable vTA on vTA Cluster
Set-TrustAuthorityCluster -TrustAuthorityCluster $vTA -State Enabled
# Check to see if vTA Cluster is enabled
$vTACluster = Get-TrustAuthorityCluster #| Where-Object{$_.state -eq "Enabled"}

Write-Host "vTA Cluster state is " $vTACluster.state
# Import the Trusted Host Information to the Trust Authority Cluster

New-TrustAuthorityPrincipal -TrustAuthorityCluster $vTA -FilePath $temp\principal.json

# To verify the import, run Get-TrustAuthorityPrincipal.
Get-TrustAuthorityPrincipal -TrustAuthorityCluster $vTA

# import the TPM CA certificate information
# New-TrustAuthorityTpm2CACertificate -Name tpmca -TrustAuthorityCluster $vTA -FilePath $temp\cacert.cer

# import the ESXi host description
foreach ($VMHost in $VMHosts) {
New-TrustAuthorityVMHostBaseImage -TrustAuthorityCluster $vTA -FilePath $temp\$VMHost.tgz
}

# create the trusted key provider user and password
New-TrustAuthorityKeyProvider -TrustAuthorityCluster $vTA -MasterKeyId $masterkeyid -Name $kmipname -
 -KmipServerAddress $kmip_ipaddress -KmipServerPassword $kmip_server_password -KmipServerUsername $kmip_server_name

 # create the trusted key provider client certificate, assign the variable $kp
$kp = Get-TrustAuthorityKeyProvider -TrustAuthorityCluster $vTA

# Run New-TrustAuthorityKeyProviderClientCertificate.
New-TrustAuthorityKeyProviderClientCertificate -KeyProvider $kp

# Check to see if the certificate is not trusted. (set to False)
Get-TrustAuthorityKeyProviderServerCertificate -KeyProviderServer $kp.KeyProviderServers |Where-Object{$_.state -eq $false}

# add the KMIP server certificate to the trusted key provider
$cert = Get-TrustAuthorityKeyProviderServerCertificate -KeyProviderServer $kp.KeyProviderServers

# Run Add-TrustAuthorityKeyProviderServerCertificate.
Add-TrustAuthorityKeyProviderServerCertificate -ServerCertificate $cert

# export the Trust Authority Cluster's Attestation Service and Key Provider Service information
Export-TrustAuthorityServicesInfo -TrustAuthorityCluster $vTA -FilePath $temp\clsettings.json

<# Import the Trust Authority Cluster Information to the Trusted Hosts
Once the Trust Authority Cluster information is imported to the Trusted Cluster,
the Trusted Hosts start attestation with the Trust Authority Cluster. The Trusted Hosts
can then request encryption keys to encrypt virtual machines. #>

# Disconnect from the vCenter Server of the Trust Authority Cluster.
Disconnect-VIServer -server * -Confirm:$false

# Connect to the vCenter Server of the Trusted Cluster
Connect-VIServer -server $Trusted_vc_server -User $TrustedAdmin_username -Password $TrustedAdmin_password

# Check to see if the vTA cluster is in a disabled state before continuing. (Add code to check)
Get-TrustedCluster #where state is disabled

# 4.	assign the variable vTA to Get-TrustedCluster
$vTA = Get-TrustedCluster -Name $trustedclustername

# Import the Trust Authority Cluster information
Import-TrustAuthorityServicesInfo -TrustedCluster $vTA -FilePath  $temp\clsettings.json -Confirm:$false

#Check to see if Attestation Service is running. The service address should be the name of the ESXi hosts in the vTA cluster
Get-AttestationServiceInfo

# Check to see if trusted key provider is configured. The service address should be the name of the ESXi hosts in the vTA cluster
Get-KeyProviderServiceInfo

# Assign the trusted key provider from Get-KeyProvider to the variable workload_kp.
$workload_kp = Get-KeyProvider

# 4.	Register the trusted key provider.
Register-KeyProvider -KeyProvider $workload_kp

# 5.	Set the default trusted key provider to use.
Set-KeyProvider -KeyProvider $workload_kp

#
# Now create a encrypted VM to verify that everything works
try {
    $policy = Get-SpbmStoragePolicy "VM Encryption Policy"
    $ds = Get-Datastore datastore
    New-VM -Name 'MyVM' -Datastore $ds -StoragePolicy $policy -SkipHardDisks
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Break
}



