# pip install bleak
import asyncio, subprocess
from bleak import BleakScanner, BleakClient

SERVICE_UUID = "e44b9ddb-630f-9052-9f2c-1b764b52ce72"
CHAR_UUID    = "ebe9db63-5705-8280-37d5-808d4f5a35fb"
TARGET_NAME  = "IPAD_SYNC"

STREAMLIT_PATH = r"C:\Users\hasegawa-lab\Desktop\OpenCampas\webinterface.py"

async def main():
    print("Scanning for", TARGET_NAME)
    device = None
    for d in await BleakScanner.discover():
        if (d.name or "").strip() == TARGET_NAME:
            device = d; break
    if not device:
        print("Not found:", TARGET_NAME); return

    async with BleakClient(device) as client:
        print("Connected:", device)

        def on_notify(_, data: bytearray):
            print("Notify:", data)
            if data == b"\x01": #個々の数値にもう少し足すことで経路ごとの表示時間を変化させる
                print("Trigger received! Launching Streamlit…")
                subprocess.Popen(["streamlit", "run", STREAMLIT_PATH])

        await client.start_notify(CHAR_UUID, on_notify)
        print("Waiting notify… (Ctrl+C to exit)")
        while True:
            await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(main())