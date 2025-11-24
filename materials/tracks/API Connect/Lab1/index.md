# Create and Publish your first REST API to expose an existing REST Service

${toc}

## 1. Objectives

In this lab you will learned how to:

- Create an API by importing an OpenAPI definition for an existing REST service.

- Configure ClientID/Secret Security, endpoints, and proxy to invoke endpoint.

- Test a REST API in the Developer Toolkit.

- Publish an API for developers.

## 2. Prerequisites

- Reserve the lab environment. If you have not reserved the lab environment yet, then click [[here](https://techzone.ibm.com/collection/jam-in-a-box-for-integration-automation-cp4i/environments)]

- Create **Provider Organization** and Configure **Developer portal**. Go through [FAQs](https://ibmintegration.github.io/jam-in-a-box/faq)

- Go through the presentation to get the knowledge about API connect capabilities. Cleck [here](https://ibm.box.com/s/zdvlrkbmobejvkd5hzhiqf7jur4fc6sj)


## 3. Getting started with lab1

Before we can use API Connect we must publish an API to expose. We will deploy a Customer Database REST service and then we will download the OpenAPI file for the the Customer Database REST service that we deployed.

1\. In a browser, enter the URL for the Platform Navigator. Go to [FAQs](https://ibmintegration.github.io/jam-in-a-box/faq#TZ-ocp-console) to learn, how to access your enviroment.

2\. When prompted, use the username(admin) and password provided to you for this lab.

![Platform Navigator login page with username and password fields](./images/105.png)

4\. When you log in for the first time, you may see a **Welcome, let's get started** window.  Feel free to review the contents by click **Start the tour** or by click on the **X** to close the window.

![Welcome dialog box with 'Start the tour' button and close X option](../images/CP91.png)

5\. Navigate to the **App Connect Dashboard**.

![Platform Navigator homepage showing App Connect Dashboard tile in the integration capabilities section](../images/CP92.png)

6\. Click on the **Dashboard** icon in the left navigation.

![App Connect interface with Dashboard icon highlighted in the left navigation menu](../images/CP93.png)

7\. If you would like to create this web service yourself, follow the instructions in the **Using a REST API to manage a set of records** tutorial (https://www.ibm.com/docs/en/app-connect/11.0.0?topic=enterprise-toolkit-tutorials-github).  Otherwise, you can download the **CustomerDatabaseV1.bar** file for the service [here](./resources/CustomerDatabaseV1.bar).

8\. Click on **Create server**.

![App Connect Dashboard with prominent 'Create server' button in the center](../images/CP94.png)

9\. Click **Quick start toolkit integration** and click **Next**.

![Server creation wizard showing 'Quick start toolkit integration' option selected with Next button](../images/CP95.png)

10\. Drag and drop the BAR file that you just downloaded or click to upload.  Click **Next**.

![File upload interface with drag and drop area for BAR files and upload button](../images/CP96.png)

11\. Click **Next**.

![Configuration screen in the server creation wizard with Next button](../images/CP97.png)

12\. Give the Integration Server a **Name** (e.g. <span style="color: red">username</span>-customerdb) and click **Create**.

![Integration Server creation form with name field highlighted showing 'username-customerdb' format](../images/CP98.png)

13\. This will take you back to the Servers Dashboard where you will see your new server. It will likely be showing Pending while it is starting up the pod.

![Servers Dashboard showing newly created integration server with 'Pending' status](../images/CP99.png)

14\. Note: It may take a couple of minutes to start up. You can refresh the page. Once it is up and running it will show the following:

![Servers Dashboard showing integration server with 'Running' status and green checkmark](../images/CP100.png)

15\.  Click on the newly created Integration Server.

![Integration Server tile in the dashboard with server name highlighted for clicking](../images/CP101.png)

16\. Click on the **CustomerDatabaseV1** API.

![Integration Server details page showing CustomerDatabaseV1 API tile](../images/CP102.png)

17\. Confirm that the **Overview** tab is selected and click **Download OpenAPI Document**.

![API overview page with 'Download OpenAPI Document' button highlighted](../images/CP103.png)

## 3a. Import an API into API Connect

1\. Click on **IBM Automation** in the upper left.

![Navigation breadcrumb showing 'IBM Automation' link in the upper left corner](../images/CP104.png)

2\. Navigate to the API Connect instance.

![Platform Navigator showing API Connect instance tile in the integration capabilities](../images/CP6.png)

3\. Select API Manager User Registry.

![API Connect login page with 'API Manager User Registry' option highlighted](./images/118.png)

4\. Use the user name and password that you have created while creating the provider organization. Refer FAQs section 5)k).

![API Manager login form with username and password fields for provider organization access](./images/119.png)

5\. When you log in for the first time, you may see a **Get started** window.  Feel free to review the contents and close the window.

6\. Confirm that you are in the provider organization for your username (upper right) and then click on **Develop APIs and products**.

![API Manager dashboard with provider organization name shown in upper right and 'Develop APIs and products' tile highlighted](../images/CP9.png)

7\. We are now able to begin to create APIs and Products.  Click **Add**.

![API development workspace showing prominent 'Add' button for creating new APIs and products](../images/CP10.png)

8\. Click **API (from REST, GraphQL or SOAP)**.

![Add menu dropdown showing 'API (from REST, GraphQL or SOAP)' option selected](../images/CP11.png)

9\. Click **Existing OpenAPI** under **Import** and click **Next**.

![API creation wizard showing 'Existing OpenAPI' option under Import section with Next button](../images/CP12.png)

10\.  Select the **Customer_Database-1.0.0.yaml** file that was just downloaded and click **Next**.

![File selection dialog showing Customer_Database-1.0.0.yaml file selected for upload](../images/CP13.png)

11\. Make sure that the **Activate API** <span style="color: red">is not</span> selected and click **Next**. 

![API import options showing 'Activate API' checkbox unchecked as required](../images/CP14.png)12\.  The API should be imported successfully as shown in the image below.  Click **Edit API**.

![API import success screen showing Customer Database API imported successfully with 'Edit API' button](../images/CP15.png)

## 3b. Configure the API

After importing the existing API, the first step is to configure basic security before exposing it to other developers. By creating a client key and secret security, we are able to identify the application using the API.

Next, we will define the backend endpoints where the API is actually running. IBM API Connect supports pointing to multiple backend endpoints to match your multiple build stage environments.

Finally, we will configure the proxy call to invoke the endpoint.

### i. Configure API Key Security

1\. Upon import, you will notice that an error has been detected.  Click on the **error**.

![API editor interface showing an error indicator that needs to be clicked to view details](../images/CP16.png)

2\. The error indicates that **the openapi definition must contain the 'https' scheme.**.  After reviewing the error, click on the **X** to close the window.

![Error dialog showing message about missing 'https' scheme in OpenAPI definition with X close button](../images/CP17.png)

3\. To resolve the error, make sure that the **Design** tab is selected and click on the **+** next to **Schemes List**.

![API Design tab showing Schemes List section with + button highlighted for adding new schemes](../images/CP18.png)

4\. From the **Select an option** drop-down menu, select **https**.  Click **Create**.

![Dropdown menu showing scheme options with 'https' selected for creation](../images/CP19.png)

![Schemes configuration interface showing https option being configured](../images/CP20.png)

![Schemes configuration interface showing https option being configured](../images/CP20.png)

5\. Expand the **Schemes List** section.  Under the Schemes List, **http** and **https** are listed.  Click **Save**.

![Expanded Schemes List showing both http and https schemes configured with Save button](../images/CP21.png)

Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.  You should no longer see the warning indicator.

![Success notification dialog showing 'Your API has been updated' message with X close button](../images/CP22.png)

6\. Make sure that the **Design** tab is selected and click on the **+** next to **Security Schemes**.

![Design tab interface showing Security Schemes section with + button highlighted for adding new security scheme](../images/CP23.png)

7\. For the **Security Definition Name (Key)**, enter a name (e.g., **X-IBM-Client-Id**) and select **apiKey** in the drop-down menu for **Security Definition Type**.

![Security definition form with X-IBM-Client-Id name and apiKey type selected](../images/CP24.png)

8\. For the **Name**, enter a name (e.g., **X-IBM-Client-Id**), select **client_id** from the drop-down menu for **Key Type (optional)**, and select **header** from the drop-down menu for **Located In**.  Click **Create**.

![Security definition configuration showing X-IBM-Client-Id name, client_id key type, and header location settings](../images/CP25.png)

9\. Click **Save**.

![](../images/CP26.png)

10\. Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.

![Success notification showing 'Your API has been updated' message with X close button](../images/CP22.png)

11\. Make sure that the **Design** tab is selected and click on the **+** next to **Security Schemes**.

![Design tab showing Security Schemes section with + button for adding the second security scheme](../images/CP31.png)

12\. For the **Security Definition Name (Key)**, enter a name (e.g., **X-IBM-Client-Secret**) and select **apiKey** in the drop-down menu for **Security Definition Type**.

![Security definition form configured for X-IBM-Client-Secret with apiKey type selected](../images/CP32.png)

13\. For the **Name**, enter a name (e.g., **X-IBM-Client-Secret**), select **client_secret** from the drop-down menu for **Key Type (optional)**, and select **header** from the drop-down menu for **Located In**.  Click **Create**.

![Security definition configuration for X-IBM-Client-Secret showing client_secret key type and header location settings](../images/CP33.png)

14\. Click **Save**.

![API editor interface with Save button to persist the Client-Secret security scheme](../images/CP26.png)

15\. Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.

![Success notification dialog showing 'Your API has been updated' confirmation message](../images/CP22.png)

16\. Make sure that the **Design** tab is selected and click on the **+** next to **Security**.

![Design tab showing Security section with + button highlighted for adding security requirements](../images/CP34.png)

17\. Select **"X-IBM-Client-Id"** and **"X-IBM-Client-Secret"** and click **Create**.

![Security requirement dialog showing both X-IBM-Client-Id and X-IBM-Client-Secret selected for creation](../images/CP35.png)

18\. Click **Submit**.

![Security configuration interface with Submit button to apply the security requirements](../images/CP37.png)

19\. Click **Save**.

![API editor with Save button to persist all security configuration changes](../images/CP26.png)

20\. Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.

![Final success notification showing 'Your API has been updated' after security setup completion](../images/CP22.png)

### ii. Define a Target-URL for Sandbox Environment

1\. Make sure that the **Design** tab is selected and click on **Host**.

![Design tab interface showing Host section highlighted for configuration](../images/CP38.png)

2\. Copy the value in the **Host (optional)** field.

![Host configuration showing the host URL value that needs to be copied for later use](../images/CP39.png)

3\. Navigate to the **Gateway** tab.

![API editor interface showing Gateway tab highlighted in the navigation](../images/CP40.png)

4\. Make sure that the **Gateway** tab is selected and expand **Properties**.  Click on **target-url**.

![Gateway tab showing expanded Properties section with target-url property highlighted](../images/CP41.png)

5\. Replace the **Property Value (optional)** with the value that you copied in Step 2.  **Note:**  Make sure to include a **http://** at the beginning and remove the **:** and **port number** (e.g. **:80**) from the end if it exists.

![Property configuration dialog for target-url showing value field being updated with copied host URL](../images/CP42.png)

6\. Click **Update**.

![Property configuration dialog showing Update button to save the target-url changes](../images/CP43.png)

7\. Click **Save**.

![Gateway tab interface with Save button to persist the target-url property configuration](../images/CP44.png)

8\. Navigate to the **Design** tab.

![API editor showing Design tab being selected to return to design configuration](../images/CP45.png)

9\. Click on **Host**.

![Design tab interface with Host section selected for configuration](../images/CP46.png)

10\. Delete the value in the **Host (optional)** field.

![Host configuration showing the host field being cleared of its previous value](../images/CP47.png)

14\. Click **Save**.

![API editor interface with Save button to persist the Client-Secret security scheme](../images/CP26.png)button to persist all security configuration changes](../images/CP26.png)

20\. Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.

![Final success notification showing 'Your API has been updated' after security setup completion](../images/CP22.png)

### iii. Configure Proxy Call in Designer

1\. Navigate to the **Gateway** tab.

![API editor with Gateway tab highlighted for configuring proxy policies](../images/CP48.png)

2\. Make sure the **Gateway** tab is selected and click on **Policies**.

![Gateway tab interface showing Policies section highlighted for assembly configuration](../images/CP49.png)

3\. Click on the **Invoke** task in the assembly panel.

![Gateway policies assembly showing Invoke task highlighted in the policy flow diagram](../images/CP50.png)

4\. Update the **URL** so that it reads **$(target-url)$(request.path)**.

![Invoke policy configuration showing URL field being updated with target-url and request.path variables](../images/CP51.png)

5\. Click **Save**.

![Gateway tab with Save button to persist the Invoke policy URL configuration](../images/CP52.png)

6\. Once saved, you will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.

![Success notification showing 'Your API has been updated' after proxy configuration completion](../images/CP53.png)

## 3c. Test the API

In the API Designer, you have the ability to test the API immediately after creation in the Assemble view!

1\. Switch the toggle from Offline to Online. This step automatically publishes the API.

![API editor interface showing toggle switch being changed from Offline to Online status](../images/CP54.png)

2\. You will see an indicator window appear that shows that **Your API has been updated**.  Click on the **X** to close the window.  You should see that the API is now Online.

![API status confirmation showing the API is now Online with success notification dialog](../images/CP55.png)

3\. Click on the **Test** tab.

![API editor showing Test tab highlighted in the navigation for API testing](../images/CP56.png)

4\. For the **Request**, select the request that begins with **GET** and ends in **../customerdb/v1/customers**.  Click **Send**.

![Test interface showing GET request to customerdb/v1/customers endpoint selected with Send button](../images/CP57.png)

**Note:** If this is the first time testing the API after publishing it, you may get a **No response received** popup. Click **Here** and accept the certificate to see the 401 message.

![Error dialog showing 'No response received' message with link to accept certificate](../images/CP58.png)

To add an exception in the Chrome browser, click in the whitespace of the page.

![Chrome browser certificate error page with whitespace area for clicking to bypass security warning](../images/CP59.png)

Blindly type **thisisunsafe**.  This should direct you to a new page that states **401 - Unauthorized**.

![Browser page showing '401 - Unauthorized' error message after certificate bypass](../images/CP60.png)

Navigate back to the **API Connect** browser window.

To add an exception in the Firefox browser, click **Advanced** and click **Accept the Risk and Continue**.

![Firefox security warning page with Advanced button highlighted for certificate exception](../images/CP61.png)

![Firefox advanced security options showing 'Accept the Risk and Continue' button](../images/CP62.png)

This will direct you to a new page that states **401 - Unauthorized**.

![Firefox showing 401 - Unauthorized page after accepting certificate risk](../images/CP63.png)

Navigate back to the **API Connect** browser window.

5\. Click **Send**.

![Test interface with Send button highlighted for executing the GET request to retrieve customers](../images/CP57.png)

6\. The **Response** will show all of the customers in the database.

![Test response showing JSON array of customer records retrieved from the database](../images/CP64.png)

7\. Now let's add a record to the database.  Click **Clear**.

![Test interface with Clear button highlighted to reset the test form for new request](../images/CP65.png)

8\. For the **Request**, select the request that begins with **POST** and ends in **../customerdb/v1/customers**.  Click on the **Body** tab.

 ![Test interface showing POST request selected with Body tab highlighted for JSON payload entry](../images/CP66.png)

9\. In the **Body** tab, enter some text in the following JSON format:<br\>
```
{  
"firstname" : "Emily",  
"lastname" : "Drew",  
"address" : "123 Colorado Address"  
}  
```

Click **Send**.

![Test Body tab showing JSON customer data entered for POST request with Send button](../images/CP67.png)

10\. Make note of the **ID** number in the response.  In the example below, the ID is 9.

![Test response showing newly created customer record with ID number 9 highlighted](../images/CP68.png)

11\. For the **Request**, select the request that begins with **GET** and ends in **../customerdb/v1/customers/{customerId}** and click **Clear**.

![Test interface showing GET by customerId request selected with Clear button for new test](../images/CP69.png)

12\. Click on the **Parameters** tab and enter the **ID** that you noted in step 10. Click **Send**.

![Test Parameters tab showing customer ID field populated with value 9 and Send button](../images/CP70.png)

13\. In the response, you will see the customer information that you entered in step 9.

![Test response showing individual customer record matching the ID parameter](../images/CP71.png)

14\. We can now update the customer information. For the **Request**, select the request that begins with **PUT** and ends in **../customerdb/v1/customers/{customerId}** and click **Clear**.

![Test interface showing PUT request for customer update selected with Clear button](../images/CP72.png)

15\. Enter the **ID** that you noted in step 10 and click on the **Body** tab.

![PUT request setup showing customer ID parameter and Body tab for JSON payload entry](../images/CP73.png)

16\. In the **Body** tab, enter some text in the following JSON format:<br\>
```
{
  "firstname": "Emily",
  "lastname": "Drew",
  "address": "123 Colorado Address"
}
```
and click **Send**.

![PUT request Body tab with updated JSON customer data and Send button highlighted](../images/CP74.png)

17\. The response should show that the customer ID was updated.

![PUT response confirming successful customer record update](../images/CP75.png)

18\. For the **Request**, select the request that begins with **GET** and ends in **../customerdb/v1/customers/{customerId}** and click **Clear**.

![Test interface selecting GET request by customer ID with Clear button for new test setup](../images/CP69.png)

19\. Make sure that the **Parameters** tab is selected and enter the **ID** that you noted in step 10. Click **Send**.

![Parameters tab with customer ID populated for verification GET request with Send button](../images/CP70.png)

20\. In the response, you will see the customer information that you entered in step 16.

![GET response showing updated customer information confirming the PUT operation was successful](../images/CP76.png)

21\. You can also delete a customer from the customer database.  For the **Request**, select the request that begins with **DELETE** and ends in **../customerdb/v1/customers/{customerId}** and click **Clear**.

![Test interface showing DELETE request for customer removal selected with Clear button](../images/CP77.png)

22\. Make sure that the **Parameters** tab is selected and enter the **ID** that you noted in step 10 and enter **secr3t** for **Authorization**. Click **Send**.

![DELETE request Parameters tab showing customer ID and Authorization field with 'secr3t' value](../images/CP78.png)

23\. In the response, you will see the customer was deleted.

![DELETE response confirming successful customer record deletion from the database](../images/CP79.png)

## 3d. Publish API

In this lab, we will make the API available to developers. In order to do so, the API must be first put into a product and then published to the Sandbox catalog. A product dictates rate limits and API throttling.

When the product is published, the Invoke policy defined in the previous lab is written to the gateway. 

### 6a. Create Customer Product and Add API

1\. From the vertical navigation menu on the left, click **Develop**.

![API Connect interface with Develop option highlighted in the left navigation menu](../images/CP80.png)

2\. Click the **Products** tab.

![Develop workspace showing Products tab selected for creating API products](../images/CP82.png)

3\. Click **Add** and click **Product** from the drop-down menu.

![Products workspace with Add button and Product option highlighted in dropdown menu](../images/CP83.png)

![Add menu dropdown showing Product option for creating new API product](../images/CP84.png)

4\. Click **New product** and click **Next**.

![Product creation wizard showing 'New product' option selected with Next button](../images/CP85.png)

5\. Enter **Customer** for the **Title** and click **Next**.

![Product creation form with 'Customer' entered as the title and Next button](../images/CP86.png)

6\. Select the **Customer Database** API and click **Next**.

![API selection screen showing Customer Database API selected for inclusion in product](../images/CP87.png)

7\. Keep the **Default Plan** as is and click **Next**.

![Plan configuration screen showing Default Plan settings maintained with Next button](../images/CP88.png)

8\. Select **Publish product** and confirm that **Visibility** is set to **Public** and **Subscribability** is set to **Authenticated**.  Click **Next**.

![Publication settings showing Publish product selected with Public visibility and Authenticated subscribability options](../images/CP89.png)

9\.  The Product is now published successfully with the API base URL listed and available for developers from the Developer Portal.  Click **Done**.

![Product publication success screen showing API base URL and confirmation that product is available in Developer Portal](../images/CP90.png)

### [Return to main APIC lab page](../api-connect/)
