<#
        .Synopsis
        pfSense management functions. 

        .DESCRIPTION
        Haven't been able to find another API, or command line management for pfSense
        
        .NOTES
        It runs on Linux guys.... there shouldn't be a need for these functions...
        
        .COMPONENT
        Security, Networking, Firewall
        
        .FUNCTIONALITY
        pfSense task automation and scriptability
#>


#region Verion Info

<#
        Version 0.1
        - Day one - it's my birfday!
#>

#endregion

#region Prerequisites

# All modules require the core
If (!(Get-Module -Name core))
{
    Try
    {
        Import-Module -Name 'core' -ErrorAction Stop
    }

    Catch
    {
        Try
        {
            $uriCoreModule = 'https://raw.githubusercontent.com/masters274/Posh_Repo/master/Modules/Core/core.psm1'
    
            $moduleCode = (Invoke-WebRequest -Uri $uriCoreModule -UseBasicParsing).Content
            
            Invoke-Expression -Command $moduleCode
        }
    
        Catch
        {
            Write-Error -Message ('Failed to load {0}, due to missing core module' -f $PSScriptRoot)
        }
    }
}

#endregion

#================================================= MEAT! =========================================================#

#region Connection functions


Function Connect-pfSense
{
    <#
            .DESCRIPTION
            Authenticates to a pfSense server and returns the session variable
    #>
    [CmdLetBinding()]
    Param
    (
        [Parameter(
                Mandatory=$true,
                Position=0,
                HelpMessage='Hostname of pfSesense server'
        )]
        [Alias('HostName')]
        [String] $Server,
        
        [Parameter(
                Mandatory=$true,
                Position=1,
                HelpMessage='Credentials for administering pfSense'
        )]
        [PSCredential] $Credential,
        
        [Switch] $NoTLS # Not recommended
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process
    {
        # Variables
        $uri = 'https://{0}/index.php' -f $Server
        $pfWebSession = $null
        $retObject = @()
        $dictOptions = @{
            host=$Server
            NoTLS=$([bool] $NoTLS)
        }
        
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
        
        $request = iwr -Uri $uri
        
        $webCredential = @{login='Login'
            usernamefld=$Credential.GetNetworkCredential().UserName
            passwordfld=$Credential.GetNetworkCredential().Password
            __csrf_magic=$($request.InputFields[0].Value)
        }

        Invoke-WebRequest -Uri $uri -Body $webCredential -Method Post -SessionVariable pfWebSession | Out-Null
        
        $retObject += $pfWebSession
        $retObject += $dictOptions
        
        $retObject
    }
}


#endregion

#region User functions


Function Add-pfSenseUser
{
    <#
            .Synopsis
            Adds a new user via pfSense user management page

            .DESCRIPTION
            Great for automating the turn up of new remote users

            .EXAMPLE
            $Creds = Get-Credential
            $pfs = Connect-pfSense -Server firewall.local -Credential $Creds
            Add-pfSenseUser -Session $pfs -Server firewall.local -UserName 'player1' -Password 'MySecretPassword' -FullName 'Player One'

            Creates a user account on the pfSense firewall named "firewall.local"

            .NOTES
            For the certificate, you'll need to get the CA's reference ID. This is located in the page source
            code of either the CA itself, or on the Add User Management Page. This can be found by visiting one of
            these pages, right-click and select view page source, the perfrom a search for caref. 
            
            I'll write something to get this later... an example of this: 4813b1f414fec
            
            <div>
            <select class="form-control" name="caref" id="caref">
            <option value="4813b1f414fec">pfSenseCertificateAuthority</option>
            </div>
    #>

    [CmdLetBinding()]
    [CmdletBinding(DefaultParameterSetName='NoCert')]
    Param
    (
        [Parameter(Mandatory=$true, Position=0,
                HelpMessage='Valid/active websession to server'
        )] [PSObject] $Session,
        
        [Parameter(Mandatory=$true, Position=1,
                HelpMessage='User name'
        )] [String] $UserName,
        
        [Parameter(Mandatory=$true, Position=2,
                HelpMessage='Password for the user'
        )] [String] $Password,
        
        [Parameter(Mandatory=$true, Position=3,
                HelpMessage='Display name for the user'
        )] [String] $FullName,
        
        [Parameter(ParameterSetName='Certificate')]
        [Switch] $Certificate,
        
        [Parameter(Mandatory=$false,ParameterSetName="NoCert")]
        [Parameter(Mandatory=$true,ParameterSetName="Certificate",
                HelpMessage='Name of the CA'
        )] [String] $CA,
        
        [Int] $KeyLength = 2048,
        
        [Int] $LifeTime = 3650,
        
        [Switch] $Quiet # No output upon completion
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process
    {
        # Variables
        $Server = $Session.host
        [bool] $NoTLS = $Session.NoTLS 
        [Microsoft.PowerShell.Commands.WebRequestSession] $webSession = $Session[0]
        $uri = 'https://{0}/system_usermanager.php' -f $Server
        
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
        
        # pfSense requires a lot of magic.... ++ foreach POST 
        $request = Invoke-WebRequest -Uri $uri -Method Get -WebSession $webSession
        
        $dictPostData = @{
            __csrf_magic=$($request.InputFields[0].Value)
            usernamefld=$UserName
            passwordfld1=$Password
            passwordfld2=$Password
            descr=$FullName
            utype='user' 
            save='Save'
        } # Change the utype to 'system' to create a protected system user
        
        $dictCertData = @{ # Extra form fields when requesting a certificate for the user
            showcert='yes'
            name="$($UserName)_cert"
            caref=$CA
            keylen=$KeyLength
            lifetime=$LifeTime
        }
            
        If ($Certificate) # Should we request a cert from the CA?
        {
            $dictPostData += $dictCertData
        }
        
        # submit/post the form to the server
        $uri += '?act=new'
        Invoke-DebugIt -Console -Message '[INFO]' -Value ('Post URI: {0}' -f $uri)
        
        Try
        {
            $rawRet = Invoke-WebRequest -Uri $uri -Method Post -Body $dictPostData -WebSession $webSession -EA Stop |
            Out-Null
            
            If ($rawRet.StatusCode -eq 200 -and -not $Quiet)
            {
                Invoke-DebugIt -Console -Message 'Success' -Force -Color 'Green' `
                -Value ('User: {0}, created successfully!' -f $FullName)
            }
        }
        
        Catch
        {
            Write-Error -Message 'Something went wrong submitting the form'
        }
    }
    
    End
    {
     
    }
}


Function Get-pfSenseUser
{
    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0,
                HelpMessage='Valid/active websession to server'
        )] [PSObject] $Session
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
        
        Function Script:Where-Deleteable
        {
            param
            (
                [Object]
                [Parameter(Mandatory=$true, ValueFromPipeline=$true, HelpMessage="Data to filter")]
                $InputObject
            )
            process
            {
                if ($InputObject.title -match 'Delete user')
                {
                    $InputObject
                }
            }
        }
    }
    
    Process
    {
        # Variables
        $Server = $Session.host
        [bool] $NoTLS = $Session.NoTLS 
        [Microsoft.PowerShell.Commands.WebRequestSession] $webSession = $Session[0]
        $uri = 'https://{0}/system_usermanager.php' -f $Server
        
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
        
        # pfSense requires a lot of magic.... ++ foreach POST 
        $request = Invoke-WebRequest -Uri $uri -Method Get -WebSession $webSession
        
        # Get a list of deletable users. 
        $objUsers = @()
        $users = $request.Links | Where-Deleteable # Note: can't delete yourself
        
        # Build an array with usernames and IDs, which can be deleted by the current user. 
        Foreach ($user in $users)
        {
            $uname = $user.href.Split(';').Replace('&amp','').Trim() -match 'username'
            $uid = $user.href.Split(';').Replace('&amp','').Trim() -match 'userid'
            
            $objBuilder = New-Object -TypeName PSObject
            $objBuilder | Add-Member -MemberType NoteProperty -Name 'Username' -Value $($uname.Split('=')[1])
            $objBuilder | Add-Member -MemberType NoteProperty -Name 'UserID' -Value $($uid.Split('=')[1])
            
            $objUsers += $objBuilder
        }
        
        $objUsers
    }
    
    End
    {
     
    }        
}


Function Remove-pfSenseUser
{
    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0,
                HelpMessage='Valid/active websession to server'
        )] [PSObject] $Session,
        
        [Parameter(Mandatory=$true, Position=1,
                HelpMessage='User name'
        )] [String] $UserName
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process
    {
        # Variables
        $Server = $Session.host
        [bool] $NoTLS = $Session.NoTLS 
        [Microsoft.PowerShell.Commands.WebRequestSession] $webSession = $Session[0]
        $uri = 'https://{0}/system_usermanager.php' -f $Server
        
        
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
            
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
        
        # pfSense requires a lot of magic.... ++ foreach POST 
        $request = Invoke-WebRequest -Uri $uri -Method Get -WebSession $webSession
        
        # Get a list of deletable users. 
        $objUsers = Get-pfSenseUser -Session $Session
        
        # Get the ID of the username to be deleted. 
        Try
        {
            $userID = $objUsers | Where-Object {$_.Username -eq $UserName} | ForEach-Object {$_.UserID}
            
            Invoke-DebugIt -Console -Message '[INFO]' -Value ('User ID found: {0}' -f $userID)
        }
        
        Catch
        {
            Write-Error -Message `
            'Failed to get the user ID for the username provided. Check the username, and try again'
            return
        }
        
        <#
                - After we get the user ID, we need to check if the user has a certificate. 
                - We need to revoke the certificate before we remove the user. User ID will not be
                found after the user has been deleted... 

                Revoke-pfSenseUserCert
        #>
        
        # Dictionary submitted as body in our POST request
        $dictPostData = @{
            __csrf_magic=$($request.InputFields[0].Value)
            'delete_check[]'=$userID
            'dellall'='dellall'
        }
        
        Try
        {
            $rawRet = Invoke-WebRequest -Uri $uri -Method Post -Body $dictPostData -WebSession $webSession -EA Stop |
            Out-Null
        }
        
        Catch
        {
            Write-Error -Message 'Something went wrong submitting the form'
        }
    }
    
    End
    {
     
    }
}


Function Export-pfSenseUserCert
{
    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0,
                HelpMessage='Valid/active websession to server'
        )] [PSObject] $Session,
        
        [Parameter(Mandatory=$true, Position=1,
                HelpMessage='User name'
        )] [String] $UserName,
        
        [Parameter(Position=2)]
        [ValidateSet('Cert','Key','P12')]
        [String] $CertAction = 'Cert',
        
        [Parameter(Position=3)]
        [ValidateScript({
                    try {
                        $Folder = Get-Item $_ -ErrorAction Stop
                    } catch [System.Management.Automation.ItemNotFoundException] {
                        Throw [System.Management.Automation.ItemNotFoundException] "${_} Maybe there are network issues?"
                    }
                    if ($Folder.PSIsContainer) {
                        $True
                    } else {
                        Throw [System.Management.Automation.ValidationMetadataException] "The path '${_}' is not a container."
                    }
        })]
        [String] $FilePath
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process
    {
        # Variables
        $Server = $Session.host
        [bool] $NoTLS = $Session.NoTLS 
        [Microsoft.PowerShell.Commands.WebRequestSession] $webSession = $Session[0]
        $uri = 'https://{0}/system_certmanager.php' -f $Server
        
        
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
          
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
        
        # Get a list of deletable users. 
        $objUsers = Get-pfSenseUser -Session $Session
        
        # Get the ID of the username to be deleted. 
        Try
        {
            $userID = $objUsers | Where-Object {$_.Username -eq $UserName} | ForEach-Object {$_.UserID}
            
            Invoke-DebugIt -Console -Message '[INFO]' -Value ('User ID found: {0}' -f $userID)
        }
        
        Catch
        {
            Write-Error -Message `
            'Failed to get the user ID for the username provided. Check the username, and try again'
            return
        }
        
        Switch ($CertAction)
        {
            Key {
                $uri += ('?act=key&id={0}' -f $userID)
                $fExt = 'key'
                Break
            }
            
            P12 {
                $uri += ('?act=p12&id={0}' -f $userID)
                $fExt = 'p12'
                Break
            }
            
            Default {
                $uri += ('?act=exp&id={0}' -f $userID)
                $fExt = 'crt'
                Break
            }
        }
        
        If (!$FilePath)
        {
            [String] $FilePath = ('{0}\{1}_pfSenseUserCertificate.{2}' -f $($PWD.Path), $UserName, $fExt)
        }
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value ('Export path = {0}' -f $FilePath) -Force 
        
        Invoke-DebugIt -Console -Message '[INFO]' -Value ('URI = {0}' -f $uri.ToString())

        $request = Invoke-WebRequest -Uri $uri -Method Get -WebSession $webSession
        
        ConvertFrom-HexToFile -HexString $request.Content -FilePath $FilePath
    }
    
    End
    {
     
    }
}


Function Revoke-pfSenseUserCert
{
    
}


#endregion

#region System functions


Function Backup-pfSenseConfig
{
    <#
            .Synopsis
            Backup your pfSense firewall

            .DESCRIPTION
            Long description

            .EXAMPLE
            $Creds = Get-Credential
            $pfs = Connect-pfSense -Server firewall.local -Credential $Creds
            Backup-pfSenseConfig -Server firewall.local -Session $pfs
    #>
    
    [CmdLetBinding()]
    Param
    (
        [Parameter(
                Mandatory=$true,
                Position=0,
                HelpMessage='Valid/active websession to server'
        )]
        [PSObject] $Session,
        
        [Parameter(Position=1)]
        [ValidateScript({
                    try {
                        $Folder = Get-Item $_ -ErrorAction Stop
                    } catch [System.Management.Automation.ItemNotFoundException] {
                        Throw [System.Management.Automation.ItemNotFoundException] "${_} Maybe there are network issues?"
                    }
                    if ($Folder.PSIsContainer) {
                        $True
                    } else {
                        Throw [System.Management.Automation.ValidationMetadataException] "The path '${_}' is not a container."
                    }
        })]
        [String] $FilePath = ('{0}\{1}_pfSenseBackup.xml' -f $($PWD.Path), $(Get-Date -UFormat '%Y%m%d_%H%M%S')),
        
        [Parameter(Position=2)]
        [String] $EncryptPassword
    )
    
    Begin
    {
        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process
    {
        # Variables
        $Server = $Session.host
        [bool] $NoTLS = $Session.NoTLS 
        [Microsoft.PowerShell.Commands.WebRequestSession] $webSession = $Session[0]
        $uri = 'https://{0}/diag_backup.php' -f $Server
    
        If ($NoTLS) # highway to tha Danger Zone!!!
        {
            $uri = $uri -Replace "^https:",'http:'
            Invoke-DebugIt -Console -Message '[WARNING]' -Value 'Insecure option selected (no TLS)' -Color 'Yellow'
        }
    
        Invoke-DebugIt -Console -Message '[INFO]' -Value $uri.ToString()
    
        # pfSense requires a lot of magic.... ++ foreach POST 
        $request = Invoke-WebRequest -Uri $uri -Method Get -WebSession $webSession
    
    
        $dictPostData = @{
            __csrf_magic=$($request.InputFields[0].Value)
            donotbackuprrd='yes'
            download='Download configuration as XML'
        }
        
        If ($EncryptPassword)
        {
            $dictSecurity = @{
                encrypt_password="$EncryptPassword" 
            }
        
            $dictPostData += $dictSecurity
        
            Invoke-DebugIt -Console -Message '[INFO]' -Value 'Encryption password set'
        }
    
        Try
        {
            $rawRequest = Invoke-WebRequest -Uri $uri -Method Post -Body $dictPostData -WebSession $webSession -EA Stop
        }
        
        Catch
        {
            Write-Error -Message 'Something went wrong submitting the form'
        }
    
        If ($rawRequest)
        {
            Invoke-DebugIt -Console -Message '[INFO]' -Value ('Output file: {0}' -f $FilePath)
            ConvertFrom-HexToFile -HexString $rawRequest.Content -FilePath $FilePath
        }
    
        Else
        {
            Write-Error -Message 'Failed to read the output file'
        }
    }
    
    End
    {
        
    }
}


Function Add-pfSenseStaticRoute
{
    
}


Function Remove-pfSenseStaticRoute
{
    
}


Function Add-pfSenseGateway
{
    
}


Function Remove-pfSenseGateway
{
    
}


#endregion

#region Firewall functions


Function Add-pfSenseFirewallRule
{
    
}


Function Remove-pfSenseFirewallRule
{
    
}


Function Add-pfSenseNatRule
{

}


Function Remove-pfSenseNatRule
{
    
}


#endregion








