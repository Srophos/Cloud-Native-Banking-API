import os
import json
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
from azure.servicebus.aio import ServiceBusClient
from azure.servicebus import ServiceBusMessage
from azure.identity.aio import DefaultAzureCredential

SERVICE_BUS_HOSTNAME = os.environ.get("SERVICE_BUS_HOSTNAME")
SERVICE_BUS_QUEUE_NAME = "transactions"

class Transaction(BaseModel):
    from_account: str
    to_account: str
    amount: float

app = FastAPI(title="Transaction Service")

async def send_transaction_message(transaction: Transaction):
    credential = DefaultAzureCredential()
    async with ServiceBusClient(fully_qualified_namespace=str(SERVICE_BUS_HOSTNAME), credential=credential) as client:
        sender = client.get_queue_sender(queue_name=SERVICE_BUS_QUEUE_NAME)
        async with sender:
            message_body = transaction.model_dump_json()
            message = ServiceBusMessage(message_body)
            await sender.send_messages(message)
            print(f"Sent transaction message to queue: {message_body}")

@app.post("/transactions", status_code=202)
async def create_transaction(transaction: Transaction):
    if SERVICE_BUS_HOSTNAME is None:
        raise HTTPException(status_code=500, detail="Server is misconfigured.")
    try:
        await send_transaction_message(transaction)
        return {"status": "accepted", "details": transaction}
    except Exception as e:
        print(f"Error sending message: {e}")
        raise HTTPException(status_code=500, detail="Failed to enqueue transaction.")