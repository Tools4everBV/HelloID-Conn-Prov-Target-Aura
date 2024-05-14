
# HelloID-Conn-Prov-Target-Aura

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Aura](#helloid-conn-prov-target-Aura)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Field mapping](#field-mapping)
      - [Correlation configuration](#correlation-configuration)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Aura_ is a _target_ connector. _Aura_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description |
| -------- | ----------- |
| /        |   There is only one endpoint used, the one specified in the BaseUrl, wich is the endpoint that receives all SOAP messages


The following lifecycle actions are available:

| Action                 | Description                                      |
| ---------------------- | ------------------------------------------------ |
| create.ps1             | PowerShell _create_ lifecycle action             ||
| disable.ps1            | PowerShell _disable_ lifecycle action            ||
| update.ps1             | PowerShell _update_ lifecycle action             |
| configuration.json     | Default _[Configuration.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-V2-Template/blob/main/target/configuration.json)_ |
| fieldMapping.json      | Default _[FieldMapping.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-V2-Template/blob/main/target/fieldMapping.json)_   |

## Getting started

### Provisioning PowerShell V2 connector

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

See the description of each field in this file (or in the Helloid Fields tab after import).

The Unique Id of the account to be created, should be provided in the LENERSCODE field.


#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Aura_ to a person in _HelloID_.

To properly setup the correlation:
1. Make sure you have inported the field mapping, and configured the mapping for the LENERSCODE field.

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `ExternalId`                      |
    | Account correlation field | `LENERSCODE`                      |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.



### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                        | Mandatory |
| -------- | ---------------------------------- | --------- |
| Password | The Password to connect to the API | Yes       |
| BaseUrl  | The URL to the API                 | Yes       |

### Prerequisites

### Remarks

The "Aura Account" data model , as specified by the HelloId field mapping, and as used by the Aura application database, is not directly serviced by the Aura API itself.

The Aura Api makes use of the much more general generic soap/xml data definition as defined in  http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0
to transport the 'Aura account' information between HelloID to the Aura database.

Therefore the "Aura account" datamodel has to be converted to the generic Ims data model, before it can be used by the Aura API, and the other way around when information is read from the API.

This Ims format serves only as a transport mechanism. This format is not directly used in the fields mapping, as it would expose the unnessesary complexity of this model to the field mapping without any added functionality. The translation from the 'Aura account' as specified by HelloID to the ims schema en visa versa is therfore 'hardcoded' in the powershell connector, and the fields in HelloId are used to map the HelloID data to the "Aura account".


HelloID generates the values of the 'Aura account' by means of the  field mapping. The meaning of the 'Aura account' fields is listed in the description of each field in the mapping.


- There is no delete functionality for an account in Aura.  Accounts can however be disabled, by specifiying the  UITSDATUM field. This is implemented in the disable.ps1. Accounts cannot be re-enabled by means of the connector. The UITSDATUM field is only to be used in the disable script and is the only field in that script.



## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
