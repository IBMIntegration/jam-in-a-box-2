# Configuring Multi-Protocol Gateway with DataPower

_A Step-by-Step Guide_

${toc}

## Introduction

In a world where disruption is the norm, ensuring your environments can support modern protocols like Kafka and AMQP while supporting existing protocols like http and MQ is essential to modernizing your environments.

IBM DataPower is an industry-leading integration solution that is designed to secure and protect your integration solutions. It provides the ability to deploy a variety of services for your solutions. One of the most used services within IBM DataPower is the Multi-Protocol Gateway (MPGW). An MPGW is a flexible, highly configurable endpoint for managing, transforming, and routing various types of network traffic and data formats, acting as a versatile intermediary for handling diverse tasks.

For this Lab we are putting you in the role of a Senior Integration Operations Specialist from Focus Corporation. You are expected to create a Multi-Protocol Gateway that takes https: traffic flowing into a DataPower and convert it to http. The lab will give you the concepts on how to create a Multi-Protocol Gateway that can supports other protocols to converts to protocol your backend might support.


### About this hands-on lab

In the first part of this lab, you will log into an application domain in DataPower. An application domain is a feature that allows the creation of a development partition for services that process requests. The default domain is used by DataPower Gateway to create, modify and control system-wide resources such as network interfaces, users, and control DataPower objects. Application domains can only be created in the default domains. An example is an airline has four lines of business on their DataPower Gateways, Loyalty, Ticketing, Baggage and Revenue. They can partition their DataPower as follows:

![DataPower Domain Structure](images/MP1.svg)

In the second part of this lab, you will create a key/cert pair that will used with the Multi-Protocol Gateway. Keys and certs are used for secure communication and authentication.

- Private Key: This key is kept secret and is used to decrypt data encrypted with its corresponding public key, and to create digital signatures.
- Public Key: This key can be shared freely and is used to encrypt data that can only be decrypted by the corresponding private key.
- Key Pairs: A public and private key are mathematically linked and form a key pair.
- Certificate: An electronic document that binds a public key to an identity, a website, a user or an organization.

In the third part of the lab, you will create and configure a multi-protocol gateway that will take https: traffic and converts it to http: traffic.

In the final part of the lab, you will test the multi-protocol gateway using website.
By the end of the lab, you will understand how to create and configure a multi-protocol gateway from the application domain to the method to test multi-protocol gateway using a https: to http: service.

### Architecture

DataPower Multi-Protocol Gateway Architecture

A multiprotocol gateway can accept client-originated messages in various protocols. The service can then pass messages to a remote server with various protocols. The protocol that the client uses does not need to be the same as the protocol that the remote server uses.

A multi-protocol gateway supports the following protocols.

- AMQP
- FTP
- HTTP
- HTTPS
- IBM® MQ
- IMS Callout
- IMS Connect
- Kafka
- MEIG AS2
- NFS
- SFTP
- Stateful raw XML
- Stateless raw XML
- TIBCO EMS
- WebSphere® JMS

A multiprotocol gateway can support more than one client protocol. Similarly, the service can support more than one server protocol.

The following figure provides an illustration of the static server architecture that the service supports.

![Static server architecture diagram](images/MP2.svg)

A multiprotocol gateway can accept client requests through any of the protocol handlers that are shown (HTTP, HTTPS, or IBM MQ). A static URL determines the destination for all traffic. This server-side traffic can employ one of the protocols that are shown (HTTP, HTTPS, or IBM MQ).

When the remote service endpoint is determined dynamically, the multiprotocol gateway supports a stateful raw XML handler. Because the connection is stateful, this protocol handler can communicate with only a remote service that also uses the same protocol. The following figure shows other protocol handlers that can route to the other protocols dynamically.

![Dynamic server architecture diagram](images/MP3.svg)

Taken from IBM DataPower Knowledge Centre - https://www.ibm.com/docs/en/datapower-gateway/10.6.0?topic=development-multi-protocol-gateway

## Login into the DataPower Web Console

1. The login link for the webui is provided on your list of user details.

    1. Enter `{{ dataPowerAdminUser | admin }}` in the `Username` field
    1. Enter {{ dataPowerAdminPassword | password }} into  `Password` field
    1. Select `default` in the `Domain` field
    1. Click `Log in` to log in to DataPower’s Web Console

    ![Datapower login screen](images/MP4.png)

## Create an application domain

As a general best practice, the `default` domain should only be used for administrative tasks. Let's create a new domain for our lab.

