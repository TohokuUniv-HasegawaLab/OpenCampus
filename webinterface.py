# link: http://localhost:8501 or http://[hostIP]:8501
import streamlit as st
import numpy as np
import os
import time
import random
from PIL import Image
import threading
import queue
from streamlit_receive import start_ble_listener

st.set_page_config(page_title="Block Image Send Simulator", layout="wide")

uploaded_file = r"C:\Users\hasegawa-lab\Desktop\OpenCampas\picture\photo_send.jpg"

if uploaded_file:
    image = Image.open(uploaded_file).convert("RGB")

    # site_labels = ["NCCなし", "フランクフルト", "ムンバイ", "ソウル", "NCC3台"]
    # if "selected" not in st.session_state:
    #     st.session_state.selected = None

    # BLE event queue and background thread starter
    if "ble_queue" not in st.session_state:
        st.session_state.ble_queue = queue.Queue()
    if "ble_thread_started" not in st.session_state:
        st.session_state.ble_thread_started = False

    # Preset buttons for target_time
    if "target_time" not in st.session_state:
        st.session_state.target_time = 0.5

    # site_cols = st.columns(len(site_labels))
    # site = st.columns(5)

    max_height = 800
    scale_ratio = min(max_height / image.height, 1.0)
    new_width = int(image.width * scale_ratio)
    new_height = int(image.height * scale_ratio)
    image_resized = image.resize((new_width, new_height))
    image_np = np.array(image_resized)

    # st.image(image_resized, caption="Original Resized Image", use_container_width=True)


    # ---
    # バイトデータとして画像をエンコード
    import io
    import base64

    buf = io.BytesIO()
    image_resized.save(buf, format="PNG")
    byte_im = buf.getvalue()
    base64_image = base64.b64encode(byte_im).decode()

    # HTMLで画像を右上に表示（小さめに）
    # st.markdown(
    #     f"""
    #     <div style="position: fixed; top: 10px; right: 10px; z-index: 9999; border: 2px solid #ccc; border-radius: 8px; padding: 4px; background-color: white;">
    #         <img src="data:image/png;base64,{base64_image}" width="150" />
    #         <div style="text-align:center; font-size:12px;">Original</div>
    #     </div>
    #     """,
    #     unsafe_allow_html=True
    # )

    st.markdown(
    f"""
    <div style="
        position: fixed;
        bottom: 50px;
        left: 300px;
        z-index: 9999;
        border: 2px solid #ccc;
        border-radius: 10px;
        padding: 6px;
        background-color: white;
        box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        text-align: center;
    ">
        <img src="data:image/png;base64,{base64_image}" width="300" />
        <div style="font-size:14px; margin-top:4px;">Original</div>
    </div>
    """,
    unsafe_allow_html=True
    )



    # ---
    # Controls: presets for exhibition scenarios (latency in ms)
    presets = {
        "NCCなし": 2695.46,
        "Paris": 2738.38,
        "Mumbai": 15170.48,
        "Seoul": 2440,
        "NCC3台": 1280,
    }

    if "preset" not in st.session_state:
        st.session_state.preset = None
        st.session_state.preset_ms = None

    with st.sidebar:
        st.header("Preset")
        for name, ms in presets.items():
            if st.button(f"{name} ({ms} ms)"):
                st.session_state.preset = name
                st.session_state.preset_ms = ms
        # 
        st.markdown(
        f"""
        <div style="font-size:18px; font-weight:bold; color:#6088C6;">
            Selected
        </div>
        <div style="font-size:35px; font-weight:bold; color:black;">
            {st.session_state.preset}
        </div>
        """,
        unsafe_allow_html=True)

    # Start BLE listener thread once. Capture the queue locally to avoid
    # accessing st.session_state from another thread.
    if not st.session_state.ble_thread_started:
        ble_q = st.session_state.ble_queue

        def _ble_thread(q=ble_q):
            start_ble_listener(q)

        t = threading.Thread(target=_ble_thread, daemon=True)
        t.start()
        st.session_state.ble_thread_started = True

    height, width, _ = image_np.shape


    caption_placeholder = st.empty()
    caption_placeholder.markdown(
    "<div style='text-align: center; font-size: 50px; font-weight: bold;'>受信した画像</div>",
    unsafe_allow_html=True)
    
    # single main placeholder for image display
    main_placeholder = st.empty()
    main_placeholder.image(image_resized, caption="受信した画像", use_column_width=True)

    lines_per_block = 10
    num_blocks = (height + lines_per_block - 1) // lines_per_block

    # Wait indefinitely and react to BLE notify events. On notify (0x01),
    # progressively reveal the image based on the selected preset (ms).
    while True:
        try:
            evt = st.session_state.ble_queue.get(timeout=0.5)
        except Exception:
            evt = None

        if evt and evt.get("type") == "notify" and evt.get("data") == b"\x01" and st.session_state.preset is not None:
            duration = float(st.session_state.preset_ms) / 1000.0
            # prepare blank canvas
            canvas = np.zeros_like(image_np)
            sleep_per_block = duration / max(1, num_blocks)
            main_placeholder.image(Image.fromarray(canvas), use_column_width=True)
            for y in range(0, height, lines_per_block):
                y_end = min(y + lines_per_block, height)
                canvas[y:y_end, :] = image_np[y:y_end, :]
                main_placeholder.image(Image.fromarray(canvas), use_column_width=True)
                time.sleep(sleep_per_block)
            # ensure full image shown at end
            main_placeholder.image(image_resized, use_column_width=True)

        # small sleep to avoid busy loop
        time.sleep(0.1)