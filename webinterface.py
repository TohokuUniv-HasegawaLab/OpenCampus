# # link: http://localhost:8501 or http://[hostIP]:8501
# import streamlit as st
# import numpy as np
# import os
# import time
# import random
# from PIL import Image

# st.set_page_config(page_title="Block Image Send Simulator", layout="wide")

# uploaded_file = r"C:\Users\hasegawa-lab\Desktop\OpenCampas\picture\photo_send.jpg"

# if uploaded_file:
#     image = Image.open(uploaded_file).convert("RGB")

#     max_height = 800
#     scale_ratio = min(max_height / image.height, 1.0)
#     new_width = int(image.width * scale_ratio)
#     new_height = int(image.height * scale_ratio)
#     image_resized = image.resize((new_width, new_height))
#     image_np = np.array(image_resized)

#     st.image(image_resized, caption="Original Resized Image", use_container_width=False)

#     height, width, _ = image_np.shape
#     col1, col2 = st.columns(2)
#     canvas_no_ncc = np.zeros_like(image_np)
#     canvas_ncc = np.zeros_like(image_np)

#     placeholder_no_ncc = col1.empty()
#     placeholder_ncc = col2.empty()

#     col1.subheader("NCC OFF")
#     col2.subheader("NCC ON")

#     lines_per_block = 10
#     num_blocks = (height + lines_per_block - 1) // lines_per_block

#     # Change the expected send time here
#     target_time_no_ncc = 10
#     target_time_ncc = 0.5
    
#     speed_ratio = int(target_time_no_ncc / target_time_ncc)
#     lines_per_update_ncc = lines_per_block * speed_ratio
#     lines_per_update_no_ncc = lines_per_block

#     #if st.button("Send Image (Compare NCC)"):
#     time.sleep(2)

#     start_time = time.time()
#     last_time_no_ncc = start_time
#     last_time_ncc = start_time
    
#     y_pos_ncc = 0
#     y_pos_no_ncc = 0
#     ncc_finished = False
#     no_ncc_finished = False

#     while y_pos_ncc < height or y_pos_no_ncc < height:
#         current_time = time.time()

#         # --- NCC OFF (Slower) ---
#         if y_pos_no_ncc < height:
#             y_end_no_ncc = min(y_pos_no_ncc + lines_per_update_no_ncc, height)
#             canvas_no_ncc[y_pos_no_ncc:y_end_no_ncc, :] = image_np[y_pos_no_ncc:y_end_no_ncc, :]
#             placeholder_no_ncc.image(Image.fromarray(canvas_no_ncc), use_container_width=False)
#             time.sleep(target_time_no_ncc / num_blocks)
#             y_pos_no_ncc = y_end_no_ncc
#             if y_pos_no_ncc >= height and not no_ncc_finished:
#                 no_ncc_time = time.time() - start_time
#                 no_ncc_finished = True
#                 st.write(f"NCC OFF completed in: {no_ncc_time:.3f} seconds")

#         # --- NCC ON (Faster) ---
#         if y_pos_ncc < height:
#             y_end_ncc = min(y_pos_ncc + lines_per_update_ncc, height)
#             canvas_ncc[y_pos_ncc:y_end_ncc, :] = image_np[y_pos_ncc:y_end_ncc, :]
#             placeholder_ncc.image(Image.fromarray(canvas_ncc), use_container_width=False)
#             elapsed_ncc = time.time() - last_time_ncc
#             to_sleep_ncc = (target_time_ncc / num_blocks) - elapsed_ncc
#             if to_sleep_ncc > 0:
#                 time.sleep(to_sleep_ncc)
#             last_time_ncc = time.time()
#             y_pos_ncc = y_end_ncc
#             if y_pos_ncc >= height and not ncc_finished:
#                 ncc_time = time.time() - start_time
#                 ncc_finished = True

