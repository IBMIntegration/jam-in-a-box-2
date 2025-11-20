# Deploy a Cloud Native HA persistent IBM MQ Queue Manager on CP4I

_Hands-on lab guide_

${toc}

## MQ Native HA Overview

A Native HA configuration provides a highly available queue manager where the recoverable MQ data (for example, the messages) are replicated across multiple sets of storage, preventing loss from storage failures. The queue manager consists of multiple running instances, one is the leader, the others are ready to quickly take over
in the event of a failure, maximizing access to the queue manager and its messages.

A Native HA configuration consists of three Kubernetes pods, each with an instance of the queue manager. One instance is the active queue manager, processing messages and writing to its recovery log. Whenever the recovery log is written, the active queue manager sends the data to the other two instances, known as replicas. Each replica
writes to its own recovery log, acknowledges the data, and then updates its own queue data from the replicated recovery log. If the pod running the active queue manager fails, one of the replica instances of the queue manager takes over the active role and has current data to operate with.

A Kubernetes Service is used to route TCP/IP client connections to the current active instance, which is identified as being the only pod which is ready for network traffic. This happens without the need for the client application to
be aware of the different instances.

Three pods are used to greatly reduce the possibility of a split-brain situation arising. In a two-pod high availability system split-brain could occur when the connectivity between the two pods breaks. With no connectivity, both pods could run the queue manager at the same time, accumulating different data. When connection is restored, there would be two different versions of the data (a 'split-brain'), and manual intervention is required to decide which data set to keep, and which to discard.

Native HA uses a three pod system with quorum to avoid the split-brain situation. Pods that can communicate with at least one of the other pods form a quorum. A queue manager can only become the active instance on a pod that has quorum. The queue manager cannot become active on a pod that is not connected to at least one other pod, so there can never be two active instances at the same time:

- If a single pod fails, the queue manager on one of the other two pods can take over. If two pods fail, the queue manager cannot become the active instance on the remaining pod because the pod does not have quorum (the remaining pod cannot tell whether the other two pods have failed, or they are still running and it has lost connectivity).
- If a single pod loses connectivity, the queue manager cannot become active on this pod because the pod does not have quorum. The queue manager on one of the remaining two pods can take over, which do have quorum. If all pods lose connectivity, the queue manager is unable to become active on any of the pods, because none of the pods have quorum.
- If an active pod fails, and subsequently recovers, it can rejoin the group in a replica role.

The following figure shows a typical deployment with three instances of a queue manager deployed in three containers.

![Active queue manager replicating to two Replica queue managers](images/QM1.svg)

## Deploy the MQ Queue Manager with associated resources

In this lab we will provide a configmap that will be used by the MQ operator to create/configure all the required objects(queues, channels and security settings) on pod startup.