1. In the search field in the top left corner, search for `Application` and click `Application domain`. `Application domain` may be listed twice. That's ok; simply click the first one.

    ![Search for Application Domain](images/MP5.png)

    Click `Add` in the top left corner.

    ![Add button](images/MP6.png)

    Give your new Application Domain the name `mpgw-lab` and click `Apply`.

    ![Application Domain screen](images/MP7.png)

    Save your changes. Click `Save`.

    ![Confirmation screen and Save button](images/MP8.png)

    Switch to your new Application domain. Click the domain pulldown (labeled with the current domain `default`) and select your new domain.

    ![Domain switch](images/MP9.png)

## Create a TLS server profile

A TLS server profile is used to reference the certificate objects that are exposed to request coming into the DataPower.

### Generate a self-signed certificate

You need keys and certificates to do create your TLS server profile. You may provide your own keys, or use DataPower to generate a self-signed certificate. In this section, we'll cover how to do the latter.

1. In the search field in the top left corner, search for `crypto` and click `Crypto tools`.

    ![Search for crypto tools](images/MP10.png)

1. Fill in the subject fields for the certificate. You may fill in as many as you like, but only the `CN` field is required.
1. In the `Key type` field, select `ECDSA`.

    ![Certificate subject and key type](images/MP11.png)

1. Scroll down and enable `Export private key`. This is your only opportunity to export a key; you will not be able to download the key later.
1. Ensure `Generate key and certificate objects` is enabled. It should be enabled by default.
1. Give the objects a name like `mpg-lab-keys`.

    ![Export and generate keys](images/MP12.png)

1. Scroll back up and click `Submit`

    ![Export and generate keys](images/MP12-1.png)

1. Confirm the confirmation

    ![Export and generate keys](images/MP12-2.png)

1. Click `Save`

    ![Export and generate keys](images/MP12-3.png)

### Create a keystore

The keystore, formerly known as "indentification credentials" encapsulates a key and certificate pair.

1. In the search field in the top left corner, search for `key` and click `Keystore (identification credentials)`

    ![Search for keystore](images/MP13.png)

1. Click `Add`

    ![img](images/MP14.png)

1. Give your keystore a name like `mpgw-idcreds` and select the self-signed key and certificate objects you created in the previous section of this exercise. It's not necessary to select an intermediate certificate with self-signed credentials.

    ![img](images/MP15.png)

1. Click `Apply` and `Save`

    ![img](images/MP16.png)

### Create the TLS server profile

Now that we have a Keystore, let's create a TLS server profile

1. Search for `TLS server profile`.

    ![Search for TLS server profile](images/MP17.png)

1. Click on the `Add` button

    ![Add button](images/MP18.png)

1. Give your TLS Server Profile a name like `mpgw-lab-tls-server-profile`.

    ![Profile name](images/MP19.png)

1. Scroll down and select the Keystore object you createed in the previous section.

    ![Profile name](images/MP20.png)

1. Click `Apply` and then `Save`

    ![Profile name](images/MP21.png)

## Create a HTTPS handler

The HTTPS Handler represents the listener at that takes requests into DataPower.

1. Search for `HTTPS Handler`

    ![Search for HTTPS Handler](images/MP22.png)

1. Click `Add`

    ![Add button](images/MP23.png)

1. From Create HTTPS handler page

    1. Give your handler a name, such as `mpgw-lab-handler`.

        ![Handler name](images/MP24.png)

    1. In the Port field, set the port you would like to bind your HTTPS handler to. For the purposes of this lab, Use `10443`. A service and route has already been created in OpenShift to expose that port.

        ![](images/MP25.png)


    1. For Allowed Methods and versions ensure that GET Method is selected

        ![](images/MP26.png)

    1. For TLS server type, select Server profile

    1. For the TLS server profile, select the profile you created earlier.

        ![](images/MP27.png)

    1. Click `Apply` and then `Save`

        ![](images/MP28.png)

        Note: You will get a message that the handler is down. This is expected.

        ![](images/MP29.png)

## Create a Multi-Protocol Gateway Policy

The MPGW-Policy is the logic for the call. In this example we are going to set a single variable and call some gateway script. The GatewayScript will set a response payload. Normally this logic can be used to route to downstream endpoints, apply forms of protection.

1. Search for `Multi-Protocol Gateway Policy`

    ![](images/MP30.png)

1. Click `Add`

    ![](images/MP31.png)

