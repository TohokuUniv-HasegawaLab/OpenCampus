# pip install bleak
import asyncio
import time
from bleak import BleakScanner, BleakClient

SERVICE_UUID = "e44b9ddb-630f-9052-9f2c-1b764b52ce72"
CHAR_UUID    = "ebe9db63-5705-8280-37d5-808d4f5a35fb"

TARGET_NAME  = "IPAD_SYNC"

STREAMLIT_PATH = r"C:\Users\hasegawa-lab\Desktop\OpenCampas\webinterface.py"


def start_ble_listener(event_queue, service_uuid: str = SERVICE_UUID, char_uuid: str = CHAR_UUID, target_name: str = TARGET_NAME):
    """Start a BLE listener in the current (background) thread.

    This will create and run its own asyncio event loop and push notify events
    into the provided queue as dicts: {"type":"notify","data":bytes,...}
    """
    async def _run():
        while True:
            print("Scanning for", target_name)
            device = None
            try:
                for d in await BleakScanner.discover():
                    if (d.name or "").strip() == target_name:
                        device = d
                        break
            except Exception as e:
                print("BLE scan error:", e)
                await asyncio.sleep(5)
                continue

            if not device:
                print("Not found:", target_name)
                await asyncio.sleep(5)
                continue

            try:
                async with BleakClient(device) as client:
                    print("Connected:", device)

                    def on_notify(_, data: bytearray):
                        print("Notify:", data)
                        try:
                            event_queue.put({"type": "notify", "data": bytes(data), "timestamp": time.time()})
                        except Exception as e:
                            print("Queue put error:", e)
                        # Optional: launch streamlit externally if needed
                        if data == b"\x01":
                            print("Trigger received! (byte 0x01)")
                            # subprocess.Popen(["streamlit", "run", STREAMLIT_PATH])

                    await client.start_notify(char_uuid, on_notify)
                    print("Waiting notify…")
                    while True:
                        await asyncio.sleep(1)
            except Exception as e:
                print("BLE connection error:", e)
                await asyncio.sleep(5)

    try:
        asyncio.run(_run())
    except Exception as e:
        print("BLE listener stopped with exception:", e)


async def main():
    # Backwards compatible standalone entrypoint
    print("Starting BLE listener as standalone")
    # Create a temporary queue and run listener (for testing)
    import queue as _q
    q = _q.Queue()
    start_ble_listener(q)


if __name__ == "__main__":
    asyncio.run(main())