#                 st.write(f"NCC ON completed in: {ncc_time:.3f} seconds")

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


    st.title("yokonarabi")
    site_labels = ["NCCなし", "フランクフルト", "ムンバイ", "ソウル", "NCC3台"]
    if "selected" not in st.session_state:
        st.session_state.selected = None

    # BLE event queue and background thread starter
    if "ble_queue" not in st.session_state:
        st.session_state.ble_queue = queue.Queue()
    if "ble_thread_started" not in st.session_state:
        st.session_state.ble_thread_started = False

    # Preset buttons for target_time
    if "target_time" not in st.session_state:
        st.session_state.target_time = 0.5

    site_cols = st.columns(len(site_labels))
    site = st.columns(5)

    max_height = 800
    scale_ratio = min(max_height / image.height, 1.0)
    new_width = int(image.width * scale_ratio)
    new_height = int(image.height * scale_ratio)
    image_resized = image.resize((new_width, new_height))
    image_np = np.array(image_resized)

    st.image(image_resized, caption="Original Resized Image", use_container_width=False)

    # Controls: presets for target_time
    with st.sidebar:
        st.header("Preset target_time")
        if st.button("Short (0.5s)"):
            st.session_state.target_time = 0.5
        if st.button("Medium (1.5s)"):
            st.session_state.target_time = 1.5
        if st.button("Long (3.0s)"):
            st.session_state.target_time = 3.0
        st.write("Current target_time:", st.session_state.target_time)

    # Start BLE listener thread once
    if not st.session_state.ble_thread_started:
        def _ble_thread():
            start_ble_listener(st.session_state.ble_queue)

        t = threading.Thread(target=_ble_thread, daemon=True)
        t.start()
        st.session_state.ble_thread_started = True

    height, width, _ = image_np.shape
    col1, col2 = st.columns(2)
    canvas_no_ncc = np.zeros_like(image_np)
    canvas_ncc = np.zeros_like(image_np)

    placeholder_no_ncc = col1.empty()
    placeholder_ncc = col2.empty()
    notify_placeholder = st.empty()

    col1.subheader("NCC OFF")
    col2.subheader("NCC ON")

    lines_per_block = 10
    num_blocks = (height + lines_per_block - 1) // lines_per_block

    # Change the expected send time here
    target_time_ncc = 0.5
    # default for the slower (no NCC) path
    target_time_no_ncc = 10.0

    # avoid division by zero
    try:
        speed_ratio = max(1, int(target_time_no_ncc / target_time_ncc))
    except Exception:
        speed_ratio = 1
    lines_per_update_ncc = lines_per_block * speed_ratio
    lines_per_update_no_ncc = lines_per_block

    #if st.button("Send Image (Compare NCC)"):
    time.sleep(2)

    start_time = time.time()
    last_time_no_ncc = start_time
    last_time_ncc = start_time
    
    y_pos_ncc = 0
    y_pos_no_ncc = 0
    ncc_finished = False
    no_ncc_finished = False

    # Main animation loop for demo; also poll BLE queue for notify events
    # We will run the image rendering loop but also check for BLE events
    while y_pos_ncc < height or y_pos_no_ncc < height:
        current_time = time.time()

        # Check BLE queue non-blocking
        try:
            evt = st.session_state.ble_queue.get_nowait()
        except Exception:
            evt = None
        if evt and evt.get("type") == "notify":
            # Show temporary display for the configured duration
            duration = float(st.session_state.target_time)
            with notify_placeholder.container():
                st.write("BLE Notify received at", time.strftime('%H:%M:%S', time.localtime(evt.get('timestamp', time.time()))))
                st.write(f"Temporary display for {duration} s")
                st.progress(0)
                # simple progress animation
                steps = 20
                for i in range(steps):
                    st.progress((i + 1) / steps)
                    time.sleep(duration / steps)
            # clear placeholder
            notify_placeholder.empty()

        # --- NCC OFF (Slower) ---
        if y_pos_no_ncc < height:
            y_end_no_ncc = min(y_pos_no_ncc + lines_per_update_no_ncc, height)
            canvas_no_ncc[y_pos_no_ncc:y_end_no_ncc, :] = image_np[y_pos_no_ncc:y_end_no_ncc, :]
            placeholder_no_ncc.image(Image.fromarray(canvas_no_ncc), use_container_width=False)
            time.sleep(target_time_no_ncc / num_blocks)
            y_pos_no_ncc = y_end_no_ncc
            if y_pos_no_ncc >= height and not no_ncc_finished:
                no_ncc_time = time.time() - start_time
                no_ncc_finished = True
                st.write(f"NCC OFF completed in: {no_ncc_time:.3f} seconds")

        # --- NCC ON (Faster) ---
        if y_pos_ncc < height:
            y_end_ncc = min(y_pos_ncc + lines_per_update_ncc, height)
            canvas_ncc[y_pos_ncc:y_end_ncc, :] = image_np[y_pos_ncc:y_end_ncc, :]
            placeholder_ncc.image(Image.fromarray(canvas_ncc), use_container_width=False)
            elapsed_ncc = time.time() - last_time_ncc
            to_sleep_ncc = (target_time_ncc / num_blocks) - elapsed_ncc
            if to_sleep_ncc > 0:
                time.sleep(to_sleep_ncc)
            last_time_ncc = time.time()
            y_pos_ncc = y_end_ncc
            if y_pos_ncc >= height and not ncc_finished:
                ncc_time = time.time() - start_time
                ncc_finished = True

                st.write(f"NCC ON completed in: {ncc_time:.3f} seconds")

