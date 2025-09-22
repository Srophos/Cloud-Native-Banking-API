import os
import asyncio
import sys
from azure.servicebus.aio import ServiceBusClient
from azure.identity.aio import DefaultAzureCredential

SERVICE_BUS_HOSTNAME = os.environ.get("SERVICE_BUS_HOSTNAME")
SERVICE_BUS_QUEUE_NAME = "transactions"

if SERVICE_BUS_HOSTNAME is None:
    print("ERROR: SERVICE_BUS_HOSTNAME environment variable not set.")
    sys.exit(1)

async def process_messages():
    print("Worker starting up...")
    credential = DefaultAzureCredential()
    async with ServiceBusClient(fully_qualified_namespace=str(SERVICE_BUS_HOSTNAME), credential=credential) as client:
        receiver = client.get_queue_receiver(queue_name=SERVICE_BUS_QUEUE_NAME)
        async with receiver:
            print(f"Listening for messages on the '{SERVICE_BUS_QUEUE_NAME}' queue...")
            while True:
                try:
                    received_msgs = await receiver.receive_messages(max_wait_time=10)
                    for msg in received_msgs:
                        print("----------------------------------------------------")
                        print(f"Received message: {str(msg)}")
                        print(f"Processing transaction: {str(msg)}")
                        await receiver.complete_message(msg)
                        print("Message processing complete.")
                        print("----------------------------------------------------")
                except Exception as e:
                    print(f"An error occurred: {e}")
                    await asyncio.sleep(5)

if __name__ == '__main__':
    asyncio.run(process_messages())