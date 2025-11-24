# Discover your unknown APIs

_Hands-on lab guide_

${toc}

## Introduction

In a world where disruption is the norm, we often have more APIs than we are aware. API proliferation is a challenge that all sizes of organization must face. APIs that are not known cannot be governed or validated and can allow security flaws to be unknowingly exposed.

IBM API Connect is an industry-leading integration solution that is designed to create, govern, socialize and secure your APIs. In IBM API Connect v10.0.8 a new feature called API Discovery has been included to help solve the challenge of discovering APIs in your estate.

For this Lab we are putting you in the role of a Senior Integration Operations Specialist. You are discovering unknown APIs exposed via from artifacts in GitHub.

## Preparation for this hands-on lab

In the second part of the demo, you will configure an agent to retrieve OpenAPI documents from GitHub, then use the AI Assistance to populate various fields.

1. Go to the API Manager console using the link provided in reference sheet. Click on Cloud Pak User
Registry.

2. Login to API Manager instance with your credentials.

3. On the address bar, add /apikeys to the end of the URL (after the organization name) and enter.
E.g - https://api-manage-1720ed5d-api-manager-tech-jam-apic.tj-isa-1-
420eb34f056ae68f3969289d61f61851-0000.jp-tok.containers.appdomain.cloud/manager/tech-jam-
01/apikeys

4. Click on Add

5. Provide a title(student<no>_key) and description. Click Create.

6. Copy the API Key that is generated which will be used later.

7. Be careful of the expiration time of the APIKey. Make sure finish the lab before the key expires.

## Discovering APIs from GitHub

**Note:** For this part of the Lab, we will make code changes directly in the GitHub UI so that no extra tooling is required other than your web browser.

The goal of this part of the demo is to send an OpenAPI Specification Document from GitHub to the API Discovery Service.

### API Discovery

1. Log into your own github.com account. Create one if not having one yet.

1. Fork the repo in your GitHub account:

    1. In a browser window, navigate to the GitHub repository for this lab.
      https://github.com/APIDiscoveryTechExchange2024/apic-discovery-lab

    1. Click on Fork.

    1. Select your github user as Owner
    1. Uncheck the box against Copy the main branch only.
    1. Click on Create fork.

3. Go to the forked instance in your own github, e.g. https://github.com/tutorial-org-mkz/apic-discovery-lab

4. Navigate to the branch in that repository based on your participant code (given to you by the lab attendants) E.g. lab_participant_16.

Please ensure you are only using the branch ID for the lab participant code you have been given and not that of someone else. e.g. https://github.com/tutorial-org-mkz/apic-discovery- lab/tree/lab_participant_16

5. Navigate to the send-to-discovery.yml file in your branch's .github/workflows directory, and open the file E.g. https://github.com/APIDiscoveryTechExchange2024/apic-discovery-lab/blob/lab_participant_0/.github/workflows/send-to-discovery.yml

6. In the code find the api_key field and see what the name of the apikey is. Each branch has a unique
api_key name.

    This will be the unique name which needs to be used when creating the Action Secret below. Copy the value of api_key.

    E.g. api_key: ${{ secrets.apicApikey_participant_1 }}

7. Navigate to the “Settings” of your forked repository:

    E.g. - https://github.com/sinamitk/apic-discovery-lab/settings

8. Under the "Secrets and variables" section in the left menu, select the "Actions" option.

    Click on the "New repository secret" button

9. Add a new Secret

    Name: Secret: Exact name of the api_key found at step 6 above.

    Api Key value generated in Section 2 using API Manager.

8. Navigate to Actions tab.

9. Enable Workflows.

    Click on “I understand my workflows, go ahead and enable them”.

10. Navigate back to the send-to-discovery.yml file under your unique branch and press the "Edit this file" button (i.e. the Pencil icon in the file header bar).

    Under the env: property in the file

    - API_HOST - Replace the current API_HOST value with one given in reference file.
    
        Example - tj-isa-1-420eb34f056ae68f3969289d61f61851-0000.jp-tok.containers.appdomain.cloud

    - PROVIDER_ORG - Replace the current Provider_Org value with tech-jam-<studentno>, replace <studentno> with your allotted one (01,02 etc).

    - Add env variable PLATFORM_API_PREFIX and provide the value given in reference file.

    - Add another env variable INSECURE_SKIP_TLS_VERIFY with value set to true.

    - Update the API_FILES variable to be the relative path to the sample API specification for this demo e.g. APIfolder/photos.yaml.

    After doing the above mentioned changes, the `env:` section in `send-to-discovery.yml` file should look like this:

    Scroll further in the send-to-discovery.yml and add line

    ```yaml
    insecure_skip_tls_verify: $\{{ env.INSECURE_SKIP_TLS_VERIFY }\}
    ```

    as next line after `git_diff: $\{{ steps.difference-output.outputs.action_updates }\}

    11. Commit the changes to GitHub by pressing the "Commit changes" button.

    Update the commit message with a unique message which you'll be able to track; use your unique branch name in the commit message so you can find your executing action more easily.

    12. Once committed, navigate to the “Actions” panel which will show all the executing actions which are running against the repository.

    Find your executing action based on the unique commit message you added in the previous step.

    13. Click on the Action commit message and ensure that the action has executed properly, and the file has been sent to the API Discovery Service of the API Connect SaaS Instance.

    14. IBM CP4I TechJam – ISA - 2024 Navigate to the API Manager Console (Following Section 2: step 1 and 2).

    15. Access the “Discover” panel by selecting the binoculars icon in the left-hand navigation bar Observe that the API Specification Document provided in send-to-discovery.yml is now visible in the UI under the "APIs" section.

    Select the API and have a look at its details in the API explorer UI.

    16. Select the Sources section and observe that there is a new Datasource of Type “GitHub” with the GitHub repository name.

    ### Develop API

    - Once again, on the “Discover” page of the API Manager Console, open the API that was discovered from GitHub, and then press the "Copy to draft" button.

    This will make the API available as a Draft API within your Provider Organization.

    - Open the API Developer UI by clicking on the Pencil icon in the left-hand navigation bar, and then open the copied Draft API in the API list to edit it.

    Navigate to the Code "Source" view by pressing the source slug button on the UI:

    - Edit the API as follow to set target-url value as show in screenshot below.

    assembly->target-url : $(target-url)$(api.operation.path)

    properties->target-url->value: https://jsonplaceholder.typicode.com

    - Save API

    ### Testing and Publishing

    1. Click on Test tab.

    2. Click on Target Configuration.

    3. Toggle Auto Publish to On which automatically publishes APIs to Sandbox catalog for testing.

    4. Test API.

    Add /1 at the end of path in GET request. Click Send.

    5. Alternatively, you can test it via other client like Postman.

    6. The API is automatically published to Sandbox catalog under corresponding auto product which can be viewed here.

    7. The API can be further explored with the built-in consumer catalog

    Click on Catalog Settings

    8. Click on the Consumer Catalog URL and examine and play with the API

    You have now successfully completed this section of the demo.

    ## Summary

    Let’s summarize what you have done today. In this lab you:

    - Configured and deployed the API Connect Discovery Agent
    - Discovered in OpenAPI Specifications from GitHub
    - Observed and Edited the Discovered APIs within IBM API Connect.
    - Published the API for testing.