Please ensure you have the `oc` command line installed and logged in ([see prerequisites](../index.html#prerequisites)).

1. Create your MQ project

    ```sh
    oc new-project {{mqLabNamespace | mq-lab }}
    ```

    Ensure that the namespace of that project has a pull secret named `ibm-entitlement-key`. On the TechZone jam-in-a-box machines, you may copy this secret from the `tools` namespace.

    ```sh
    oc get secret ibm-entitlement-key -n tools -o yaml | \
      sed 's/namespace: tools/namespace: {{mqLabNamespace | mq-lab }}/' | \
      oc apply -f -
    ```

1. Create a TLS secret. You will need this later.

    ```sh
    openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=mq-lab" && \
    oc create secret tls mq-lab-tls-secret --key=tls.key --cert=tls.crt && \
    rm tls.key tls.crt
    ```

1. Create a ConfigMap containing scripts for MQ objects creation.

    Linux and macOS users can directly run the command below in the CLI:

    ```sh
    oc apply -f - <<EOF
    kind: ConfigMap
    apiVersion: v1
    metadata:
      name: nativehamqsc
      namespace: {{mqLabNamespace | mq-lab }}
    data:
      nativehamqsc.mqsc: |-
        define ql(APPQ) DEFPSIST(YES)
        define ql(APPQ1) DEFPSIST(YES)
        DEFINE CHANNEL(EXTERNALCHL) CHLTYPE(SVRCONN) TRPTYPE(TCP) SSLCAUTH(OPTIONAL) SSLCIPH('ANY_TLS12_OR_HIGHER')
        set chlauth(EXTERNALCHL) TYPE(BLOCKUSER) USERLIST(NOBODY)
        ALTER QMGR CONNAUTH('')
        REFRESH SECURITY TYPE(CONNAUTH)
    EOF
    ```

    Windows users can create a file named `nativehamqsc.yaml` in their working directory with the content below, and then run `oc apply -f nativehamqsc.yaml`:

    ```yaml
    kind: ConfigMap
    apiVersion: v1
    metadata:
      name: nativehamqsc
      namespace: {{mqLabNamespace | mq-lab }}
    data:
      nativehamqsc.mqsc: |-
        define ql(APPQ) DEFPSIST(YES)
        define ql(APPQ1) DEFPSIST(YES)
        DEFINE CHANNEL(EXTERNALCHL) CHLTYPE(SVRCONN) TRPTYPE(TCP) SSLCAUTH(OPTIONAL) SSLCIPH('ANY_TLS12_OR_HIGHER')
        set chlauth(EXTERNALCHL) TYPE(BLOCKUSER) USERLIST(NOBODY)
        ALTER QMGR CONNAUTH('')
        REFRESH SECURITY TYPE(CONNAUTH)
    ```

1. Open the {{ platformNavigatorLink | Platform Navigator }} and {{ platformNavigatorLogin | log in }}.

    ![Platform Navigator login](images/QM2.png)

    You may be asked to change your password. For the purposes of this lab, you may simply reuse the password you just logged in with.

1. Click `Create an Instance`.

    ![Create an instance](images/QM3.png)

1. A number of tiles are displayed. Click the `Queue Manager` tile, then click `Next`.

    ![Queue manager tile and Next button](images/QM4.png)

1. Click `Quick start` then click `Next`.

    ![Quick start tile and Next button](images/QM5.png)

1. Type `mq-lab-qm` as Name and select `mq-lab` from the namespace drop-down.

    Click on the License acceptance checkbox and check the License is populated.

    ![Name, namespace, and license](images/QM6.png)

1. Scroll down to **Queue Manager** section and select the `NativeHA` in the *Type of Availability* drop-down.

    ![Queue manager availability is NativeHA](images/QM7.png)

1. Under **Storage** select a storage class. For this lab, we will use `ocs-external-storagecluster-ceph-rdb` as our _Default class_.

    For **Queue Manager**, select `persistent-claim` in the _Type of volume_ drop-down.

    ![Storage class and type-of-volume selection](images/QM8.png)

1. Enable the _Advanced Settings_ togle and then scroll to **PKI**. Then click on `Add` under _Keys_.

    ![Advanced settings and PKI add-keys button](images/QM9.png)

1. Provide the key details:

    - Name: type `keystore`
    - Items: Type `tls.key` and press ENTER, then `tls.crt` and press ENTER again.
    - Secret Name: Select `mq-lab-tls-secret` from the drop-down.

    ![Enter PKI properties](images/QM10.png)

1. Scroll down to the MQSC section. This allows you to provide an MQ command script file so the MQ objects are created and configured automatically on pod startup.

    Click on `Add`

    ![MQSC Add](images/QM11.png)

1. In the `Advanced:Items` field, type `nativehamqsc.mqsc` and press enter text box.

    Then select the name of the configmap you created earlier in this lab (`nativehamqsc`) _Advanced: Name_ drop down combo.

    ![MQSC Config map](images/QM12.png)

1. Click Create.

    ![Create button](images/QM13.png)

1. The new Queue Manager instance will be created. It will be in `Pending` status initially.

    ![Queue manager in Pending state](images/QM14.png)

    Wait for couple of minutes then click refresh. Check the status in queue manager, its status should change from `Pending` to `Ready`.

1. Return to terminal. Run `oc get pods`. You will see three pods for the nativeha queue manager.

```sh
$> oc get pods
NAME                 READY   STATUS    RESTARTS   AGE
mq-lab-qm-ibm-mq-0   1/1     Running   0          20m
mq-lab-qm-ibm-mq-1   0/1     Running   0          20m
mq-lab-qm-ibm-mq-2   0/1     Running   0          20m
```

One of the pods has 1 of 1 container running. The other two pods have 0 of 1 container running. This is the nature of nativeHA, one pod running the queue manager and data being replicated to the other two pods which are in standby mode.

## Viewing the status of Native HA queue managers

You can view the status of the Native HA instances by running the dspmq command inside one of the running Pods.

You can use the dspmq command in one of the running Pods to view the operational status of a queue manager instance. The information returned depends on whether the instance is active or a replica. The information supplied by the active instance is definitive, information from replica nodes might be out of date. You can perform
the following actions:

- View whether the queue manager instance on the current node is active or a replica.
- View the Native HA operational status of the instance on the current node.
- View the operational status of all three instances in a Native HA configuration.

The following status fields are used to report Native HA configuration status:

- **ROLE** - Specifies the current role of the instance and is one of Active, Replica or Unknown.
IBM TechXchange 2024 / © 2024 IBM Corporation 14
- **INSTANCE** - The name provided for this instance of the queue manager when it was created.
- **INSYNC** - Indicates whether the instance is able to take over as the active instance if required.
- **QUORUM** - Reports the quorum status in the form number_of_instances_in-sync/number_of_instances_configured.
- **REPLADDR** - The replication address of the queue manager instance.
- **CONNACTV** - Indicates whether the node is connected to the active instance.
- **BACKLOG** - Indicates the number of KB that the instance is behind.
- **CONNINST** - Indicates whether the named instance is connected to this instance.
- **ALTDATE** - Indicates the date on which this information was last updated (blank if it has never been updated).
- **ALTTIME** - Indicates the time at which this information was last updated (blank if it has never been updated).

1. Go back to the terminal having `oc` login. If its disconnected, please reconnect as described in the [prerequisites](../index.html#prerequisites).

1. Run `oc get pods`.

    ```sh
    $> oc get pods
    NAME                 READY   STATUS    RESTARTS   AGE
    mq-lab-qm-ibm-mq-0   1/1     Running   0          20m
    mq-lab-qm-ibm-mq-1   0/1     Running   0          20m
    mq-lab-qm-ibm-mq-2   0/1     Running   0          20m
    ```

1. Run `oc rsh «pod»`, where `«pod»` is the name of the pod that is in `1/1 Running` status. In this case, it's `mq-lab-qm-ibm-mq-0`

    ```sh
    $> oc rsh mq-lab-qm-ibm-mq-0
    sh-5.1$
    ```

1. Type dspmq and hit Enter to check the status of the local queue manager.


    ```sh
    sh-5.1$ dspmq
    QMNAME(QUICKSTART)        STATUS(Running)
    ```

    You will see that in its status it'll say either Running or Replica depending on if it is the active queue manager or one of the two replicas of the Native HA cluster.

1. Type `dspmq -o nativeha -m QUICKSTART` to display the complete nativeha status of the local queue manager.

    ```sh
    sh-5.1$ dspmq -o nativeha -m QUICKSTART
    QMNAME(QUICKSTART)        ROLE(Active) INSTANCE(mq-lab-qm-ibm-mq-0) INSYNC(yes) QUORUM(3/3) GRPLSN(<0:0:19:33699>) GRPNAME() GRPROLE(Live)
    ```

    It'll show the role of the queue manager, nativeha instance name, if it is in sync with the other two replicas and the number of queue managers in quorum.

1. Type `dspmq -o nativeha -x -m QUICKSTART` to display the complete nativeha status of all 3 queue managers in the nativeha cluster.

    ```sh
    sh-5.1$ dspmq -o nativeha -x -m QUICKSTART
    QMNAME(QUICKSTART)        ROLE(Active) INSTANCE(mq-lab-qm-ibm-mq-0) INSYNC(yes) QUORUM(3/3) GRPLSN(<0:0:19:33699>) GRPNAME() GRPROLE(Live)
    INSTANCE(mq-lab-qm-ibm-mq-0) ROLE(Active) REPLADDR(mq-lab-qm-ibm-mq-replica-0) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:44:37.171474Z) ALTDATE(2025-11-12) ALTTIME(23.44.37)
    INSTANCE(mq-lab-qm-ibm-mq-1) ROLE(Replica) REPLADDR(mq-lab-qm-ibm-mq-replica-1) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:44:36.754094Z) ALTDATE(2025-11-12) ALTTIME(23.44.37)
    INSTANCE(mq-lab-qm-ibm-mq-2) ROLE(Replica) REPLADDR(mq-lab-qm-ibm-mq-replica-2) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:44:36.754094Z) ALTDATE(2025-11-12) ALTTIME(23.44.37)
    ```

    We will not test every possibility, but the following are possible displays to expect. Review the possibilities.

    - An active instance of the queue manager named `QUICKSTART` would report the following status:

        ```text
        QMNAME(QUICKSTART) STATUS(Running)
        ```

    - A replica instance of the queue manager would report the following status:

        ```text
        QMNAME(QUICKSTART) STATUS(Replica)
        ```

    - An inactive instance would report the following status:

        ```text
        QMNAME(QUICKSTART) STATUS(Ended Immediately)
        ```

    To determine Native HA operational status of the instance in the specified pod,issue the command dspmq -o nativeha -m QUICKSTART:
    - The active instance of the queue manager named QUICKSTART might report the following status:

        ```text
        QMNAME(QUICKSTART)        ROLE(Active) INSTANCE(my-qm-inst) INSYNC(yes) QUORUM(3/3)
        ```

    - A replica instance of the queue manager might report the following status:

        ```text
        QMNAME(QUICKSTART)        ROLE(Replica) INSTANCE(my-qm-inst) INSYNC(yes) QUORUM(3/3)
        ```

    - An inactive instance of the queue manager might report the following status:

        ```text
        QMNAME(QUICKSTART) ROLE(Unknown) INSTANCE(my-qm-inst) INSYNC(no) QUORUM(0/3)
        ```

    To determine the Native HA operational status of all the instances in the Native HA configuration, issue the command `dspmq -o nativeha -x -m QUICKSTART`:

    - If you issue the command on the node running the active instance of queue manager QUICKSTART, you might receive the following status:

        ```text
        sh-5.1$ dspmq -o nativeha -x -m QUICKSTART
        QMNAME(QUICKSTART)        ROLE(Active) INSTANCE(my-qm-inst-0) INSYNC(yes) QUORUM(3/3) GRPLSN(<0:0:19:33699>) GRPNAME() GRPROLE(Live)
        INSTANCE(my-qm-inst-0) ROLE(Active) REPLADDR(my-qm-inst-replica-0) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:10.757703Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        INSTANCE(my-qm-inst-1) ROLE(Replica) REPLADDR(my-qm-inst-replica-1) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:09.865842Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        INSTANCE(my-qm-inst-2) ROLE(Replica) REPLADDR(my-qm-inst-replica-2) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:09.865842Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        ```

    - If you issue the command on a node running a replica instance of queue manager QUICKSTART, you might receive the following status, which indicates that one of the replicas is lagging behind:

        ```text
        sh-5.1$ dspmq -o nativeha -x -m QUICKSTART
        QMNAME(QUICKSTART)        ROLE(Replica) INSTANCE(my-qm-inst-1) INSYNC(yes) QUORUM(3/3) GRPLSN(<0:0:19:33699>) GRPNAME() GRPROLE(Live)
        INSTANCE(my-qm-inst-1) ROLE(Replica) REPLADDR(my-qm-inst-replica-1) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:09.865842Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        INSTANCE(my-qm-inst-2) ROLE(Replica) REPLADDR(my-qm-inst-replica-2) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:09.865842Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        INSTANCE(my-qm-inst-0) ROLE(Active) REPLADDR(my-qm-inst-replica-0) CONNACTV(yes) INSYNC(yes) BACKLOG(0) CONNINST(yes) ACKLSN(<0:0:19:33699>) HASTATUS(Normal) SYNCTIME(2025-11-12T23:54:10.757703Z) ALTDATE(2025-11-12) ALTTIME(23.54.10)
        ```

    - If you issue the command on a node running an inactive instance of queue manager QUICKSTART, you might receive the following status:

        ```text
        sh-5.1$ dspmq -o nativeha -x -m QUICKSTART
        QMNAME(QUICKSTART)        ROLE(Unknown) INSTANCE(my-qm-inst-X) INSYNC(no) QUORUM(0/3)
        INSTANCE(my-qm-inst-0) ROLE(Unknown) REPLADDR(my-qm-inst-0) CONNACTV(Unknown) INSYNC(Unknown) BACKLOG(Unknown) CONNINST(yes) ALTDATE() ALTTIME()
        INSTANCE(my-qm-inst-1) ROLE(Unknown) REPLADDR(my-qm-inst-1) CONNACTV(Unknown) INSYNC(Unknown) BACKLOG(Unknown) CONNINST(yes) ALTDATE() ALTTIME()
        INSTANCE(my-qm-inst-2) ROLE(Unknown) REPLADDR(my-qm-inst-2) CONNACTV(Unknown) INSYNC(Unknown) BACKLOG(Unknown) CONNINST(yes) ALTDATE() ALTTIME()
        ```

    - If you issue the command when the instances are still negotiating which is active and which are replicas, you would receive the following status:

        ```text
        QMNAME(QUICKSTART)        STATUS(Negotiating)
        ```

## Congratulations

You have completed the lab nativeHA for MQ on CP4I.
