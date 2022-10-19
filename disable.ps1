#####################################################
# HelloID-Conn-Prov-Target-Aura-Disable
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()



# Account mapping
$account = [PSCustomObject]@{
    address = @{
        extadd = "$(Get-Date -Format 'yyyyMMdd')"
    }
    userId  = @{
        userIdValue = $p.ExternalId
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function ConvertTo-ChallengeResponseCode {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [string]
        $challengeResult
    )
    try {
        $shaobj = [System.Security.Cryptography.SHA1CryptoServiceProvider]::new()
        $shaObj.Initialize();

        $encoder = [System.Text.ASCIIEncoding]::new()
        $hash = $shaObj.ComputeHash($encoder.GetBytes($challengeResult + "tools4ever" + $config.password))

        $shaobj.Clear()
        $challengeResponseCode = [System.String]::Concat(($hash | ForEach-Object {
                    $_.ToString('X2')
                }
            ))
        Write-Output $challengeResponseCode
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Add-CookieToWebRequestSession {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WebRequestSession])]
    param(
        [string]
        $cookieResponse
    )
    try {

        $CookieNameValue = ($cookieResponse -split ';') | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($CookieNameValue)) {
            throw 'Cookie Not Found, Please check you password'
        }
        $uri = [system.uri]::new($config.BaseUrl)

        $Cookie = [System.Net.Cookie]::new()
        $Cookie.Name = ($CookieNameValue -split '=') | Select-Object -First 1
        $Cookie.Value = ($CookieNameValue -split '=') | Select-Object -Last 1
        $Cookie.Domain = $uri.DnsSafeHost

        $WebSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
        $WebSession.Cookies.Add($Cookie)

        Write-Output  $WebSession
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-AuraAuthenticationCookie {
    [OutputType([System.String])]
    [CmdletBinding()]
    param()
    try {
        # Challenge Request
        [xml]$xmlChallenge = '<?xml version="1.0" encoding="utf-8"?>
        <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
        <soap12:Body>
                <Challenge xmlns="http://www.imsglobal.org/services/pms/wsdl/imsPersonManServiceSync_v1p0" />
        </soap12:Body>
        </soap12:Envelope>'

        $splatWebRequest = @{
            Method      = 'POST'
            Uri         = $config.BaseUrl
            ContentType = 'text/xml; charset=utf-8'
            Body        = $xmlChallenge.InnerXml
        }
        [xml]$Response = (Invoke-WebRequest @splatWebRequest -UseBasicParsing -Verbose:$false).Content
        $challengeResult = $Response.Envelope.Body.ChallengeResponse.ChallengeResult


        # Challenge Response Request
        [xml]$xmlResponse = '<?xml version="1.0" encoding="utf-8"?>
        <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
        <soap12:Body>
            <Response xmlns="http://www.imsglobal.org/services/pms/wsdl/imsPersonManServiceSync_v1p0">
                <respCode></respCode>
            </Response>
        </soap12:Body>
        </soap12:Envelope>'
        $xmlResponse.Envelope.Body.Response.respCode = "$(ConvertTo-ChallengeResponseCode $challengeResult)"
        $splatWebRequest['Body'] = $xmlResponse
        $responseChallenge = Invoke-WebRequest @splatWebRequest  -UseBasicParsing -Verbose:$false
        Write-Output  $responseChallenge.Headers['Set-Cookie']
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Write-ToAuraXmlDocument {
    [Cmdletbinding()]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
        $Properties,

        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]
        $XmlDocument,

        [Parameter(Mandatory)]
        [System.Xml.XmlElement]
        $XmlParentElement
    )
    if ($Properties.GetType().Name -eq "PSCustomObject") {
        $ParameterList = @{ }
        foreach ($prop in $Properties.PSObject.Properties) {
            $ParameterList[$prop.Name] = $prop.Value
        }
    } else {
        $ParameterList = $Properties
    }
    try {
        foreach ($param in $ParameterList.GetEnumerator()) {
            $xmlns = $null
            $xmlns = switch ($param.name) {
                { @( 'address', 'formatName', 'name', 'photo', 'extension', 'recordInfo', 'tel', 'demographics' , 'userId') -contains $_ } {
                    'http://www.imsglobal.org/services/pms/xsd/imsPersonManDataSchema_v1p0'
                    break
                }
                { @('extensionField', 'email', 'dataSource', 'authenticationType', 'passWord', 'pwEncryptionType', 'userIdType', 'userIdValue', 'identifier') -contains $_ } {
                    'http://www.imsglobal.org/services/common/imsCommonSchema_v1p0'
                    break
                }
                { @('comments', 'URL') -contains $_ } {
                    'http://www.imsglobal.org/services/pms/xsd/imsCommonSchema_v1p0'
                    break
                }
                default { $null }
            }
            $xmlElement = $null
            if ([string]::IsNullOrEmpty($xmlns)) {
                Clear-Variable  xmlns
            }
            $xmlElement = $XmlDocument.CreateElement($param.Name, $xmlns)

            if ((($param.Value) -is [PSCustomObject] -or ($param.Value) -is [Hashtable]) -and $null -ne $param.Value) {
                $ParameterList[$param.Name] | Write-ToAuraXmlDocument -XmlDocument  $XmlDocument -XmlParentElement $xmlElement
                $null = $XmlParentElement.AppendChild($xmlElement)
            } elseif ($param.Value -is [System.Object[]]) {
                $childElement = $XmlDocument.CreateElement($param.Name, $xmlns)
                foreach ($paramValue in $param.value) {
                    $paramValue | Write-ToAuraXmlDocument -XmlDocument  $XmlDocument -XmlParentElement $childElement
                }
                $null = $XmlParentElement.AppendChild($childElement)

            } else {
                $null = $xmlElement.InnerText = "$($param.Value)"
                $null = $XmlParentElement.AppendChild($xmlElement)
            }
        }
    } catch {
        $_
    }
}

function Resolve-AuraError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = ''
            FriendlyMessage  = ''
        }
        $ErrorObject.ErrorDetails.Message

        if ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($ErrorObject.ErrorDetails) {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
                $httpErrorObj.FriendlyMessage = ($ErrorObject.ErrorDetails.Message.Substring($ErrorObject.ErrorDetails.Message.IndexOf(';') + 2)) -replace ('---\u0026gt;', ';')
            } elseif ($null -eq $ErrorObject.Exception.Response) {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                if ($ErrorObject.ErrorDetails) {
                    $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
                }
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
            } else {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
                # $ErrorObject | select *
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                $httpErrorObj.ErrorDetails = "$($ErrorObject.Exception.Message) $streamReaderResponse"
                if ($null -ne $streamReaderResponse) {
                    $errorResponse = ( $streamReaderResponse | ConvertFrom-Json)
                    $httpErrorObj.FriendlyMessage = $errorResponse
                    $httpErrorObj.ErrorDetails = $errorResponse
                    # $httpErrorObj.FriendlyMessage = switch ($errorResponse) {
                    #     { $_.error_description } { $errorResponse.error_description }
                    #     { $_.issue.details } { $errorResponse.issue.details }
                    #     { $_.error.message } { "Probably OrganisationId or Environment not found: Error: $($errorResponse.error.message)" }
                    #     default { ($errorResponse | ConvertTo-Json) }
                    # }
                }
            }
        } else {
            $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
            $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Get Get-Aura Authentication Cookie
    $cookieResponse = Get-AuraAuthenticationCookie

    # Add Cookie To WebRequest Session
    $WebSession = Add-CookieToWebRequestSession  $cookieResponse

    [xml]$xmlGetUser = '<?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <soap:Body>
            <readPersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                <sourcedId>
                    <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                </sourcedId>
            </readPersonRequest>
        </soap:Body>
    </soap:Envelope>'

    $xmlGetUser.Envelope.Body.readPersonRequest.sourcedId.identifier.InnerText = "$($account.userId.userIdValue)"
    $splatWebRequest = @{
        Method      = 'POST'
        Uri         = $config.BaseUrl
        ContentType = 'text/xml; charset=utf-8'
        Body        = $xmlGetUser.InnerXml
        WebSession  = $WebSession
    }
    $userResponse = Invoke-RestMethod @splatWebRequest -UseBasicParsing -Verbose:$false
    $userXmlObject = ([xml]$userResponse).Envelope.Body.readPersonResponse.person

    Write-Verbose "Verifying if a Aura account for [$($p.DisplayName)] exists"
    if (-not [string]::IsNullOrEmpty($userXmlObject.userId.userIdValue.'#text')) {
        $action = 'Found'
        $dryRunMessage = "Disable Aura account for: [$($p.DisplayName)] will be executed during enforcement"

    } elseif ($null -eq $userResponse) {
        $action = 'NotFound'
        $dryRunMessage = "Aura account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Found' {
                Write-Verbose "Disable Aura account with accountReference: [$aRef]"

                [xml]$updateXML = '<?xml version="1.0" encoding="utf-8"?>
                <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                    <soap:Body>
                        <updatePersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                            <sourcedId>
                                <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                            </sourcedId>
                        </updatePersonRequest>
                    </soap:Body>
                </soap:Envelope>'

                $updateXML.Envelope.Body.updatePersonRequest.sourcedId.identifier.InnerText = "$($account.userId.userIdValue)"

                $parentXmlElementPerson = $updateXML.Envelope.Body.updatePersonRequest.AppendChild( $updateXML.CreateElement('person'))
                $account | Select-Object * -ExcludeProperty ExternalId  | Write-ToAuraXmlDocument -XmlDocument $updateXML -XmlParentElement $parentXmlElementPerson
                $splatWebRequest = @{
                    Method      = 'POST'
                    Uri         = $config.BaseUrl
                    ContentType = 'text/xml; charset=utf-8'
                    Body        = $updateXML.InnerXml.Replace(' xmlns="">', '>') #Remove empty NameSpace
                    WebSession  = $WebSession
                }
                $userResponse = Invoke-RestMethod @splatWebRequest -UseBasicParsing -Verbose:$false

                if ($userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.codeMajor -eq 'failure' -or
                    ($userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.codeMajor -ne 'success' -and
                    $userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.description.text.'#text' -ne 'alles Ok'  )
                ) {
                    Write-Verbose $userResponse.Envelope.Header.syncResponseHeaderInfo.InnerXml
                    throw $userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.description.text.'#text'
                }

                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Disable account was successful'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Aura account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action"
                        IsError = $false
                    })
                break
            }
        }

        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AuraError -ErrorObject $ex
        $auditMessage = "Could not disable Aura account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable Aura account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
