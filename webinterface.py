import streamlit as st
import numpy as np
import time
import random
from PIL import Image
import plotly.graph_objects as go

st.set_page_config(page_title="Block Image Send Simulator", layout="wide")

uploaded_file = st.file_uploader("Select a photo", type=["jpg","jpeg","png","bmp","tiff"])

if uploaded_file:
    image = Image.open(uploaded_file).convert("RGB")

    max_height = 800
    scale_ratio = min(max_height / image.height, 1.0)
    new_width = int(image.width * scale_ratio)
    new_height = int(image.height * scale_ratio)
    image_resized = image.resize((new_width, new_height))
    image_np = np.array(image_resized)

    st.image(image_resized, caption="Original Resized Image", use_container_width=False)

    height, width, _ = image_np.shape
    col1, col2 = st.columns(2)
    canvas_no_ncc = np.zeros_like(image_np)
    canvas_ncc = np.zeros_like(image_np)

    placeholder_no_ncc = col1.empty()
    placeholder_ncc = col2.empty()

    col1.subheader("NCC OFF")
    col2.subheader("NCC ON")

    lines_per_block = 10
    num_blocks = (height + lines_per_block - 1) // lines_per_block

    target_time_no_ncc = 5.0
    target_time_ncc = 0.5
    
    speed_ratio = int(target_time_no_ncc / target_time_ncc)
    lines_per_update_ncc = lines_per_block * speed_ratio
    lines_per_update_no_ncc = lines_per_block

    if st.button("Send Image (Compare NCC)"):
        start_time = time.time()
        last_time_no_ncc = start_time
        last_time_ncc = start_time
        
        y_pos_ncc = 0
        y_pos_no_ncc = 0
        ncc_finished = False
        no_ncc_finished = False

        while y_pos_ncc < height or y_pos_no_ncc < height:
            current_time = time.time()

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