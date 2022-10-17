#####################################################
# HelloID-Conn-Prov-Target-Aura-Create
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
    address         = @{
        country  = 'nl'
        extadd   = ''
        locality = ''
        pobox    = ''
        postcode = '1234ac'
        region   = ''
        street   = 'Tools'
    }
    dataSource      = 'Aura Software'
    demographics    = @{
        gender = 'Male'  # female
        bday   = '2000-01-02'  # yyyy-mm-dd
    }
    email           = $p.Contact.Business.Email
    formatName      = ''
    name            = @(
        @{
            nameType = 'Full'
        },
        @{
            partName = @{
                namePartType  = 'First'
                namePartValue = $p.Name.NickName
            }
        },
        @{
            partName = @{
                namePartType  = 'Middle'
                namePartValue = $null
            }
        },
        @{
            partName = @{
                namePartType  = 'Last'
                namePartValue = $p.Name.FamilyName
            }
        }
    )
    systemRole      = 'User' # SysAdmin, SysSupport, Creator,AccountAdmin,User,Administrator,None,
    userId          = @{
        authenticationType = ''
        passWord           = '$3Cret'  # Only used for new created account
        pwEncryptionType   = ''
        userIdType         = ''
        userIdValue        = $p.ExternalId
    }
    institutionRole = @(
        @{
            InstitutionRoleDType = @{
                # Student,  Faculty,  Member,  Learner,  Instructor,  Mentor,  Staff,  Alumni,  ProspectiveStudent,  Guest,  Other,  iAdministrator,  Observer,
                institutionRoleType_ = ''
                primaryRoleType      = ''
            }
        }
    )
    extension       = @(
        @{
            extensionField = @{ #extensionField
                fieldName  = 'rentalcode'
                fieldType  = 'String'
                fieldValue = 700
            }
        },
        @{
            extensionField = @{
                fieldName  = 'vestiging'
                fieldType  = 'String'
                fieldValue = ''
            }
        }
    )
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $true

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
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                $httpErrorObj.ErrorDetails = "$($ErrorObject.Exception.Message) $streamReaderResponse"
                if ($null -ne $streamReaderResponse) {
                    $errorResponse = ( $streamReaderResponse | ConvertFrom-Json)
                    $httpErrorObj.FriendlyMessage = $errorResponse
                    $httpErrorObj.ErrorDetails = $errorResponse
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
    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    # Get Get-Aura Authentication Cookie
    $cookieResponse = Get-AuraAuthenticationCookie

    # Add Cookie To WebRequest Session
    $WebSession = Add-CookieToWebRequestSession  $cookieResponse

    # Get User
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

    if ([string]::IsNullOrEmpty($userXmlObject.userId.userIdValue.'#text')) {
        $action = 'Create-Correlate'
    } elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    } else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Aura account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating Aura account'
                [xml]$createXML = '<?xml version="1.0" encoding="utf-8"?>
                <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                    <soap:Body>
                        <createPersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                            <sourcedId>
                                <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                            </sourcedId>
                        </createPersonRequest>
                    </soap:Body>
                </soap:Envelope>'

                $createXML.Envelope.Body.createPersonRequest.sourcedId.identifier.InnerText = "$($account.userId.userIdValue)"

                $parentXmlElementPerson = $createXML.Envelope.Body.createPersonRequest.AppendChild( $createXML.CreateElement('person'))
                $account | Select-Object *  -ExcludeProperty externalId | Write-ToAuraXmlDocument -XmlDocument $createXML -XmlParentElement $parentXmlElementPerson
                $splatWebRequest = @{
                    Method      = 'POST'
                    Uri         = $config.BaseUrl
                    ContentType = 'text/xml; charset=utf-8'
                    Body        = $createXML.InnerXml.Replace(' xmlns="">', '>') #Remove empty NameSpace
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
                $accountReference = "$($account.userId.userIdValue)"
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating Aura account'
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
                $account.userId.Remove('password')
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
                $accountReference = "$($account.userId.userIdValue)"
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Aura account'
                $accountReference = "$($account.userId.userIdValue)"
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $ex = $PSItem
    $errorObj = Resolve-AuraError -ErrorObject $ex
    Write-Verbose "Could not $action Aura account. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $auditLogs.Add([PSCustomObject]@{
            Message = "Could not $action Aura account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}

