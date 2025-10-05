# Cloud-native Banking API
🌟 Project Highlights (At a Glance)

This project is a capstone demonstrating skills from the AZ-900 to AZ-305 (Azure Solutions Architect Expert) certification path.

+  Enterprise Architecture: Designed a secure and resilient backend using a Microservices architecture, with an API Gateway (APIM) and an asynchronous messaging queue (Azure Service Bus).

+  Passwordless Security: Implemented a modern, zero-trust security model using Azure Managed Identities and Role-Based Access Control (RBAC), eliminating the need for storing secrets like connection strings in code.

+  Complete Automation: The entire cloud environment is defined as Infrastructure as Code (IaC) using Bicep. A full CI/CD pipeline in GitHub Actions automatically builds, tests, and deploys all infrastructure and application code on every commit.

🛠️ Technology Stack

| Category                  | Technology / Service                               |
| ------------------------- | -------------------------------------------------- |
| **Cloud Platform** | Microsoft Azure                                    |
| **Compute** | Azure Container Apps                               |
| **API Gateway** | Azure API Management (Consumption Tier)            |
| **Messaging** | Azure Service Bus (Queues)                         |
| **Containerization** | Docker                                             |
| **Backend Language** | Python 3.12 with FastAPI                           |
| **Infrastructure as Code**| Bicep                                              |
| **CI/CD** | GitHub Actions                                     |

🔹 Microservices Architecture: The system is decomposed into three distinct, containerized microservices (AccountService, TransactionService, and a background TransactionWorker), allowing for independent scaling and development.

🔹 Secure API Gateway: All incoming traffic is routed through Azure API Management (APIM). This provides a single, secure entry point that handles authentication, security policies, and intelligent routing.

🔹 Resilient & Asynchronous Processing: To ensure no transaction is ever lost, the system uses an asynchronous messaging pattern with Azure Service Bus. The API instantly accepts requests and places them in a durable queue for safe processing by a background worker.

🔹 Serverless Compute: All services are deployed on Azure Container Apps, a serverless container orchestration platform that provides automatic scaling without the need to manage any underlying infrastructure.

</details>

<details>
<summary><strong>Click to see the System Flow and Deployment Steps</strong></summary>

🌊 System Flow: Creating a Transaction

  1. A client sends a POST /transactions request to the public APIM Gateway URL, including its API subscription key.

  2. APIM validates the key and routes the request to the internal TransactionService.

  3. The TransactionService validates the request body, places the transaction details as a message onto the Service Bus Queue, and immediately returns a 202 Accepted response.

  4. The TransactionWorker, which is constantly listening to the queue, picks up the new message.

  5. The worker processes the transaction logic and, upon success, deletes the message from the queue to mark it as complete.

🚀 Setup and Deployment

This project is configured for fully automated deployment. To replicate this environment:

  1. Fork the Repository and clone it locally.

  2. Create an Azure Service Principal with "Contributor" rights on your subscription.

  3. Add GitHub Secrets: AZURE_CREDENTIALS (the JSON output from the principal) and AZURE_SUBSCRIPTION_ID.

  4. Push a commit to the main branch to trigger the GitHub Actions workflow, which will build and deploy the entire project.

</details>

🌱 Future Enhancements

+ Integrate a Database: Replace the mock data in the AccountService with a real Azure SQL or Cosmos DB.

+ Build a Frontend: Create a simple React or Angular web app that interacts with the secure APIM endpoints and deploy it to Azure Static Web Apps.