1. From the Configure Multi-Protocol Gateway Style Policy page:

    1. Give it a name, like `lab-mpgw-policy`
    2. Click `Add` to add a rule

    ![](images/MP32.png)

1. From the Rule tab,

    1. In the `Rule type` drop-down, select Client to Server.

        ![](images/MP33.png)

    1. Observe the ⚠️ next to the `Match rule` icon. Click the icon.

        ![](images/MP34.png)

    1. We need to create a match rule. Click the `+` sign button next to the `Matching Rule` field.

        ![](images/MP35.png)

    1. Name it `all-uri-paths`, then click on `Add`.

        ![](images/MP33.png)

    1. Set the URL match to `*` (asterisk) and click `Apply`

        ![](images/MP37.png)

    1. Observe the URL match rule you just created is listed under `Rules`. Click `Apply`.

        ![](images/MP38.png)

    1. Observe the `Matching Rule` is set to the rule you just created. Click `Done`

        ![](images/MP39.png)

    1. Notice the ⚠️ seen earlier is gone.

        ![](images/MP40.png)

1. Any policy without a backend must have `service/mpgw/skip-backside` set to `. Let's add the policy rule to set that variable value.

    1. Click on the `+` the right of the Match rule icon.

        ![](images/MP41.png)
    
    1. Scroll down and select `Set Variable`.

        ![](images/MP42.png)

    1. Observe the ⚠️ next to the new `Set Variable` icon. Click the icon.

        ![](images/MP43.png)

    1. Set the `Context` to `INPUT`

        ![](images/MP44.png)

    1. In the `Options` pane, set the following values and then click `Done`:

        - **Select a protocol** to `var://`
        - **Variable name** to `service/mpgw/skip-backside`
        - **Variable value** to `1`

        ![](images/MP45.png)

1. Now add a GatewayScript policy rule to set a very simple response payload.

    1. Click on the `+` the right of the Set Variable rule icon.

        ![](images/MP46.png)

    1. Select `GatewayScript`

        ![](images/MP47.png)

    1. Observe the ⚠️ next to the new `GatewayScript` icon. Click the icon.

        ![](images/MP48.png)

    1. Upload the file in [resources/gws.js](resources/gws.js).
    
        1. Download the [linked file](resource/gws.js).
        1. Click the upload icon

            ![](images/MP49.png)

        1. Upload the file. Drag the file from your local OS file manager (e.g. macOS Finder) to the `Drag and drop...` area and click `Upload`.

            ![](images/MP50.png)
    
    1. Click `Done`.

        ![](images/MP51.png)

1. One more policy rule is needed to complete the chain: the `Results` rule.

    1. Click on the `+` the right of the GatewayScript rule icon.

      ![](images/MP2.png)

    1. Select `Results`.

        ![](images/MP53.png)
    
    1. No further configuration is needed but you may view the options available by clicking the `Results` icon.

        ![](images/MP54.png)

        Click `×` (cancel) or `Done` to exit. The `Done` button is only activated if there are changes.

        ![](images/MP55.png)

1. Click `Done`

    ![](images/MP56.png)

1. Click `Apply Policy` and then `Save`

    ![](images/MP57.png)

## Create a New Multi-Protocol Gateway

The MPGW brings everything together. The listen is set to determine how it receives traffic and the MPGW-Policy determines how the traffic is processed.

1. Search for `New multi-protocol gateway`

    ![](images/MP58.png)

1. In the `General Configuration` settings:

    1. Give it a name like `lab-mpgw`
    1. Set **XML Manager** to `default`
    1. Set **Processing policy**`** to the multi-protocol gateway policy we created earlier.
    1. Set **Type** to `Dynamic backend`.

    ![](images/MP59.png)

1. In the Front side settings

    1. In Front Side Protocol (Required) selection (A) field, select the Front Side handler you created earlier and press the `Add` button.

    ![](images/MP60.png)

    1. The `[down - Cannot install without a service.]` message is normal at this point. The message will go away when this new multi-protocol gateway setup is completed.

    ![](images/MP61.png)

1. In the User Agent settings:

    1. Set both **Characterize response traffic** and **Characterize request traffic** to `XML`

    ![](images/MP62.png)

    2. Toggle Propagate URI (B) to Off

    ![](images/MP63.png)

1. Click on the `Apply` and `Save`

    ![](images/MP64.png)

## Testing

In a browser window navigate to the test URL that was provided alongside your credentials.
You should see a response similar to


