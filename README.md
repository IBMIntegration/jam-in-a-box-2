# integration-jam-in-a-box

## Getting Started

1. Set up your IBM Tech Zone environment at IBM Technology Zone. Please note that once you have reserved your environment, it can take 2-3 hours to provision it.

    1. Access the collection "[Cloud Pak for Integration SC2 & CD Demo Environments](https://techzone.ibm.com/collection/674eb0d582e9ed71ce38688b)". You may need to log into IBM Technology Zone using your w3id or IBMid.
    1. Click on the button at the bottom of the environment called **CP4I on OCP-V (2.0)**.
        ![Select environment](README-images/GS1.png)
    1. Click **Request an environment**
        ![Request an environment](README-images/GS2.png)
    1. Give your environment a name and click **Education**
        ![Environment name and purpose](README-images/GS3.png)
    1. Scroll down. Describe the purpose of your reservation (e.g. "Learning the fundamentals of the IBM Integration portfolio") and select the region that is closest to you.
        ![Description and region](README-images/GS4.png)
    1. Note that your reservation time is limited. Your Tech Zone environment will be delete at that time unless you extend your reservation later. Select the **CP4I version** you would like to install. The `SC2` version is recommended unless there is a specific feature of the `CD` version you would like to explore.
        ![Reservation time and CP4I Version](README-images/GS5.png)
    1. Agree to the terms and submit your request
        ![Agree and submit](README-images/GS6.png)
    1. You will receive a confirmation screen and IBM Technology Zone will start provisioning your server. **Note that this process takes two hours**. You will receive an email when the provisioning is complete.
    
        In the meantime, you may click the `My Reservations` button to check the status of your reservation.

        ![View Reservations button](README-images/GS7.png)
    1. The reservation appears as a card on the **My Reservations** page. This card has a yellow title bar when the OCP environment is provisioning, and that will turn to green when it's done.
        ![My reservations](README-images/GS8.png)
    1. Relax and get some coffee. IBM Technology Zone will send you an email when the OCP environment provisioning process is complete. When you receive this email, your reservation in the **My Reservations** page will turn green. Click **Open this environment**.
        ![My reservations](README-images/GS9.png).
    1. You will see your login credentials and the URL of your OpenShift console here. Use these credentials to log in.
        ![Login credentials](README-images/GS10.png)

1. Wait for Cloud Pak for Integration to set itself up.

    - Your CP4I installation will start automatically. When it starts, you will see a blue bar across the top of the screen saying "cp4i-demo is still running. Please check the status here".
        ![CP4I still installing](README-images/GS11.png)
    If you click the **check the status here** link, you may follow the deployment pipelines.
    - You will know the CP4I installation is complete when
        1. There is a `tools` namespace
        1. There is a green bar at the top that says "Pipeline cp4i-demo ran successfully. Please check the logs to view the login details here"
        ![CP4I installation is complete](README-images/GS12.png)

1. Log in to the OpenShift console

    1. If you don't already have the OpenShift `oc` command line installed on your local machine, download and install it from either:
        1. Your local OpenShift console, or
        1. [developers.redhat.com](https://developers.redhat.com/learning/learn:openshift:download-and-install-red-hat-openshift-cli/resource/resources:download-and-install-oc)

    1. Use `oc` to log in to OpenShift

        1. Get a login command from the OpenShift Console. Click on your username at the top right corner and then select `Copy login command`

        ![Copy login command](README-images/OC1.png)

        1. You may be asked to log in again. Once you have logged in, click `Display Token`.

        1. Copy and paste the entire `oc login` command line into your terminal.

        ![oc login command line](README-images/OC2.png)

        ```plaintext
        $> oc login --token=sha256~D6f...jHwBFbk --server=https://api.itz-lcqsie.hub01-lb.techzone.ibm.com:6443

        Logged into "https://api.itz-lcqsie.hub01-lb.techzone.ibm.com:6443" as "kube:admin" using the token provided.

        You have access to 89 projects, the list has been suppressed. You can list all projects with 'oc projects'

        Using project "default".
        ```

1. Download and install the Jam-in-a-Box tooling and materials.

    ```sh
    # Basic usage (no parameters)
    oc apply -f https://raw.githubusercontent.com/IBMIntegration/jam-in-a-box-2/main/setup.yaml
    ```

    This process will take 10-15 minutes to complete.

    - The first pod to appear, the `jam-setup-pod`, will take about five minutes, mostly creating an image regstry and building images.

1. Get the URL and credentials for the jam-in-a-box app.

    TODOC
