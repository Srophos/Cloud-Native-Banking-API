# Cloud-Native-Banking-API
Cloud-Native Banking API on Microsoft Azure
This repository contains the source code and infrastructure blueprint for a comprehensive, cloud-native banking API backend. This project serves as a capstone, demonstrating the practical application of skills acquired through the Microsoft Azure certification path from AZ-900 to AZ-305 (Azure Solutions Architect Expert).

The architecture is designed to be secure, resilient, scalable, and fully automated, reflecting modern enterprise-level cloud practices.

Architecture Diagram
(This is where you should insert the architecture diagram you created. Replace the placeholder link below with the path to your image.)

Core Features
This project is not just a simple application; it's a complete system designed with professional architectural patterns:

🔹 Microservices Architecture: The system is decomposed into three distinct, containerized microservices (AccountService, TransactionService, and a background TransactionWorker), allowing for independent scaling and development.

🔹 Secure API Gateway: All incoming traffic is routed through Azure API Management (APIM). This provides a single, secure entry point that handles:

Authentication: All clients must provide a valid API subscription key.

Security: A "secret handshake" pattern (via a custom header) ensures that backend services only trust and serve requests originating from the APIM gateway.

Routing: Intelligently forwards requests to the appropriate internal microservice.

🔹 Resilient & Asynchronous Processing: To ensure no transaction is ever lost, the system uses an asynchronous messaging pattern with Azure Service Bus. The API instantly accepts requests and places them in a durable queue, while a separate background worker processes them safely and reliably.

🔹 Serverless Compute: All services are deployed on Azure Container Apps, a serverless container orchestration platform. This provides automatic scaling (including scaling to zero to save costs) without the need to manage any underlying virtual machines.

🔹 Passwordless Security: The architecture employs a modern, passwordless security model. Services authenticate to each other and to Azure resources (like Service Bus) using Azure Managed Identities and Role-Based Access Control (RBAC), completely eliminating secrets like connection strings from the application code.

🔹 Infrastructure as Code (IaC): The entire cloud infrastructure—every service, setting, and permission—is defined declaratively in a master blueprint using Bicep. This allows for consistent, reliable, and repeatable deployments.

🔹 Full Automation (CI/CD): A complete GitHub Actions workflow provides a full CI/CD pipeline. Every git push to the main branch automatically:

Builds all Docker images.

Pushes them to a private Azure Container Registry.

Deploys the full infrastructure from the Bicep template.

Updates the running container apps with the new images.

Technology Stack
Cloud Platform: Microsoft Azure

Compute: Azure Container Apps

API Gateway: Azure API Management (Consumption Tier)

Messaging: Azure Service Bus (Queues)

Containerization: Docker

Container Registry: Azure Container Registry (ACR)

Backend Language: Python 3.12 with FastAPI

Infrastructure as Code: Bicep

CI/CD: GitHub Actions

System Flow: Creating a Transaction
A client sends a POST /transactions request to the public APIM Gateway URL, including its API subscription key.

APIM validates the key and routes the request to the internal TransactionService.

The TransactionService validates the request body, places the transaction details as a message onto the Service Bus Queue, and immediately returns a 202 Accepted response.

The TransactionWorker, which is constantly listening to the queue, picks up the new message.

The worker processes the transaction logic and, upon success, deletes the message from the queue to mark it as complete.

Setup and Deployment
This project is configured for fully automated deployment. To replicate this environment, you would need to:

Prerequisites: An Azure subscription and the Azure CLI installed.

Fork the Repository: Fork this repository to your own GitHub account.

Create a Service Principal: Create an Azure Service Principal with the "Contributor" role on your subscription.

Create GitHub Secrets:

AZURE_CREDENTIALS: The full JSON output from the service principal creation.

AZURE_SUBSCRIPTION_ID: Your Azure Subscription ID.

Push a Change: Pushing a commit to the main branch will trigger the GitHub Actions workflow, which will build and deploy the entire project to your Azure subscription.

Future Enhancements
Integrate a Database: Replace the mock data in the AccountService with a real Azure SQL or Cosmos DB, including adding it to the Bicep template.

Build a Frontend: Create a simple React or Angular web app that interacts with the secure APIM endpoints and deploy it to Azure Static Web Apps.
