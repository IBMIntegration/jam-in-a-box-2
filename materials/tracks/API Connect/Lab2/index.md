# The Developer Portal Experience

${toc}

## 1. Objectives

We will begin by creating a new catalog and configuring the Developer Portal for our Customer 1.0.0 Product. We will then define a new Plan in the Product and publish to our new Developer Portal.

In this lab, you will explore the following key capabilities:

- Configure the Developer Portal and publish the APIs

- Create a Portal Account

- Create an application and subscribe to a Plan

- Test the API in the Developer Portal

## 2. Prerequisites

- Reserve the lab environment. If you have not reserved the lab environment, then click [here](https://techzone.ibm.com/collection/jam-in-a-box-for-integration-automation-cp4i/environments)

- Create Provider Organization and Configure Developer portal. Go through [FAQs](https://ibmintegration.github.io/jam-in-a-box/faq)

- Go through the presentation to get the knowledge about API connect capabilities. Click [here](https://ibm.box.com/s/zdvlrkbmobejvkd5hzhiqf7jur4fc6sj)

- Finish the Lab1. You will publish the REST API that you have created in the Lab1,

## 3. Getting started with Lab2

A Developer Portal for the Sandbox catalog has already been configured in this environment. Refer FAQs.

### 2a. Login to the API Connect Developer Portal

1\. In a browser, enter the URL for the Platform Navigator and use username(admin)/password that is provided to you.

2\. Navigate to the API Connect instance.

![Platform Navigator showing API Connect instance tile highlighted for developer portal access](../images/PTL6.png)

3\. Select API Manager User Registry.

![API Connect login page with 'API Manager User Registry' authentication option selected](./images/118.png)

4\. Use the user name and password that you have created while creating the provider organization. Refer FAQs section 5)k).

![Provider organization login form with username and password fields for API Manager access](./images/119.png)

5\. Click on **Manage catalogs**.  If you are already logged in and continuing from the previous lab, click on the **Home** icon on the left navigation bar.

![API Manager interface showing 'Manage catalogs' option highlighted in the navigation menu](../images/PTL9.png)

6\. Click on **Sandbox**.

![Catalog management interface showing Sandbox catalog tile highlighted for selection](../images/PTL10.png)

7\. Select the **Catalog settings** tab.

![Sandbox catalog interface with 'Catalog settings' tab highlighted in the navigation](../images/PTL11.png)

8\. From the left menu, click on **Portal**.

![Catalog settings left navigation menu with 'Portal' option highlighted](../images/PTL12.png)

9\. Copy the **Portal URL** and paste it in a new browser tab.

![Portal configuration page showing Portal URL field with copy option for accessing developer portal](../images/PTL13.png)

10\.  The IBM API Connect Developer Portal provides consumers access to API Catalog information.  This gives application developers the opportunity to explore and test APIs, register applications, and subscribe to Plans. 

A Portal Administrator can customize the look and feel to their organizational specifications. The default Developer Portal looks like the image below.  Note:  Depending on what you have published, the Products that you see may be different.

![IBM API Connect Developer Portal homepage showing available API products and navigation menu](../images/PTL14.png)

11\. Some Products are visible to all users without an account depending on the Product visibility setting. Additional options are available when you log into the Developer Portal.

The portal is setup for self service so we will create a new account as a developer. If you have a username beginning with jam, you can skip to Step 16.  If not, click on **Create an account**.

![Developer Portal showing 'Create an account' link highlighted for new user registration](../images/PTL15.png)

12\. Fill in the form and make sure to use a valid email address since that is where the activation email is sent.  At the bottom when done, click **Sign up**.

![User registration form with fields for email, username, first name, last name and Sign up button](../images/PTL16.png)

13\. You will receive an email that you will copy the link and paste in to your browser to complete the registration at which point you can log in. 

![Email activation message showing account verification link for completing registration](../images/PTL17.png)

14\. Go to **Sign in** and enter your Username and Password you just created.  Click **Sign in**.

![Developer Portal sign in form with username and password fields and Sign in button](../images/PTL18.png)

## 3. Register a Test Application
 
 1\. Once you are logged in, you can explore various sections in the Developer Portal.  The Products that you see in your Portal may vary from what is shown in the lab images.  Click on **Customer 1.0.0**.  This is the Product that we published in the "Create and Secure an API to Proxy an Existing REST Web Service" lab. 

![Developer Portal products page showing Customer 1.0.0 product tile highlighted for selection](../images/PTL19.png)

2\. You will see the API and Plan that is associated with the Customer 1.0.0 Product.

![Customer 1.0.0 product detail page showing associated Customer Database API and Default Plan](../images/PTL20.png)

### 3a. Create a new Consumer Application

IBM API Connect enforces entitlement rules to ensure that consumers are allowed to access the APIs that are being requested.  In the following steps you will register your consumer application and subscribe to an API Product.

1\. Click on **Apps**.

![Developer Portal top navigation menu with 'Apps' section highlighted for application management](../images/PTL21.png)

2\. Click **Create new app**.

![Apps page showing 'Create new app' button for registering new consumer application](../images/PTL22.png)

3\. Give your application a **title** (e.g. Customer Demo) and click **Save**.

![New application form with title field showing 'Customer Demo' and Save button highlighted](../images/PTL23.png)

4\.  When your consumer application is registered in the IBM API Connect system, it is assigned a unique set of client credentials. These credentials must be provided on each API request in order for the system to validate your subscription entitlements. The Client Key can be retrieved anytime but the Client Secret can only be retrieved at this time.

Make note of your **Client Key** and **Client Secret** by click on the copy icon for each.  You will need the Client Secret in a future step.  Click **OK**.

![Application credentials dialog showing Client Key and Client Secret with copy icons and OK button](../images/PTL24.png)

## 4. Subscribe to the API Product

At this point, your registered consumer application has no entitlements.

In order to grant it access to an API resource, you must subscribe to a Product and Plan.

1\. Click on **API Products**.

![Developer Portal top navigation showing 'API Products' menu item highlighted for browsing available products](../images/PTL25.png)

2\. Click the **Customer 1.0.0** Product.

![API Products page showing Customer 1.0.0 product tile selected for subscription](../images/PTL26.png)

3\. Click on **Select** for the **Default Plan**.

![Customer 1.0.0 product page showing Default Plan with Select button highlighted for subscription](../images/PTL27.png)

4\. Select the application (e.g. **Customer Demo**) that you just created.  **Note:** The number of applications that you see in your environment may differ.

![Subscription dialog showing Customer Demo application selection for plan subscription](../images/PTL28.png)

5\. Review the subscription information and click **Next**.

![Subscription review page showing plan and application details with Next button](../images/PTL29.png)

6\. Click **Done**.

![Subscription confirmation page with Done button to complete the subscription process](../images/PTL30.png)

## 5. Test the API

The API Connect Developer Portal allows consumers to test the APIs directly from the website. This feature may be enabled or disabled per-API.

1\. You should be on a screen that shows the API and Plan for the **Customer 1.0.0** Product.  If you are not on this screen, click on **API Products** in the top navigation and select the **Customer 1.0.0** Product.

![Customer 1.0.0 product overview page showing API and plan information with navigation breadcrumb](../images/PTL31.png)

2\. Click on the **Customer Database 1.0.0** API.

![Product page showing Customer Database 1.0.0 API tile highlighted for testing](../images/PTL32.png)

3\. Click on the **GET /customers** operation.

![API documentation showing GET /customers endpoint highlighted for testing](../images/PTL33.png)

4\. On the right, you will find information about the request parameters and links to the response schemas.  Click the **Try it** tab.

![API operation documentation with 'Try it' tab highlighted for interactive testing](../images/PTL34.png)

5\. If you only have one application registered, it will be automatically selected in the **API Key** drop-down menu. If you have more than one, select the application (**Customer Demo**) which is subscribed to this API Product.

Paste your **Client Secret** in the **API Secret** field.

Click **Send**.

![API testing form with API Key dropdown, Client Secret field, and Send button for executing requests](../images/PTL35.png)

6\. Scroll down to see the call results.

![API test results showing successful response with customer data from the GET /customers endpoint](../images/PTL36.png)

Note: If running for the first time, you may see Code: 0 No response received. Causes include a lack of CORS support on the target server, the server being unavailable, or an untrusted certificate being encountered.  Clicking the link below will open the server in a new tab.

If the browser displays a certificate issue, you may choose to accept it and return here to test again.

7\. Feel free to test the rest of the operations.  Testing will be similar to the testing that was completed in the "Create and Secure an API to Proxy an Existing REST Web Service" lab.

### [Return to main APIC lab page](../api-connect)
