##################################################V2
# HelloID-Conn-Prov-Target-Aura-Disable
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
        $hash = $shaObj.ComputeHash($encoder.GetBytes($challengeResult + "tools4ever" + $actionContext.Configuration.password))

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
        $uri = [system.uri]::new($actionContext.Configuration.BaseUrl)

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
            Uri         = $actionContext.Configuration.BaseUrl
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
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $cookieResponse = Get-AuraAuthenticationCookie
    $WebSession = Add-CookieToWebRequestSession  $cookieResponse

    Write-Information "Verifying if a Aura account for [$($personContext.Person.DisplayName)] exists"

    [xml]$xmlGetUser =  '<?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <soap:Body>
            <readPersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                <sourcedId>
                    <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                </sourcedId>
            </readPersonRequest>
        </soap:Body>
    </soap:Envelope>'

    $xmlGetUser.Envelope.Body.readPersonRequest.sourcedId.identifier.InnerText = "$($actionContext.References.Account)"
    $splatWebRequest = @{
        Method      = 'POST'
        Uri         = $actionContext.Configuration.BaseUrl
        ContentType = 'text/xml; charset=utf-8'
        Body        = $xmlGetUser.InnerXml
        WebSession  = $WebSession
    }

    if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
        $splatWebRequest['Proxy'] = $actionContext.Configuration.ProxyAddress
    }

    $userResponse =Invoke-RestMethod @splatWebRequest -UseBasicParsing -Verbose:$false
    $userXmlObject = ([xml]$userResponse).Envelope.Body.readPersonResponse.person
    $correlatedAccountID = $userXmlObject.userId.userIdValue.'#text'

    if ($null -ne $correlatedAccountID) {
        $action = 'DisableAccount'
        $dryRunMessage = "Disable Aura account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Aura account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DisableAccount' {
                Write-Information "Disabling Aura account with accountReference: [$($actionContext.References.Account)]"

                $ImsDisableAccount = [PSCustomObject]@{
                    address = @{
                        extadd = "$($ActionContext.Data.UITSDATUM)"
                    }
                    userId  = @{
                        userIdValue = $correlatedAccountID
                    }
                }

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

                $updateXML.Envelope.Body.updatePersonRequest.sourcedId.identifier.InnerText = "$($actionContext.References.Account)"
                $parentXmlElementPerson = $updateXML.Envelope.Body.updatePersonRequest.AppendChild( $updateXML.CreateElement('person'))

                $ImsDisableAccount |  Select-Object *  | Write-ToAuraXmlDocument -XmlDocument $updateXML -XmlParentElement $parentXmlElementPerson

                $splatWebRequest = @{
                    Method      = 'POST'
                    Uri         = $actionContext.Configuration.BaseUrl
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

                $outputContext.data = $actionContext.Data
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Disable account was successful'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Aura account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AuraError -ErrorObject $ex
        $auditMessage = "Could not disable Aura account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable Aura account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
