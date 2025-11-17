# Introduction

In this lab you will build a new connector to an application so that in can be used within an integration flow built on ACE Designer.

Connectors abstract you from the technical details of calling an application allowing you to build no-code or low-code integration solutions.

${toc}

## Create a Connector using the Connector Development Kit

We will be using a couple of files for this lab.
Please download the following files and save them into a folder in your computer:

- [`pet-store.yaml`](./resources/pet-store.yaml)
- [`pet-store.svg`](./resources/pet-store.svg)

1. In browser go to [http://explorer.automation.ibm.com]. Automation Explorer contains assets for IBM integration products such as connectors for IBM App Connect and IBM Event Automation.

   Click on Connector Development Kit.

   ![CDK](images/CDK1.png)

1. Click on Login and enter your IBMid credentials.

   ![CDK](images/CDK2.png)

1. Click on Create a Connector.

   ![CDK](images/CDK3.png)

1. Drag and drop the `pet-store.yaml` file you had previously downloaded into the OpenAPI document field of the Create a connector dialog.

   For Application Name enter Swagger Petstore and select Supply Chain as category.

   Click on the pencil icon in the Image field to edit the image and then drag an drop the pet-store.svg you downloaded
   Finally, press the Create connector button

   ![CDK](images/CDK4.png)

1. The connector editor will show some tabs that need more information to be completed.

   Click on the Actions tab. And then on the Add or remove actions link,

   ![CDK](images/CDK5.png)

1. We will not be performing any updates on this lab so uncheck the Updates pet in the store action and then click on the Apply changes button.

   ![CDK](images/CDK6.png)

1. Click on the Events tab. Events allow connectors to extract data from sources then this data is created or updated. For this to happen there needs to be an API in the source system which returns the business objects and there should be a field that contains the timestamp of the last update of the object.

   The application we are using in this lab does not have such timestamp field and we will not be creating nor updating any data externally so we will remove the events capability from our connector.

   Click on the Enable or disable events link.

   ![CDK](images/CDK7.png)

1. Unselect all events ad click Apply changes.

   ![CDK](images/CDK8.png)

1. Next, we will configure the connections properties of the application. This will include any required authorization  types and a test connection configuration action that will be used to confirm if the connection is valid and active.

1. Click on Connection Properties.
   Select Only API Key from the supported authorization types.

   ![CDK](images/CDK9.png)

1. Under Test connection configuration select the Configure custom action.

   We will need to configure any API call that would return an HTTP 200 code if the application is available to confirm the connection.

   Enter /pet/findByStatus in the Base path field.

   Select GET as a Method.

   Under Query parameters add a query parameter and type status as its name. For value type available.

   ![CDK](images/CDK10.png)

1. We are ready to test the connector.
   Click on the Test actions tab ant then in the Connect button.

   ![CDK](images/CDK11.png)

1. Enter any API Key  (it is not really validated in our test application) and then click COnnect

   ![CDK](images/CDK12.png)

1. You should see that connector appears as connected in the top right corner with a green check boc and the operations and their.parameters are shown.

   Click on Find Pets by status.

   ![CDK](images/CDK13.png)

1. In the where condition select status, equals and available from the drop down combos and then click Submit.

   ![CDK](images/CDK14.png)

1. You should see a successful test result and show in the following screen:

   ![CDK](images/CDK15.png)

1. Let's try out another operation. Click on the Find pet By Id operation then select equals in the where condition and enter the number 2 as value. Click Submit.

   ![CDK](images/CDK16.png)

1. You should see another successful test with the pet with id of 2 as a result.

   ![CDK](images/CDK17.png)

1. Now we are ready to download the connector from the Connector Development Kit so we can later on install it on an ACE instance.

   Click on the 3 vertically aligned dots on the top right of the window and select Download.

   Save the .car file in a folder in your computer.

   ![CDK](images/CDK18.png)

## Install the connector in an ACE Designer instance

1. In Platform Navigator open the ACE Designer instance.

   Click on the Catalog icon on the left.

   ![CDK](images/CDK19.png)

1. Click on the plus sign to add a connector.

   ![CDK](images/CDK20.png)

1. Select Import a connector file or API document and click Next

   ![CDK](images/CDK21.png)

1. Select Community connector as Document type and drag and drop the .car file you download into the Import section.

   ![CDK](images/CDK22.png)

1. Click on Import connector.

   ![CDK](images/CDK23.png)

1. Now search for the connector from the connector list by typing swa. It should filter out the connectors and show the connector you just imported. Click on Connect.

   ![CDK](images/CDK24.png)

   Typ in any API key and click Connect

   ![CDK](images/CDK25.png)

   Now we will be building a new flow that uses that connector.

1. Click on the Dashboard icon on the left and then click on the Create button

   ![CDK](images/CDK26.png)

   We will be building a REST API that uses the connector to retrieve a pet from the pet store.

1. Select Flows for an API.

   ![CDK](images/CDK27.png)

   We need to create the data model that the API will use. Lets create a Pet.

1. Type Pet in the text box and then click on Create model.

   ![CDK](images/CDK28.png)

1. Add the following properties to the model by clicking on Add property.

   ![CDK](images/CDK29.png)

1. Click on Operations and select Retrieve Pet by ID

   ![CDK](images/CDK30_1.png)

1. Click on Implement flow.

   ![CDK](images/CDK30_2.png)

1. A basic flow with a request and a response will be generated. Click on the plus sign in the middle to add our connector.

   ![CDK](images/CDK31.png)

   It will first list all the connectors that are already connected.

1. Click on the down arrow besides the Swagger Petstore connector to show the available objects and operations.

   ![CDK](images/CDK32.png)

1. Select pet and then Find pet by ID

   ![CDK](images/CDK33.png)

1. The Find pet by ID has an id parameter. We will now map the id property from the ACE API we are building with the ID field of the Find pet by ID operation of the connector.

   Click on the rows icon. It will show available objects at that step in the flow with their field.

   ![CDK](images/CDK34.png)

1. Select the Id field from the Request URL parameters of the API.

   ![CDK](images/CDK35.png)

   We now need to map the response from the connector to the response of our API.

1. Go back to the flow an click in the Response node.

   ![CDK](images/CDK36.png)

   ACE Designer has embedded AI and can suggest mappings.

1. Click on the Preview 3 mapping suggestions button.

   ![CDK](images/CDK37.png)

1. The corresponding fields will be mapped. Click on Apply suggestions.

   ![CDK](images/CDK38.png)

   If not mapped before, the suggestion might miss the Category field since it is in a nested object in the application and that object has multiple fields.

1. Click in the rows icon to the right of the category field. It will suggest mappings once more showing a degree of confidence to the right. The category Name and Id fields are suggested. Click on  Name.

   ![CDK](images/CDK39.png)

   Your mapping should look like this:

   ![CDK](images/CDK40.png)

1. Back in the flow click on Done.

   ![CDK](images/CDK41.png)

1. Click on the top left text box to change the name of the flow and type PetsAPI. Then Click on the toggle button at the top right corner to start the flow.

   ![CDK](images/CDK42.png)

## Test the flow with the connector

1. A new Test tab will appear. Click on it then Click on GET /Pet/{Id}

   ![CDK](images/CDK43.png)

1. Click on Try it

   ![CDK](images/CDK44.png)

1. Scroll down and enter 2 as Id then click Send.

   ![CDK](images/CDK45.png)

1. You should get a successful response with a Pet.

   ![CDK](images/CDK46.png)
