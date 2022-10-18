
# HelloID-Conn-Prov-Target-Aura


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.aura.nl/portals/0/logo.jpg"
   alt="drawing" style="width:300px;"/>
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Aura_ is a _target_ connector. Aura provides a set of REST API's that allow you to programmatically interact with its data. The connector supports create and updating the account and authorization are out of scope.



## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| Password     | The Password to connect to the API| Yes         |
| BaseUrl      | The URL to the API                 | Yes         |

### Prerequisites

### Remarks
- The update action does not compare the current user in Aura against the new account object. It always updates the account. When this is required this need to be added during implementation.
- Due to the 'complex' user account structure not all the properties are prefilled. You can add and remove properties in the account object to the customer needs.
- The properties which are not sent to the webservice are not updated. When a property is sent without a value the value will be cleared in Aura.
- You must disable a user account with the property address.extadd (room number) with an endDate [yyyyMMdd]. If the value not contains a valid date the room number will be updated
- There are no Enable or Delete tasks
- The connector is created for PS 5.1 and core 7.1. But there are some .net objects under investigation for our cloud agent. In the meantime the connector only works on the agent.


#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.
You can change this behavior in the `create.ps1` by setting the boolean `$updatePerson` to the value of `$true`.
> Be aware that this might have unexpected implications.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
